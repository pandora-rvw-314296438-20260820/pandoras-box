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
  path.join(root, "supabase/migrations/20260916103635_r058_trusted_coordinator_gate.sql"),
  "utf8",
);
const packageJson = fs.readFileSync(path.join(root, "package.json"), "utf8");
const canonicalWorkflow = fs.readFileSync(
  path.join(root, ".github/workflows/canonical-release-evidence.yml"),
  "utf8",
);

test("R-058 runtime enables fenced PASS and keeps merge transport external to the minimal GitHub App", () => {
  assert.match(edge, /const PASS_ENABLED = true;/); assert.match(edge, /PASS_DISABLED_UNTIL_SHEET_FENCE/); assert.match(edge, /action === "claimMerge"/); assert.match(edge, /pandora_coordinator_gate_claim_merge_v2/); assert.match(edge, /action === "completeMerge"/); assert.match(edge, /pandora_coordinator_gate_complete_merge_v2/); assert.match(edge, /action === "abortMerge"/); assert.match(edge, /pandora_coordinator_gate_abort_merge_v2/); assert.match(edge, /MERGE_TRANSPORT_EXTERNAL/); assert.match(edge, /assertMergeReady/); assert.doesNotMatch(edge, /mergePull\s*\(/);
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

test("GitHub App creates checks through the repository check-runs endpoint", () => {
  assert.match(edge, /githubJson\(token, "check-runs", \{/);
  assert.doesNotMatch(edge, /commits\/\$\{String\(payload\.head_sha\)\}\/check-runs/);
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

test("D-041 effective Sheet snapshot promotion is fenced across publish, promotion, expiry, and merge", () => {
  const fenceMigration = fs.readFileSync(
    path.join(root, "supabase/migrations/20260916103837_r058_effective_sheet_snapshot_fence.sql"),
    "utf8",
  );
  assert.match(fenceMigration, /fence_state in \('idle','promoting','publishing','merging'\)/);
  assert.match(fenceMigration, /pandora_coordinator_snapshot_prepare_v1/);
  assert.match(fenceMigration, /pandora_coordinator_snapshot_record_revocation_v1/);
  assert.match(fenceMigration, /required_revocations<>v_promotion\.completed_revocations/);
  assert.match(fenceMigration, /p_provider_conclusion<>'action_required'/);
  assert.match(fenceMigration, /pandora_coordinator_gate_begin_decision_v2/);
  assert.match(fenceMigration, /effective_snapshot_generation<>p_authoritative_snapshot_generation/);
  assert.match(fenceMigration, /fence_state='publishing'/);
  assert.match(fenceMigration, /pandora_coordinator_gate_begin_expiry_v2/);
  assert.match(fenceMigration, /pandora_coordinator_gate_claim_merge_v2/);
  assert.match(fenceMigration, /fence_state='merging'/);
  assert.match(fenceMigration, /pandora_coordinator_gate_complete_merge_v2/);
  assert.match(edge, /pandora_coordinator_gate_begin_decision_v2/);
  assert.match(edge, /pandora_coordinator_gate_record_publish_v2/);
  assert.match(edge, /promoteSnapshot/);
  assert.match(edge, /revokeCheckForSnapshot/);
});
test("R-058 runtime reconciles ambiguous durable writes by exact provider/database readback", () => {
  assert.match(edge, /GATE_STATE_BEGIN_READBACK_FAILED/);
  assert.match(edge, /GATE_STATE_RECORD_READBACK_FAILED/);
  assert.match(edge, /ambiguous_recovered/);
  assert.match(edge, /SNAPSHOT_EFFECTIVE_REPLAY_MISMATCH/);
});

test("stuck pre-provider publication can be retired only by exact audited recovery", () => {
  const recoveryMigration = fs.readFileSync(
    path.join(root, "supabase/migrations/20260916110444_r058_publication_abort_recovery.sql"),
    "utf8",
  );
  assert.match(recoveryMigration, /pandora_coordinator_gate_abort_publication_v2/);
  assert.match(recoveryMigration, /current_check_run_id is not null/);
  assert.match(recoveryMigration, /provider_state='publication_aborted'/);
  assert.match(recoveryMigration, /fence_state='idle'/);
});
