const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');

const app = read('apps', 'control-tower', 'owner-app.js');
const workspace = read('apps', 'control-tower', 'owner-project-workspace.js');

test('active rebuild polling preserves the mounted exact preview', () => {
  assert.match(app, /renderAfter = true/);
  assert.match(app, /loadProjectWorkspace\(item\.sourceId, \{ quiet: true, renderAfter: false \}\)/);
  assert.match(app, /updateWorkspaceProgressDom\(\)/);
  const pollStart = app.indexOf('for (let attempt = 0; attempt < 60; attempt += 1)');
  const pollEnd = app.indexOf("throw new Error('Pandora is still building that change.", pollStart);
  assert.ok(pollStart > 0 && pollEnd > pollStart);
  const poll = app.slice(pollStart, pollEnd);
  const success = poll.indexOf("showToast('Preview updated.");
  assert.ok(success > 0);
  assert.doesNotMatch(poll.slice(0, success), /\brender\(\);/);
  assert.match(poll.slice(success), /render\(\);/);
});

test('Build Theatre and change controls expose bounded in-place update targets', () => {
  assert.match(workspace, /data-workspace-theatre-message/);
  assert.match(workspace, /data-workspace-theatre-progress/);
  assert.match(workspace, /data-workspace-theatre-stages/);
  assert.match(workspace, /data-workspace-theatre-current/);
  assert.match(workspace, /data-workspace-theatre-updated/);
  assert.match(workspace, /data-workspace-change-submit/);
  assert.match(app, /querySelector\('\[data-workspace-theatre-message\]'\)/);
  assert.match(app, /querySelectorAll\('\[data-workspace-theatre-stages\]'\)/);
});

test('automatic project refresh stays lightweight while a change is active', () => {
  assert.match(app, /state\.route === 'project' && state\.projectWorkspace\.changing === true/);
  assert.match(app, /loadProjectWorkspace\(routeResourceFromLocation\(\), \{ quiet: true, renderAfter: false \}\)/);
  assert.match(app, /return;\s*}\s*await refresh\(\);/);
});

test('continuous preview does not weaken exact preview or verification authority', () => {
  assert.match(workspace, /exactPreviewUrl/);
  assert.match(workspace, /previewIdentity/);
  assert.doesNotMatch(workspace, /allow-same-origin/);
  assert.match(app, /nextVersion === candidateVersion && verification === 'passed'/);
  assert.match(app, /nextVersion === currentVersion && experience\.current_verified === true/);
  assert.match(app, /nextVersion !== baselineVersion/);
});
