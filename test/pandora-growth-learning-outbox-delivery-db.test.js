"use strict";

const assert = require("node:assert/strict");
const { createHash, createHmac } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { projectGrowthLearningCandidate } = require("../src/pandora-growth-learning-schema.js");

const root = path.resolve(__dirname, "..");
const read = (name) => fs.readFileSync(path.join(root, "supabase/migrations", name), "utf8");
const migration = read("20260929040000_growth_learning_outbox_delivery_v1.sql");
const lifecycle = read("20260807083337_projectos_memory_lifecycle_enforcement.sql");
const visible = read("20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql");
const transport = read("20260903021000_pandora_project_memory_decision_transport_v2.sql");
const reconciliation = read("20260903013000_pandora_visible_memory_response_contract_v2.sql");
const fencing = read("20260929013000_pandora_learning_outbox_fencing_v2.sql");
const scope = Object.freeze({
  organization_id: "2270b266-59da-4c39-bfd9-9f8d08352af0",
  project_id: "ee282126-3f61-4058-8c92-2fedbfcecf1f",
});
const kinds = ["verified_fact", "user_decision", "provider_evidence", "inference", "assumption", "superseded"];
const sha = (value) => createHash("sha256").update(value).digest("hex");
const canonical = (value) => Array.isArray(value)
  ? `[${value.map(canonical).join(",")}]`
  : value !== null && typeof value === "object"
    ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`
    : JSON.stringify(value);

// The wire fixture follows PR804 2822a8e64bc606192728816b333c0d112d22c55e.
// The real FB025 projector creates every candidate; no simulated provider result
// is reported as runtime evidence. Cross-repository parity is checked separately.
function input(kind = "verified_fact", id = `synthetic-${kind}`) {
  const authorities = {
    verified_fact: ["independent_verification", "verification"],
    user_decision: ["owner_decision", "owner"],
    provider_evidence: ["provider_readback", "provider"],
    inference: ["model_inference", "model"],
    assumption: ["assumption", "model"],
    superseded: ["supersession", "verification"],
  };
  return {
    schema_version: "growth-learning-v1", learning_id: id, ...scope,
    subject_key: "growth.synthetic", claim_kind: kind,
    statement: `Synthetic ${kind} fixture; no provider action occurred.`,
    observed_at: "2026-09-29T00:00:00.000Z",
    validity: { effective_at: "2026-09-29T00:00:00.000Z", review_due_at: "2026-10-29T00:00:00.000Z", expires_at: null },
    confidence: 1e-7, confidence_basis: "Synthetic offline contract fixture.",
    authority: { kind: authorities[kind][0], ref: "fixture:authority" },
    provenance: { source_type: authorities[kind][1], source_locator: "fixture:source", source_sha: null, observed_at: "2026-09-29T00:00:00.000Z" },
    evidence_refs: kind === "assumption" || kind === "user_decision" ? [] : [{ type: "fixture", ref: "fixture:evidence" }],
    supersession: kind === "superseded" ? { supersedes_ref: "fixture:prior", reason: "Synthetic replacement only." } : null,
  };
}

function rebind(payload) {
  payload.context_hash = sha(canonical(payload.growth_learning));
  const bytes = Buffer.from(sha(`growth-learning-request-v1\n${payload.context_hash}`).slice(0, 32), "hex");
  bytes[6] = (bytes[6] & 15) | 80;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.toString("hex");
  payload.source_event_id = [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-");
  payload.source_request_id = payload.source_event_id;
  payload.result_fingerprint = payload.growth_learning.candidate.content_hash;
  return payload;
}

function payloadFor(value = input()) {
  const candidate = projectGrowthLearningCandidate(value, scope);
  return rebind({
    schema_version: 1, product_key: "projectos", source_event_id: "", source_request_id: "",
    organization_id: scope.organization_id, intake_id: null,
    project_id: "7c686cbd-d968-49d5-86cc-918f5e777bd2", project_key: "mcpmaster-pandoras-box",
    tool: "facebook.growth_learning", risk: "write", outcome_status: "completed", duration_ms: 0,
    completed_at: candidate.observed_at, context_status: "available", context_hash: "",
    result_fingerprint: candidate.content_hash, error_fingerprint: null, privacy_policy: "metadata_only_v1",
    learning_kind: "growth_learning_v1",
    growth_learning: {
      schema_version: "growth-learning-outbox-binding-v1", source_scope: { ...scope },
      target_memory: { project_id: "7c686cbd-d968-49d5-86cc-918f5e777bd2", project_key: "mcpmaster-pandoras-box", namespace: "real_life", principal_key: "projectos-mcpmaster-production", environment: "production" },
      candidate,
    },
  });
}

function receipt(payload, overrides = {}) {
  return {
    ok: true, status: "pending_review", source_event_id: payload.source_event_id,
    learning_id: payload.growth_learning.candidate.source_event_id,
    content_hash: payload.growth_learning.candidate.content_hash,
    candidate_id: "11111111-1111-4111-8111-111111111111",
    review_item_id: "22222222-2222-4222-8222-222222222222",
    review_required: true, canonical_memory_written: false,
    promotion_status: "not_promoted", retrieval_status: "not_retrievable", deduplicated: false,
    ...overrides,
  };
}

function reviewedReceipt(payload, reviewStatus = "approved_for_append", overrides = {}) {
  return {
    ok: true, status: "already_reviewed", source_event_id: payload.source_event_id,
    learning_id: payload.growth_learning.candidate.source_event_id,
    content_hash: payload.growth_learning.candidate.content_hash,
    candidate_id: "11111111-1111-4111-8111-111111111111",
    review_item_id: "22222222-2222-4222-8222-222222222222",
    review_status: reviewStatus, deduplicated: true,
    ...overrides,
  };
}

function definition(source, name) {
  const start = source.indexOf(`create or replace function ${name}(`);
  assert.notEqual(start, -1, name);
  const tail = source.slice(start);
  const match = /\bas (\$[a-zA-Z_]*\$)/.exec(tail);
  assert.ok(match, name);
  return tail.slice(0, tail.indexOf(`${match[1]};`, match.index + match[0].length) + match[1].length + 1);
}

let imports;
async function makeDb({ beforeMigration } = {}) {
  imports ??= Promise.all([import("@electric-sql/pglite"), import("@electric-sql/pglite/contrib/pgcrypto")]);
  const [{ PGlite }, { pgcrypto }] = await imports;
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema private; create schema extensions; create schema net;
    create extension pgcrypto with schema extensions;
    create table private.execution_plans(id uuid primary key);
    create table private.integration_secrets(secret_name text primary key,secret_value text);
    insert into private.integration_secrets values ('projectos_memory_learning_hmac','synthetic-local-test-key');
    create table net.test_requests(id bigserial primary key,url text,headers jsonb,body jsonb,timeout_milliseconds integer);
    create table net._http_response(id bigint,status_code integer,content text,error_msg text,timed_out boolean,created timestamptz default now());
    create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer)
    returns bigint language plpgsql as $$ declare request_id bigint; begin
      insert into net.test_requests(url,headers,body,timeout_milliseconds)
      values(url,headers,body,timeout_milliseconds) returning id into request_id;
      return request_id;
    end $$;
  `);
  // Execute the real durable table/index DDL and actual transport functions.
  await db.exec(lifecycle.slice(lifecycle.indexOf("create table if not exists private.execution_learning_outbox"), lifecycle.indexOf("create or replace function private.execution_learning_signature_basis")));
  await db.exec(visible.slice(visible.indexOf("alter table private.execution_learning_outbox"), visible.indexOf("create or replace function private.visible_creation_evidence_basis")));
  await db.exec(definition(lifecycle, "private.execution_learning_signature_basis"));
  await db.exec(definition(transport, "private.dispatch_execution_learning"));
  await db.exec(definition(reconciliation, "private.reconcile_execution_learning_responses"));
  await db.exec(fencing);
  if (beforeMigration) await beforeMigration(db);
  await db.exec(migration);
  return db;
}

