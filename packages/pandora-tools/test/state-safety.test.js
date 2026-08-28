"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../src");

const ORG = "org_alpha", PROJECT = "project_alpha", ACTOR = "actor_1";
const proposal = (path = "src/a.js") => ({ tool: "write_file", version: 1, arguments: { project_id: PROJECT, environment: "preview", path, content_ref: "artifact://content/a", request_id: "request-0001", idempotency_key: "idem-key-0001" } });
function binding(overrides = {}) {
  return T.approvalBindingFromAction({ proposal: proposal(), organization_id: ORG, project_id: PROJECT, actor_id: ACTOR, environment: "preview", target_resource: "workspace", project_version: "v18", project_state_hash: "state18", risk: T.RISK_LEVELS.HIGH, ...overrides });
}
function grant(overrides = {}) {
  return T.createApprovalGrant(binding(), { approval_id: "approval_1", approved_by: "owner_1", approved_at: "2026-08-28T00:00:00Z", expires_at: "2026-08-29T00:00:00Z", ...overrides });
}
const throwsCode = (fn, code) => assert.throws(fn, (e) => e?.code === code);

test("approval binds exact action, project state, actor, policy and freshness", () => {
  assert.equal(T.validateApprovalGrant(grant(), binding(), { now: new Date("2026-08-28T12:00:00Z") }), true);
  const altered = T.approvalBindingFromAction({ ...binding(), proposal: proposal("src/b.js") });
  throwsCode(() => T.validateApprovalGrant(grant(), altered, { now: new Date("2026-08-28T12:00:00Z") }), "APPROVAL_ACTION_HASH_MISMATCH");
  throwsCode(() => T.validateApprovalGrant(grant(), { ...binding(), project_version: "v19" }, { now: new Date("2026-08-28T12:00:00Z") }), "APPROVAL_PROJECT_VERSION_STALE");
  throwsCode(() => T.validateApprovalGrant(grant(), { ...binding(), project_state_hash: "state19" }, { now: new Date("2026-08-28T12:00:00Z") }), "APPROVAL_PROJECT_STATE_STALE");
  throwsCode(() => T.validateApprovalGrant(grant(), { ...binding(), actor_id: "actor_2" }, { now: new Date("2026-08-28T12:00:00Z") }), "APPROVAL_ACTOR_MISMATCH");
  throwsCode(() => T.validateApprovalGrant(grant(), { ...binding(), policy_version: "policy/2" }, { now: new Date("2026-08-28T12:00:00Z") }), "APPROVAL_POLICY_STALE");
  throwsCode(() => T.validateApprovalGrant(grant(), binding(), { now: new Date("2026-08-30T00:00:00Z") }), "APPROVAL_EXPIRED");
});

test("revoked and consumed one-time approvals fail closed", async () => {
  const store = new T.MemoryApprovalStore();
  await store.put(grant());
  await store.consume("approval_1", binding().action_hash, new Date("2026-08-28T01:00:00Z"));
  const consumed = await store.get("approval_1");
  throwsCode(() => T.validateApprovalGrant(consumed, binding(), { now: new Date("2026-08-28T02:00:00Z") }), "APPROVAL_ALREADY_CONSUMED");
  const another = T.createApprovalGrant(binding(), { approval_id: "approval_2", approved_by: "owner_1", approved_at: "2026-08-28T00:00:00Z", expires_at: "2026-08-29T00:00:00Z" });
  await store.put(another); await store.revoke("approval_2", new Date("2026-08-28T01:00:00Z"));
  const revoked = await store.get("approval_2");
  throwsCode(() => T.validateApprovalGrant(revoked, binding(), { now: new Date("2026-08-28T02:00:00Z") }), "APPROVAL_REVOKED");
});

