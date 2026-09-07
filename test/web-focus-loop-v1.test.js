const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const auth = read('apps/control-tower/auth.js');
const data = read('apps/control-tower/owner-data.js');
const preview = read('apps/control-tower/owner-preview-focus.js');
const workspace = read('apps/control-tower/owner-project-workspace.js');
const app = read('apps/control-tower/owner-app.js');
const first = read('apps/control-tower/owner-first.js');
const index = read('apps/control-tower/index.html');

test('web exact preview uses authenticated preview-content and a privileged sandbox channel', () => {
  assert.match(auth, /pandora-preview-content/);
  assert.match(app, /hydrateExactWorkspacePreview/);
  assert.match(app, /bundle\.artifactDigest/);
  assert.match(preview, /setAttribute\('sandbox', 'allow-scripts'\)/);
  assert.match(preview, /new MessageChannel\(\)/);
  assert.match(preview, /event\.stopImmediatePropagation\(\)/);
  assert.match(preview, /connect-src 'none'/);
  assert.doesNotMatch([auth, preview, app].join('\n'), /Github_supabase|SUPABASE_SERVICE_ROLE|PRIVATE KEY|gemini_api_key|openai_api_key|moonshot_api_key/i);
});

test('FocusToken v2 is exact-version, exact-artifact and fifteen-minute bounded', () => {
  assert.match(preview, /schemaVersion: 2/);
  assert.match(preview, /artifactDigest/);
  assert.match(preview, /15 \* 60 \* 1000/);
  assert.match(preview, /That selection belongs to an older preview/);
  assert.match(preview, /Apply the owner change specifically to this exact selected object/);
  assert.match(app, /PandorasOwnerPreviewFocus\.intentContext\(focusToken\)/);
});

test('focused web changes enter durable intent, exact spec compilation and governed build', () => {
  assert.match(auth, /pandora_project_intents/);
  assert.match(auth, /intent_kind: 'change'/);
  assert.match(auth, /pandora_project_specs/);
  assert.match(app, /compileExactChange/);
  assert.match(app, /source_intent_id === intentId/);
  assert.match(app, /pandora-project-source-generator/);
  assert.match(app, /candidate_verification_state/);
  assert.match(app, /previewBundle\?\.versionId === candidate/);
});

test('current preview remains authoritative until a verified exact candidate is hydrated', () => {
  assert.match(app, /candidateState === 'passed'/);
  assert.match(app, /current_verified === true/);
  assert.match(app, /Your previous verified result remains current/);
  assert.match(workspace, /data-owner-preview-host/);
  assert.match(workspace, /Focus object/);
});

test('focus assets compose under one cache revision before workspace rendering', () => {
  const revision = 'web-focus-loop-v1-20260907-1';
  assert.ok(first.includes(revision));
  assert.ok(first.indexOf('owner-preview-focus.js') < first.indexOf('owner-project-workspace.js'));
  assert.ok(index.includes(revision));
  assert.ok(data.includes('focusToken: null'));
});