async function valid(db, payload) {
  return (await db.query("select private.pandora_growth_learning_payload_is_valid_v1($1::jsonb) as valid", [JSON.stringify(payload)])).rows[0].valid;
}
async function enqueue(db, payload) {
  return (await db.query("select private.enqueue_growth_learning_v1($1::jsonb) as id", [JSON.stringify(payload)])).rows[0].id;
}
async function accepted(db, payload, content = receipt(payload), status = 202, error = null, timedOut = false) {
  return (await db.query("select private.execution_learning_response_is_valid($1::jsonb,$2,$3,$4,$5) as valid", [JSON.stringify(payload), status, typeof content === "string" ? content : JSON.stringify(content), error, timedOut])).rows[0].valid;
}
async function snapshot(db, id) {
  return (await db.query("select to_jsonb(o) as row from private.execution_learning_outbox o where id=$1", [id])).rows[0].row;
}

test("six epistemic classes and eighteen SHA/number variants survive the real schema and SQL hashes", async () => {
  const db = await makeDb();
  try {
    for (const kind of kinds) for (const sourceSha of [null, "a".repeat(40), "A".repeat(40)]) {
      const value = input(kind, `synthetic-${kind}-${sourceSha === null ? "null" : sourceSha[0]}`);
      value.provenance.source_sha = sourceSha;
      value.statement += " Unicode evidence: café 東京.";
      const payload = payloadFor(value);
      assert.equal(await valid(db, payload), true, `${kind}:${sourceSha}`);
      const id = await enqueue(db, payload);
      const row = await snapshot(db, id);
      assert.deepEqual(row.payload, payload);
      assert.equal(row.project_id, scope.project_id);
      assert.equal(row.payload.project_id, "7c686cbd-d968-49d5-86cc-918f5e777bd2");
      assert.equal(row.payload.growth_learning.candidate.claim_kind, kind);
      assert.equal(row.delivery_status, "pending");
      assert.equal(row.attempt_count, 0);
    }
    assert.equal((await db.query("select count(*)::integer as n from net.test_requests")).rows[0].n, 0);
  } finally { await db.close(); }
});

