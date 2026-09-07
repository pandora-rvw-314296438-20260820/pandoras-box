const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');

const app = read('apps', 'control-tower', 'owner-app.js');
const workspace = read('apps', 'control-tower', 'owner-project-workspace.js');
const preview = read('api', 'preview.ts');
const operator = read('apps', 'meta-business-mcp', 'src', 'operator', 'api.js');
const change = read('apps', 'meta-business-mcp', 'src', 'operator', 'project-change.js');

test('web focus loop keeps the exact preview as the result hero', () => {
  assert.match(workspace, /data-project-preview-frame/);
  assert.match(workspace, /Focus object/);
  assert.match(workspace, /previewIdentity/);
  assert.match(workspace, /runtimePreview\?\.artifact_digest/);
  assert.match(workspace, /focusCapablePreviewUrl/);
  assert.match(workspace, /https:\/\/mcpmaster\.vercel\.app/);
  assert.match(workspace, /trustedOrigins\.has\(url\.origin\)/);
  assert.ok(workspace.includes('/^\\/preview\\/[0-9a-f]{64}\\/index\\.html$/i'));
  assert.match(workspace, /Object focus is unavailable on this preview transport/);
  assert.doesNotMatch(workspace, /allow-same-origin/);
});

test('preview focus bridge stays sandboxed and communicates by postMessage', () => {
  assert.match(preview, /injectFocusBridge/);
  assert.match(preview, /pandora\.preview\.selection\.v2/);
  assert.match(preview, /parent\.postMessage/);
  assert.match(preview, /sandbox allow-scripts allow-popups allow-modals allow-downloads/);
  assert.doesNotMatch(preview, /allow-same-origin/);
});

test('FocusToken v2 is created only from the currently visible exact identity', () => {
  assert.match(app, /schemaVersion: 2/);
  assert.match(app, /15 \* 60 \* 1000/);
  assert.match(app, /token\.artifactDigest === identity\.artifactDigest/);
  assert.match(app, /That selection belongs to an older preview/);
  assert.match(app, /pandora\.preview\.focus-mode\.v1/);
});

test('Tell Pandora now enters the durable change to build path without browser credentials', () => {
  assert.match(app, /\/projects\/.*\/change/);
  assert.match(change, /pandora_project_intents/);
  assert.match(change, /pandora-project-spec-compiler/);
  assert.match(change, /pandora-project-source-generator/);
  assert.match(change, /source_intent_id/);
  assert.match(operator, /projectos:execute/);
  assert.match(operator, /EXECUTOR_ROLE_REQUIRED/);
  assert.doesNotMatch(app, /Github_supabase|service[_-]?role|SUPABASE_SERVICE_ROLE/i);
  assert.doesNotMatch(change, /Github_supabase|SUPABASE_SERVICE_ROLE|github_pat_/i);
});
