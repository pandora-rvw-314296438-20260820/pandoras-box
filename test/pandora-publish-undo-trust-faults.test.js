
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const runtime = fs.readFileSync('supabase/functions/pandora-project-runtime/index.ts', 'utf8');
const receiptAliasPath = 'supabase/migrations/20260901093000_pandora_publish_receipts_v1.sql';
const receiptAlias = fs.readFileSync(receiptAliasPath, 'utf8');
const canonicalReceiptMatch = receiptAlias.match(/Canonical executable migration:\s+([0-9A-Za-z_.-]+\.sql)/);
const receiptPath = canonicalReceiptMatch ? `supabase/migrations/${canonicalReceiptMatch[1]}` : receiptAliasPath;
const receipts = fs.readFileSync(receiptPath, 'utf8');
const restore = fs.readFileSync('packages/pandora-verification/src/restore-semantics.js', 'utf8');

const publishStart = runtime.indexOf('async function publishProject');
const finalizeStart = runtime.indexOf('async function finalizeProductionVerification');
const undoStart = runtime.indexOf('async function undoProject');
const summaryStart = runtime.indexOf('async function runtimeSummary', undoStart);
const serveStart = runtime.indexOf('\n\nDeno.serve', finalizeStart);
const publish = runtime.slice(publishStart, finalizeStart);
const finalize = runtime.slice(finalizeStart, serveStart);
const undo = runtime.slice(undoStart, summaryStart);

test('stale or unrelated preview can never satisfy reviewed-candidate publish identity', () => {
  assert.match(publish, /eq\("version_id", requestedVersion\)/);
  assert.match(publish, /preview\.source_sha256/);
  assert.match(publish, /preview\.artifact_digest/);
  assert.match(publish, /preview\.source_commit_sha/);
  assert.match(publish, /verification\.preview_deployment_id\) !== previewDeploymentId/);
  assert.match(publish, /completedAt < Math\.max\(versionCreatedAt, previewCreatedAt\)/);
  assert.match(publish, /VERIFICATION_IDENTITY_MISMATCH/);
  assert.match(publish, /VERIFICATION_STALE/);
});

test('Publish promotes the exact reviewed deployment and preserves prior live URL until production verification', () => {
  assert.match(publish, /\/promote\/\$\{encodeURIComponent\(previewDeploymentId\)\}/);
  assert.match(publish, /provider_deployment_id: previewDeploymentId/);
  assert.match(publish, /promoted_from_id: preview\.id/);
  assert.match(publish, /const previousLiveUrl = textValue\(journey\.liveUrl\) \|\| null/);
  assert.match(publish, /stage: "publishing"/);
  assert.match(publish, /liveUrl: previousLiveUrl/);
  assert.match(publish, /productionCandidateUrl/);
  assert.doesNotMatch(publish, /stage: "live"/);
});

test('ambiguous provider publish is quarantined for reconciliation instead of blindly repeated', () => {
  assert.match(publish, /status: "uncertain", ambiguous: true/);
  assert.match(publish, /PUBLISH_RECONCILIATION_REQUIRED/);
  assert.match(publish, /PUBLISH_IN_PROGRESS/);
  assert.match(publish, /pandora_runtime_operations/);
  assert.match(publish, /idempotency_key/);
});

test('stable live domain is provider-read and bound to the exact verified production deployment', () => {
  assert.match(finalize, /required_check_profile\) !== "production_release"/);
  assert.match(finalize, /verification\.preview_deployment_id\) !== providerDeploymentId/);
  for (const fact of ['ownership_verified','dns_configured','tls_ready','routing_ready','runtime_healthy']) {
    assert.match(finalize, new RegExp(fact));
  }
  assert.match(finalize, /vercelRequest\(`\/v9\/projects\/\$\{encodeURIComponent\(providerProjectId\)\}`/);
  assert.match(finalize, /textValue\(productionTarget\.id\) === providerDeploymentId/);
  assert.match(finalize, /defaultDomainStatus = "live_verified"/);
});

test('publish receipt proves what went live and retains the exact previous production rollback pointer', () => {
  assert.match(receipts, /version_id uuid not null/);
  assert.match(receipts, /production_deployment_id uuid not null/);
  assert.match(receipts, /source_sha256 text/);
  assert.match(receipts, /artifact_digest text/);
  assert.match(receipts, /preview_verification_run_id text not null/);
  assert.match(receipts, /production_verification_run_id text/);
  assert.match(receipts, /previous_production_version_id uuid/);
  assert.match(receipts, /previous_production_deployment_id uuid/);
  assert.match(receipts, /PUBLISH_RECEIPT_MISSING/);
});

test('Undo is exact-parent application restore and refuses implicit production rollback', () => {
  assert.match(undo, /expectedVersionId/);
  assert.match(undo, /parent_version_id/);
  assert.match(undo, /UNDO_PRECONDITION_MISMATCH/);
  assert.match(undo, /UNDO_PARENT_NOT_VERIFIED/);
  assert.match(undo, /UNDO_PARENT_PREVIEW_UNAVAILABLE/);
  assert.match(undo, /UNDO_REQUIRES_ROLLBACK/);
  assert.match(undo, /source_sha256/);
  assert.match(undo, /artifact_digest/);
  assert.match(undo, /source_commit/);
});

test('application restore, production rollback, and database recovery remain separate governed meanings', () => {
  assert.match(restore, /application_restore/);
  assert.match(restore, /production_rollback/);
  assert.match(restore, /database_recovery/);
  assert.match(restore, /Persistent data is not reversed or recovered/);
  assert.match(restore, /Persistent data is unchanged/);
  assert.match(restore, /explicit verified recovery point/);
  assert.match(restore, /database_recovery_included: false/);
  assert.match(restore, /production_rollback_included: false/);
});
