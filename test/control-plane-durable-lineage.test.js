
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migration = readFileSync(
  join(process.cwd(), 'supabase', 'migrations', '20260828170000_pandora_durable_execution_lineage_v1.sql'),
  'utf8',
);

test('Worker A durable execution migration exposes the required lineage contracts', () => {
  for (const table of [
    'pandora_build_jobs','pandora_build_job_steps','pandora_build_job_attempts','pandora_build_job_events',
    'pandora_model_runs','pandora_tool_calls','pandora_tool_results','pandora_artifacts','pandora_artifact_versions',
    'pandora_artifact_links','pandora_verification_runs','pandora_verification_checks','pandora_verification_evidence','pandora_policy_actions',
  ]) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}\\b`, 'i'));
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
  }
  for (const event of ['PROJECT_CREATED','INTENT_RECEIVED','SPEC_COMPILATION_REQUESTED','SPEC_READY','BUILD_REQUESTED','BUILD_STARTED','BUILD_STEP_STARTED','BUILD_STEP_COMPLETED','BUILD_FAILED','REPAIR_REQUESTED','REPAIR_STARTED','VERIFY_REQUESTED','VERIFICATION_STARTED','VERIFICATION_FAILED','VERIFICATION_PASSED','PREVIEW_REQUESTED','PREVIEW_READY','PUBLISH_REQUESTED','PUBLISH_STARTED','PUBLISHED','ROLLBACK_REQUESTED','ROLLED_BACK','CANCELLED']) {
    assert.match(migration, new RegExp(`'${event}'`));
  }
});

test('Worker A durable execution migration stays aligned to worker contracts', () => {
  for (const task of ['understand_intent','compile_project_spec','plan_build','generate_code','repair_code','derive_acceptance_tests']) assert.match(migration, new RegExp(`'${task}'`));
  for (const status of ['PENDING','RUNNING','PASS','FAIL','BLOCKED','INCONCLUSIVE','STALE']) assert.match(migration, new RegExp(`'${status}'`));
  assert.match(migration, /source_commit ~ '\^\[0-9a-f\]\{40\}\$'/);
  assert.match(migration, /artifact_digest ~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(migration, /builder_identity is null or builder_identity <> verifier_identity/);
  assert.match(migration, /action_hash ~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(migration, /approval action hash binding mismatch/);
  assert.match(migration, /project version artifact digest verification mismatch/);
  assert.match(migration, /project version source digest verification mismatch/);
});

test('Worker A durable execution migration is service-owned and stores no plaintext provider credential fields', () => {
  assert.match(migration, /revoke all on function private\.pandora_claim_build_job\(uuid,text,text,integer\) from public, anon, authenticated;/);
  assert.match(migration, /grant execute on function private\.pandora_claim_build_job\(uuid,text,text,integer\) to service_role;/);
  assert.match(migration, /revoke all on public\.%I from anon, authenticated/);
  assert.match(migration, /grant select on public\.%I to authenticated/);
  assert.match(migration, /grant select, insert, update, delete on public\.%I to service_role/);
  assert.doesNotMatch(migration, /\b(password|api_key|access_token|refresh_token|client_secret)\s+text\b/i);
  assert.doesNotMatch(migration, /\bcredential_value\s+/i);
  assert.match(migration, /lease_token_sha256/);
  assert.match(migration, /metadata_redacted/);
  assert.match(migration, /provenance_redacted/);
});

test('Worker A durable job claims are leased, idempotent and bounded', () => {
  assert.match(migration, /unique index if not exists pandora_build_jobs_idempotency_uidx/);
  assert.match(migration, /attempt_count<j\.max_attempts|attempt_count < j\.max_attempts/);
  assert.match(migration, /for update skip locked/);
  assert.match(migration, /lease_expires_at<=now\(\)|lease_expires_at <= now\(\)/);
  assert.match(migration, /private\.pandora_heartbeat_build_job/);
  assert.match(migration, /private\.pandora_requeue_expired_build_jobs/);
});
