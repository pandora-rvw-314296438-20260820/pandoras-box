const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');

const api = readFileSync('api/preview.ts', 'utf8');
const vercel = JSON.parse(readFileSync('vercel.json', 'utf8'));
const migration = readFileSync(
  'supabase/migrations/20260906193000_pandora_renderable_preview_transport_v1.sql',
  'utf8',
);
const convergenceMigration = readFileSync(
  'supabase/migrations/20260906202137_pandora_renderable_preview_reverification_convergence_v2.sql',
  'utf8',
);
const reverifyFinalizerMigration = readFileSync(
  'supabase/migrations/20260906202142_pandora_renderable_preview_reverification_finalizer_v1.sql',
  'utf8',
);
const previewMemoryMigration = readFileSync(
  'supabase/migrations/20260906203622_pandora_preview_memory_reverification_idempotency_v1.sql',
  'utf8',
);
const previewCapabilityRotationMigration = readFileSync(
  'supabase/migrations/20260906204103_pandora_preview_capability_rotation_v1.sql',
  'utf8',
);
const productionReverifyMigration = readFileSync(
  'supabase/migrations/20260906204458_pandora_renderable_production_reverification_finalizer_v1.sql',
  'utf8',
);
const lifecyclePreservationMigration = readFileSync(
  'supabase/migrations/20260906204653_pandora_renderable_reverification_lifecycle_preservation_v1.sql',
  'utf8',
);
const receiptBackfillMigration = readFileSync(
  'supabase/migrations/20260906204932_pandora_legacy_publish_receipt_reverification_backfill_v1.sql',
  'utf8',
);
const staticAcceptanceMigration = readFileSync(
  'supabase/migrations/20260906221927_pandora_static_preview_acceptance_v3.sql',
  'utf8',
);
const failedPreviewRetryMigration = readFileSync(
  'supabase/migrations/20260906222048_pandora_failed_preview_verification_retry_v1.sql',
  'utf8',
);
const ownerApiDuplicateReceipt = readFileSync(
  'supabase/migrations/20260906224812_pandora_owner_api_exact_source_bundle_v1.sql',
  'utf8',
);
const acceptanceV4Migration = readFileSync(
  'supabase/migrations/20260906224847_pandora_static_preview_acceptance_v4_vercel_retry.sql',
  'utf8',
);

test('Vercel preview proxy preserves capability authority but serves renderable HTML', () => {
  assert.match(api, /pandora-preview-host/);
  assert.match(api, /text\/html; charset=utf-8/);
  assert.match(api, /sandbox allow-scripts/);
  assert.doesNotMatch(api, /allow-same-origin/);
  assert.match(api, /Access-Control-Allow-Origin/);
  assert.match(api, /MAX_FILE_BYTES/);
  assert.match(api, /redirect: 'error'/);
  assert.match(api, /AbortController/);
  assert.equal(
    new Map(vercel.rewrites.map(({ source, destination }) => [source, destination]))
      .get('/preview/:token/:path*'),
    '/api/preview?token=:token&path=:path*',
  );
});

test('preview and production fallback URLs leave the Supabase shared HTML domain', () => {
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/preview\//);
  assert.match(migration, /pandora_create_supabase_preview_fallback_20260830/);
  assert.match(migration, /pandora_publish_supabase_fallback_20260831/);
  assert.match(migration, /ready_for_verification/);
});

test('Worker E rejects HTTP 200 that is not renderable HTML', () => {
  assert.match(migration, /content-type/);
  assert.match(migration, /content-security-policy/);
  assert.match(migration, /text\/html%/);
  assert.match(migration, /allow-scripts/);
  assert.match(migration, /allow-same-origin/);
  assert.match(migration, /runtime_not_renderable/);
});

test('verification replay is transport-bound and cannot reuse the old PASS', () => {
  assert.match(migration, /static_site_renderable_v2/);
  assert.match(migration, /supabase-static-production-renderable-v3/);
  assert.match(migration, /v_base:=private\.pandora_worker_e_verify_supabase_preview_20260830/);
  assert.match(migration, /SUPABASE_PREVIEW_BASE_VERIFICATION_MISSING/);
});

