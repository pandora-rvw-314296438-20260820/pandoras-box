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
const providerBootstrap = fs.readFileSync(
  'supabase/migrations/20260830160159_pandora_static_build_provider_bootstrap_v3.sql',
  'utf8',
);
const fallbackConvergence = fs.readFileSync(
  'supabase/migrations/20260830160323_pandora_static_build_fallback_convergence_v4.sql',
  'utf8',
);
const acceptanceV2 = fs.readFileSync(
  'supabase/migrations/20260830160904_pandora_observable_acceptance_reverification_v5a.sql',
  'utf8',
);
const verifiedRecovery = fs.readFileSync(
  'supabase/migrations/20260830161010_pandora_verified_failure_recovery_v6.sql',
  'utf8',
);
const acceptanceConvergencePatch = fs.readFileSync(
  'supabase/migrations/20260830225100_pandora_observable_acceptance_convergence_patch_v5b.sql',
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


test('static convergence bootstraps the provider project before preview work', () => {
  assert.match(providerBootstrap, /pandora_ensure_static_build_vercel_project_20260830/);
  assert.match(providerBootstrap, /pandora_worker_f_vercel_api_20260829/);
  assert.match(providerBootstrap, /vercelProjectId/);
  assert.match(providerBootstrap, /vercelProjectName/);
});

test('static convergence uses the quota-aware v2 fallback path', () => {
  assert.match(
    fallbackConvergence,
    /private\.pandora_converge_static_site_build_v2_20260830\(v_job\.id\)/,
  );
});

test('fallback verification independently proves observable acceptance', () => {
  assert.match(acceptanceV2, /pandora_evaluate_supabase_preview_acceptance_v2_20260830/);
  assert.match(acceptanceV2, /criteriaPassed/);
  assert.match(acceptanceV2, /worker-e-supabase-preview-verifier-v2/);
  assert.match(acceptanceV2, /observable-acceptance-v2/);
  assert.match(acceptanceV2, /private\.pandora_worker_e_verify_supabase_preview_v2_20260830/);
});

test('observable verifier migration is replay-safe and patched after canonical fallback', () => {
  assert.match(acceptanceV2, /if v_def is null then\s+null;/s);
  assert.doesNotMatch(acceptanceV2, /STATIC_CONVERGENCE_V2_PATCH_TARGET_MISSING/);
  assert.match(acceptanceConvergencePatch, /STATIC_CONVERGENCE_V2_PATCH_TARGET_MISSING/);
  assert.match(
    acceptanceConvergencePatch,
    /private\.pandora_worker_e_verify_supabase_preview_v2_20260830/,
  );
  assert.match(
    acceptanceConvergencePatch,
    /private\.pandora_worker_e_verify_supabase_preview_20260830/,
  );
});

test('terminal verification failures can recover only with exact independent PASS proof', () => {
  assert.match(verifiedRecovery, /old\.error_code='VERIFICATION_FAILED'/);
  assert.match(verifiedRecovery, /upper\(r\.status\)='PASS'/);
  assert.match(verifiedRecovery, /r\.builder_identity is distinct from r\.verifier_identity/);
  assert.match(verifiedRecovery, /pandora_recover_verified_static_build_20260830/);
});
