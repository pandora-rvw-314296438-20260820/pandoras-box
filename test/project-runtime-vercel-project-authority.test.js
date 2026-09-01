const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const source = fs.readFileSync('supabase/functions/pandora-project-runtime/index.ts', 'utf8');

function block(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0, `missing ${startMarker}`);
  assert.ok(end > start, `missing ${endMarker}`);
  return source.slice(start, end);
}

test('stored Vercel project bindings require authoritative provider readback before reuse', () => {
  const ensure = block('async function ensureVercelProject', 'async function projectByIdentifier');
  const existing = ensure.indexOf('if (existingId && existingName)');
  const readback = ensure.indexOf('vercelRequest(`/v9/projects/${encodeURIComponent(existingId)}`');
  const reusableReturn = ensure.indexOf('return { id: existingId', existing);
  assert.ok(existing >= 0);
  assert.ok(readback > existing, 'provider readback must occur inside the existing-binding path');
  assert.ok(reusableReturn > readback, 'stored binding must not be returned before provider readback');
  assert.match(ensure, /authoritativeId !== existingId \|\| !authoritativeName/);
  assert.match(ensure, /VERCEL_PROJECT_IDENTITY_MISMATCH/);
});

test('provider-confirmed rename/default-domain drift is refreshed from authority', () => {
  const ensure = block('async function ensureVercelProject', 'async function projectByIdentifier');
  assert.match(ensure, /const defaultDomain = `\$\{authoritativeName\}\.vercel\.app`/);
  assert.match(ensure, /vercelProjectName: authoritativeName/);
  assert.match(ensure, /vercelDefaultDomain: defaultDomain/);
  assert.match(ensure, /config: nextConfig/);
});

test('missing provider project is a fail-closed trust conflict', () => {
  const request = block('async function vercelRequest', 'async function ensureVercelProject');
  assert.match(request, /status === 404/);
  assert.match(request, /\.test\(path\)/);
  assert.match(request, /VERCEL_PROJECT_NOT_FOUND/);
  assert.match(source, /"VERCEL_PROJECT_NOT_FOUND", "VERCEL_PROJECT_IDENTITY_MISMATCH"/);
});
