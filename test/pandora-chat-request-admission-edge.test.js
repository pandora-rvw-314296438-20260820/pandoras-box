import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
import { admitChatModelRun, chatAdmissionNotice } from "../supabase/functions/pandora-intelligence-chat/chat-admission.ts";

const org = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const thread = "11111111-1111-4111-8111-111111111111";
const message = "22222222-2222-4222-8222-222222222222";
const job = "33333333-3333-4333-8333-333333333333";
const claim = "44444444-4444-4444-8444-444444444444";
const run = "55555555-5555-4555-8555-555555555555";
const fingerprint = "a".repeat(64);
const input = (overrides = {}) => ({ organizationId: org, threadId: thread, userMessageId: message,
  requestSha: "b".repeat(64), entryId: null, activityJobId: job, activityClaimId: claim,
  activityRequestFingerprint: fingerprint, metadata: { max_attempts: 6 }, ...overrides });
const admitted = (overrides = {}) => ({ admitted: true, replay: false, id: run, fallback_chain_id: run,
  organization_id: org, thread_id: thread, ...overrides });
function caller(data = admitted(), error = null) {
  const calls = [];
  return { calls, rpc: async (name, parameters) => { calls.push({ name, parameters }); return { data, error }; } };
}

test("admission sends exact authenticated scope and existing Activity identity", async () => {
  const user = caller();
  assert.deepEqual(await admitChatModelRun(user, input()), { id: run, fallbackChainId: run });
  assert.deepEqual(user.calls, [{ name: "pandora_chat_request_admit_v1", parameters: {
    p_organization_id: org, p_thread_id: thread, p_user_message_id: message,
    p_request_sha256: "b".repeat(64), p_entry_id: null,
    p_metadata: { max_attempts: 6, activity_job_id: job, activity_claim_id: claim,
      activity_request_fingerprint: fingerprint },
  } }]);
});

test("metadata cannot override the verified Activity identifiers", async () => {
  const user = caller();
  await admitChatModelRun(user, input({ metadata: { activity_job_id: "foreign", activity_claim_id: "foreign", activity_request_fingerprint: "foreign" } }));
  assert.equal(user.calls[0].parameters.p_metadata.activity_job_id, job);
  assert.equal(user.calls[0].parameters.p_metadata.activity_claim_id, claim);
  assert.equal(user.calls[0].parameters.p_metadata.activity_request_fingerprint, fingerprint);
});

test("a retried Activity remains stable even if a new message was persisted", async () => {
  const user = caller(admitted({ replay: true }));
  await assert.rejects(admitChatModelRun(user, input({ userMessageId: claim })), { message: "CHAT_REQUEST_ALREADY_ADMITTED" });
  assert.equal(user.calls[0].parameters.p_metadata.activity_job_id, job);
  assert.equal(user.calls[0].parameters.p_metadata.activity_request_fingerprint, fingerprint);
  assert.equal(chatAdmissionNotice(Error("CHAT_REQUEST_ALREADY_ADMITTED")).status, 409);
});

test("enrolled missing-job requests are denied by the authoritative policy", async () => {
  const user = caller({ admitted: false, code: "CHAT_REQUEST_IDEMPOTENCY_REQUIRED" });
  await assert.rejects(admitChatModelRun(user, input({ activityJobId: null, activityClaimId: null, activityRequestFingerprint: null })),
    { message: "CHAT_REQUEST_IDEMPOTENCY_REQUIRED" });
  assert.equal(user.calls.length, 1);
  assert.match(chatAdmissionNotice(Error("CHAT_REQUEST_IDEMPOTENCY_REQUIRED")).message, /current Pandora composer/);
});

test("legacy unenrolled null-job requests still require successful server admission", async () => {
  const user = caller();
  await admitChatModelRun(user, input({ activityJobId: null, activityClaimId: null, activityRequestFingerprint: null }));
  assert.equal(user.calls.length, 1);
  assert.equal(user.calls[0].parameters.p_metadata.activity_job_id, null);
});

test("server admission rate limiting returns safe 429 without provider dispatch or internal identifiers", async () => {
  const user = caller({ admitted: false, code: "CHAT_REQUEST_RATE_LIMITED", key_hash: "internal-bucket-key",
    message: "private runtime bucket detail" });
  let providerCalls = 0;
  await assert.rejects(async () => {
    await admitChatModelRun(user, input({ activityJobId: null, activityClaimId: null, activityRequestFingerprint: null }));
    providerCalls++;
  }, { message: "CHAT_REQUEST_RATE_LIMITED" });
  const notice = chatAdmissionNotice(Error("CHAT_REQUEST_RATE_LIMITED"));
  assert.equal(notice.code, "CHAT_REQUEST_RATE_LIMITED");
  assert.equal(notice.status, 429);
  assert.match(notice.message, /Check Activity.*wait a minute/);
  assert.doesNotMatch(notice.message, /bucket|key_hash|private runtime|internal/);
  assert.equal(user.calls.length, 1);
  assert.equal(providerCalls, 0);
});

test("incomplete or malformed request identities fail before database invocation", async () => {
  for (const overrides of [{ activityJobId: null }, { activityClaimId: null }, { activityRequestFingerprint: "invalid" },
    { organizationId: "invalid" }, { threadId: "invalid" }, { userMessageId: "invalid" }, { requestSha: "invalid" }, { entryId: "invalid" }]) {
    const user = caller();
    await assert.rejects(admitChatModelRun(user, input(overrides)), { message: "CHAT_REQUEST_ADMISSION_UNAVAILABLE" });
    assert.equal(user.calls.length, 0);
  }
});

