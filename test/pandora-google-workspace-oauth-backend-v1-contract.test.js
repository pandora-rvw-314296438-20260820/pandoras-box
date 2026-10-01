const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const root = join(__dirname, '..');
const baseMigration = readFileSync(join(root, 'supabase/migrations/20260912070000_pandora_google_workspace_oauth_backend_v1.sql'), 'utf8');
const laneMigration = readFileSync(join(root, 'supabase/migrations/20261001130000_pandora_connections_lane_a_v1.sql'), 'utf8');
const hardeningMigration = readFileSync(join(root, 'supabase/migrations/20261001140500_pandora_google_workspace_oidc_verification_v2.sql'), 'utf8');
const edge = readFileSync(join(root, 'supabase/functions/pandora-google-workspace-oauth/index.ts'), 'utf8');
const verifier = readFileSync(join(root, 'supabase/functions/pandora-google-workspace-oauth/google_oidc_verification.mjs'), 'utf8');

test('Google Workspace OAuth uses owner-scoped PKCE, nonce and exact read-first scopes', () => {
  assert.match(baseMigration, /pandora_google_workspace_oauth_prepare_v1/);
  assert.match(hardeningMigration, /interval '10 minutes'/);
  assert.match(hardeningMigration, /code_challenge_method','S256'/);
  assert.match(baseMigration, /pandora_google_workspace_oauth_client_id/);
  assert.match(baseMigration, /pandora_google_workspace_oauth_client_secret/);
  assert.match(baseMigration, /google_workspace_oauth_not_configured/);
  assert.match(laneMigration, /drive\.metadata\.readonly/);
  assert.match(laneMigration, /spreadsheets\.readonly/);
  assert.doesNotMatch(laneMigration.match(/create or replace function private\.pandora_google_workspace_required_scopes_v1[\s\S]*?\$\$;/)?.[0] || '', /auth\/drive'/);
  assert.match(hardeningMigration, /'include_granted_scopes','false'/);
  assert.match(hardeningMigration, /nonceHash',v_row\.nonce_hash/);
});

test('refresh token is service-role committed to Supabase Vault and never exposed to authenticated clients', () => {
  assert.match(baseMigration, /pandora_google_workspace_oauth_material_v1/);
  assert.match(laneMigration, /pandora_google_workspace_oauth_commit_v1/);
  assert.match(laneMigration, /pandora_connection_store_verified_credential_v1/);
  assert.match(laneMigration, /vault\.create_secret/);
  assert.match(laneMigration, /vault\.update_secret/);
  assert.match(baseMigration, /refresh_token_secret_id uuid not null/);
  assert.match(baseMigration, /grant execute on function public\.pandora_google_workspace_oauth_commit_v1[^;]+service_role/);
  assert.match(hardeningMigration, /pandora_google_connected_exact_read_scopes_v2/);
});

test('callback verifies signed OIDC identity, scopes and live Drive access before commit', () => {
  assert.match(edge, /pandora_google_workspace_oauth_material_v1/);
  assert.match(edge, /code_verifier: verifier/);
  assert.match(edge, /oauth2\.googleapis\.com\/token/);
  assert.match(edge, /verifyGoogleIdToken/);
  assert.match(edge, /openidconnect\.googleapis\.com\/v1\/userinfo/);
  assert.match(edge, /drive\/v3\/about\?fields=user/);
  assert.match(edge, /hasExactGoogleReadScopes/);
  assert.match(edge, /driveEmail === identity\.email/);
  assert.match(edge, /pandora_google_workspace_oauth_commit_v1/);
  assert.match(verifier, /crypto\.subtle\.verify/);
  assert.match(verifier, /https:\/\/www\.googleapis\.com\/oauth2\/v3\/certs/);
  assert.match(verifier, /GOOGLE_ISSUERS/);
  assert.match(verifier, /expectedNonceHash/);
  assert.doesNotMatch(edge, /tokeninfo\?/);
  assert.doesNotMatch(edge, /\?access_token=/);
  assert.doesNotMatch(edge, /\?id_token=/);
  assert.doesNotMatch(edge, /console\.(log|debug|info|warn|error)/);
});

test('callback escapes provider identity and avoids URL constructor shadowing', () => {
  assert.match(edge, /const escapeHtml =/);
  assert.match(edge, /escapeHtml\(body\)/);
  assert.match(edge, /const requestUrl = new URL\(req\.url\)/);
  assert.doesNotMatch(edge, /const URL = Deno\.env/);
  assert.match(edge, /content-security-policy/);
});

test('Connected fails closed on stale health or any scope outside the exact read-first set', () => {
  assert.match(hardeningMigration, /status='needs_attention',health_state='unhealthy'/);
  assert.match(hardeningMigration, /GOOGLE_SCOPE_OVERPRIVILEGED/);
  assert.match(hardeningMigration, /v_row\.last_verified_at>=clock_timestamp\(\)-interval '15 minutes'/);
  assert.match(hardeningMigration, /v_row\.scopes<@private\.pandora_google_workspace_required_scopes_v1\(\)/);
  assert.match(hardeningMigration, /validate constraint pandora_google_connected_exact_read_scopes_v2/);
});
