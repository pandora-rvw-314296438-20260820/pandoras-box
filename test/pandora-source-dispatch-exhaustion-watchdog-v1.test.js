const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase/migrations/20260901193000_pandora_source_dispatch_exhaustion_watchdog_v1.sql'),
  'utf8',
);
const generator = readFileSync(
  join(root, 'supabase/functions/pandora-project-source-generator/index.ts'),
  'utf8',
);
const originalConvergence = readFileSync(
  join(root, 'supabase/migrations/20260830233000_pandora_self_healing_source_convergence_v1.sql'),
  'utf8',
);

function offset(source, needle) {
  const value = source.indexOf(needle);
  assert.notEqual(value, -1, `missing contract fragment: ${needle}`);
  return value;
}

test('fifth stale source dispatch fails closed instead of remaining dispatching forever', () => {
  assert.match(migration, /pandora_fail_exhausted_source_dispatches_v1/);
  assert.match(migration, /q\.status\s*=\s*'dispatching'/);
  assert.match(migration, /q\.dispatched_at\s*<=\s*v_now\s*-\s*interval '3 minutes'/);
  assert.match(migration, /q\.dispatch_count\s*>=\s*5/);
  assert.match(migration, /for update skip locked/);
  assert.match(migration, /SOURCE_DISPATCH_RETRY_EXHAUSTED/);
  assert.match(migration, /request_id\s*=\s*null/);
  assert.match(migration, /dispatched_at\s*=\s*null/);
  assert.match(migration, /completed_at\s*=\s*coalesce/);
});

test('exhausted modern source generation fails only the unmaterialized admitted candidate', () => {
  assert.match(migration, /v_row\.build_job_id is not null/);
  assert.match(migration, /j\.status\s*=\s*'queued'/);
  assert.match(migration, /j\.target_project_version_id is null/);
  assert.match(migration, /SOURCE_GENERATION_RETRY_EXHAUSTED/);
  assert.match(migration, /Your current version is unchanged/);
  assert.match(migration, /lease_owner\s*=\s*null/);
  assert.match(migration, /lease_token_sha256\s*=\s*null/);
  assert.match(migration, /lease_expires_at\s*=\s*null/);
  assert.doesNotMatch(migration, /delete\s+from\s+public\.pandora_project_versions/i);
});

test('server dispatcher adjudicates exhausted requests before ordinary refresh and new dispatch', () => {
  const exhausted = offset(migration, 'pandora_fail_exhausted_source_dispatches_v1(100)');
  const refresh = offset(migration, 'pandora_refresh_source_generation_queue_20260831()');
  const queued = offset(migration, "where status = 'queued'");
  assert.ok(exhausted < refresh);
  assert.ok(refresh < queued);
  assert.match(migration, /v_exhausted \|\| v_refresh \|\| jsonb_build_object/);
  assert.match(migration, /workerKeyAvailable/);
  assert.match(migration, /net\.http_post/);
});

test('background source execution remains server-owned and independent of the client request lifetime', () => {
  assert.match(originalConvergence, /pandora-source-generation-convergence-v1/);
  assert.match(originalConvergence, /'\* \* \* \* \*'/);
  assert.match(originalConvergence, /pandora_dispatch_source_generation_tick_20260831\(\)/);
  assert.match(generator, /pandora_admit_authorized_build_service_v1/);
  assert.match(generator, /runtime\.waitUntil\(runGenerationInBackground/);
  const admit = offset(generator, 'pandora_admit_authorized_build_service_v1');
  const waitUntil = offset(generator, 'runtime.waitUntil(runGenerationInBackground');
  assert.ok(admit < waitUntil, 'durable admission must precede optional Edge continuation');
});

test('exhaustion watchdog is bounded and service-role-only', () => {
  assert.match(migration, /p_limit integer default 100/);
  assert.match(migration, /p_limit < 1 or p_limit > 1000/);
  assert.match(migration, /revoke all on function private\.pandora_fail_exhausted_source_dispatches_v1\(integer\)[\s\S]+from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function private\.pandora_fail_exhausted_source_dispatches_v1\(integer\)[\s\S]+to service_role/i);
});
