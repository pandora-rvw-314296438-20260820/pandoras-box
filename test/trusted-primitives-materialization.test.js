const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase/migrations/20260831090000_pandora_worker_i_materialization_v1.sql'),
  'utf8',
);
const worker = readFileSync(
  join(root, 'supabase/functions/pandora-source-convergence-worker/index.ts'),
  'utf8',
);

test('Worker I materializer re-reads exact frozen source and Worker E evidence', () => {
  assert.match(migration, /pandora_integration_github_api_20260825/);
  assert.match(migration, /source_commit !~ '\^\[0-9a-f\]\{40\}\$'/);
  assert.match(migration, /verifier_identity <> 'pandora-verification-engine'/);
  assert.match(migration, /v_run\.status <> 'PASS'/);
  assert.match(migration, /PRIMITIVE_FILE_HASH_MISMATCH/);
  assert.match(migration, /PRIMITIVE_BUNDLE_HASH_MISMATCH/);
  assert.match(migration, /worker_e_evidence_ref::uuid/);
  assert.match(migration, /grant execute on function public\.pandora_worker_i_materialize_project_spec_primitives_20260831\(uuid\) to service_role/);
  assert.match(migration, /revoke all on function public\.pandora_worker_i_materialize_project_spec_primitives_20260831\(uuid\) from public, anon, authenticated/);
});

test('trusted project-version lineage requires matching primitive Worker E run', () => {
  assert.match(migration, /primitive_verification_run_id uuid/);
  assert.match(migration, /trusted materialized primitive requires Worker E verification/);
  assert.match(migration, /materialized primitive Worker E evidence mismatch/);
  assert.match(migration, /v_run\.primitive_name <> new\.primitive_name/);
  assert.match(migration, /v_run\.primitive_version <> new\.primitive_version/);
  assert.match(migration, /v_run\.source_digest <> new\.source_digest/);
});

test('source worker overlays immutable primitive files after model output', () => {
  const parseAt = worker.indexOf('parsed = JSON.parse(output)');
  const overlayAt = worker.indexOf('applyPrimitiveMaterialization(' , parseAt);
  const canonicalAt = worker.indexOf('const canonical = await canonicalBundle(', overlayAt);
  assert.ok(parseAt >= 0 && overlayAt > parseAt && canonicalAt > overlayAt);
  assert.match(worker, /path\.startsWith\("pandora-primitives\/"\)/);
  assert.match(worker, /PRIMITIVE_SOURCE_OWNERSHIP_VIOLATION/);
  assert.match(worker, /PANDORA_PRIMITIVE_COMPOSITION\.json/);
  assert.match(worker, /await sha256Bytes\(bytes\) !== expectedSha/);
});

test('composition receipt is required on fresh intake and replay', () => {
  const occurrences = worker.match(/await recordPrimitiveComposition\(/g) || [];
  assert.equal(occurrences.length, 2);
  assert.match(worker, /PRIMITIVE_COMPOSITION_WRITE_FAILED/);
  assert.match(worker, /PRIMITIVE_COMPOSITION_RECEIPT_INVALID/);
  assert.match(migration, /insert into public\.pandora_project_version_compositions/);
  assert.match(migration, /insert into public\.pandora_project_version_primitives/);
  assert.match(migration, /on conflict \(project_version_id,primitive_name\) do update/);
});
