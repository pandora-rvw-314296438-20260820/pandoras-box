const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260908045200_pandora_exact_application_undo_v2.sql', 'utf8');
const runtime = fs.readFileSync('supabase/functions/pandora-project-runtime/index.ts', 'utf8');
const workspace = fs.readFileSync('apps/control-tower/owner-project-workspace.js', 'utf8');
const app = fs.readFileSync('apps/control-tower/owner-app.js', 'utf8');
const mobile = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_experience_v2.dart', 'utf8');

test('Exact Undo v2 is a single service-only atomic database primitive', () => {
  assert.match(migration, /create or replace function private\.pandora_apply_application_undo_v2/);
  assert.match(migration, /security definer/);
  assert.match(migration, /for update/);
  assert.match(migration, /UNDO_REQUIRES_ROLLBACK/);
  assert.match(migration, /UNDO_PARENT_NOT_VERIFIED/);
  assert.match(migration, /UNDO_PARENT_PREVIEW_UNAVAILABLE/);
  assert.match(migration, /UNDO_PRECONDITION_MISMATCH/);
  assert.match(migration, /current_version_id=p_parent_version_id/);
  assert.match(migration, /current_deployment_id=p_parent_preview_deployment_id/);
  assert.match(migration, /verification_state='live_verified'/);
  assert.match(migration, /set lifecycle_status='rolled_back'/);
  assert.match(migration, /'previewUrl',p_parent_preview_url/);
  assert.match(migration, /revoke all on function private\.pandora_apply_application_undo_v2[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /grant execute on function private\.pandora_apply_application_undo_v2[\s\S]*to service_role/);
});

test('projection can_undo is forced off for production and non-application current versions', () => {
  assert.match(migration, /pandora_project_experience_undo_guard_v2/);
  assert.match(migration, /new\.current_version_id=new\.production_version_id/);
  assert.match(migration, /v_version\.parent_version_id is null/);
  assert.match(migration, /v_version\.lifecycle_status not in \('built','verification_pending','verified','preview_ready'\)/);
  assert.match(migration, /set can_undo=can_undo/);
  assert.match(migration, /Exact Undo v2 invariant failed/);
});

test('runtime delegates the mutation to the atomic RPC after exact lineage checks', () => {
  const start = runtime.indexOf('async function undoProject');
  const end = runtime.indexOf('async function runtimeSummary', start);
  assert.ok(start > 0 && end > start);
  const undo = runtime.slice(start, end);
  assert.match(undo, /parent_version_id/);
  assert.match(undo, /verification_state\) !== "live_verified"/);
  assert.match(undo, /source_sha256/);
  assert.match(undo, /artifact_digest/);
  assert.match(undo, /source_commit/);
  assert.match(undo, /admin\.rpc\("pandora_apply_application_undo_v2"/);
  assert.match(undo, /p_expected_version_id: expectedVersionId/);
  assert.match(undo, /p_parent_version_id: parentVersionId/);
  assert.match(undo, /p_parent_preview_deployment_id: parentPreviewData\.id/);
  assert.doesNotMatch(undo, /\.update\(\{ lifecycle_status: "rolled_back" \}\)/);
});

test('web Undo uses current not publish candidate and proves the parent before success', () => {
  assert.match(workspace, /function exactUndoIdentity/);
  assert.match(workspace, /runtimeVersionId !== currentVersionId/);
  assert.match(workspace, /currentVersionId === productionVersionId/);
  assert.match(workspace, /runtimeStatus/);
  assert.match(app, /expectedVersionId: undoIdentity\.currentVersionId/);
  assert.match(app, /waitForUndoResolution/);
  assert.match(app, /currentVersionId === identity\.parentVersionId/);
  assert.match(app, /runtimeVersionId === identity\.parentVersionId/);
  assert.match(app, /previewIdentity\?\.versionId === identity\.parentVersionId/);
  assert.match(app, /productionVersionId !== identity\.productionVersionId/);
  assert.match(app, /Undo verified\. Pandora restored the exact verified parent preview and production did not move/);
});


test('native Simple Mode uses the same exact current-to-parent Undo identity', () => {
  assert.match(mobile, /String\? get _undoCurrentVersionId/);
  assert.match(mobile, /runtimeCurrent\.versionId != current/);
  assert.match(mobile, /projection\.productionVersionId == current/);
  assert.match(mobile, /final versionId = _undoCurrentVersionId/);
  assert.match(mobile, /snapshot\.candidate\?\.versionId != parentVersionId/);
  assert.match(mobile, /snapshot\.preview\?\.versionId != parentVersionId/);
  assert.match(mobile, /transition\.currentVersionId != parentVersionId/);
  assert.match(mobile, /transition\.productionVersionId != expectedProductionVersionId/);
  assert.match(mobile, /_loadExactPreviewFiles/);
  assert.match(mobile, /Undo verified\. The exact parent is Current and Live did not move/);
});
