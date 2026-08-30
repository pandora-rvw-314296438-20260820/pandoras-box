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

test('mobile never calls a production candidate Live before verified state arrives', () => {
  assert.match(projectExperience, /return 'Publishing · verifying';/);
  assert.match(projectExperience, /Publishing\. Pandora is verifying this exact version\./);
  assert.match(projectExperience, /_watchPublishCompletion/);
  assert.match(projectExperience, /_snapshot\?\.project\.isLive == true/);
  assert.match(projectExperience, /production\.versionId == candidate\.versionId/);
  assert.match(projectExperience, /_snapshot\?\.production\?\.versionId !=\s+_candidate\?\.versionId/);
});
