const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('domain registrar is Vault-backed, exact-price and explicit-confirmation gated', () => {
  const migration = read('supabase/migrations/20260830090000_pandora_vercel_domain_registrar.sql');
  assert.match(migration, /vault\.decrypted_secrets/);
  assert.match(migration, /where name='vercel'/);
  assert.match(migration, /pandora_quote_domain/);
  assert.match(migration, /pandora_purchase_domain/);
  assert.match(migration, /p_expected_price/);
  assert.match(migration, /p_confirm is not true/);
  assert.match(migration, /DOMAIN_PURCHASE_RECONCILIATION_REQUIRED/);
  assert.match(migration, /contactInformation',p_contact_information/);
  assert.doesNotMatch(migration, /safe_result[^;]*p_contact_information/);
});

test('mobile domain flow uses live quote and purchase RPCs instead of placeholder checkout', () => {
  const api = read('apps/pandora-mobile/lib/core/data/domain_registrar_api.dart');
  const screen = read('apps/pandora-mobile/lib/features/simple/domains_screen.dart');
  const main = read('apps/pandora-mobile/lib/main.dart');
  assert.match(api, /pandora_quote_domain/);
  assert.match(api, /pandora_purchase_domain/);
  assert.match(api, /'p_confirm': true/);
  assert.match(screen, /Check availability/);
  assert.match(screen, /Buy domain/);
  assert.match(screen, /registration contact details|Registration details/);
  assert.doesNotMatch(screen, /needs the RedApple registrar connection/);
  assert.match(main, /DomainRegistrarApi/);
  assert.match(main, /domainRegistrar: domainRegistrar/);
});
