import { assertIndependentReview } from "./independent-review.mjs";
import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import {
  CANONICAL_REPOSITORY,
  INTEGRATION_APP_ID,
  SPREADSHEET_ID,
  RULE_CONTEXT,
  bindEnvelope,
} from "./contract.mjs";
import { assertLiveIdentity, expireCheck, publishDecision, revokeCheckForSnapshot } from "./publisher.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const INSTALLATION_ID = 158056492;
const MAX_BODY_BYTES = 48 * 1024;
const PASS_ENABLED = true;

type JsonRecord = Record<string, unknown>;
function rec(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}
function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}
function adminClient() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("SERVICE_UNAVAILABLE");
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
async function readBody(request: Request) {
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new Error("BODY_TOO_LARGE");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) throw new Error("BODY_TOO_LARGE");
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { throw new Error("INVALID_JSON"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("INVALID_JSON");
  return parsed as JsonRecord;
}
function b64(bytes: Uint8Array) {
  let raw = "";
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
}
function b64Text(value: string) { return b64(new TextEncoder().encode(value)); }
function concat(...parts: Uint8Array[]) {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) { out.set(part, offset); offset += part.length; }
  return out;
}
function derLength(length: number) {
  if (length < 128) return new Uint8Array([length]);
  const bytes: number[] = [];
  let value = length;
  while (value > 0) { bytes.unshift(value & 255); value >>>= 8; }
  return new Uint8Array([128 | bytes.length, ...bytes]);
}
function derWrap(tag: number, body: Uint8Array) { return concat(new Uint8Array([tag]), derLength(body.length), body); }
function pemDer(pem: string) {
  const compact = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const decoded = atob(compact);
  const bytes = new Uint8Array(decoded.length);
  for (let index = 0; index < decoded.length; index++) bytes[index] = decoded.charCodeAt(index);
  return bytes;
}
function pkcs1ToPkcs8(pkcs1: Uint8Array) {
  return derWrap(48, concat(
    new Uint8Array([2, 1, 0]),
    new Uint8Array([48, 13, 6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 1, 5, 0]),
    derWrap(4, pkcs1),
  ));
}
async function githubAppJwt(appId: number, privateKeyPem: string) {
  const raw = pemDer(privateKeyPem);
  const keyBytes = privateKeyPem.includes("BEGIN RSA PRIVATE KEY") ? pkcs1ToPkcs8(raw) : raw;
  const key = await crypto.subtle.importKey(
    "pkcs8", keyBytes, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = b64Text(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64Text(JSON.stringify({ iat: now - 30, exp: now + 540, iss: appId }));
  const input = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(input),
  ));
  return `${input}.${b64(signature)}`;
}
async function rpc(admin: ReturnType<typeof adminClient>, name: string, args: JsonRecord, code: string) {
  const result = await admin.rpc(name, args);
  if (result.error) throw new Error(code);
  return result.data;
}
async function validateInternalKey(admin: ReturnType<typeof adminClient>, internalKey: string) {
  const valid = await rpc(admin, "pandora_validate_coordinator_gate_key_v1", { p_token: internalKey }, "GATE_AUTH_CHECK_FAILED");
  if (valid !== true) throw new Error("GATE_AUTH_INVALID");
}
async function githubInstallationToken(admin: ReturnType<typeof adminClient>) {
  const material = rec(await rpc(admin, "pandora_get_github_app_runtime_material", {}, "GITHUB_APP_MATERIAL_UNAVAILABLE"));
  const appId = Number(material.appId);
  const installationId = Number(material.installationId);
  const privateKeyPem = typeof material.privateKeyPem === "string" ? material.privateKeyPem : "";
  if (appId !== INTEGRATION_APP_ID || installationId !== INSTALLATION_ID || !privateKeyPem.includes("PRIVATE KEY")) {
    throw new Error("GITHUB_APP_MATERIAL_INVALID");
  }
  const jwt = await githubAppJwt(appId, privateKeyPem);
  const response = await fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
    method: "POST",
    redirect: "error",
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${jwt}`,
      "content-type": "application/json",
      "user-agent": "Pandora-Coordinator-Gate/1.0",
      "x-github-api-version": "2022-11-28",
    },
    body: JSON.stringify({ permissions: { checks: "write", contents: "read", pull_requests: "read" } }),
  });
  const body = rec(await response.json().catch(() => ({})));
  if (response.status !== 201 || typeof body.token !== "string") throw new Error("GITHUB_INSTALLATION_TOKEN_FAILED");
  return body.token;
}
async function githubJson(token: string, path: string, init: RequestInit = {}, ambiguousWrite = false) {
  let response: Response;
  try {
    response = await fetch(`https://api.github.com/repos/${CANONICAL_REPOSITORY}/${path}`, {
      ...init,
      redirect: "error",
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "user-agent": "Pandora-Coordinator-Gate/1.0",
        "x-github-api-version": "2022-11-28",
        ...(init.headers || {}),
      },
    });
  } catch {
    throw new Error(ambiguousWrite ? "GITHUB_WRITE_AMBIGUOUS" : "GITHUB_READ_FAILED");
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (ambiguousWrite && response.status >= 500) throw new Error("GITHUB_WRITE_AMBIGUOUS");
    throw new Error(`GITHUB_API_${response.status}`);
  }
  return body;
}
function githubProvider(token: string) {
  return {
    async getPull(pullNumber: number) {
      return await githubJson(token, `pulls/${pullNumber}`);
    },
    async listReviews(pullNumber: number) {
      const reviews = await githubJson(token, `pulls/${pullNumber}/reviews?per_page=100`);
      if (!Array.isArray(reviews) || reviews.length >= 100) {
        throw new Error("REVIEW_LIST_UNBOUNDED");
      }
      return reviews;
    },
    async getMainSha() {
      const branch = rec(await githubJson(token, "branches/main"));
      return String(rec(branch.commit).sha || "");
    },
    async listChecks(headSha: string) {
      const name = encodeURIComponent("Pandora coordinator / integration");
      const result = rec(await githubJson(token, `commits/${headSha}/check-runs?check_name=${name}&filter=all&per_page=100`));
      if (Number(result.total_count || 0) > 100) throw new Error("CHECK_LIST_UNBOUNDED");
      return Array.isArray(result.check_runs) ? result.check_runs : [];
    },
    async getCheck(checkRunId: number) {
      return await githubJson(token, `check-runs/${checkRunId}`);
    },
    async createCheck(payload: JsonRecord) {
      return await githubJson(token, "check-runs", {
        method: "POST",
        body: JSON.stringify(payload),
      }, true);
    },
    async updateCheck(checkRunId: number, payload: JsonRecord) {
      return await githubJson(token, `check-runs/${checkRunId}`, {
        method: "PATCH",
        body: JSON.stringify(payload),
      }, true);
    },

  };
}

