const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const models = fs.readFileSync('apps/pandora-mobile/lib/core/models/project_journey_models.dart', 'utf8');
const experience = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_experience_v2.dart', 'utf8');
const safePreview = fs.readFileSync('supabase/migrations/20260830210000_pandora_worker_f_safe_first_preview.sql', 'utf8');

test('server authority defines the first-safe-preview threshold without implying verification', () => {
  assert.match(safePreview, /root_artifact_version_id is null or v_ver\.artifact_digest_sha256 is null or v_ver\.build_job_id is null or v_ver\.project_spec_id is null/);
  assert.match(safePreview, /lifecycle_status not in \('built','verification_pending','verified','preview_ready'\)/);
  assert.match(safePreview, /v_art\.content_sha256<>v_ver\.artifact_digest_sha256/);
  assert.match(safePreview, /v_provider_target='production'/);
  assert.match(safePreview, /'ready_for_verification'/);
});

test('mobile admits only preview-eligible exact candidates and keeps early preview Working', () => {
  assert.match(models, /bool get isPreviewEligible/);
  assert.match(models, /status: jsonText\(json\['status'\], fallback: 'unknown'\)/);
  assert.match(models, /'built',[\s\S]*'verification_pending',[\s\S]*'verified',[\s\S]*'preview_ready'/);
  assert.match(models, /_artifactDigestPattern\.hasMatch\(normalizedDigest\)/);
  assert.match(experience, /candidate == null \|\| !candidate\.isPreviewEligible/);
  assert.match(experience, /_localPreviewFiles\?\.isNotEmpty == true/);
  assert.match(experience, /candidate\.isPreviewEligible && !_ready && !_previewRequested/);
  assert.match(experience, /verification\.isPublishReadyFor\(candidate\)/);
  assert.match(experience, /subtitle: _ready && _publishReady \? 'Ready' : 'Working'/);
  assert.match(experience, /if \(_ready && !_publishReady\) return updating \? 'Change preview' : 'Preview'/);
  assert.doesNotMatch(experience, /subtitle: _ready \? 'Ready' : 'Working'/);
});

test('publish-ready projection is exact-version bound and fail-closed', () => {
  assert.match(models, /publishEligible && versionId == candidate\.versionId/);
  assert.match(experience, /Your exact preview is available while Pandora finishes checking it\./);
});
