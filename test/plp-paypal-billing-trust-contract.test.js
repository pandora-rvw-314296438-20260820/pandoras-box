'use strict';
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const billingPath = path.join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'features', 'enterprise', 'plp_paypal_billing_screen.dart');
const billing = fs.readFileSync(billingPath, 'utf8');

test('provider configuration is not presented as subscription verification', () => {
  assert.match(billing, /providerLabel\s*=\s*verified[\s\S]*?'Unconfirmed'[\s\S]*?'Configured'/);
  assert.match(billing, /detail: active \? providerLabel : null/);
  assert.match(billing, /final verified = !_unresolved &&\s*subscription\['source_kind'\] == 'provider_verified' &&\s*subscription\['verified_at'\] != null;/);
  assert.doesNotMatch(billing, /verified\s*\?\s*'Connected'\s*:\s*provider\['configured'\]\s*===\s*true\s*\?\s*'Ready'/);
});

test('missing renewal data is not rendered as a fabricated pending renewal date', () => {
  assert.match(billing, /final renewalDate = plpBillingShortDate\(subscription\['renews_on'\]\)/);
  assert.match(billing, /if \(renewalDate\.isNotEmpty\) 'renews \$renewalDate'/);
  assert.match(billing, /renewalDate\.isEmpty \? '' : ' from \$renewalDate'/);
  assert.doesNotMatch(billing, /'Renews '\s*\+\s*\(subscription\['renews_on'\]\s*\?\?\s*'pending'\)/);
  assert.doesNotMatch(billing, /'next cycle'/);
});

test('plan selection is separate from starting checkout', () => {
  const cardMethod = billing.slice(billing.indexOf('Widget _buildPlanCard('));
  const planSelection = cardMethod.slice(0, cardMethod.indexOf('Widget _buildReview'));
  assert.match(planSelection, /_selectedPlanCode = code;/);
  assert.match(planSelection, /OwnerAnalyticsEvent\.planSelected/);
  assert.doesNotMatch(planSelection, /_checkout/);
  assert.match(billing, /'Continue to PayPal'[\s\S]*?_checkout\(/);
});

test('plan changes have a review step before the provider operation', () => {
  assert.match(billing, /'Change plan',[\s\S]*?_show\(_BillingView\.changeConfirm, others\.first\.code\)/);
  assert.match(billing, /_view == _BillingView\.changeConfirm[\s\S]*?'Switch to \$\{target\.name\}',[\s\S]*?_tap\(\(\) => _changePlan\(target\.code\)\)/);
});

test('cancellation is confirmed in place and only reconciled state counts as cancelled', () => {
  assert.match(billing, /_view == _BillingView\.cancelConfirm[\s\S]*?keepTile,[\s\S]*?'Cancel',[\s\S]*?_tap\(_cancel\),\s*emphasis: true/);
  assert.match(billing, /if \(mounted && state != 'cancelled' && state != 'canceled'\) \{\s*setState\(\(\) => _cancelRequested = outcome\['cancelled'\] != true\);/);
  assert.match(billing, /notice = 'Cancellation pending';/);
  assert.match(billing, /cancelled\s*\?\s*\(ends\.isEmpty \? 'Cancelled' : 'Cancelled · ends \$ends'\)/);
});

test('billing tiles reserve space for the floating assistant', () => {
  assert.match(billing, /Keeps the last tile clear of the floating PLP launcher\.\s*const SizedBox\(height: 72\)/);
});

test('billing uses in-page confirmation, not Material dialogs or bottom sheets', () => {
  assert.doesNotMatch(billing, /showModalBottomSheet|showDialog|AlertDialog|BottomSheet/);
});

test('billing actions cannot double submit and retries reuse the idempotency key', () => {
  assert.match(billing, /Future<void> _run\(String pending, Future<void> Function\(\) work\) async \{\s*if \(_busy\) return;/);
  assert.match(billing, /VoidCallback\? _tap\(VoidCallback action\) => _busy \? null : action;/);
  assert.match(billing, /_idempotencyKeys\.putIfAbsent\(/);
});

test('billing never calls PayPal directly, holds no secrets and no hard-coded organization', () => {
  const api = fs.readFileSync(path.join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'core', 'data', 'plp_paypal_billing_api.dart'), 'utf8');
  for (const source of [billing, api]) {
    assert.doesNotMatch(source, /api(-m)?(\.sandbox)?\.paypal\.com|v1\/billing\/subscriptions|oauth2\/token/i);
    assert.doesNotMatch(source, /client_?secret|PAYPAL_SECRET|service_role|Basic /i);
  }
  assert.match(api, /'x-organization-id': organizationId/);
  assert.match(billing, /plpOwnerBillingTransport\(widget\.organizationId\)/);
  assert.match(api, /PandoraConfig\.ownerApiBaseUrl \+ path/);
});

test('an existing PayPal approval is resumed instead of creating another checkout', () => {
  assert.match(billing, /final existingApproval[\s\S]*?if \(existingApproval\.isNotEmpty\)\s*\{\s*await _openApproval\(existingApproval\);\s*return;/);
  assert.match(billing, /You started checkout for \$openPlanName\. Finish in PayPal or choose again\./);
  assert.match(billing, /_selectedPlanCode = loadedPlanCode/);
});

test('live price is read from DB micros before decimal fallbacks', () => {
  assert.match(billing, /final currentPrice = _monthlyPrice\(subscription\);/);
  const fn = billing.slice(billing.indexOf('static String _monthlyPrice('));
  const net = fn.indexOf("subscription['net_monthly_fee_micros']");
  const gross = fn.indexOf("subscription['monthly_fee_micros']");
  const discount = fn.indexOf("subscription['discount_micros']");
  const decimal = fn.indexOf("subscription['net_monthly_fee']");
  const decimalGross = fn.indexOf("subscription['monthly_fee']");
  assert.ok(net > 0 && gross > net && discount > gross && decimal > discount && decimalGross > decimal);
  assert.match(fn, /\(feeMicros - discountMicros\) \/ 1000000/);
  assert.match(fn, /\} \/ month';/);
  assert.match(fn, /'Price unavailable'/);
  assert.doesNotMatch(billing, /subscription\['net_monthly_fee'\] \?\? subscription\['monthly_fee'\];\s*final currentPrice = fee/);
});