test('succeeded builds do not bypass pending render-transport re-verification', () => {
  assert.match(convergenceMigration, /pandora_converge_static_site_build_v2_20260830/);
  assert.match(convergenceMigration, /pending_dep\.verification_state=''ready_for_verification''/);
  assert.match(convergenceMigration, /pending_dep\.status=''ready_for_verification''/);
  assert.match(convergenceMigration, /pending_dep\.provider=''supabase_preview''/);
  assert.match(convergenceMigration, /RENDERABLE_PREVIEW_REVERIFY_GUARD_ANCHOR_MISSING/);
});

test('renderable preview re-verification safely finalizes current and historical previews', () => {
  assert.match(reverifyFinalizerMigration, /pandora_finalize_renderable_preview_reverification_20260906/);
  assert.match(reverifyFinalizerMigration, /pandora_worker_e_verify_supabase_preview_v2_20260830/);
  assert.match(reverifyFinalizerMigration, /RENDERABLE_PREVIEW_REVERIFY_PROOF_INVALID/);
  assert.match(reverifyFinalizerMigration, /current_deployment_id=v_dep\.id/);
  assert.match(reverifyFinalizerMigration, /v_current:=found/);
  assert.match(reverifyFinalizerMigration, /previewVerificationState','verified/);
});

test('preview memory evidence remains immutable across transport re-verification', () => {
  assert.match(previewMemoryMigration, /visible:verified_preview:/);
  assert.match(previewMemoryMigration, /private\.execution_learning_outbox/);
  assert.match(previewMemoryMigration, /if exists \(/);
  assert.match(previewMemoryMigration, /return new;/);
  assert.match(previewMemoryMigration, /enqueue_visible_creation_memory_evidence/);
});

test('expired preview capability rotation preserves exact lineage and forces re-verification', () => {
  assert.match(previewCapabilityRotationMigration, /pandora_rotate_expiring_supabase_preview_capability_20260906/);
  assert.match(previewCapabilityRotationMigration, /previewCapabilityHash/);
  assert.match(previewCapabilityRotationMigration, /previewCapabilityExpiresAt/);
  assert.match(previewCapabilityRotationMigration, /v_old_expires > v_now \+ interval '1 day'/);
  assert.match(previewCapabilityRotationMigration, /current_deployment_id=v_dep\.id/);
  assert.match(previewCapabilityRotationMigration, /verification_state='ready_for_verification'/);
});

test('production transport re-verification requires exact current production lineage', () => {
  assert.match(productionReverifyMigration, /pandora_finalize_renderable_production_reverification_20260906/);
  assert.match(productionReverifyMigration, /current_deployment_id=v_dep\.id/);
  assert.match(productionReverifyMigration, /pandora_worker_e_verify_supabase_production_20260831/);
  assert.match(productionReverifyMigration, /RENDERABLE_PRODUCTION_REVERIFY_PROOF_INVALID/);
  assert.match(productionReverifyMigration, /verification_state='live_verified'/);
});

test('preview re-verification preserves production lifecycle and production reverify restores live', () => {
  assert.match(lifecyclePreservationMigration, /pe\.current_version_id=v_ver\.id/);
  assert.match(lifecyclePreservationMigration, /lifecycle_status not in \(''live'',''verified''\)/);
  assert.match(lifecyclePreservationMigration, /lifecycle_status=''live''/);
});

test('legacy publish receipt backfill requires promoted preview and fresh PASS proof', () => {
  assert.match(receiptBackfillMigration, /pandora_backfill_missing_publish_receipt_for_reverification_20260906/);
  assert.match(receiptBackfillMigration, /v_dep\.promoted_from_id/);
  assert.match(receiptBackfillMigration, /target_environment='preview'/);
  assert.match(receiptBackfillMigration, /required_check_profile='static_site'/);
  assert.match(receiptBackfillMigration, /source_digest=v_ver\.source_sha256/);
  assert.match(receiptBackfillMigration, /artifact_digest=v_ver\.artifact_digest_sha256/);
  assert.match(receiptBackfillMigration, /awaiting_production_verification/);
});

test('static preview acceptance verifies observable identity and interaction wiring', () => {
  assert.match(staticAcceptanceMigration, /pandora_static_preview_acceptance_v3/);
  assert.match(staticAcceptanceMigration, /regexp_matches\(v_body,'href=/);
  assert.match(staticAcceptanceMigration, /regexp_matches\(v_body,'onclick=/);
  assert.match(staticAcceptanceMigration, /static_site_acceptance_v3/);
  assert.match(staticAcceptanceMigration, /jsonb_array_length\(p_acceptance_scope->'functional'\)=0/);
  assert.doesNotMatch(
    staticAcceptanceMigration,
    /position\(lower\(left\(v_spec\.business_summary,80\)\) in lower\(v_runtime_body\)\)/,
  );
});

test('failed preview verification retry is narrow and recovers only a fresh PASS', () => {
  assert.match(failedPreviewRetryMigration, /pandora_retry_failed_preview_verification_20260906/);
  assert.match(failedPreviewRetryMigration, /v_dep\.status<>'failed'/);
  assert.match(failedPreviewRetryMigration, /v_job\.error_code<>'VERIFICATION_FAILED'/);
  assert.match(failedPreviewRetryMigration, /status='FAIL'/);
  assert.match(failedPreviewRetryMigration, /pandora_worker_e_verify_supabase_preview_v2_20260830/);
  assert.match(failedPreviewRetryMigration, /pandora_recover_verified_static_build_20260830/);
  assert.match(failedPreviewRetryMigration, /upper\(coalesce\(v_result->>'status',''\)\)<>'PASS'/);
});

test('duplicate owner API provider history is a source no-op receipt', () => {
  const executable = ownerApiDuplicateReceipt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('--'));
  assert.deepEqual(executable, ['select 1;']);
  assert.match(ownerApiDuplicateReceipt, /20260907063000_pandora_owner_api_exact_source_bundle_v1\.sql/);
});

test('acceptance v4 handles generic working names without weakening structure checks', () => {
  assert.match(acceptanceV4Migration, /pandora_static_preview_acceptance_v4/);
  assert.match(acceptanceV4Migration, /'decoration'/);
  assert.match(acceptanceV4Migration, /<title/);
  assert.match(acceptanceV4Migration, /<h1/);
  assert.match(acceptanceV4Migration, /404\[\[:space:\]\]\+not/);
  assert.match(acceptanceV4Migration, /regexp_matches\(v_body,'href=/);
  assert.match(acceptanceV4Migration, /regexp_matches\(v_body,'onclick=/);
});

test('Vercel Worker E uses current Supabase access and replay-safe acceptance v4', () => {
  assert.match(acceptanceV4Migration, /where name in \(''Supabase_access''/);
  assert.match(acceptanceV4Migration, /pandora_worker_e_verify_runtime_20260829/);
  assert.match(acceptanceV4Migration, /static_site_acceptance_v4/);
  assert.match(acceptanceV4Migration, /production_release_acceptance_v4/);
});

test('Vercel failed verification retry requires exact current failed build and fresh PASS', () => {
  assert.match(acceptanceV4Migration, /pandora_retry_failed_vercel_preview_verification_20260906/);
  assert.match(acceptanceV4Migration, /v_dep\.provider<>'vercel'/);
  assert.match(acceptanceV4Migration, /v_job\.error_code<>'VERIFICATION_FAILED'/);
  assert.match(acceptanceV4Migration, /status='FAIL'/);
  assert.match(acceptanceV4Migration, /pandora_worker_e_verify_runtime_20260829/);
  assert.match(acceptanceV4Migration, /pandora_recover_verified_static_build_20260830/);
});
