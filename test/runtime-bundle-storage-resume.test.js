const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');

const migration = readFileSync(
  'supabase/migrations/20260829176000_pandora_runtime_storage_resume_v1.sql',
  'utf8',
);

test('private Storage resume is exact-lineage and digest bounded', () => {
  assert.match(migration, /p_expected_bundle_sha256 !~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(migration, /v_version\.build_job_id is distinct from p_build_job_id/);
  assert.match(migration, /build_job_id=p_build_job_id and status='succeeded'/);
  assert.match(migration, /v_storage_path:='runtime\/'\|\|v_version\.project_id::text\|\|'\/'\|\|v_version\.id::text\|\|'\/'\|\|p_expected_bundle_sha256\|\|'\.json'/);
});

test('private Storage resume verifies bytes before finalization and is service-role only', () => {
  const readback = migration.indexOf("v_readback.status<>200");
  const digest = migration.indexOf("v_actual_sha:=encode");
  const finalize = migration.indexOf("private.pandora_finalize_runtime_bundle_20260829");
  assert.ok(readback > 0 && digest > readback && finalize > digest);
  assert.match(migration, /v_actual_sha<>p_expected_bundle_sha256/);
  assert.match(migration, /revoke all on function public\.pandora_resume_runtime_bundle_finalization_20260830[\s\S]*from public,anon,authenticated/);
  assert.match(migration, /grant execute on function public\.pandora_resume_runtime_bundle_finalization_20260830[\s\S]*to service_role/);
});
