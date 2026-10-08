"use strict";

// Deployed owner API (provider v97 -> v98) PayPal billing module: explicit
// sandbox routing, unchanged live path, reason pass-through, no secrets.

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const dir = path.join(__dirname, "..", "ops/supabase/runtime-patches/pandora-owner-api-v98-plp-billing-sandbox");
const modulePath = path.join(dir, "paypal-billing.mjs");
const load = () => import(modulePath);
const source = fs.readFileSync(modulePath, "utf8");
const indexSource = fs.readFileSync(path.join(dir, "index.ts"), "utf8");
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
const ORG = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const OTHER = "11111111-2222-4333-8444-555555555555";
const USER = "cee14af6-5a2a-47d7-a6c6-d79ef50d346b";

function request(headers = {}) {
  return { headers: new Headers(headers) };
}

function fakeAdmin({ allowlist = ORG, rpc = {}, tables = {} } = {}) {
  const calls = [];
  const from = (table) => {
    const q = { table, filters: [] };
    const api = {
      select() { return api; },
      eq(col, val) { q.filters.push([col, val]); return api; },
      order() { return api; },
      limit() { return api; },
      async maybeSingle() {
        calls.push({ from: table, filters: q.filters });
        if (table === "pandora_runtime_provider_configs") {
          return { data: allowlist == null ? null : { config_value: allowlist }, error: null };
        }
        return { data: (tables[table] || [])[0] ?? null, error: null };
      },
      then(resolve) { calls.push({ from: table, filters: q.filters }); resolve({ data: tables[table] || [], error: null }); },
    };
    return api;
  };
  return {
    calls,
    from,
    rpc: async (fn, args) => {
      calls.push({ rpc: fn, args });
      const handler = rpc[fn];
      if (!handler) return { data: { ok: true }, error: null };
      return handler(args);
    },
  };
}

test("live path is the exact provider v97 module, byte-for-byte, as a prefix", () => {
  const v97 = manifest.provider.baselineFiles["paypal-billing.mjs"];
  const prefix = Buffer.from(source, "utf8").subarray(0, v97.bytes);
  assert.equal(crypto.createHash("sha256").update(prefix).digest("hex"), v97.sha256);
});

test("no header or 'live' is live and never reads the sandbox allowlist", async () => {
  const { billingEnvironment } = await load();
  for (const headers of [{}, { "x-pandora-billing-environment": "live" }, { "x-pandora-billing-environment": " LIVE " }]) {
    const admin = fakeAdmin();
    assert.equal(await billingEnvironment(admin, request(headers), ORG), "live");
    assert.equal(admin.calls.length, 0);
  }
});

test("sandbox is explicit: header + x-organization-id + allowlisted org", async () => {
  const { billingEnvironment } = await load();
  const ok = request({ "x-pandora-billing-environment": "sandbox", "x-organization-id": ORG });
  assert.equal(await billingEnvironment(fakeAdmin(), ok, ORG), "sandbox");
  await assert.rejects(billingEnvironment(fakeAdmin(), request({ "x-pandora-billing-environment": "staging" }), ORG), /BILLING_ENVIRONMENT_INVALID/);
  await assert.rejects(billingEnvironment(fakeAdmin(), request({ "x-pandora-billing-environment": "sandbox" }), ORG), /BILLING_ORGANIZATION_REQUIRED/);
  await assert.rejects(billingEnvironment(fakeAdmin(), request({ "x-pandora-billing-environment": "sandbox", "x-organization-id": OTHER }), OTHER), /BILLING_SANDBOX_NOT_ALLOWED/);
  await assert.rejects(billingEnvironment(fakeAdmin({ allowlist: null }), ok, ORG), /BILLING_SANDBOX_NOT_ALLOWED/);
});

test("sandbox cancel calls only the sandbox function and passes the blocked reason through", async () => {
  const { sandboxBillingCancel } = await load();
  const blocked = { cancelRequested: false, cancelled: false, verified: false, providerState: "APPROVAL_PENDING", reason: "AWAITING_BUYER_APPROVAL" };
  const admin = fakeAdmin({ rpc: { pandora_plp_billing_sandbox_cancel_v1: async () => ({ data: blocked, error: null }) } });
  const result = await sandboxBillingCancel(admin, { organizationId: ORG, userId: USER }, { reason: "x".repeat(300) });
  assert.deepEqual(result, blocked);
  assert.deepEqual(admin.calls.map((c) => c.rpc), ["pandora_plp_billing_sandbox_cancel_v1"]);
  assert.equal(admin.calls[0].args.p_reason.length, 128);
  assert.equal(admin.calls[0].args.p_organization_id, ORG);
});

