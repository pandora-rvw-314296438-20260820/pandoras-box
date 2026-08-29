
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('domain registrar remains Vault-backed and price-confirmation gated', () => {
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

test('RedApple checkout collects through Xendit or PayPal before registrar spend', () => {
  const foundation = read('supabase/migrations/20260830091000_pandora_domain_checkout_payments_v1.sql');
  const flow = read('supabase/migrations/20260830092000_pandora_domain_checkout_public_flow_v1.sql');
  assert.match(foundation, /xendit_secret_key/);
  assert.match(foundation, /paypal_client_id/);
  assert.match(foundation, /paypal_client_secret/);
  assert.match(foundation, /\/sessions/);
  assert.match(foundation, /\/v2\/checkout\/orders/);
  assert.match(foundation, /pgp_sym_encrypt|domain_contact_encryption_key/);
  assert.match(foundation, /pandora_domain_checkouts/);
  assert.match(flow, /pandora_create_domain_checkout/);
  assert.match(flow, /pandora_reconcile_domain_checkout/);
  assert.match(flow, /pandora_purchase_domain/);
  assert.match(flow, /revoke execute on function public\.pandora_purchase_domain/);
  assert.match(flow, /\/refunds/);
  assert.match(flow, /\/v2\/payments\/captures\//);
  assert.match(flow, /registrarAutoRenew/);
  assert.match(flow, /false/);
});

test('mobile domain flow offers Xendit and PayPal hosted checkout instead of direct purchase', () => {
  const api = read('apps/pandora-mobile/lib/core/data/domain_registrar_api.dart');
  const models = read('apps/pandora-mobile/lib/core/models/domain_registrar_models.dart');
  const screen = read('apps/pandora-mobile/lib/features/simple/domains_screen.dart');
  const pubspec = read('apps/pandora-mobile/pubspec.yaml');
  const main = read('apps/pandora-mobile/lib/main.dart');
  assert.match(api, /pandora_quote_domain_checkout/);
  assert.match(api, /pandora_create_domain_checkout/);
  assert.match(api, /pandora_reconcile_domain_checkout/);
  assert.doesNotMatch(api, /pandora_purchase_domain/);
  assert.match(models, /DomainPaymentGateway/);
  assert.match(models, /xendit/);
  assert.match(models, /paypal/);
  assert.match(screen, /Xendit/);
  assert.match(screen, /PayPal/);
  assert.match(screen, /launchUrl/);
  assert.match(screen, /Check payment/);
  assert.match(screen, /Auto-renew is off for now/);
  assert.doesNotMatch(screen, /Buy domain/);
  assert.match(pubspec, /url_launcher: 6\.3\.2/);
  assert.match(main, /DomainRegistrarApi/);
  assert.match(main, /domainRegistrar: domainRegistrar/);
});
