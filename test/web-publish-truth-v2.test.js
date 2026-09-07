const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const workspace = read('apps/control-tower/owner-project-workspace.js');
const app = read('apps/control-tower/owner-app.js');
const data = read('apps/control-tower/owner-data.js');

test('web publish truth is projection driven and never equates provider return with Live', () => {
  assert.match(data, /mutationPhase: null/);
  assert.match(workspace, /label: 'Publishing'/);
  assert.match(workspace, /label: 'Checking'/);
  assert.match(app, /item\.mutationPhase = 'publishing'/);
  assert.match(app, /item\.mutationPhase = 'checking'/);
  assert.match(app, /waitForPublishResolution/);
  assert.match(app, /return 'live'/);
  assert.match(app, /return 'needs-you'/);
  assert.match(app, /return 'problem'/);
  assert.match(app, /Pandora will not call this version Live until proof arrives/);
});

test('publish reconciliation is bounded and refreshes workspace quietly', () => {
  assert.match(app, /attempts = 20, delayMs = 1500/);
  assert.match(app, /loadProjectWorkspace\(sourceId, \{ quiet: true \}\)/);
  assert.match(app, /loadProjectWorkspace\(routeResourceFromLocation\(\), \{ quiet: true \}\)/);
});