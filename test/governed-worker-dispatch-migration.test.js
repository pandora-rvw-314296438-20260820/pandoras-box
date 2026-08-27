"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.join(__dirname, "..");
const migration = fs.readFileSync(
  path.join(
    root,
    "supabase",
    "migrations",
    "20260823143000_add_governed_owner_worker_dispatch.sql",
  ),
  "utf8",
);
const rollback = fs.readFileSync(
  path.join(
    root,
    "docs",
    "supabase",
    "recovery",
    "jcyqixttuebxqqfkjonq",
    "rollback",
    "20260823143000_disable_governed_owner_worker_dispatch.sql",
  ),
  "utf8",
);

function sqlFunctionBody(name) {
  const match = migration.match(
    new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?\\n\\$\\$;`),
  );
  assert.ok(match, `missing SQL function ${name}`);
  return match[0];
}

test("worker plan claim and one-time dispatch are one guarded transaction", () => {
  assert.match(migration, /private\.owner_command_bindings/);
  assert.match(migration, /request_fingerprint/);
  assert.match(migration, /owner_idempotency_conflict/);
  assert.match(migration, /projectos_create_or_get_worker_plan/);
  assert.match(migration, /unique \(plan_id\)/i);
  assert.match(migration, /status = 'staged'/);
  assert.match(migration, /public\.claim_execution_plan\(p_organization_id, plan\.id\)/);
  assert.match(migration, /set status = 'queued'/);
  assert.match(migration, /guard_governed_worker_plan_claim/);
  assert.match(migration, /worker plan requires an atomically staged dispatch/);
  assert.match(migration, /worker plan requires reviewer-gated finalization/);
});

test("worker plan identity is exact, write-risk, and cannot mutate production", () => {
  assert.match(migration, /p_tool = 'projectos\.worker\.verify'/);
  assert.match(migration, /p_risk = 'write'/);
  assert.match(
    migration,
    /p_args -> 'schemaVersion' is not distinct from '1'::jsonb/,
  );
  assert.match(
    migration,
    /p_args -> 'productionMutationAllowed' is not distinct from 'false'::jsonb/,
  );
  assert.match(migration, /p_args \?& array\[/);
  assert.match(migration, /pandora-rvw-314296438-20260820\/pandoras-box/);
  assert.match(migration, /exactSha'.*\^\[0-9a-f\]\{40\}\$/s);
  assert.match(migration, /jsonb_object_keys[\s\S]*= 6/);
  assert.match(migration, /node_regression/);
  assert.match(migration, /supabase_migration_replay/);
  assert.doesNotMatch(migration, /arbitrary_shell|callerCommand|flutter_mobile_verify/);
});

test("worker eligibility uses a fresh pre-existing builder proof and polling cannot promote health", () => {
  assert.match(migration, /projectos_agent_runtime_proofs/);
  assert.match(migration, /verified_at >= now\(\) - interval '2 hours'/);
  assert.match(migration, /context_updated_at >= now\(\) - interval '30 minutes'/);
  assert.match(migration, /credential_state = 'ready'/);
  assert.match(migration, /health_state = 'healthy'/);
  assert.match(migration, /active_leases < proof\.max_concurrent_leases/);
  assert.doesNotMatch(migration, /upsert_agent_runtime_proof|refreshRuntimeProof/);
  assert.doesNotMatch(migration, /independent worker runtime proof unavailable/);
});

test("signature, nonce, lease, exact job, and evidence bindings fail closed", () => {
  assert.match(migration, /compute_worker_nonces/);
  assert.match(migration, /nonce_sha256/);
  assert.match(migration, /expires_at.*15 minutes/s);
  assert.match(migration, /for update skip locked[\s\S]*limit 128/);
  assert.match(migration, /active_nonce_count >= 2048/);
  assert.match(migration, /nonce already used/);
  assert.match(migration, /job_digest.*\^\[0-9a-f\]\{64\}\$/s);
  assert.match(migration, /runnerImageDigest/);
  assert.match(migration, /acquisitionImageDigest/);
  assert.match(migration, /networkPolicy.*none/s);
  assert.match(migration, /isolation.*hyperv_container/s);
  assert.match(migration, /LEASE_EXPIRED_OUTCOME_UNKNOWN/);
  assert.match(migration, /UNSIGNED_LEASE_EXPIRED_REQUEUED/);
  assert.match(migration, /status = 'ambiguous'/);
  assert.match(
    migration,
    /p_evidence_sha256 is distinct from\s+private\.projectos_worker_evidence_hash/,
  );
  assert.match(migration, /tests_discovered < 1/);
  assert.match(migration, /sourceTreeSha'.*\^\[0-9a-f\]\{40\}\$/s);
});

test("worker output is attested report-only and a separate reviewer finalizes", () => {
  const report = sqlFunctionBody("finish_governed_worker_dispatch");
  const verify = sqlFunctionBody("verify_governed_worker_dispatch");
  assert.match(report, /set status = 'result_reported'/);
  assert.match(report, /'reviewRequired', true/);
  assert.doesNotMatch(report, /public\.finish_execution_plan/);
  assert.match(verify, /proof\.role = 'reviewer'/);
  assert.match(verify, /proof\.agent_key <> dispatch\.worker_identity/);
  assert.match(verify, /proof\.verified_by <> proof\.agent_key/);
  assert.match(verify, /require_independent_vendor_review/);
  assert.match(verify, /evidence_type <> 'worker_dispatch_review'/);
  assert.match(verify, /workerEvidenceSha256/);
  assert.match(
    verify,
    /from public\.projectos_evidence evidence[\s\S]*and evidence\.invalidated_at is null[\s\S]*for update/,
  );
  assert.match(verify, /set status = 'finalizing'/);
  assert.match(verify, /public\.finish_execution_plan/);
});

test("worker key enrollment is bound to an approved exact registration plan", () => {
  const register = sqlFunctionBody("register_compute_worker_identity");
  assert.match(register, /p_registration_plan_id uuid/);
  assert.match(register, /projectos\.worker\.identity\.register/);
  assert.match(register, /registration_plan\.args <> expected_args/);
  assert.match(register, /projectos_worker_identity_plan_payload_hash/);
  assert.match(register, /active worker identity must be disabled before rotation/);
  assert.match(register, /pg_catalog\.pg_advisory_xact_lock/);
  assert.match(register, /projectos:compute-worker:/);
  assert.ok(
    register.indexOf("pg_catalog.pg_advisory_xact_lock") <
      register.indexOf("select * into existing_worker"),
    "worker enrollment lock must precede the registry lookup",
  );
  assert.match(register, /public\.claim_execution_plan/);
  assert.match(register, /public\.finish_execution_plan/);
});

test("all worker tables are private and RPCs are service-role-only", () => {
  assert.match(migration, /enable row level security/g);
  assert.match(migration, /revoke all on table private\.execution_dispatch_outbox/);
  assert.match(migration, /revoke all on table private\.compute_worker_identities/);
  assert.match(migration, /revoke all on table private\.compute_worker_nonces/);
  assert.match(migration, /from public, anon, authenticated/g);
  assert.match(migration, /to service_role/g);
  assert.doesNotMatch(migration, /grant all on table private\./i);
  assert.match(migration, /revoke all on table private\.execution_dispatch_outbox from service_role/);
});

test("rollback freezes capability but preserves historical evidence and the claim guard", () => {
  assert.match(rollback, /Historical plan, dispatch, result, and audit evidence is intentionally retained/);
  assert.match(rollback, /set status = 'draining'/);
  assert.match(rollback, /ROLLBACK_OUTCOME_REQUIRES_RECONCILIATION/);
  assert.match(rollback, /capability_rollback_before_delivery/);
  assert.match(rollback, /revoke all on function public\.claim_governed_worker_dispatch/);
  assert.doesNotMatch(rollback, /drop table|truncate|delete from/i);
  assert.doesNotMatch(rollback, /drop trigger.*guard_governed_worker_plan_claim/i);
  assert.doesNotMatch(rollback, /drop function if exists public\.finish_governed_worker_dispatch/);
  assert.doesNotMatch(rollback, /drop function if exists public\.verify_governed_worker_dispatch/);
});

test("Node and database share one fixed execution payload hash vector", async () => {
  const { workerPlanPayloadHash } = await import(
    "../supabase/functions/pandora-owner-api/command-pipeline.mjs"
  );
  const hash = await workerPlanPayloadHash({
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    jobClass: "node_regression",
  });
  assert.equal(
    hash,
    "c54926de0d4796cd926ceb82cf8fba69d19698695fc9f128b47a61953605f130",
  );
  assert.match(
    migration,
    /\{\"tool\":\"projectos\.worker\.verify\",\"args\":\{\"exactSha\":\"/,
  );
});
