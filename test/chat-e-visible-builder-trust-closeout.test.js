const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const protocol = read('docs/pandora-live-build-protocol-v2.md');
const api = read('apps/pandora-mobile/lib/core/data/project_experience_api.dart');
const repository = read('apps/pandora-mobile/lib/core/data/project_experience_repository.dart');
const workspace = read('apps/pandora-mobile/lib/features/simple/project_experience_v2.dart');
const view = read('apps/pandora-mobile/lib/features/simple/project_workspace_v2_view.dart');
const candidateTests = read('apps/pandora-mobile/test/core/project_candidate_safety_test.dart');
const runtime = read('supabase/functions/pandora-project-runtime/index.ts');

function block(source, start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0, `missing ${start}`);
  assert.ok(b > a, `missing ${end}`);
  return source.slice(a, b);
}

test('Protocol V2 freezes completed-command stdout/stderr semantics without fake live typing', () => {
  assert.match(protocol, /truthful completed-command evidence chunks/);
  assert.match(protocol, /only after the governed provider command has returned a real result/);
  assert.match(protocol, /does \*\*not\*\* claim byte-by-byte or line-by-line transport/);
  assert.match(protocol, /never synthesized from expected output/);
});

test('candidate failure preserves the visible current product across controller and safety model', () => {
  assert.match(candidateTests, /candidate failure cannot replace current/);
  assert.match(candidateTests, /Your current version is unchanged/);
  const refresh = block(workspace, 'Future<void> _refresh() async', 'Future<void> _openExactPreview() async');
  const failure = refresh.indexOf('if (safety.candidateFailed)');
  const commit = refresh.indexOf('if (commitVisible)');
  assert.ok(commit >= 0 && failure > commit, 'refresh must gate visible assignment through commitVisible');
  const commitBlock = refresh.slice(commit, failure);
  assert.match(commitBlock, /_previewFiles = files/);
  assert.match(commitBlock, /_previewVersionId = targetVersionId/);
  const failureBlock = refresh.slice(failure);
  assert.doesNotMatch(failureBlock, /_previewFiles\s*=/);
  assert.doesNotMatch(failureBlock, /_previewVersionId\s*=/);
});

test('verified publish receipt is derived from canonical conversation evidence and rendered with exact identities', () => {
  assert.match(api, /pandora_get_project_conversation_v1/);
  assert.match(api, /PUBLISH_RECEIPT/);
  assert.match(api, /project_version_id/);
  assert.match(api, /verification_run_id/);
  assert.match(api, /deployment_id/);
  assert.match(repository, /loadLatestPublishReceipt/);
  assert.match(workspace, /loadLatestPublishReceipt/);
  assert.match(workspace, /publishReceipt: _publishReceipt/);
  assert.match(view, /Key\('publish-receipt'\)/);
  assert.match(view, /Key\('publish-receipt-evidence'\)/);
  assert.match(view, /verificationRunId/);
  assert.match(view, /deploymentId/);
});

test('publish promotes the exact reviewed deployment and does not rebuild', () => {
  const publish = block(runtime, 'async function publishProject', 'async function finalizeProductionVerification');
  assert.match(publish, /previewDeploymentId/);
  assert.match(publish, /\/promote\/\$\{encodeURIComponent\(previewDeploymentId\)\}/);
  assert.match(publish, /beforePromotion/);
  assert.match(publish, /PRODUCTION_PROMOTION_NOT_CONFIRMED/);
  assert.doesNotMatch(publish, /createVercelDeployment\(/);
});

test('stored Vercel project binding must be read back before reuse', () => {
  const ensure = block(runtime, 'async function ensureVercelProject', 'async function projectByIdentifier');
  const existing = ensure.indexOf('if (existingId && existingName)');
  const readback = ensure.indexOf('vercelRequest(`/v9/projects/${encodeURIComponent(existingId)}`');
  const returned = ensure.indexOf('return { id: existingId', existing);
  assert.ok(existing >= 0 && readback > existing && returned > readback);
  assert.match(ensure, /VERCEL_PROJECT_IDENTITY_MISMATCH/);
});

test('Undo is exact-parent application restore and refuses implicit production rollback', () => {
  const undo = block(runtime, 'async function undoProject', 'async function runtimeSummary');
  assert.match(undo, /parent_version_id/);
  assert.match(undo, /UNDO_PARENT_NOT_VERIFIED/);
  assert.match(undo, /UNDO_PARENT_PREVIEW_UNAVAILABLE/);
  assert.match(undo, /UNDO_REQUIRES_ROLLBACK/);
  assert.match(undo, /current_version_id/);
  const rollback = block(runtime, 'async function rollbackProject', 'async function reconcileProjectRuntime');
  assert.match(rollback, /pandora_authorize_production_rollback_20260831/);
  assert.match(rollback, /\/rollback\/\$\{encodeURIComponent\(providerDeploymentId\)\}/);
});