test("idempotency replays successes and blocks action-hash changes and ambiguity", async () => {
  const store = new T.MemoryIdempotencyStore(); const c = new T.IdempotencyCoordinator(store); const d = T.TOOL_REGISTRY.write_file;
  const scope = { organization_id: ORG, project_id: PROJECT, environment: "preview", tool: d.name, idempotency_key: "idem-key-0001" };
  const hash = binding().action_hash;
  assert.equal((await c.begin({ definition: d, scope, action_hash: hash, request_id: "r1" })).mode, "execute");
  await c.succeeded(scope, { execution_id: "ex1", status: "succeeded" });
  const replay = await c.begin({ definition: d, scope, action_hash: hash, request_id: "r2" });
  assert.equal(replay.mode, "replay"); assert.equal(replay.receipt.execution_id, "ex1");
  await assert.rejects(c.begin({ definition: d, scope, action_hash: "f".repeat(64), request_id: "r3" }), (e) => e?.code === "IDEMPOTENCY_KEY_REUSED_FOR_DIFFERENT_ACTION");
  const scope2 = { ...scope, idempotency_key: "idem-key-0002" };
  await c.begin({ definition: d, scope: scope2, action_hash: hash, request_id: "r4" }); await c.ambiguous(scope2, { error_class: "network" });
  await assert.rejects(c.begin({ definition: d, scope: scope2, action_hash: hash, request_id: "r5" }), (e) => e?.code === "AMBIGUOUS_PRIOR_MUTATION");
});

test("failed-safe idempotent mutation may resume but active mutation may not duplicate", async () => {
  const store = new T.MemoryIdempotencyStore(); const c = new T.IdempotencyCoordinator(store); const d = T.TOOL_REGISTRY.write_file;
  const scope = { organization_id: ORG, project_id: PROJECT, environment: "preview", tool: d.name, idempotency_key: "idem-key-0003" }; const hash = binding().action_hash;
  await c.begin({ definition: d, scope, action_hash: hash, request_id: "r1" });
  await assert.rejects(c.begin({ definition: d, scope, action_hash: hash, request_id: "r2" }), (e) => e?.code === "MUTATION_ALREADY_IN_PROGRESS");
  await c.failedSafe(scope, { error_class: "timeout", mutation_started: false });
  const resumed = await c.begin({ definition: d, scope, action_hash: hash, request_id: "r3" }); assert.equal(resumed.retry, true);
});

test("mutation lease enforces expected version, exclusivity, expiry and release", async () => {
  const manager = new T.MutationLeaseManager(new T.MemoryLeaseStore());
  await assert.rejects(manager.acquire({ resource_key: "db:project_alpha", owner_id: "job1", expected_version: "v1", current_version: "v2" }), (e) => e?.code === "EXPECTED_STATE_MISMATCH");
  const lease = await manager.acquire({ resource_key: "db:project_alpha", owner_id: "job1", expected_version: "v2", current_version: "v2", ttl_ms: 1000, now: new Date("2026-08-28T00:00:00Z") });
  await assert.rejects(manager.acquire({ resource_key: "db:project_alpha", owner_id: "job2", ttl_ms: 1000, now: new Date("2026-08-28T00:00:00.500Z") }), (e) => e?.code === "MUTATION_LOCKED");
  await assert.rejects(manager.assertActive(lease, new Date("2026-08-28T00:00:02Z")), (e) => e?.code === "LEASE_EXPIRED");
  assert.equal(await manager.release(lease), true);
});

test("rate limiter is scoped and deterministic", async () => {
  const guard = new T.RateLimitGuard(new T.MemoryRateLimitStore());
  const scope = { organization_id: ORG, project_id: PROJECT, model_run_id: "mr1", build_job_id: "b1", tool: "request_build", environment: "preview" };
  await guard.consume(scope, { max_calls: 2, window_ms: 60_000 }, new Date("2026-08-28T00:00:00Z"));
  await guard.consume(scope, { max_calls: 2, window_ms: 60_000 }, new Date("2026-08-28T00:00:01Z"));
  await assert.rejects(guard.consume(scope, { max_calls: 2, window_ms: 60_000 }, new Date("2026-08-28T00:00:02Z")), (e) => e?.code === "TOOL_RATE_LIMIT_EXCEEDED");
  const other = { ...scope, project_id: "project_beta" };
  assert.equal((await guard.consume(other, { max_calls: 2, window_ms: 60_000 }, new Date("2026-08-28T00:00:02Z"))).remaining, 1);
});