test("credential scan allows ordinary hyphenated growth text", async () => {
  const db = await makeDb();
  try {
    const value = input("verified_fact", "synthetic-hyphenated-language");
    value.statement = "Use the risk-assessment-framework for task-management-dashboard and desk-research-summary-2026.";
    const payload = payloadFor(value);
    assert.equal(await valid(db, payload), true);
    assert.equal(await enqueue(db, payload) !== null, true);
  } finally { await db.close(); }
});

test("exact replay preserves the entire pending, delivered and failed row; changed semantics conflict", async () => {
  const db = await makeDb();
  try {
    const original = input();
    const payload = payloadFor(original);
    const id = await enqueue(db, payload);
    for (const state of ["pending", "delivered", "failed"]) {
      await db.query("update private.execution_learning_outbox set delivery_status=$2,attempt_count=4 where id=$1", [id, state]);
      const before = await snapshot(db, id);
      assert.equal(await enqueue(db, payload), id);
      assert.deepEqual(await snapshot(db, id), before);
    }
    const changed = payloadFor({ ...original, statement: "A changed synthetic claim with the same learning ID." });
    assert.equal(await valid(db, changed), true);
    await assert.rejects(enqueue(db, changed), (e) => e.code === "23505" && /IDEMPOTENCY_CONFLICT/.test(e.message));
    assert.equal((await db.query("select count(*)::integer as n from private.execution_learning_outbox")).rows[0].n, 1);
  } finally { await db.close(); }
});

test("payload, row binding and stable identity cannot be rewritten through replay", async () => {
  const db = await makeDb();
  try {
    const payload = payloadFor();
    const id = await enqueue(db, payload);
    await db.query("update private.execution_learning_outbox set request_id=gen_random_uuid() where id=$1", [id]);
    await assert.rejects(enqueue(db, payload), /IDEMPOTENCY_CONFLICT/);
    await assert.rejects(db.query(`insert into private.execution_learning_outbox(event_key,organization_id,request_id,project_id,project_key,payload)
      select 'different-event-key',organization_id,gen_random_uuid(),project_id,project_key,payload from private.execution_learning_outbox where id=$1`, [id]), (e) => e.code === "23505");
  } finally { await db.close(); }
});

