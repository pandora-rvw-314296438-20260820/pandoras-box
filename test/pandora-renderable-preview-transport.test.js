const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');

const api = readFileSync('api/preview.ts', 'utf8');
const vercel = JSON.parse(readFileSync('vercel.json', 'utf8'));
const migration = readFileSync(
  'supabase/migrations/20260906193000_pandora_renderable_preview_transport_v1.sql',
  'utf8',
);

test('Vercel preview proxy preserves capability authority but serves renderable HTML', () => {
  assert.match(api, /pandora-preview-host/);
  assert.match(api, /text\/html; charset=utf-8/);
  assert.match(api, /sandbox allow-scripts/);
  assert.doesNotMatch(api, /allow-same-origin/);
  assert.match(api, /Access-Control-Allow-Origin/);
  assert.match(api, /MAX_FILE_BYTES/);
  assert.match(api, /redirect: 'error'/);
  assert.match(api, /AbortController/);
  assert.equal(
    new Map(vercel.rewrites.map(({ source, destination }) => [source, destination]))
      .get('/preview/:token/:path*'),
    '/api/preview?token=:token&path=:path*',
  );
});

test('preview and production fallback URLs leave the Supabase shared HTML domain', () => {
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/preview\//);
  assert.match(migration, /pandora_create_supabase_preview_fallback_20260830/);
  assert.match(migration, /pandora_publish_supabase_fallback_20260831/);
  assert.match(migration, /ready_for_verification/);
});

test('Worker E rejects HTTP 200 that is not renderable HTML', () => {
  assert.match(migration, /content-type/);
  assert.match(migration, /content-security-policy/);
  assert.match(migration, /text\/html%/);
  assert.match(migration, /allow-scripts/);
  assert.match(migration, /allow-same-origin/);
  assert.match(migration, /runtime_not_renderable/);
});

test('verification replay is transport-bound and cannot reuse the old PASS', () => {
  assert.match(migration, /static_site_renderable_v2/);
  assert.match(migration, /supabase-static-production-renderable-v3/);
  assert.match(migration, /v_base:=private\.pandora_worker_e_verify_supabase_preview_20260830/);
  assert.match(migration, /SUPABASE_PREVIEW_BASE_VERIFICATION_MISSING/);
});
