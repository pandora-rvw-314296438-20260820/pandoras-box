'use strict';
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const billingPath = path.join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'features', 'enterprise', 'plp_paypal_billing_screen.dart');
const billing = fs.readFileSync(billingPath, 'utf8');

test('provider configuration is not presented as subscription verification', () => {
  assert.match(billing, /providerLabel\s*=\s*verified[\s\S]*?'Unconfirmed'[\s\S]*?'Configured'/);
  assert.doesNotMatch(billing, /verified\s*\?\s*'Connected'\s*:\s*provider\['configured'\]\s*===\s*true\s*\?\s*'Ready'/);
});

test('missing renewal data is not rendered as a fabricated pending renewal date', () => {
  assert.match(billing, /renewalDate\.isNotEmpty[\s\S]*?'Next renewal[\s\S]*?'Renewal date has not been confirmed by the provider\.'/);
  assert.doesNotMatch(billing, /'Renews '\s*\+\s*\(subscription\['renews_on'\]\s*\?\?\s*'pending'\)/);
});

test('plan selection is separate from starting checkout', () => {
  assert.match(billing, /Widget _planOption\(String code\)/);
  assert.match(billing, /onTap: _busy \? null : \(\) => setState\(\(\) => _selectedPlanCode = code\)/);
  assert.match(billing, /Continue with PayPal[\s\S]*?_checkout\(_selectedPlanCode\)/);
});

test('plan changes have a review step before the provider operation', () => {
  assert.match(billing, /Review plan change/);
  assert.match(billing, /if \(selection != null && selection != currentCode\)\s*\{\s*await _confirmPlanChange\(selection\);\s*\}/);
  assert.match(billing, /await _changePlan\(code\)/);
});

test('cancellation explains pending provider confirmation without guessing access timing', () => {
  assert.match(billing, /Request cancellation/);
  assert.match(billing, /effective date and any change to access will be shown only when confirmed/);
  assert.match(billing, /current status is not treated as cancelled/);
});

test('billing actions reserve space for the floating assistant', () => {
  assert.match(billing, /Widget _safeActionRow/);
  assert.match(billing, /padding: const EdgeInsets\.only\(right: 56\)/);
  assert.match(billing, /_safeActionRow\(\s*title: 'Refresh PayPal state'/);
});


test('an existing PayPal approval is resumed instead of creating another checkout', () => {
  assert.match(billing, /final existingApproval[\s\S]*?if \(existingApproval\.isNotEmpty\)\s*\{\s*await _openApproval\(existingApproval\);\s*return;/);
  assert.match(billing, /else if \(approvalUrl\.isNotEmpty\) \.\.\.\[/);
  assert.match(billing, /Continue your existing approval/);
  assert.match(billing, /_selectedPlanCode = loadedPlanCode/);
});