test("malformed nested JSON is false without throwing and never inserts a row", async () => {
  const db = await makeDb();
  try {
    const base = payloadFor();
    const mutants = [null, [], 1, "text", {}, { ...base, growth_learning: [] }];
    for (const key of ["candidate", "source_scope", "target_memory"]) for (const value of [null, [], 1, "text"]) {
      const p = structuredClone(base); p.growth_learning[key] = value; mutants.push(p);
    }
    for (const key of ["evidence_refs", "confidence", "provenance", "supersession"]) for (const value of [null, {}, [], "bad", true]) {
      if (key === "supersession" && value === null) continue; // A non-superseded candidate must carry JSON null.
      const p = structuredClone(base); p.growth_learning.candidate[key] = value; mutants.push(p);
    }
    for (const p of mutants) {
      assert.equal(await valid(db, p), false);
      await assert.rejects(enqueue(db, p), /OUTBOX_PAYLOAD_INVALID/);
    }
    assert.equal((await db.query("select count(*)::integer as n from private.execution_learning_outbox")).rows[0].n, 0);
  } finally { await db.close(); }
});

test("rehashing cannot legitimize source widening, class changes, invalid dates or coerced JSON types", async () => {
  const db = await makeDb();
  try {
    const changes = [
      (p) => { p.growth_learning.source_scope.organization_id = "11111111-1111-4111-8111-111111111111"; },
      (p) => { p.growth_learning.target_memory.principal_key = "caller-selected"; },
      (p) => { p.growth_learning.candidate.claim_kind = "inference"; },
      (p) => { p.growth_learning.candidate.source_event_id = 123; },
      (p) => { p.growth_learning.candidate.claim = 123; },
      (p) => { p.growth_learning.candidate.confidence = "0.5"; },
      (p) => { p.growth_learning.candidate.observed_at = "2026-02-31T00:00:00.000Z"; p.completed_at = p.growth_learning.candidate.observed_at; },
      (p) => { p.growth_learning.candidate.evidence_refs[0].ref = 123; },
      (p) => { p.growth_learning.candidate.extra = true; },
      (p) => { p.growth_learning.candidate.provenance.source_locator = " Bearer test "; },
    ];
    for (const change of changes) {
      const p = structuredClone(payloadFor()); change(p); rebind(p);
      assert.equal(await valid(db, p), false);
    }
  } finally { await db.close(); }
});

test("strict twelve-field receipts bind source event, learning identity, content and pending-review state", async () => {
  const db = await makeDb();
  try {
    const p = payloadFor();
    assert.equal(await accepted(db, p), true);
    assert.equal(await accepted(db, p, receipt(p, { deduplicated: true }), 200), true);
    const good = receipt(p);
    for (const key of Object.keys(good)) {
      const missing = { ...good }; delete missing[key];
      assert.equal(await accepted(db, p, missing), false, `missing:${key}`);
      assert.equal(await accepted(db, p, { ...good, [key]: null }), false, `null:${key}`);
      for (const value of [123, {}, []]) assert.equal(await accepted(db, p, { ...good, [key]: value }), false, `malformed:${key}`);
    }
    for (const changes of [
      { extra: true }, { source_event_id: "33333333-3333-4333-8333-333333333333" },
      { learning_id: "another-learning" }, { content_hash: "f".repeat(64) },
      { ok: "true" }, { review_required: "true" }, { canonical_memory_written: "false" },
      { deduplicated: "false" }, { candidate_id: "not-a-uuid" }, { review_item_id: "not-a-uuid" },
      { status: "approved" }, { promotion_status: "promoted" }, { retrieval_status: "retrievable" },
    ]) assert.equal(await accepted(db, p, { ...good, ...changes }), false);
    for (const content of ["not-json", "null", "[]", "false", "1", "", { ok: true }]) assert.equal(await accepted(db, p, content), false);
    for (const status of [null, 201, 400, 500]) assert.equal(await accepted(db, p, good, status), false);
    assert.equal(await accepted(db, p, good, 202, "network failure"), false);
    assert.equal(await accepted(db, p, good, 202, null, true), false);
  } finally { await db.close(); }
});