async function beginDecision(admin: ReturnType<typeof adminClient>, internalKey: string, envelope: JsonRecord, binding: JsonRecord) {
  const args = {
    p_internal_key: internalKey, p_repository: envelope.repository,
    p_pull_request_number: envelope.pullRequestNumber, p_decision_generation: envelope.decisionGeneration,
    p_prior_generation: envelope.priorGeneration, p_prior_check_run_id: envelope.priorCheckRunId,
    p_head_sha: envelope.headSha, p_base_sha: envelope.baseSha,
    p_authoritative_snapshot_generation: envelope.authoritativeSnapshotGeneration,
    p_authoritative_snapshot_revision: envelope.authoritativeSnapshotRevision,
    p_authoritative_snapshot_sha256: envelope.authoritativeSnapshotSha256,
    p_envelope_hash: binding.envelopeHash, p_idempotency_key: binding.idempotencyKey,
    p_decision_nonce: envelope.decisionNonce, p_decision: envelope.decision, p_expires_at: envelope.expiresAt,
  };
  const result = await admin.rpc("pandora_coordinator_gate_begin_decision_v2", args);
  if (!result.error) return rec(result.data);
  const recovered = rec(await rpc(admin, "pandora_coordinator_gate_read_state_v1", {
    p_internal_key: internalKey, p_repository: envelope.repository,
    p_pull_request_number: envelope.pullRequestNumber,
  }, "GATE_STATE_BEGIN_READBACK_FAILED"));
  const snapshot = await readEffectiveSnapshot(admin, internalKey);
  const same = recovered.repository === envelope.repository &&
    recovered.pull_request_number === envelope.pullRequestNumber &&
    recovered.current_generation === envelope.decisionGeneration &&
    recovered.head_sha === envelope.headSha && recovered.base_sha === envelope.baseSha &&
    recovered.authoritative_snapshot_generation === envelope.authoritativeSnapshotGeneration &&
    recovered.authoritative_snapshot_revision === envelope.authoritativeSnapshotRevision &&
    recovered.authoritative_snapshot_sha256 === envelope.authoritativeSnapshotSha256 &&
    recovered.envelope_hash === binding.envelopeHash && recovered.idempotency_key === binding.idempotencyKey &&
    recovered.decision_nonce === envelope.decisionNonce && recovered.decision === envelope.decision &&
    recovered.current_check_run_id === null && recovered.provider_status === null && recovered.provider_conclusion === null &&
    snapshot?.fenceState === "publishing";
  if (!same) throw new Error("GATE_STATE_BEGIN_FAILED");
  return { mode: "ambiguous_recovered", decisionId: recovered.current_decision_id, generation: recovered.current_generation };
}
async function recordPublish(
  admin: ReturnType<typeof adminClient>,
  internalKey: string,
  envelope: JsonRecord,
  binding: JsonRecord,
  check: JsonRecord,
) {
  const appId = Number(rec(check.app).id);
  const args = { p_internal_key: internalKey, p_repository: envelope.repository,
    p_pull_request_number: envelope.pullRequestNumber, p_decision_generation: envelope.decisionGeneration,
    p_authoritative_snapshot_generation: envelope.authoritativeSnapshotGeneration, p_envelope_hash: binding.envelopeHash,
    p_idempotency_key: binding.idempotencyKey, p_check_run_id: check.id, p_provider_app_id: appId,
    p_provider_status: check.status, p_provider_conclusion: check.conclusion };
  const result = await admin.rpc("pandora_coordinator_gate_record_publish_v2", args);
  if (!result.error) return rec(result.data);
  const recovered = rec(await rpc(admin, "pandora_coordinator_gate_read_state_v1", {
    p_internal_key: internalKey, p_repository: envelope.repository, p_pull_request_number: envelope.pullRequestNumber,
  }, "GATE_STATE_RECORD_READBACK_FAILED"));
  const snapshot = await readEffectiveSnapshot(admin, internalKey);
  const expectedConclusion = envelope.decision === "PASS" ? "success" : "action_required";
  const same = recovered.current_generation === envelope.decisionGeneration &&
    recovered.current_check_run_id === check.id && recovered.provider_status === "completed" &&
    recovered.provider_conclusion === expectedConclusion && recovered.envelope_hash === binding.envelopeHash &&
    recovered.idempotency_key === binding.idempotencyKey && snapshot?.fenceState === "idle";
  if (!same) throw new Error("GATE_STATE_RECORD_FAILED");
  return { ok: true, mode: "ambiguous_recovered", checkRunId: check.id, decision: envelope.decision };
}


