const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migration = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260903110000_pandora_generated_intake_replay_semantic_hardening_v1.sql'),
  'utf8',
);

test('generated intake replay is provenance-bound and fails closed on collisions', () => {
  assert.match(migration, /BUILD_INTAKE_REPLAY_COLLISION/);
  assert.match(migration, /BUILD_INTAKE_REPLAY_PROVENANCE_UNVERIFIABLE/);
  assert.match(migration, /v_existing_version\.source_sha256 is distinct from p_source_sha256/);
  assert.match(migration, /v_existing_artifact\.content_sha256 is distinct from p_source_sha256/);
  assert.match(migration, /v_existing_artifact\.byte_size is distinct from p_source_byte_size/);
  assert.match(migration, /source_payload->>'buildAdapter'/);
  assert.match(migration, /source_payload->>'generatedModelRunId' is distinct from p_model_run_id::text/);
  assert.match(migration, /source_payload->>'generatedStoragePath' is distinct from p_storage_path/);
  assert.match(migration, /generatedSourceByteSize/);
});

test('new candidate versions persist replay provenance without exposing provider secrets', () => {
  assert.match(migration, /'generatedModelRunId',p_model_run_id/);
  assert.match(migration, /'generatedStoragePath',p_storage_path/);
  assert.match(migration, /'generatedSourceByteSize',p_source_byte_size/);
  assert.doesNotMatch(migration, /api[_-]?key|authorization\s*:/i);
});

test('model runs cannot be reused across admitted build jobs', () => {
  assert.match(migration, /BUILD_INTAKE_MODEL_RUN_COLLISION/);
  assert.match(migration, /v_model_run\.build_job_id<>v_job\.id/);
  assert.match(migration, /BUILD_INTAKE_MODEL_RUN_BIND_RACE/);
  assert.match(migration, /where id=p_model_run_id and build_job_id is null/);
});

test('legacy attached builds fail closed when exact provenance cannot be proven', () => {
  assert.match(migration, /if v_existing_version\.source_payload \? 'generatedModelRunId' then/);
  assert.match(migration, /v_existing_artifact\.produced_by_model_run_id is distinct from p_model_run_id/);
  assert.match(migration, /v_existing_artifact\.storage_path is distinct from p_storage_path/);
  assert.match(migration, /BUILD_INTAKE_REPLAY_PROVENANCE_UNVERIFIABLE/);
});
