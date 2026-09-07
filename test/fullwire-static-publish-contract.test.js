import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const runtimeApi = readFileSync(
  new URL('../apps/pandora-mobile/lib/core/data/project_runtime_api.dart', import.meta.url),
  'utf8',
);
const convergence = readFileSync(
  new URL('../supabase/migrations/20260830224000_pandora_static_site_fullwire_convergence_v1.sql', import.meta.url),
  'utf8',
);

test('mobile publish sends the current production compare-and-set precondition', () => {
  assert.match(runtimeApi, /final current = await runtime\(projectId\);/);
  assert.match(runtimeApi, /final expectedProductionVersionId = current\.production\?\.versionId;/);
  assert.match(runtimeApi, /'expectedProductionVersionId': expectedProductionVersionId/);
});

test('static site build convergence is automatic and preserves worker separation', () => {
  assert.match(convergence, /pandora_worker_d_finalize_static_web_20260830/);
  assert.match(convergence, /pandora_claim_build_job/);
  assert.match(convergence, /pandora_worker_f_resume_exact_preview_20260830/);
  assert.match(convergence, /pandora_worker_e_verify_runtime_20260829/);
  assert.match(convergence, /pandora_close_verified_static_build_20260830/);
  assert.match(convergence, /pandora_converge_pending_static_sites_20260830/);
  assert.match(convergence, /pandora-static-site-convergence/);
  assert.match(convergence, /vault\.decrypted_secrets/);
  assert.doesNotMatch(convergence, /github_pat_[A-Za-z0-9_]{20,}/);
  assert.doesNotMatch(convergence, /AIza[0-9A-Za-z_-]{20,}/);
});

const productionConvergence = readFileSync(
  new URL('../supabase/migrations/20260830224500_pandora_production_release_convergence_v1.sql', import.meta.url),
  'utf8',
);
const projectExperience = readFileSync(
  new URL('../apps/pandora-mobile/lib/features/simple/project_experience_v2.dart', import.meta.url),
  'utf8',
);

test('production promotion automatically receives independent Worker E proof before Live', () => {
  assert.match(productionConvergence, /pandora_worker_e_verify_runtime_20260829\(v_dep\.id,'production_release'/);
  assert.match(productionConvergence, /required_check_profile<>'production_release'/);
  assert.match(productionConvergence, /target_environment<>'production'/);
  assert.match(productionConvergence, /verification_state='live_verified'/);
  assert.match(productionConvergence, /lifecycle_status='live'/);
  assert.match(productionConvergence, /pandora_refresh_primary_production_domain_20260830/);
  assert.match(productionConvergence, /pandora-production-release-convergence/);
});

test('publish never treats shared fallback hosting as production', () => {
  const runtime = readFileSync(
    new URL('../supabase/functions/pandora-project-runtime/index.ts', import.meta.url),
    'utf8',
  );
  const publishStart = runtime.indexOf('async function publishProject');
  const publishEnd = runtime.indexOf('async function finalizeProductionVerification');
  const publish = runtime.slice(publishStart, publishEnd);
  assert.doesNotMatch(publish, /pandora_publish_supabase_fallback_20260831/);
  assert.doesNotMatch(publish, /provider:\s*"supabase_static"/);
  assert.match(publish, /publish-vercel-preview:/);
  assert.match(publish, /pandora_worker_e_verify_runtime_20260829/);
  assert.match(publish, /textValue\(preview\.provider\)\.toLowerCase\(\) !== "vercel"/);
});

test('mobile never calls a production candidate Live before exact projection proof arrives', () => {
  assert.match(projectExperience, /String\? get _publishVersionId/);
  assert.match(projectExperience, /projection\.canPublish != true/);
  assert.match(projectExperience, /_candidateSafety\?\.candidateVerified == true/);
  assert.match(projectExperience, /projection\.currentVerified/);
  assert.match(projectExperience, /projection\.productionVersionId != currentVersionId/);
  assert.match(projectExperience, /bool get _canPublish => _publishVersionId != null;/);
  assert.match(projectExperience, /return _projection\?\.statusLabel \?\? 'Working';/);
  assert.match(
    projectExperience,
    /projection\.state == ProjectExperienceState\.live &&[\s\S]*projection\.productionVersionId == versionId/,
  );
  assert.match(projectExperience, /ProjectReleasePhase\? get _releasePhase/);
  assert.match(projectExperience, /ProjectReleasePhase\.deploying/);
  assert.match(projectExperience, /ProjectReleasePhase\.verifying/);
  assert.doesNotMatch(
    projectExperience,
    /Publishing\. Pandora is verifying this exact version\./,
  );
  assert.match(projectExperience, /await _watchPublishCompletion\(versionId\);/);
  assert.match(projectExperience, /await _showPublishedConfirmation\(\);/);
  assert.match(projectExperience, /The exact public address will be shown/);
  assert.match(projectExperience, /label: 'Open site'/);
  assert.doesNotMatch(projectExperience, /SnackBar\(content: Text\('Live\.'\)\)/);
  assert.doesNotMatch(projectExperience, /snapshot\?\.project\.isLive == true/);
});