async function readEffectiveSnapshot(admin: ReturnType<typeof adminClient>, internalKey: string) {
  const value = await rpc(admin, "pandora_coordinator_snapshot_read_effective_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
  }, "SNAPSHOT_READ_FAILED");
  return value ? rec(value) : null;
}
function validSnapshotField(value: unknown, max: number) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}
async function handleSnapshotPromotion(
  admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord,
) {
  const candidateRevision = typeof body.candidateRevision === "string" ? body.candidateRevision.trim() : "";
  const candidateSha256 = typeof body.candidateSha256 === "string" ? body.candidateSha256.trim() : "";
  const evidenceRef = typeof body.evidenceRef === "string" ? body.evidenceRef.trim() : "";
  const providerReadAt = typeof body.providerReadAt === "string" ? body.providerReadAt.trim() : "";
  const promotionNonce = typeof body.promotionNonce === "string" ? body.promotionNonce.trim() : "";
  const readMs = Date.parse(providerReadAt);
  if (!validSnapshotField(candidateRevision, 192) || !/^[0-9a-f]{64}$/.test(candidateSha256) ||
      !validSnapshotField(evidenceRef, 240) || !validSnapshotField(promotionNonce, 240) ||
      !Number.isFinite(readMs)) throw new Error("INVALID_SNAPSHOT_PROMOTION");
  const prepared = rec(await rpc(admin, "pandora_coordinator_snapshot_prepare_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_spreadsheet_id: SPREADSHEET_ID,
    p_candidate_revision: candidateRevision,
    p_candidate_sha256: candidateSha256,
    p_evidence_ref: evidenceRef,
    p_provider_read_at: providerReadAt,
    p_promotion_nonce: promotionNonce,
  }, "SNAPSHOT_PREPARE_FAILED"));
  const promotionId = String(prepared.promotionId || "");
  if (!promotionId) throw new Error("SNAPSHOT_PROMOTION_ID_MISSING");
  const targets = Array.isArray(prepared.revocations) ? prepared.revocations.map(rec) : [];
  if (targets.length > 0) {
    const provider = githubProvider(await githubInstallationToken(admin));
    for (const target of targets) {
      const checkRunId = Number(target.checkRunId);
      const pullRequestNumber = Number(target.pullRequestNumber);
      const headSha = String(target.headSha || "");
      if (!Number.isSafeInteger(checkRunId) || checkRunId < 1 ||
          !Number.isSafeInteger(pullRequestNumber) || pullRequestNumber < 1 ||
          !/^[0-9a-f]{40}$/.test(headSha)) throw new Error("SNAPSHOT_REVOCATION_TARGET_INVALID");
      const revoked = rec(await revokeCheckForSnapshot(provider, checkRunId, headSha, promotionId));
      const check = rec(revoked.check);
      await rpc(admin, "pandora_coordinator_snapshot_record_revocation_v1", {
        p_internal_key: internalKey,
        p_repository: CANONICAL_REPOSITORY,
        p_promotion_id: promotionId,
        p_pull_request_number: pullRequestNumber,
        p_check_run_id: checkRunId,
        p_provider_app_id: Number(rec(check.app).id),
        p_provider_status: check.status,
        p_provider_conclusion: check.conclusion,
      }, "SNAPSHOT_REVOCATION_RECORD_FAILED");
    }
  }
  if (prepared.mode === "effective_replay") {
    const effective = await readEffectiveSnapshot(admin, internalKey);
    if (!effective || effective.fenceState !== "idle" || effective.snapshotGeneration !== prepared.snapshotGeneration) {
      throw new Error("SNAPSHOT_EFFECTIVE_REPLAY_MISMATCH");
    }
    return { ok: true, action: "promoteSnapshot", mode: "effective_replay", ...effective };
  }
  const commitResult = await admin.rpc("pandora_coordinator_snapshot_commit_v1", {
    p_internal_key: internalKey, p_repository: CANONICAL_REPOSITORY, p_promotion_id: promotionId,
  });
  if (!commitResult.error) return { ok: true, action: "promoteSnapshot", ...rec(commitResult.data) };
  const effective = await readEffectiveSnapshot(admin, internalKey);
  const recovered = effective?.fenceState === "idle" && effective.snapshotGeneration === prepared.snapshotGeneration &&
    effective.snapshotRevision === candidateRevision && effective.snapshotSha256 === candidateSha256;
  if (!recovered) throw new Error("SNAPSHOT_COMMIT_FAILED");
  return { ok: true, action: "promoteSnapshot", mode: "ambiguous_recovered", ...effective };
}
async function handleSnapshotAbort(
  admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord,
) {
  const promotionId = typeof body.promotionId === "string" ? body.promotionId.trim() : "";
  if (!promotionId) throw new Error("INVALID_SNAPSHOT_PROMOTION");
  const result = rec(await rpc(admin, "pandora_coordinator_snapshot_abort_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_promotion_id: promotionId,
  }, "SNAPSHOT_ABORT_FAILED"));
  return { ok: true, action: "abortSnapshot", ...result };
}

