const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase/migrations/20260901153000_pandora_build_watchdog_v1.sql'),
  'utf8',
);

test('build watchdog reuses canonical lease recovery and terminalizes exhausted leases', () => {
  assert.match(migration, /private\.pandora_build_watchdog_tick_v1/);
  assert.match(migration, /private\.pandora_requeue_expired_build_jobs\(p_limit\)/);
  assert.match(migration, /attempt_count\s*>=\s*j\.max_attempts/);
  assert.match(migration, /BUILD_LEASE_RETRY_EXHAUSTED/);
  assert.match(migration, /status\s*=\s*'failed'/);
  assert.match(migration, /current_stage\s*=\s*'failed'/);
  assert.match(migration, /lease_owner\s*=\s*null/);
  assert.match(migration, /lease_token_sha256\s*=\s*null/);
  assert.match(migration, /lease_expires_at\s*=\s*null/);
  assert.match(migration, /status\s*=\s*case when a\.status = 'running' then 'expired'/);
});

test('build watchdog enforces hard deadlines and converges the durable source queue', () => {
  assert.match(migration, /deadline_at\s*<=\s*v_now/);
  assert.match(migration, /BUILD_DEADLINE_EXCEEDED/);
  assert.match(migration, /pandora_source_generation_queue/);
  assert.match(migration, /q\.status in \('queued','dispatching'\)/);
  assert.match(migration, /last_error_code\s*=\s*'BUILD_DEADLINE_EXCEEDED'/);
  assert.match(migration, /failure_class\s*=\s*coalesce\(a\.failure_class, 'deadline_exceeded'\)/);
  assert.doesNotMatch(migration, /delete\s+from\s+public\.pandora_build_job/i);
});

test('watchdog is server scheduled, bounded and service-role-only', () => {
  assert.match(migration, /p_limit integer default 100/);
  assert.match(migration, /p_limit < 1 or p_limit > 1000/);
  assert.match(migration, /for update skip locked/);
  assert.match(migration, /pandora-build-watchdog-v1/);
  assert.match(migration, /'\* \* \* \* \*'/);
  assert.match(migration, /pandora_build_watchdog_tick_v1\(100\)/);
  assert.match(migration, /revoke all on function private\.pandora_build_watchdog_tick_v1\(integer\)[\s\S]+from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function private\.pandora_build_watchdog_tick_v1\(integer\)[\s\S]+to service_role/i);
});
