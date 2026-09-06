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
