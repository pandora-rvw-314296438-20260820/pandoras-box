const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');

const app = read('apps', 'control-tower', 'owner-app.js');
const workspace = read('apps', 'control-tower', 'owner-project-workspace.js');
const operator = read('apps', 'meta-business-mcp', 'src', 'operator', 'api.js');
const broker = read('apps', 'meta-business-mcp', 'src', 'operator', 'preview-focus.js');
const edge = read('supabase', 'functions', 'pandora-preview-content', 'index.ts');

test('Vercel focus materialization is exact-version and verified-provider only', () => {
  assert.match(edge, /const FOCUS_MODE = "web_focus"/);
  assert.match(edge, /\.eq\("environment","preview"\)\.eq\("provider","vercel"\)/);
  assert.match(edge, /\.eq\("status","ready"\)\.eq\("provider_state","READY"\)\.eq\("verification_state","live_verified"\)/);
  assert.match(edge, /HOSTED_PREVIEW_IDENTITY_MISMATCH/);
  assert.match(edge, /exactVercelPreviewUrl/);
  assert.match(edge, /host\.endsWith\("\.vercel\.app"\)/);
  assert.match(edge, /HOSTED_PREVIEW_REDIRECT_INVALID/);
  assert.match(edge, /p_action:"preview\.web_focus"/);
  assert.match(edge, /pandora\.web-focus-preview\.v1/);
  const focusStart = edge.indexOf('if(mode===FOCUS_MODE)');
  const entitlement = edge.indexOf('pandora_get_source_entitlement_v1');
  const artifactDownload = edge.indexOf('.download(text(artifactVersion.storage_path))');
  assert.ok(focusStart > 0 && entitlement > focusStart && artifactDownload > entitlement);
  assert.doesNotMatch(edge.slice(focusStart, entitlement), /storage\.from|\.download\(/);
});

test('focus-only HTML contains the same sandbox bridge contract without an iframe escape', () => {
  assert.match(edge, /injectFocusBridge/);
  assert.match(edge, /pandora\.preview\.selection\.v2/);
  assert.match(edge, /event\.source!==parent/);
  assert.match(edge, /parent\.postMessage/);
  assert.doesNotMatch(edge, /allow-same-origin/);
  assert.doesNotMatch(edge, /createSignedUrl|signedURL|signedUrl/);
});

test('same-origin operator route uses read scope and independently verifies returned HTML', () => {
  assert.match(operator, /focus-preview/);
  assert.match(operator, /return 'projectos:read'/);
  assert.match(operator, /(?:change\|focus-preview|change\|focus-preview)/);
  assert.match(broker, /pandora-preview-content/);
  assert.match(broker, /mode: "web_focus"/);
  assert.match(broker, /identity\.accessToken/);
  assert.match(broker, /createHash/);
  assert.match(broker, /htmlDigest !== text\(payload\.sha256\)\.toLowerCase\(\)/);
  assert.doesNotMatch(broker, /SUPABASE_SERVICE_ROLE|service[_-]?role|github_pat_|Github_supabase/i);
});

test('browser re-proves exact identity and SHA before mounting sandboxed srcdoc', () => {
  assert.match(app, /focusHtmlFromEnvelope/);
  assert.match(app, /crypto\.subtle\.digest\('SHA-256', bytes\)/);
  assert.match(app, /payload\.projectId !== identity\.projectId/);
  assert.match(app, /payload\.versionId !== identity\.versionId/);
  assert.match(app, /payload\.artifactDigest/);
  assert.match(app, /frame\.srcdoc = item\.focusPreviewHtml/);
  assert.match(app, /\/focus-preview/);
  assert.match(app, /The preview changed while Pandora was preparing object focus/);
  assert.match(workspace, /preparedFocus \? 'about:blank' : embedded/);
  assert.match(workspace, /sandbox="allow-scripts allow-popups allow-modals allow-downloads"/);
  assert.doesNotMatch(workspace, /allow-same-origin/);
});

test('prepared focus HTML is invalidated when exact preview identity advances', () => {
  assert.match(app, /item\.focusPreviewVersionId !== previewIdentity\.versionId/);
  assert.match(app, /item\.focusPreviewArtifactDigest !== previewIdentity\.artifactDigest/);
  assert.match(app, /item\.focusPreviewHtml = null/);
  assert.match(app, /clearPreparedFocusPreview/);
});
