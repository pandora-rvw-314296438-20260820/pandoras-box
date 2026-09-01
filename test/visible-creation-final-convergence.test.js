const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const preview = fs.readFileSync('supabase/functions/pandora-preview-content/index.ts', 'utf8');
const api = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart', 'utf8');
const workspace = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_experience_v2.dart', 'utf8');
const workspaceView = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_workspace_v2_view.dart', 'utf8');

test('exact preview is bound to deployment, source, commit and artifact identity', () => {
  assert.match(preview, /source_commit/);
  assert.match(preview, /source_commit_sha/);
  assert.match(preview, /previewDeploymentId/);
  assert.match(preview, /sourceSha256:sourceSha/);
  assert.match(preview, /sourceCommitSha/);
  assert.match(api, /previewDeploymentId/);
  assert.match(api, /sourceSha256/);
  assert.match(api, /sourceCommitSha/);
  assert.match(workspace, /ProjectPreviewIdentity\.fromExactPreviewFiles/);
  assert.match(workspace, /exact preview identity is still preparing/);
});

test('subsequent changes keep the product visible while real build theatre streams', () => {
  assert.match(workspace, /_activeBuildStreamId/);
  assert.match(workspace, /_activeBuildSnapshot/);
  assert.match(workspace, /watchResilientBuildStream/);
  assert.match(workspace, /_startActiveBuildTheatre\(experience, buildStart\)/);
  assert.match(workspaceView, /_LiveBuildActivityCapsule/);
  assert.match(workspaceView, /ProjectBuildStreamTheatreProjection\.fromSnapshot/);
  assert.match(workspaceView, /LiveBuildTheatre\(state: theatre!\)/);
  assert.doesNotMatch(workspaceView, /% complete|progressPercent|progress_percent/i);
});


test('durable conversation history is surfaced inside the live product workspace', () => {
  const repository = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_repository.dart', 'utf8');
  assert.match(repository, /loadProjectConversation/);
  assert.match(workspace, /_conversationHistory/);
  assert.match(workspace, /loadProjectConversation/);
  assert.match(workspaceView, /_ProjectHistoryCard/);
  assert.match(workspaceView, /project-conversation-history/);
  assert.match(workspaceView, /Project history/);
});
