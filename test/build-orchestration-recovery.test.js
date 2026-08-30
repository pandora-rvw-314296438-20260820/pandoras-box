const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const experienceV2 = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart',
  'utf8',
);
const theatreGuard = fs.readFileSync(
  'supabase/migrations/20260830155431_pandora_build_theatre_latest_job_guard_v1.sql',
  'utf8',
);
const staticTick = fs.readFileSync(
  'supabase/migrations/20260830155516_pandora_static_build_tick_v1.sql',
  'utf8',
);
const staticCron = fs.readFileSync(
  'supabase/migrations/20260830155544_pandora_static_build_cron_v1.sql',
  'utf8',
);

test('V2 Build Theatre reuses one stable initial build identity', () => {
  assert.match(
    experienceV2,
    /idempotencyKey: 'pandora-v2-build:\$\{widget\.project\.id\}'/,
  );
  assert.doesNotMatch(
    experienceV2,
    /pandora-v2-build:\$\{widget\.project\.id\}:\$\{widget\.project\.updatedAt/,
  );
});

test('V2 Build Theatre only says checking for a real verification check', () => {
  assert.match(
    experienceV2,
    /_snapshot\?\.verification\?\.state == 'checking'/,
  );
  assert.doesNotMatch(
    experienceV2,
    /_snapshot\?\.verification != null\) return 'Checking your project'/,
  );
});

test('V2 Build Theatre does not expose the raw project objective', () => {
  const buildScreen = experienceV2.split('class ProjectWorkspaceV2Screen')[0];
  assert.doesNotMatch(buildScreen, /widget\.project\.objective/);
});

test('Build Theatre projection rejects stale superseded build ownership', () => {
  assert.match(theatreGuard, /from public\.pandora_build_jobs newer/);
  assert.match(theatreGuard, /newer\.created_at > new\.created_at/);
  assert.match(theatreGuard, /return new;/);
});

test('bounded static tick advances queued builds through governed convergence', () => {
  assert.match(staticTick, /pg_try_advisory_xact_lock/);
  assert.match(staticTick, /j\.status in \('queued','claimed','running','waiting_verification'\)/);
  assert.match(staticTick, /buildAdapter',''\)='static-web'/);
  assert.match(staticTick, /limit 5/);
  assert.match(staticTick, /private\.pandora_converge_static_site_build_20260830\(v_job\.id\)/);
});

test('static convergence tick is scheduled every minute', () => {
  assert.match(staticCron, /pandora-static-build-convergence-v1/);
  assert.match(staticCron, /'\* \* \* \* \*'/);
  assert.match(staticCron, /private\.pandora_converge_static_builds_tick_20260830\(\)/);
});