test("quota and policy denials never reach a provider or trust returned error prose", async () => {
  for (const code of ["CHAT_REQUEST_LIMIT_REACHED", "CHAT_REQUEST_POLICY_UNAVAILABLE", "CHAT_REQUEST_IDEMPOTENCY_REQUIRED", "CHAT_REQUEST_RATE_LIMITED"]) {
    let providerCalls = 0;
    const user = caller({ admitted: false, code, message: "authorization: private material" });
    await assert.rejects(async () => { await admitChatModelRun(user, input()); providerCalls++; }, { message: code });
    assert.equal(providerCalls, 0);
    assert.doesNotMatch(chatAdmissionNotice(Error(code)).message, /authorization:|private material/);
  }
});

test("replayed running, failed, or succeeded runs never grant a second provider dispatch", async () => {
  for (const status of ["running", "failed", "succeeded"]) {
    let providerCalls = 0;
    await assert.rejects(async () => { await admitChatModelRun(caller(admitted({ replay: true, status })), input()); providerCalls++; },
      { message: "CHAT_REQUEST_ALREADY_ADMITTED" });
    assert.equal(providerCalls, 0);
  }
});

test("missing RPC, connection failures, and revoked authority cannot fall back to service writes", async () => {
  for (const failure of [{ code: "42501", message: "private membership detail" }, { code: "PGRST202", message: "private schema" }]) {
    const user = caller(null, failure);
    await assert.rejects(admitChatModelRun(user, input()), { message: failure.code === "42501" ? "CHAT_REQUEST_ADMISSION_DENIED" : "CHAT_REQUEST_ADMISSION_UNAVAILABLE" });
    assert.equal(user.calls.length, 1);
  }
  await assert.rejects(admitChatModelRun({ rpc: async () => { throw Error("Bearer private material"); } }, input()),
    { message: "CHAT_REQUEST_ADMISSION_UNAVAILABLE" });
  assert.match(chatAdmissionNotice(Error("CHAT_REQUEST_ADMISSION_UNAVAILABLE")).message, /Check Activity.*before starting another request/);
  assert.doesNotMatch(chatAdmissionNotice(Error("CHAT_REQUEST_ADMISSION_UNAVAILABLE")).message, /No cloud model was called/);
});

test("malformed and cross-tenant receipts cannot authorize provider execution", async () => {
  for (const data of [null, {}, { admitted: false, code: "private exception" }, admitted({ id: "bad" }),
    admitted({ fallback_chain_id: "bad" }), admitted({ replay: null }), admitted({ organization_id: message }), admitted({ thread_id: message })]) {
    await assert.rejects(admitChatModelRun(caller(data), input()), { message: "CHAT_REQUEST_ADMISSION_UNAVAILABLE" });
  }
  assert.equal(chatAdmissionNotice(Error("provider_failure")), null);
});

test("actual chat entry calls caller-JWT admission once before the provider attempt loop", () => {
  const source = readFileSync(new URL("../supabase/functions/pandora-intelligence-chat/index.ts", import.meta.url), "utf8");
  assert.match(source, /modelRun=await beginChatModelRun\(c\.user,/);
  assert.doesNotMatch(source, /beginChatModelRun\(c\.admin,/);
  assert.match(source, /activityJobId:i\.activityJobId,activityClaimId:executionClaim\.claimId,activityRequestFingerprint:i\.activityJobId\?requestFingerprint:null/);
  const admittedAt = source.indexOf("modelRun=await beginChatModelRun(c.user,");
  const attemptLoop = source.indexOf("for(let index=0;index<list.length;index++)", admittedAt);
  const providerAt = source.indexOf("result=await providerExact(", attemptLoop);
  assert.ok(admittedAt > 0 && attemptLoop > admittedAt && providerAt > attemptLoop);
  assert.equal((source.match(/modelRun=await beginChatModelRun\(/g) || []).length, 1);
  assert.match(source, /const admission=chatAdmissionNotice\(e\);if\(admission\)return\[admission.status,admission.message\]/);
  assert.match(source, /sourceId:"pandora-chat-request-admission"/);
});

test("routing evidence query is bound to the authenticated tenant before using model rows", async () => {
  const source = readFileSync(new URL("../supabase/functions/pandora-intelligence-chat/index.ts", import.meta.url), "utf8");
  const start = source.indexOf("async function verifiedRoutingPerformance(");
  const end = source.indexOf("\nasync function beginChatModelRun", start);
  assert.ok(start > 0 && end > start);
  const compiled = ts.transpileModule(`${source.slice(start, end)}\nexports.run = verifiedRoutingPerformance;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  new Function("exports", "txt", compiled)(exports, (value) => typeof value === "string" ? value : "");
  const calls = [];
  const query = {
    select(fields) { calls.push(["select", fields]); return this; },
    eq(key, value) { calls.push(["eq", key, value]); return this; },
    not(...args) { calls.push(["not", ...args]); return this; },
    order(...args) { calls.push(["order", ...args]); return this; },
    async limit(value) {
      calls.push(["limit", value]);
      assert.deepEqual(calls.filter(([op, key]) => op === "eq" && key === "organization_id"), [["eq", "organization_id", org]]);
      return { data: [], error: null };
    },
  };
  assert.deepEqual(await exports.run({ from(table) { assert.equal(table, "pandora_model_runs"); return query; } }, org), {});
  assert.match(source, /await verifiedRoutingPerformance\(c\.admin,c\.organizationId\)/);
  assert.doesNotMatch(source, /await verifiedRoutingPerformance\(c\.admin\)/);
});