test("already-reviewed replay is an exact terminal receipt and never impersonates pending review", async () => {
  const db = await makeDb();
  try {
    const p = payloadFor();
    for (const status of [
      "needs_clarification","blocked_namespace_mismatch","blocked_sensitive",
      "blocked_policy","approved_for_append","rejected","archived",
    ]) {
      assert.equal(await accepted(db, p, reviewedReceipt(p, status), 200), true, status);
    }
    assert.equal(await accepted(db, p, reviewedReceipt(p), 202), false);
    assert.equal(await accepted(db, p, reviewedReceipt(p, "pending_review"), 200), false);
    assert.equal(await accepted(db, p, reviewedReceipt(p, "approved_for_append", { extra: true }), 200), false);
    assert.equal(await accepted(db, p, reviewedReceipt(p, "approved_for_append", { deduplicated: false }), 200), false);
  } finally { await db.close(); }
});

test("growth markers and unknown or malformed kinds fail closed instead of taking generic success", async () => {
  const db = await makeDb();
  try {
    const base = payloadFor();
    for (const kind of [undefined, null, "", "unknown", "visible_creation_evidence_v1", 1, {}, []]) {
      const p = structuredClone(base);
      if (kind === undefined) delete p.learning_kind; else p.learning_kind = kind;
      assert.equal(await accepted(db, p, { ok: true }), false);
    }
    const p = structuredClone(base); delete p.learning_kind; delete p.growth_learning;
    assert.equal(await accepted(db, p, { ok: true }), false);
    assert.equal(await accepted(db, { tool: "other", learning_kind: "unrecognized" }, { ok: true }), false);
    assert.equal(await accepted(db, { tool: "other", growth_learning: null }, { ok: true }), false);
    for (const malformed of [null, [], 1, "text"]) assert.equal(await accepted(db, malformed, { ok: true }), false);
    assert.equal(await accepted(db, { tool: "existing.generic" }, { ok: true }, 200), true);
  } finally { await db.close(); }
});

test("existing signer and consumer validate only an exact synthetic response before marking delivered", async () => {
  const db = await makeDb();
  try {
    const p = payloadFor();
    const id = await enqueue(db, p);
    const first = (await db.query("select private.dispatch_execution_learning($1) as id", [id])).rows[0].id;
    const request = (await db.query("select * from net.test_requests where id=$1", [first])).rows[0];
    assert.equal(request.url, "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-learning");
    assert.deepEqual(request.body, p);
    const basis = (await db.query("select private.execution_learning_signature_basis($1) as basis", [p])).rows[0].basis;
    const expected = createHmac("sha256", "synthetic-local-test-key").update(`${request.headers["x-pandora-timestamp"]}.${basis}`).digest("hex");
    assert.equal(request.headers["x-pandora-signature"], expected);
    await db.query("insert into net._http_response(id,status_code,content,timed_out) values($1,200,$2,false)", [first, '{"ok":true}']);
    await db.query("select private.reconcile_execution_learning_responses()");
    assert.equal((await snapshot(db, id)).delivery_status, "pending");
    const second = (await db.query("select private.dispatch_execution_learning($1) as id", [id])).rows[0].id;
    assert.notEqual(first, second);
    await db.query("insert into net._http_response(id,status_code,content,timed_out) values($1,202,$2,false)", [second, JSON.stringify(receipt(p))]);
    await db.query("select private.reconcile_execution_learning_responses()");
    const row = await snapshot(db, id);
    assert.equal(row.delivery_status, "delivered");
    assert.equal(row.attempt_count, 2);
    assert.deepEqual(JSON.parse(row.last_response_excerpt), receipt(p));
    assert.equal(row.payload.growth_learning.candidate.canonical_memory_written, false);
  } finally { await db.close(); }
});

test("receipt mismatch exhausts the established attempt bound without creating a new transport", async () => {
  const db = await makeDb();
  try {
    const p = payloadFor(); const id = await enqueue(db, p);
    await db.query("update private.execution_learning_outbox set attempt_count=4 where id=$1", [id]);
    const requestId = (await db.query("select private.dispatch_execution_learning($1) as id", [id])).rows[0].id;
    await db.query("insert into net._http_response(id,status_code,content,timed_out) values($1,202,$2,false)", [requestId, JSON.stringify(receipt(p, { content_hash: "f".repeat(64) }))]);
    await db.query("select private.reconcile_execution_learning_responses()");
    const row = await snapshot(db, id);
    assert.equal(row.delivery_status, "failed"); assert.equal(row.attempt_count, 5);
    assert.equal(row.delivered_at, null);
    assert.equal(await enqueue(db, p), id);
    assert.deepEqual(await snapshot(db, id), row);
  } finally { await db.close(); }
});

