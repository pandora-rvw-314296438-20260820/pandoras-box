const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const root = join(__dirname, '..');
const migration = readFileSync(join(root, 'supabase/migrations/20260925061000_pandora_meta_oauth_marketing_read_v1.sql'), 'utf8');
const edge = readFileSync(join(root, 'supabase/functions/pandora-meta-oauth/index.ts'), 'utf8');
const resolver = readFileSync(join(root, 'apps/meta-business-mcp/src/secrets/supabase-installation-resolver.js'), 'utf8');
const catalog = readFileSync(join(root, 'apps/meta-business-mcp/src/tools/catalog.js'), 'utf8');

test('Meta OAuth is owner-scoped, one-time, and Vault-backed', () => {
  assert.match(migration, /pandora_meta_oauth_owner_required/);
  assert.match(migration, /state_hash/);
  assert.match(migration, /claimed_at is null/);
  assert.match(migration, /consumed_at/);
  assert.match(migration, /vault\.create_secret\(p_user_token/);
  assert.match(migration, /vault\.create_secret\(v_page_token/);
  assert.match(migration, /'vault:\/\/'\|\|v_page_secret/);
  assert.match(migration, /v_page-'access_token'/);
  assert.doesNotMatch(migration, /user_token\s+text/);
});

test('Meta callback verifies live identity, permissions, Pages, and ad accounts before commit', () => {
  assert.match(edge, /me\?fields=id,name/);
  assert.match(edge, /me\/permissions/);
  assert.match(edge, /me\/accounts\?fields=id,name,tasks,access_token/);
  assert.match(edge, /me\/adaccounts\?fields=id,account_id,name,account_status,currency/);
  assert.match(edge, /requiredScopes\.every/);
  assert.match(edge, /pandora_meta_oauth_commit_v1/);
});

test('Meta runtime resolves Page and Marketing credentials from exact installation through service-only RPC', () => {
  assert.match(resolver, /installation:\\/\\/[^\\s]+\\/(?:page|marketing)/);
  assert.match(resolver, /pandora_meta_runtime_secret_v1/);
  assert.match(migration, /pandora_meta_runtime_service_role_required/);
  assert.match(migration, /p_installation_id/);
  assert.match(migration, /p_organization_id/);
});

test('Marketing API reads are exposed while external writes remain separately gated', () => {
  for (const tool of ['meta_ad_accounts_list','meta_ad_campaigns_list','meta_ad_account_insights','meta_campaign_insights']) {
    assert.match(catalog, new RegExp(tool));
  }
  assert.match(catalog, /requiredCapabilities: \['ads\.read'\]/);
  assert.match(catalog, /name: 'meta_post_publish'[\s\S]*mode: 'write'[\s\S]*risk: 'R2'/);
});
