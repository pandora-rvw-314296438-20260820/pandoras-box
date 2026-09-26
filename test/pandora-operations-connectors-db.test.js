"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID, createHmac } = require("node:crypto");
const { PGlite } = require("@electric-sql/pglite");
const { normalizeTask, digest } = require("../packages/pandora-operations-room/contracts");
const { NativeDeliveryJournal, ConnectorOperationsStore } = require("../packages/pandora-operations-connectors/native-journal.cjs");
const { WorkspaceAgentClient, workerDispatch } = require("../packages/pandora-operations-connectors/workspace-agents.cjs");
const { createWorkerAcknowledgementHandler } = require("../packages/pandora-operations-connectors/worker-callback.cjs");
let db;
async function rpc(name, args) {
  assert.match(name, /^pandora_ops_[a-z0-9_]+$/);
  const keys = Object.keys(args);
  for (const key of keys) assert.match(key, /^p_[a-z_]+$/);
  const values = Object.values(args).map((v) => v !== null && typeof v === "object" && !Array.isArray(v) ? JSON.stringify(v) : v);
  const result = await db.query(`select public.${name}(${keys.map((k, i) => `${k}=>$${i + 1}`).join(",")}) as value`, values);
  return result.rows[0].value;
}
const native = { async rpc(name, args) {
  try { return { data: await rpc(name, args), error: null }; }
  catch (e) { return { data: null, error: { message: e.message, code: e.code } }; }
} };
const callbackClock = () => 1790379600000;
const signingKey = () => Buffer.alloc(32, 7); // Synthetic fixture only; never provisioned to a provider.
test.before(async () => {
  db = await PGlite.create();
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema private; create schema extensions;
    create table public.organizations(id uuid primary key);
    create table public.memberships(organization_id uuid,user_id uuid,role text,status text);
    create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,project_id uuid not null,status text not null,source_commit text,required_check_profile text,completed_at timestamptz);
    create function extensions.digest(data bytea,algorithm text) returns bytea language plpgsql immutable as $$ begin if algorithm<>'sha256' then raise exception 'unsupported digest'; end if; return pg_catalog.sha256(data); end $$;`);
  await db.exec(fs.readFileSync(path.join(__dirname, "../supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql"), "utf8"));
  await db.exec(fs.readFileSync(path.join(__dirname, "../packages/pandora-operations-connectors/delivery-schema.sql"), "utf8"));
});
test.after(async () => { await db?.close(); });
async function fixture() {
  const org = randomUUID(), project = randomUUID();
  const args = { p_organization_id: org, p_project_id: project };
  await db.query("insert into public.organizations(id) values($1)", [org]);
  await rpc("pandora_ops_project_binding_v1", { ...args, p_state: "active", p_evidence_ref: "fixture:owner-project" });
  await rpc("pandora_ops_initialize_v1", { ...args, p_budget_micros: 100, p_max_concurrency: 2 });
  await rpc("pandora_ops_register_worker_v1", { ...args, p_worker_key: "fixture-worker", p_principal_key: "fixture-principal",
    p_lanes: ["backend"], p_capabilities: ["source.write"], p_capacity: 1, p_receipt_ref: "fixture:authenticated-enrollment" });
  const spec = normalizeTask({ id: "connector-task", title: "Synthetic connector source task", lane: "backend", priority: 0,
    dependsOn: [], resources: [{ key: "source/fixture", mode: "write" }], requiredCapabilities: ["source.write"],
    maxCostMicros: 0, maxDurationSeconds: 600, maxAttempts: 2, risk: "source", acceptance: ["fixture exact source tests"],
    source: { repository: "pandora-rvw-314296438-20260820/pandoras-box", baseSha: "a".repeat(40) } });
  await rpc("pandora_ops_ingest_v1", { ...args, p_tasks: JSON.stringify([spec]) });
  await rpc("pandora_ops_control_v1", { ...args, p_expected_revision: 0, p_action: "resume" });
  const claim = await rpc("pandora_ops_claim_v1", { ...args, p_task_key: spec.id, p_worker_key: "fixture-worker", p_task_revision: 0, p_control_revision: 1 });
  assert.equal(claim.claimed, true);
  const intent = await rpc("pandora_ops_dispatch_v1", { ...args, p_lease_id: claim.leaseId, p_generation: 1 });
  assert.equal(intent.canSend, true);
  const binding = { organizationId: org, projectId: project, workerId: "fixture-worker", principalKey: "fixture-principal", channelId: "agtch_fixture" };
  let triggerCount = 0;
  const agent = new WorkspaceAgentClient({ binding, getAccessToken: () => "fixture-only-credential",
    fetchImpl: async () => { triggerCount++; return new Response(JSON.stringify({ agent_trigger_run_id: "apirun_fixture", conversation_url: "https://chatgpt.com/c/fixture" }),
      { status: 202, headers: { "content-type": "application/json" } }); } });
  const raw = { organizationId: org, projectId: project, workerId: "fixture-worker", principalKey: "fixture-principal",
    taskId: spec.id, dispatchId: intent.dispatchId, leaseId: claim.leaseId, generation: 1 };
  const envelope = agent.envelope(raw);
  const journal = new NativeDeliveryJournal({ client: native, scope: { organizationId: org, projectId: project } });
  const store = new ConnectorOperationsStore(native);
  return { args, org, project, binding, claim, intent, raw, envelope, agent, journal, store,
    scope: { organizationId: org, projectId: project }, triggers: () => triggerCount };
}
async function deliver(f) {
  const input = "fixture approved input";
  const requestDigest = digest({ envelope: f.envelope, input });
  const prepared = await f.journal.prepare(f.envelope, requestDigest);
  assert.equal(prepared.canSend, true);
  await f.journal.authorizeSend(f.envelope);
  const receipt = await f.agent.trigger(f.raw, input);
  await f.journal.recordDelivery(f.envelope, receipt);
  return receipt;
}
function callbackRequest(f, { wrongKey = false, offset = 0, envelope = f.envelope, runId = "apirun_fixture", extra = {} } = {}) {
  const body = JSON.stringify({ envelope, runId, accepted: true, ...extra });
  const timestamp = String(Math.floor(callbackClock() / 1000) + offset);
  const signature = createHmac("sha256", wrongKey ? Buffer.alloc(32, 8) : signingKey()).update(timestamp).update(".").update(body).digest("hex");
  return new Request("https://fixture.invalid/worker/ack", { method: "POST", body,
    headers: { "content-type": "application/json", "x-pandora-timestamp": timestamp, "x-pandora-signature": `sha256=${signature}` } });
}
function callback(f) {
  return createWorkerAcknowledgementHandler({ agentClient: f.agent, journal: f.journal, getSigningKey: signingKey, clock: callbackClock });
}
test("DB connector objects are private, deny table access and admit only service RPCs", async () => {
  const result = await db.query(`select c.relrowsecurity as rls,
    has_table_privilege('anon',c.oid,'SELECT') as anon_read,
    has_table_privilege('authenticated',c.oid,'INSERT') as auth_insert,
    has_table_privilege('service_role',c.oid,'UPDATE') as service_update,
    has_function_privilege('anon','public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb)','EXECUTE') as anon_rpc,
    has_function_privilege('service_role','public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb)','EXECUTE') as service_rpc
    from pg_class c where c.oid='private.pandora_ops_connector_deliveries'::regclass`);
  assert.deepEqual(result.rows[0], { rls: true, anon_read: false, auth_insert: false, service_update: false, anon_rpc: false, service_rpc: true });
});
test("DB exact prepare grants one sender and retains request identity", async () => {
  const f = await fixture(), d = digest("input");
  assert.equal((await f.journal.prepare(f.envelope, d)).canSend, true);
  assert.equal((await f.journal.prepare(f.envelope, d)).canSend, false);
  await assert.rejects(() => f.journal.prepare(f.envelope, digest("changed")), /REQUEST_CONFLICT/);
});
test("DB rejects foreign project, principal and generation", async () => {
  const f = await fixture();
  await assert.rejects(() => f.journal.prepare({ ...f.envelope, projectId: randomUUID() }, digest("x")), /SCOPE_DENIED/);
  await assert.rejects(() => f.journal.prepare({ ...f.envelope, principalKey: "other" }, digest("x")), /PRINCIPAL_MISMATCH/);
  await assert.rejects(() => f.journal.prepare({ ...f.envelope, generation: 2 }, digest("x")), /LEASE_MISMATCH/);
});
test("DB immutable envelope prevents channel substitution and history deletion", async () => {
  const f = await fixture(); await f.journal.prepare(f.envelope, digest("x"));
  await assert.rejects(() => f.journal.prepare({ ...f.envelope, channelId: "agtch_other" }, digest("x")), /ENVELOPE_CONFLICT/);
  await assert.rejects(() => db.query("delete from private.pandora_ops_connector_deliveries where dispatch_id=$1", [f.intent.dispatchId]), /HISTORY_IMMUTABLE/);
});
test("DB rechecks pause at the actual send boundary", async () => {
  const f = await fixture(); await f.journal.prepare(f.envelope, digest("x"));
  await rpc("pandora_ops_control_v1", { ...f.args, p_expected_revision: 1, p_action: "pause" });
  await assert.rejects(() => f.journal.authorizeSend(f.envelope), /EXECUTION_FENCED/);
});
test("DB rechecks project revocation at send boundary", async () => {
  const f = await fixture(); await f.journal.prepare(f.envelope, digest("x"));
  await rpc("pandora_ops_project_binding_v1", { ...f.args, p_state: "revoked", p_evidence_ref: "fixture:revocation" });
  await assert.rejects(() => f.journal.authorizeSend(f.envelope), /EXECUTION_FENCED/);
});
test("DB keeps provider queue receipt separate from actual worker start", async () => {
  const f = await fixture(); const receipt = await deliver(f);
  const read = await f.journal.read(f.envelope);
  assert.deepEqual(read.receipt, receipt); assert.equal(read.acknowledgement, null);
  const result = await db.query("select state from private.pandora_ops_leases where id=$1", [f.claim.leaseId]);
  assert.equal(result.rows[0].state, "dispatching");
});
test("DB uncertain delivery retains identity and prevents automatic replay", async () => {
  const f = await fixture(); const d = digest("x");
  await f.journal.prepare(f.envelope, d); await f.journal.markUnknown(f.envelope);
  assert.equal((await f.journal.prepare(f.envelope, d)).canSend, false);
  await assert.rejects(() => f.journal.authorizeSend(f.envelope), /SEND_FENCED/);
});
test("DB accepts late delivery evidence after lease expiry without authorizing a send", async () => {
  const f = await fixture(); const input = "fixture approved input";
  await f.journal.prepare(f.envelope, digest({ envelope: f.envelope, input }));
  const receipt = await f.agent.trigger(f.raw, input);
  await db.query("update private.pandora_ops_leases set expires_at=clock_timestamp()-interval '1 second' where id=$1", [f.claim.leaseId]);
  await f.journal.recordDelivery(f.envelope, receipt);
  assert.equal((await f.journal.read(f.envelope)).receipt.runId, "apirun_fixture");
  await assert.rejects(() => f.journal.authorizeSend(f.envelope), /EXECUTION_FENCED/);
});
test("DB rejects changed provider receipt and premature ACK", async () => {
  const f = await fixture(); const receipt = await deliver(f);
  await assert.rejects(() => f.journal.recordDelivery(f.envelope, { ...receipt, runId: "apirun_other" }), /RECEIPT_CONFLICT/);
  await assert.rejects(() => f.journal.acknowledge(f.envelope, { accepted: true }), /AUTHENTICATED_ACK_REQUIRED/);
});
test("Signed callback advances only the original task and retained lease", async () => {
  const f = await fixture(); await deliver(f);
  const response = await callback(f)(callbackRequest(f));
  assert.equal(response.status, 200);
  const result = await db.query("select l.state,t.status,l.generation from private.pandora_ops_leases l join private.pandora_ops_tasks t on t.organization_id=l.organization_id and t.project_id=l.project_id and t.task_key=l.task_key where l.id=$1", [f.claim.leaseId]);
  assert.deepEqual(result.rows[0], { state: "running", status: "implementing", generation: 1 });
  assert.equal(f.triggers(), 1);
});
test("Delayed signed ACK recovers the same lease after uncertain-delivery reconciliation", async () => {
  const f = await fixture(); await deliver(f);
  await f.store.markReconciliationRequired(f.scope, f.claim, { code: "DISPATCH_OUTCOME_UNKNOWN" });
  assert.equal((await callback(f)(callbackRequest(f))).status, 200);
  const result = await db.query("select state from private.pandora_ops_leases where id=$1", [f.claim.leaseId]);
  assert.equal(result.rows[0].state, "running"); assert.equal(f.triggers(), 1);
});
test("A stale dispatch error cannot overwrite an already authenticated running ACK", async () => {
  const f = await fixture(); await deliver(f);
  assert.equal((await callback(f)(callbackRequest(f))).status, 200);
  const result = await f.store.markReconciliationRequired(f.scope, f.claim, { code: "DISPATCH_OUTCOME_UNKNOWN" });
  assert.equal(result.reconciliationRequired, false); assert.equal(result.workerAcknowledged, true);
});
test("Signed callback replay is idempotent and never re-triggers the provider", async () => {
  const f = await fixture(); await deliver(f); const handler = callback(f);
  assert.equal((await handler(callbackRequest(f))).status, 200);
  assert.equal((await handler(callbackRequest(f))).status, 200);
  assert.equal(f.triggers(), 1);
  const count = await db.query("select count(*)::int as n from private.pandora_ops_events where organization_id=$1 and project_id=$2 and event_type='worker_started'", [f.org, f.project]);
  assert.equal(count.rows[0].n, 1);
});
for (const options of [{ wrongKey: true }, { offset: -301 }, { offset: 31 }, { runId: "apirun_foreign" }])
  test(`Signed callback rejects ${JSON.stringify(options)}`, async () => {
    const f = await fixture(); await deliver(f);
    assert.notEqual((await callback(f)(callbackRequest(f, options))).status, 200);
    assert.equal(await f.journal.readAcknowledgement(f.envelope), null);
  });
test("Signed callback rejects extra payload fields and browser origin", async () => {
  const f = await fixture(); await deliver(f); const handler = callback(f);
  assert.notEqual((await handler(callbackRequest(f, { extra: { grantAdmin: true } }))).status, 200);
  const request = callbackRequest(f); request.headers.set("origin", "https://example.invalid");
  assert.equal((await handler(request)).status, 403);
});
test("Signed callback does not override cancellation or expired generation", async () => {
  const f = await fixture(); await deliver(f);
  await rpc("pandora_ops_control_v1", { ...f.args, p_expected_revision: 1, p_action: "cancel_task", p_task_key: f.raw.taskId });
  assert.equal((await callback(f)(callbackRequest(f))).status, 401);
  assert.equal(await f.journal.readAcknowledgement(f.envelope), null);
});
test("Native transport returns the same core ACK after authenticated callback readback", async () => {
  const f = await fixture(); await deliver(f);
  assert.equal((await callback(f)(callbackRequest(f))).status, 200);
  const dispatch = workerDispatch({ client: f.agent, journal: f.journal,
    getInput: async () => "fixture approved input", authorizeSend: (e) => f.journal.authorizeSend(e),
    readAcknowledgement: (e) => f.journal.readAcknowledgement(e) });
  const ack = await dispatch({ scope: f.scope, claim: f.claim, dispatchId: f.intent.dispatchId });
  await f.store.acknowledgeDispatch(f.scope, f.claim, ack);
  assert.equal(ack.accepted, true); assert.equal(f.triggers(), 1);
});