test("sandbox checkout/reconcile route to sandbox functions; change-plan is refused, not emulated", async () => {
  const m = await load();
  const admin = fakeAdmin();
  await m.sandboxBillingCheckout(admin, { organizationId: ORG, userId: USER }, { planCode: "launch", idempotencyKey: "plp-checkout-123456789" });
  await m.sandboxBillingReconcile(admin, { organizationId: ORG, userId: USER });
  assert.deepEqual(admin.calls.map((c) => c.rpc), ["pandora_plp_billing_sandbox_checkout_v1", "pandora_plp_billing_sandbox_reconcile_v1"]);
  assert.throws(() => m.sandboxBillingChangePlan(), /SANDBOX_PLAN_CHANGE_UNAVAILABLE/);
  assert.deepEqual(m.sandboxBillingErrorResponse("SANDBOX_PLAN_CHANGE_UNAVAILABLE")[0], 409);
});

test("sandbox raised codes map to specific codes, unknown ones never leak raw messages", async () => {
  const m = await load();
  const raising = (message) => fakeAdmin({ rpc: { pandora_plp_billing_sandbox_reconcile_v1: async () => ({ data: null, error: { message } }) } });
  const ctx = { organizationId: ORG, userId: USER };
  await assert.rejects(m.sandboxBillingReconcile(raising("PAYPAL_SANDBOX_AUTH_FAILED"), ctx), (e) => e.message === "PAYPAL_SANDBOX_AUTH_FAILED");
  await assert.rejects(m.sandboxBillingReconcile(raising("PAYPAL_PATH_NOT_ALLOWED"), ctx), (e) => e.message === "PAYPAL_SANDBOX_REQUEST_BLOCKED");
  await assert.rejects(m.sandboxBillingReconcile(raising("relation secret_thing does not exist Bearer abc"), ctx), (e) => e.message === "SANDBOX_BILLING_REQUEST_FAILED");
  for (const code of ["PAYPAL_SANDBOX_AUTH_FAILED", "PAYPAL_SANDBOX_REQUEST_BLOCKED", "SANDBOX_BILLING_REQUEST_FAILED", "BILLING_SANDBOX_NOT_ALLOWED", "BILLING_ENVIRONMENT_INVALID"]) {
    assert.ok(m.sandboxBillingErrorResponse(code), code);
  }
  assert.equal(m.sandboxBillingErrorResponse("PLAN_NOT_FOUND"), null, "live codes keep their live mapping");
});

test("sandbox status is a read-only select shaped like live status", async () => {
  const { sandboxBillingStatus } = await load();
  const admin = fakeAdmin({ tables: {
    pandora_paypal_sandbox_billing_sessions: [{ id: "s1", plan_code: "launch", status: "approval_pending", paypal_subscription_id: "I-DEULPR0J35DH", approval_url: "https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-test", expires_at: null, created_at: "2026-10-08T19:04:03Z", updated_at: "2026-10-08T19:04:03Z" }],
    pandora_service_plans: [{ id: "p1", code: "launch", name: "Launch", currency: "USD", monthly_fee_micros: 49000000 }],
    pandora_paypal_catalog_bindings: [{ plan_code: "launch", paypal_plan_id: "P-1" }],
  } });
  const status = await sandboxBillingStatus(admin, ORG);
  assert.equal(status.environment, "sandbox");
  assert.equal(status.subscription, null);
  assert.equal(status.checkout.status, "approval_pending");
  assert.equal(status.checkout.trust, "pending_action");
  assert.equal(status.plans[0].monthly_fee, "49.00");
  assert.equal(status.plans[0].provider_linked, true);
  assert.ok(admin.calls.every((c) => !c.rpc), "status performs no RPC (no PayPal call)");
});

test("module and index never touch secrets; sandbox never falls through to live routes", () => {
  assert.doesNotMatch(source, /decrypted_secret|vault\.|SERVICE_ROLE|access_token|Bearer|console\./);
  assert.match(indexSource, /x-organization-id, x-pandora-billing-environment"/);
  const sandboxBlock = indexSource.slice(indexSource.indexOf('=== "sandbox") {'), indexSource.indexOf('if (req.method === "GET" && route === "/billing/paypal/status") {\n        return send(await billingStatus('));
  assert.match(sandboxBlock, /A sandbox request never falls through to a live route\.\n\s+return reject\(404/);
  assert.doesNotMatch(sandboxBlock, /billingCancel\(|billingCheckout\(|billingReconcile\(|billingChangePlan\(/);
});
