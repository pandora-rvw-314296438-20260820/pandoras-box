"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const test = require("node:test");

const migration = readFileSync(
  "supabase/migrations/20261009013800_pandora_plp_enterprise_billing_workspace_v1.sql",
  "utf8",
);
const billing = readFileSync(
  "supabase/functions/pandora-owner-api/paypal-billing.mjs",
  "utf8",
);
const ownerApi = readFileSync(
  "supabase/functions/pandora-owner-api/index.ts",
  "utf8",
);
const screen = readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/plp_paypal_billing_screen.dart",
  "utf8",
);

test("billing status exposes subscription, plan change, and real activity sources", () => {
  for (const table of [
    "pandora_paypal_billing_sessions",
    "pandora_paypal_plan_change_sessions",
    "pandora_paypal_billing_webhook_events",
    "pandora_customer_payments",
    "pandora_customer_subscriptions",
    "pandora_service_plans",
  ]) {
    assert.match(migration, new RegExp(table));
  }
  for (const field of [
    "plan_code",
    "renews_on",
    "provider_reference",
    "verified_at",
    "pendingPlanChange",
    "approval_url",
    "price_delta",
  ]) {
    assert.match(migration, new RegExp(field));
  }
  assert.doesNotMatch(migration, /jsonb_build_object\([^)]*decrypted_secret/i);
  assert.match(migration, /revoke all on function public\.pandora_plp_billing_status_v1/);
});

test("owner billing routes stay authenticated and do not echo secrets", () => {
  for (const route of [
    "/billing/paypal/status",
    "/billing/paypal/checkout",
    "/billing/paypal/change-plan",
    "/billing/paypal/reconcile",
    "/billing/paypal/cancel",
  ]) {
    assert.match(ownerApi, new RegExp(route.replaceAll("/", "\\/")));
  }
  assert.match(billing, /pandora_plp_billing_status_v1/);
  assert.doesNotMatch(billing, /paypal_client_secret/);
  assert.doesNotMatch(screen, /client_secret|PAYPAL_CLIENT/i);
});

test("billing screen is a revenue workspace, not the rejected settings layout", () => {
  assert.match(screen, /eyebrow: 'Revenue'/);
  assert.match(screen, /Current subscription/);
  assert.match(screen, /\/ month/);
  assert.match(screen, /Reconcile with PayPal/);
  assert.match(screen, /Cancel subscription/);
  assert.match(screen, /Awaiting PayPal approval/);
  assert.doesNotMatch(screen, /USD 49 \/ month/);
  assert.doesNotMatch(screen, /Choose a plan/);
  assert.doesNotMatch(screen, /Pandora billing\./);
});
