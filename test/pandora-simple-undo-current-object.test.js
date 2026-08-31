const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const runtime = readFileSync(
  join(root, 'supabase/functions/pandora-project-runtime/index.ts'),
  'utf8',
);
const api = readFileSync(
  join(root, 'apps/pandora-mobile/lib/core/data/project_runtime_api.dart'),
  'utf8',
);
const models = readFileSync(
  join(root, 'apps/pandora-mobile/lib/core/models/project_journey_models.dart'),
  'utf8',
);
const workspace = readFileSync(
  join(root, 'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart'),
  'utf8',
);

test('runtime binds the visible current object to the exact candidate version', () => {
  assert.match(runtime, /select\("id, parent_version_id, artifact_digest_sha256, lifecycle_status, created_at"\)/);
  assert.match(runtime, /\["built", "verification_pending", "verified", "preview_ready", "live"\]/);
  assert.match(runtime, /previewQuery = previewQuery\.eq\("version_id", candidate\.data\.id\)/);
  assert.match(runtime, /parentVersionId: candidate\.data\.parent_version_id \?\? null/);
});

test('Undo is exact-version, parent-bound, and refuses implicit live rollback', () => {
  assert.match(runtime, /async function undoProject\(/);
  assert.match(runtime, /expectedVersionId/);
  assert.match(runtime, /parent_version_id/);
  assert.match(runtime, /UNDO_REQUIRES_ROLLBACK/);
  assert.match(runtime, /UNDO_PARENT_PREVIEW_UNAVAILABLE/);
  assert.match(runtime, /lifecycle_status: "rolled_back"/);
  assert.match(runtime, /\/projects\\\/\(\[\^\/\]\+\)\\\/undo/);
});

test('Simple Mode exposes Changed · Undo through the governed runtime API', () => {
  assert.match(api, /operation: 'customerProject\.undo'/);
  assert.match(api, /routeTemplate: '\/projects\/:id\/undo'/);
  assert.match(models, /final String\? parentVersionId/);
  assert.match(models, /bool get canUndo/);
  assert.match(workspace, /Future<void> _undoChange\(\)/);
  assert.match(workspace, /'Verified change'/);
  assert.match(workspace, /'Undo'/);
  assert.doesNotMatch(workspace, /CURRENT OBJECT/);
  assert.doesNotMatch(workspace, /Your first version is ready/);
  assert.match(
    workspace,
    /bool get _canUndo =>[\s\S]*_projection\?\.canUndo == true && _projection\?\.candidateVersionId != null;/,
  );
  assert.match(workspace, /final versionId = _projection\?\.candidateVersionId;/);
  assert.match(workspace, /runtime\.undo\([\s\S]*versionId: versionId/);
});
