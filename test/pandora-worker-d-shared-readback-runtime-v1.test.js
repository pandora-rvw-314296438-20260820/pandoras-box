const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const worker = readFileSync(
  join(root, 'supabase', 'functions', 'pandora-source-convergence-worker', 'index.ts'),
  'utf8',
);
const deadline = readFileSync(
  join(root, 'supabase', 'migrations', '20260906031143_pandora_build_execution_deadline_phase_v2.sql'),
  'utf8',
);
const rebind = readFileSync(
  join(root, 'supabase', 'migrations', '20260906032950_pandora_worker_d_readback_shared_runtime_v1.sql'),
  'utf8',
);

test('shared source worker preserves a distinct exact Worker-D readback route', () => {
  assert.match(worker, /exactKeys\(body, \["buildJobId"\]\)/);
  assert.match(worker, /readbackWorkerDSource/);
  assert.match(worker, /pandora-worker-d-static-web/);
  assert.match(worker, /lease_expires_at/);
  assert.match(worker, /artifact_kind/);
  assert.match(worker, /source_snapshot/);
  assert.match(worker, /SOURCE_READBACK_MISMATCH/);
  assert.match(worker, /SOURCE_READBACK_UNSAFE/);
  assert.match(worker, /pandora_validate_source_worker_key_20260831/);
});

test('source generation no longer consumes Worker-D execution deadline', () => {
  assert.match(deadline, /new\.target_project_version_id is null[\s\S]*new\.deadline_at := null/);
  assert.match(deadline, /old\.target_project_version_id is null[\s\S]*new\.target_project_version_id is not null/);
  assert.match(deadline, /new\.deadline_at := clock_timestamp\(\) \+ interval '30 minutes'/);
});

test('Worker-D finalizer is rebound to the existing internal source runtime', () => {
  assert.match(rebind, /pandora-source-convergence-worker/);
  assert.match(rebind, /pandora-worker-d-source-readback/);
  assert.match(rebind, /WORKER_D_READBACK_REBIND_VERIFY_FAILED/);
});
