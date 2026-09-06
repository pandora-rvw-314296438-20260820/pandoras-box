const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = join(__dirname, '..');
const ownerApi = readFileSync(
  join(root, 'supabase/functions/pandora-owner-api/index.ts'),
  'utf8',
);
const migration = readFileSync(
  join(root, 'supabase/migrations/20260906154250_pandora_meta_live_connection_verifier_v1.sql'),
  'utf8',
);

test('owner Meta connection test uses the live Vault-backed verifier', () => {
  assert.match(ownerApi, /async function verifyMetaConnection\(/);
  assert.match(ownerApi, /pandora_verify_meta_connection_20260906/);
  assert.match(
    ownerApi,
    /normalizedProvider === "meta"[\s\S]{0,180}verifyMetaConnection\(context, connectionId\)/,
  );
});

test('Meta verifier binds exact connector, Vault ref, Page identity, and service-role execution', () => {
  assert.match(migration, /provider = 'meta'/);
  assert.match(migration, /credential_refs/);
  assert.match(migration, /rotation_state = 'current'/);
  assert.match(migration, /\^vault:\/\//);
  assert.match(migration, /vault\.decrypted_secrets/);
  assert.match(migration, /https:\/\/graph\.facebook\.com\//);
  assert.match(migration, /coalesce\(v_body->>'id', ''\) <> v_page_id/);
  assert.match(migration, /status = 'active'::public\.connector_status/);
  assert.match(migration, /grant execute[\s\S]*to service_role/i);
  assert.match(migration, /revoke all[\s\S]*from public, anon, authenticated/i);
});

test('Meta verifier never returns credential material and does not claim App ownership', () => {
  const returnBlock = migration.slice(migration.lastIndexOf('return jsonb_build_object('));
  assert.doesNotMatch(returnBlock, /v_token|decrypted_secret|secret_ref/i);
  assert.match(returnBlock, /appOwnershipVerified/);
  assert.match(returnBlock, /app_ownership_verified/);
});