async function handlePublish(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {
  const envelope = rec(body.envelope);
  if (envelope.decision === "PASS" && !PASS_ENABLED) {
    throw new Error("PASS_DISABLED_UNTIL_SHEET_FENCE");
  }
  const binding = rec(await bindEnvelope(envelope));
  const token = await githubInstallationToken(admin);
  const provider = githubProvider(token);
  if (envelope.decision === "PASS") {
    const pullNumber = Number(envelope.pullRequestNumber);
    const [pull, reviews] = await Promise.all([
      provider.getPull(pullNumber), provider.listReviews(pullNumber),
    ]);
    // Reject absent or fabricated review labels before acquiring a durable fence.
    assertIndependentReview({
      pull, reviews, headSha: envelope.headSha,
      reviewId: envelope.reviewId, reviewerVendor: envelope.reviewerVendor,
    });
  }
  const begun = await beginDecision(admin, internalKey, envelope, binding);
  const published = rec(await publishDecision(provider, envelope));
  const check = rec(published.check);
  await recordPublish(admin, internalKey, envelope, binding, check);
  return {
    ok: true,
    action: "publish",
    mode: published.state,
    generation: envelope.decisionGeneration,
    decision: envelope.decision,
    checkRunId: check.id,
    headSha: envelope.headSha,
    envelopeHash: String(binding.envelopeHash || "").slice(0, 16),
    idempotencyKey: String(binding.idempotencyKey || "").slice(0, 16),
    stateMode: begun.mode,
  };
}
function assertMergeReady(state: JsonRecord, snapshot: JsonRecord, pull: unknown, mainSha: string, check: unknown) {
  const checkRow = rec(check);
  assertLiveIdentity({ pullRequestNumber: state.pull_request_number, headSha: state.head_sha, baseSha: state.base_sha }, pull, mainSha);
  if (state.decision !== "PASS" || state.provider_status !== "completed" || state.provider_conclusion !== "success" || state.consumed_at !== null || Date.parse(String(state.expires_at || "")) <= Date.now()) throw new Error("MERGE_NOT_AUTHORIZED");
  if (Number(snapshot.snapshotGeneration) !== Number(state.authoritative_snapshot_generation) || snapshot.snapshotRevision !== state.authoritative_snapshot_revision || snapshot.snapshotSha256 !== state.authoritative_snapshot_sha256) throw new Error("MERGE_SNAPSHOT_MISMATCH");
  if (checkRow.name !== RULE_CONTEXT || checkRow.head_sha !== state.head_sha || Number(rec(checkRow.app).id) !== INTEGRATION_APP_ID || checkRow.status !== "completed" || checkRow.conclusion !== "success" || Number(checkRow.id) !== Number(state.current_check_run_id)) throw new Error("MERGE_CHECK_MISMATCH");
}

async function readState(admin: ReturnType<typeof adminClient>, internalKey: string, pullNumber: number) {
  const value = await rpc(admin, "pandora_coordinator_gate_read_state_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_pull_request_number: pullNumber,
  }, "GATE_STATE_READ_FAILED");
  return value ? rec(value) : null;
}
async function handleClaimMerge(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {
  const pullNumber=Number(body.pullRequestNumber); if(!Number.isSafeInteger(pullNumber)||pullNumber<1) throw new Error("INVALID_PULL_REQUEST");
  const state=await readState(admin,internalKey,pullNumber), snapshot=await readEffectiveSnapshot(admin,internalKey); if(!state||!snapshot) throw new Error("MERGE_STATE_NOT_FOUND");
  const provider=githubProvider(await githubInstallationToken(admin)), checkRunId=Number(state.current_check_run_id); const [pull,mainSha,check]=await Promise.all([provider.getPull(pullNumber),provider.getMainSha(),provider.getCheck(checkRunId)]); assertMergeReady(state,snapshot,pull,mainSha,check);
  assertIndependentReview({pull,reviews:await provider.listReviews(pullNumber),headSha:state.head_sha});
  const claimId=crypto.randomUUID(); const claimed=rec(await rpc(admin,"pandora_coordinator_gate_claim_merge_v2",{p_internal_key:internalKey,p_repository:CANONICAL_REPOSITORY,p_pull_request_number:pullNumber,p_decision_generation:state.current_generation,p_authoritative_snapshot_generation:state.authoritative_snapshot_generation,p_authoritative_snapshot_revision:state.authoritative_snapshot_revision,p_authoritative_snapshot_sha256:state.authoritative_snapshot_sha256,p_envelope_hash:state.envelope_hash,p_idempotency_key:state.idempotency_key,p_decision_nonce:state.decision_nonce,p_check_run_id:checkRunId,p_head_sha:state.head_sha,p_base_sha:state.base_sha,p_claim_id:claimId},"MERGE_CLAIM_FAILED"));
  const [pull2,main2,check2]=await Promise.all([provider.getPull(pullNumber),provider.getMainSha(),provider.getCheck(checkRunId)]); assertMergeReady(state,snapshot,pull2,main2,check2); return {ok:true,action:"claimMerge",claimId,pullRequestNumber:pullNumber,headSha:state.head_sha,baseSha:state.base_sha,checkRunId,...claimed};
}
async function handleCompleteMerge(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {
  const pullNumber=Number(body.pullRequestNumber), claimId=String(body.claimId||""); if(!Number.isSafeInteger(pullNumber)||pullNumber<1||!claimId) throw new Error("INVALID_MERGE_CLAIM"); const state=await readState(admin,internalKey,pullNumber); if(!state||state.merge_claim_id!==claimId) throw new Error("MERGE_CLAIM_MISMATCH"); const provider=githubProvider(await githubInstallationToken(admin)), pull=rec(await provider.getPull(pullNumber)), mergeSha=String(pull.merge_commit_sha||""), headSha=String(rec(pull.head).sha||"");
  if(pull.merged!==true||headSha!==state.head_sha||!/^[0-9a-f]{40}$/.test(mergeSha)) throw new Error("MERGE_PROVIDER_READBACK_MISMATCH"); const completed=rec(await rpc(admin,"pandora_coordinator_gate_complete_merge_v2",{p_internal_key:internalKey,p_repository:CANONICAL_REPOSITORY,p_pull_request_number:pullNumber,p_decision_generation:state.current_generation,p_claim_id:claimId,p_merge_sha:mergeSha},"MERGE_COMPLETE_FAILED")); return {ok:true,action:"completeMerge",pullRequestNumber:pullNumber,claimId,mergeSha,...completed};
}
async function handleAbortMerge(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {
  const pullNumber=Number(body.pullRequestNumber), claimId=String(body.claimId||""); if(!Number.isSafeInteger(pullNumber)||pullNumber<1||!claimId) throw new Error("INVALID_MERGE_CLAIM"); const state=await readState(admin,internalKey,pullNumber); if(!state||state.merge_claim_id!==claimId) throw new Error("MERGE_CLAIM_MISMATCH"); const provider=githubProvider(await githubInstallationToken(admin)), checkRunId=Number(state.current_check_run_id), check=rec(await provider.getCheck(checkRunId)); if(Number(check.id)!==checkRunId||check.head_sha!==state.head_sha||Number(rec(check.app).id)!==INTEGRATION_APP_ID) throw new Error("MERGE_ABORT_CHECK_IDENTITY_MISMATCH");
  const payload={name:RULE_CONTEXT,external_id:check.external_id,status:"completed",conclusion:"action_required",completed_at:new Date().toISOString(),output:{title:"Pandora coordinator HOLD",summary:`Merge claim ${claimId} was aborted before verified completion.`}}; await provider.updateCheck(checkRunId,payload); const readback=rec(await provider.getCheck(checkRunId)); if(readback.status!=="completed"||readback.conclusion!=="action_required"||Number(rec(readback.app).id)!==INTEGRATION_APP_ID) throw new Error("MERGE_ABORT_CHECK_READBACK_MISMATCH"); const aborted=rec(await rpc(admin,"pandora_coordinator_gate_abort_merge_v2",{p_internal_key:internalKey,p_repository:CANONICAL_REPOSITORY,p_pull_request_number:pullNumber,p_decision_generation:state.current_generation,p_claim_id:claimId,p_check_run_id:checkRunId,p_provider_app_id:Number(rec(readback.app).id),p_provider_status:readback.status,p_provider_conclusion:readback.conclusion},"MERGE_ABORT_FAILED")); return {ok:true,action:"abortMerge",pullRequestNumber:pullNumber,claimId,checkRunId,...aborted};
}
async function handleExpire(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {
  const pullNumber = Number(body.pullRequestNumber);
  if (!Number.isSafeInteger(pullNumber) || pullNumber < 1) throw new Error("INVALID_PULL_REQUEST");
  const state = await readState(admin, internalKey, pullNumber);
  if (!state) throw new Error("GATE_STATE_NOT_FOUND");
  const checkRunId = Number(state.current_check_run_id);
  const headSha = String(state.head_sha || "");
  if (!Number.isSafeInteger(checkRunId) || checkRunId < 1) throw new Error("GATE_CHECK_NOT_PUBLISHED");
  const expiresAt = Date.parse(String(state.expires_at || ""));
  if (Number.isFinite(expiresAt) && expiresAt > Date.now()) {
    return { ok: true, action: "expire", pullRequestNumber: pullNumber, state: "fresh", checkRunId };
  }
  await rpc(admin, "pandora_coordinator_gate_begin_expiry_v2", {
    p_internal_key: internalKey, p_repository: CANONICAL_REPOSITORY,
    p_pull_request_number: pullNumber, p_decision_generation: state.current_generation,
    p_check_run_id: checkRunId,
  }, "GATE_EXPIRY_FENCE_FAILED");
  const token = await githubInstallationToken(admin);
  const result = rec(await expireCheck(githubProvider(token), checkRunId, headSha));
  if (result.state === "expired" || result.state === "already_invalid") {
    await rpc(admin, "pandora_coordinator_gate_mark_expired_v2", {
      p_internal_key: internalKey, p_repository: CANONICAL_REPOSITORY,
      p_pull_request_number: pullNumber, p_decision_generation: state.current_generation,
      p_check_run_id: checkRunId,
    }, "GATE_EXPIRY_RECORD_FAILED");
  }
  return { ok: true, action: "expire", pullRequestNumber: pullNumber, state: result.state, checkRunId };
}
function publicState(state: JsonRecord | null) {
  if (!state) return null;
  return {
    repository: state.repository,
    pullRequestNumber: state.pull_request_number,
    generation: state.current_generation,
    headSha: state.head_sha,
    baseSha: state.base_sha,
    snapshotGeneration: state.authoritative_snapshot_generation,
    snapshotRevision: state.authoritative_snapshot_revision,
    snapshotSha256: state.authoritative_snapshot_sha256,
    decision: state.decision,
    expiresAt: state.expires_at,
    checkRunId: state.current_check_run_id,
    providerStatus: state.provider_status,
    providerConclusion: state.provider_conclusion,
    consumedAt: state.consumed_at,
    mergedSha: state.merged_sha,
  };
}
Deno.serve(async (request) => {
  if (request.method !== "POST" || request.headers.get("origin")) {
    return reply(405, { ok: false, error: "METHOD_NOT_ALLOWED" });
  }
  const internalKey = request.headers.get("x-pandora-coordinator-key")?.trim() || "";
  const admin = adminClient();
  try {
    await validateInternalKey(admin, internalKey);
    const body = await readBody(request);
    const action = typeof body.action === "string" ? body.action : "";
    if (action === "promoteSnapshot") {
      return reply(200, await handleSnapshotPromotion(admin, internalKey, body));
    }
    if (action === "abortSnapshot") {
      return reply(200, await handleSnapshotAbort(admin, internalKey, body));
    }
    if (action === "readSnapshot") {
      return reply(200, { ok: true, action: "readSnapshot", state: await readEffectiveSnapshot(admin, internalKey) });
    }
    if (action === "publish") {
      return reply(200, await handlePublish(admin, internalKey, body));
    }
    if (action === "expire") {
      return reply(200, await handleExpire(admin, internalKey, body));
    }
    if (action === "read") {
      const pullNumber = Number(body.pullRequestNumber);
      if (!Number.isSafeInteger(pullNumber) || pullNumber < 1) throw new Error("INVALID_PULL_REQUEST");
      return reply(200, {
        ok: true,
        action: "read",
        state: publicState(await readState(admin, internalKey, pullNumber)),
      });
    }
    if (action === "claimMerge") return reply(200, await handleClaimMerge(admin, internalKey, body));
    if (action === "completeMerge") return reply(200, await handleCompleteMerge(admin, internalKey, body));
    if (action === "abortMerge") return reply(200, await handleAbortMerge(admin, internalKey, body));
    if (action === "merge") throw new Error("MERGE_TRANSPORT_EXTERNAL");
    throw new Error("UNKNOWN_ACTION");
  } catch (error) {
    const code = error instanceof Error ? error.message : "COORDINATOR_GATE_FAILED";
    const status = code.includes("AUTH") ? 401
      : code === "BODY_TOO_LARGE" ? 413
      : code === "INVALID_JSON" || code === "UNKNOWN_ACTION" || code === "INVALID_PULL_REQUEST" || code === "INVALID_SNAPSHOT_PROMOTION" ? 400
      : code.includes("DISABLED_UNTIL_SHEET_FENCE") ? 409
      : code.includes("NOT_FOUND") ? 404
      : 409;
    return reply(status, { ok: false, error: code });
  }
});