test("migration and one new enqueue leave historical generic and public orphan rows untouched", async () => {
  let oldPrivate; let oldPublic;
  const db = await makeDb({ beforeMigration: async (db) => {
    await db.exec(`insert into private.execution_learning_outbox(event_key,organization_id,request_id,project_key,payload,attempt_count)
      values('historical-generic','${scope.organization_id}',gen_random_uuid(),'existing','{}',4);
      insert into public.pandora_verified_learning_outbox(organization_id,activity_job_id,idempotency_key,memory_project_id,learning_kind,learning_summary,promotion_basis,confidence,execution)
      values('${scope.organization_id}',gen_random_uuid(),'historical-orphan',gen_random_uuid(),'outcome','synthetic old row','synthetic',0.5,'{}');`);
    oldPrivate = (await db.query("select to_jsonb(o) as row from private.execution_learning_outbox o")).rows;
    oldPublic = (await db.query("select to_jsonb(o) as row from public.pandora_verified_learning_outbox o")).rows;
  } });
  try {
    await enqueue(db, payloadFor());
    assert.deepEqual((await db.query("select to_jsonb(o) as row from private.execution_learning_outbox o where event_key='historical-generic'")).rows, oldPrivate);
    assert.deepEqual((await db.query("select to_jsonb(o) as row from public.pandora_verified_learning_outbox o")).rows, oldPublic);
  } finally { await db.close(); }
});

test("enqueue remains management-only and existing service response validation remains usable", async () => {
  const db = await makeDb();
  try {
    for (const role of ["anon", "authenticated", "service_role"]) for (const fn of [
      "private.enqueue_growth_learning_v1(jsonb)", "private.pandora_growth_learning_payload_is_valid_v1(jsonb)",
      "private.pandora_canonical_json_v1(jsonb)", "private.pandora_growth_learning_content_json_v1(jsonb)",
    ]) assert.equal((await db.query("select has_function_privilege($1,$2,'execute') as allowed", [role, fn])).rows[0].allowed,
      role === "service_role" && !fn.startsWith("private.enqueue_growth_learning_v1"));
    assert.equal((await db.query("select has_function_privilege('service_role','private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)','execute') as allowed")).rows[0].allowed, true);
    const p = payloadFor();
    await db.exec("grant usage on schema private,extensions to service_role; set role service_role;");
    assert.equal(await accepted(db, p), true);
    assert.equal(await accepted(db, p, { ok: true }), false);
    await assert.rejects(enqueue(db, p), (e) => e.code === "42501");
    await db.exec("reset role;");
    for (const role of ["anon", "authenticated"]) {
      await db.exec(`grant usage on schema private to ${role}; set role ${role};`);
      await assert.rejects(enqueue(db, p), (e) => e.code === "42501");
      await assert.rejects(accepted(db, p), (e) => e.code === "42501");
      await db.exec("reset role;");
    }
    await assert.rejects(db.query("select * from public.pandora_claim_verified_learning_outbox(1)"), /V1_DISABLED/);
  } finally { await db.exec("reset role;"); await db.close(); }
});

test("transport implementation and promotion boundaries remain outside the new migration", () => {
  assert.doesNotMatch(migration, /create or replace function private\.(?:dispatch_execution_learning|process_execution_learning_outbox|reconcile_execution_learning_responses)\(/);
  assert.doesNotMatch(definition(migration, "private.enqueue_growth_learning_v1"), /dispatch_execution_learning|process_execution_learning_outbox|net\.http_post|cron\./);
  assert.doesNotMatch(migration, /(?:insert into|update|delete from)\s+(?:public\.memory_|public\.pandora_verified_learning_outbox|public\.pandora_runtime_provider_configs)/i);
  assert.doesNotMatch(migration, /create\s+(?:table|trigger|policy)|cron\.schedule|https:\/\//i);
  assert.match(migration, /p_status is null/);
  const maximum = payloadFor(input("verified_fact", "x".repeat(256)));
  assert.ok(JSON.stringify(receipt(maximum)).length <= 1000, "bound canonical receipt survives the established excerpt limit");
});
