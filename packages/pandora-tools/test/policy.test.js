"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../src");
const O = "org_alpha", P = "project_alpha";
const actor = (capabilities, organization_id = O) => ({ id: "actor_1", organization_id, capabilities });
function input(definition, args, capabilities, extra = {}) {
  return { definition, args, actor: actor(capabilities), organization_id: O, project: { id: P, organization_id: O, version_id: "v18" }, environment: args.environment, resource: { project_id: P, organization_id: O }, ...extra };
}
const write = { project_id: P, environment: "preview", path: "src/a.js", content_ref: "artifact://a/content", request_id: "request-0001", idempotency_key: "idem-key-0001" };

test("policy binds organization, project, environment and capabilities", () => {
  let r = T.evaluatePolicy(input(T.TOOL_REGISTRY.read_file, { project_id: P, environment: "preview", path: "src/a.js" }, ["workspace.files.read"], { actor: actor(["workspace.files.read"], "org_other") }));
  assert.equal(r.reason_code, "CROSS_ORG_ACCESS");
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.read_file, { project_id: P, environment: "preview", path: "src/a.js" }, ["workspace.files.read"], { resource: { project_id: "project_other", organization_id: O } }));
  assert.equal(r.reason_code, "CROSS_PROJECT_ACCESS");
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.write_file, write, [])); assert.equal(r.reason_code, "CAPABILITY_MISSING");
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.write_file, { ...write, project_id: "project_other" }, ["workspace.files.write"])); assert.equal(r.reason_code, "PROJECT_BINDING_MISMATCH");
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.write_file, { ...write, environment: "development" }, ["workspace.files.write"], { environment: "preview" })); assert.equal(r.reason_code, "ENVIRONMENT_BINDING_MISMATCH");
});

test("preview capability never authorizes production mutation", () => {
  const args = { project_id: P, environment: "production", version_id: "v18", verification_run_id: "vr18", preview_id: "pr18", artifact_digest: "a".repeat(64), target_environment: "production", request_id: "request-0001", idempotency_key: "idem-key-0001" };
  const verification = { status: "passed", run_id: "vr18", project_id: P, version_id: "v18", artifact_digest: "a".repeat(64), project_spec_version: "s4", migration_state_version: "m8" };
  const r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_publish, args, ["production.publish"], { verification, project_spec_version: "s4", migration_state_version: "m8" }));
  assert.equal(r.reason_code, "PRODUCTION_CAPABILITY_MISSING");
});

test("budget gate blocks or elevates expensive work", () => {
  const args = { project_id: P, environment: "preview", version_id: "v18", request_id: "request-0001", idempotency_key: "idem-key-0001" };
  let r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_build, args, ["build.execute"], { budget: { exhausted: true, remaining_units: 0 } }));
  assert.equal(r.reason_code, "DENY_BUDGET_EXHAUSTED");
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_build, args, ["build.execute"], { budget: { remaining_units: 5, requires_approval_for_extra_spend: true } }));
  assert.equal(r.disposition, T.TOOL_DECISIONS.REQUIRE_APPROVAL);
});

test("publish rejects missing/stale/wrong-version/changed verification", () => {
  const args = { project_id: P, environment: "production", version_id: "v18", verification_run_id: "vr18", preview_id: "pr18", artifact_digest: "a".repeat(64), target_environment: "production", request_id: "request-0001", idempotency_key: "idem-key-0001" };
  const caps = ["production.publish", "production.access"];
  const verified = { status: "passed", run_id: "vr18", project_id: P, version_id: "v18", artifact_digest: "a".repeat(64), project_spec_version: "s4", migration_state_version: "m8" };
  const common = { project_spec_version: "s4", migration_state_version: "m8" };
  for (const verification of [null, { ...verified, version_id: "v17" }, { ...verified, artifact_digest: "b".repeat(64) }, { ...verified, project_spec_version: "s3" }]) {
    assert.equal(T.evaluatePolicy(input(T.TOOL_REGISTRY.request_publish, args, caps, { ...common, verification })).reason_code, "VERIFICATION_REQUIRED_OR_STALE");
  }
  const r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_publish, args, caps, { ...common, verification: verified }));
  assert.equal(r.disposition, T.TOOL_DECISIONS.REQUIRE_APPROVAL); assert.equal(r.risk, T.RISK_LEVELS.HIGH);
});

test("destructive production migration requires authoritative preflight and becomes critical", () => {
  const args = { project_id: P, environment: "production", migration_ref: "artifact://migrations/001", migration_kind: "schema_change", destructive: true, request_id: "request-0001", idempotency_key: "idem-key-0001" };
  let r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_migration, args, ["database.migration.request", "production.access"]));
  assert.equal(r.risk, T.RISK_LEVELS.CRITICAL); assert.equal(r.reason_code, "MIGRATION_PREFLIGHT_REQUIRED_OR_STALE");
  const migration_preflight = { authoritative: true, organization_id: O, project_id: P, environment: "production", migration_ref: args.migration_ref, destructive: true, risk: "CRITICAL", status: "PASS" };
  r = T.evaluatePolicy(input(T.TOOL_REGISTRY.request_migration, args, ["database.migration.request", "production.access"], { migration_preflight }));
  assert.equal(r.risk, T.RISK_LEVELS.CRITICAL); assert.equal(r.disposition, T.TOOL_DECISIONS.REQUIRE_APPROVAL);
});
