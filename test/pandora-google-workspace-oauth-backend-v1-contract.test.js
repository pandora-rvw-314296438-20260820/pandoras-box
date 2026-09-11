const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const root = join(__dirname, '..');
const migration = readFileSync(join(root, 'supabase/migrations/20260912070000_pandora_google_workspace_oauth_backend_v1.sql'), 'utf8');
const edge = readFileSync(join(root, 'supabase/functions/pandora-google-workspace-oauth/index.ts'), 'utf8');

test('Google Workspace OAuth uses owner-scoped PKCE and fails closed without Vault client material', () => {
  assert.match(migration, /pandora_google_workspace_oauth_prepare_v1/);
  assert.match(migration, /interval '10 minutes'/);
  assert.match(migration, /code_challenge_method','S256'/);
  assert.match(migration, /pandora_google_workspace_oauth_client_id/);
  assert.match(migration, /pandora_google_workspace_oauth_client_secret/);
  assert.match(migration, /google_workspace_oauth_not_configured/);
  assert.match(migration, /https:\/\/www\.googleapis\.com\/auth\/drive/);
  assert.match(migration, /https:\/\/www\.googleapis\.com\/auth\/spreadsheets/);
});

test('refresh token is service-role committed to Supabase Vault and never exposed to authenticated clients', () => {
  assert.match(migration, /pandora_google_workspace_oauth_material_v1/);
  assert.match(migration, /pandora_google_workspace_oauth_commit_v1/);
  assert.match(migration, /vault\.create_secret/);
  assert.match(migration, /vault\.update_secret/);
  assert.match(migration, /refresh_token_secret_id uuid not null/);
  assert.match(migration, /grant execute on function public\.pandora_google_workspace_oauth_commit_v1[^;]+service_role/);
  assert.match(migration, /pandora_google_workspace_connection_v1/);
});

test('callback verifies identity, scopes and live Drive access before commit', () => {
  assert.match(edge, /pandora_google_workspace_oauth_material_v1/);
  assert.match(edge, /code_verifier: verifier/);
  assert.match(edge, /oauth2\.googleapis\.com\/token/);
  assert.match(edge, /oauth2\/v3\/userinfo/);
  assert.match(edge, /drive\/v3\/about\?fields=user/);
  assert.match(edge, /tokeninfo\?access_token=/);
  assert.match(edge, /requiredScopes\.every/);
  assert.match(edge, /pandora_google_workspace_oauth_commit_v1/);
  assert.doesNotMatch(edge, /console\.(log|debug|info|warn|error)/);
});