"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "..");
const edge = fs.readFileSync(
  path.join(root, "supabase/functions/pandora-coordinator-gate/index.ts"),
  "utf8",
);
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260916073000_r058_trusted_coordinator_gate.sql"),
  "utf8",
);
const packageJson = fs.readFileSync(path.join(root, "package.json"), "utf8");
const canonicalWorkflow = fs.readFileSync(
  path.join(root, ".github/workflows/canonical-release-evidence.yml"),
  "utf8",
);

test("R-058 runtime is HOLD-capable but PASS and merge stay disabled until the Sheet fence exists", () => {
  assert.match(edge, /const PASS_ENABLED = false;/);
  assert.match(edge, /PASS_DISABLED_UNTIL_SHEET_FENCE/);
  assert.match(edge, /MERGE_DISABLED_UNTIL_SHEET_FENCE/);
  assert.doesNotMatch(edge, /mergePull\s*\(/);
});
test("trusted runtime mints only the fixed GitHub App installation token with minimal enabled permissions", () => {
  assert.match(edge, /const INSTALLATION_ID = 158056492;/);
  assert.match(edge, /appId !== INTEGRATION_APP_ID/);
  assert.match(edge, /installationId !== INSTALLATION_ID/);
  assert.match(edge, /checks: "write"/);
  assert.match(edge, /contents: "read"/);
  assert.match(edge, /pull_requests: "read"/);
  assert.doesNotMatch(edge, /GITHUB_TOKEN|Github_supabase|mcpmaster_github_account_1_pat/);
});

test("coordinator HTTP entrypoint requires a non-browser internal-key path", () => {
  assert.match(edge, /x-pandora-coordinator-key/);
  assert.match(edge, /request\.headers\.get\("origin"\)/);
  assert.match(edge, /pandora_validate_coordinator_gate_key_v1/);
  assert.match(migration, /pandora_coordinator_gate_internal_v1/);
  assert.match(migration, /extensions\.digest\(convert_to\(p_token,'utf8'\),'sha256'\)/);
});

test("durable state enforces generation, nonce, idempotency, persistent check identity, and single merge claim", () => {
  assert.match(migration, /unique index if not exists pandora_coordinator_gate_decision_generation_uq/);
  assert.match(migration, /unique index if not exists pandora_coordinator_gate_idempotency_uq/);
  assert.match(migration, /unique index if not exists pandora_coordinator_gate_nonce_uq/);
  assert.match(migration, /p_decision_generation<>v_state\.current_generation\+1/);
  assert.match(migration, /p_prior_check_run_id is distinct from v_state\.current_check_run_id/);
  assert.match(migration, /pandora_coordinator_gate_check_identity_conflict/);
  assert.match(migration, /pandora_coordinator_gate_merge_already_claimed/);
  assert.match(migration, /consumed_at is not null/);
});
test("R-058 source is part of governed Edge type-check surfaces", () => {
  const sourcePath = "supabase/functions/pandora-coordinator-gate/index.ts";
  assert.ok(packageJson.includes(sourcePath));
  assert.ok(canonicalWorkflow.includes(sourcePath));
});

test("database mutation RPCs are service-role-only and still require the coordinator secret", () => {
  for (const functionName of [
    "pandora_coordinator_gate_begin_decision_v1",
    "pandora_coordinator_gate_record_publish_v1",
    "pandora_coordinator_gate_mark_expired_v1",
    "pandora_coordinator_gate_claim_merge_v1",
    "pandora_coordinator_gate_complete_merge_v1",
  ]) {
    assert.ok(migration.includes(`create or replace function public.${functionName}`));
    assert.ok(migration.includes(`grant execute on function public.${functionName}`));
  }
  assert.match(migration, /pandora_validate_coordinator_gate_key_v1\(p_internal_key\)/g);
  assert.match(migration, /revoke all on table private\.pandora_coordinator_gate_decisions from public,anon,authenticated/);
  assert.match(migration, /revoke all on table private\.pandora_coordinator_gate_state from public,anon,authenticated/);
});
