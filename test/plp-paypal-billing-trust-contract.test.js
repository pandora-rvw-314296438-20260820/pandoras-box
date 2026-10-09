'use strict';
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');
const billingPath=path.join(__dirname,'..','apps','pandora-mobile','lib','features','enterprise','plp_paypal_billing_screen.dart');
const billing=fs.readFileSync(billingPath,'utf8');
test('only provider-verified status and timestamp imply verified billing',()=>{
 assert.match(billing,/subscription\['source_kind'\] == 'provider_verified' && subscription\['verified_at'\] != null/);
 assert.match(billing,/verified \? 'Active' : 'Unconfirmed'/);
 assert.match(billing,/'Subscription status unconfirmed'/);
});
test('renewal and plan-change timing use only known values',()=>{
 assert.match(billing,/plpBillingShortDate\(subscription\['renews_on'\]\)/);
 assert.match(billing,/The effective date will follow the provider-confirmed subscription state/);
 assert.doesNotMatch(billing,/'next cycle'/);
});
test('billing keeps its shell key and resumes pending approvals',()=>{
 assert.match(billing,/key: const ValueKey\('plp-paypal-billing'\)/);
 assert.match(billing,/Widget _pendingCheckoutPage\(String approval\)/);
});
test('plans and approval handoff are separate screens',()=>{
 assert.match(billing,/key: const ValueKey\('plp-capability-pay-with-paypal'\)/);
 assert.match(billing,/key: const ValueKey\('plp-capability-continue-to-paypal'\)/);
});
test('plan changes and cancellation require owner confirmation',()=>{
 assert.match(billing,/title: 'Change plan\.'/);
 assert.match(billing,/Confirm plan change/);
 assert.match(billing,/title: 'Cancel subscription\?'/);
 assert.match(billing,/key: const ValueKey\('plp-billing-confirm-cancel'\)/);
});
test('retry resumes the existing PayPal approval and does not duplicate checkout',()=>{
 assert.match(billing,/_pendingApprovalUrl \?\? _existingApprovalUrl\(\)/);
 assert.match(billing,/await _refreshAfterHandoff\(\)/);
});
test('post-handoff status errors get a status-only recovery path',()=>{
 assert.match(billing,/PayPal opened, but billing status could not be refreshed/);
 assert.match(billing,/key: const ValueKey\('plp-billing-refresh-status'\)/);
});
test('approval URLs are HTTPS PayPal URLs only',()=>{
 assert.match(billing,/uri\.scheme != 'https' \|\| !trustedHost/);
 assert.match(billing,/host == 'paypal\.com' \|\| host\.endsWith\('\.paypal\.com'\)/);
});
test('billing retains owner API boundary and has no embedded PayPal credentials',()=>{
 const api=fs.readFileSync(path.join(__dirname,'..','apps','pandora-mobile','lib','core','data','plp_paypal_billing_api.dart'),'utf8');
 for(const source of [billing,api]){
  assert.doesNotMatch(source,/api(-m)?(\.sandbox)?\.paypal\.com|v1\/billing\/subscriptions|oauth2\/token/i);
  assert.doesNotMatch(source,/client_?secret|PAYPAL_SECRET|service_role|Basic /i);
 }
 assert.match(api,/'x-organization-id': organizationId/);
 assert.match(billing,/plpOwnerBillingTransport\(widget\.organizationId\)/);
});
