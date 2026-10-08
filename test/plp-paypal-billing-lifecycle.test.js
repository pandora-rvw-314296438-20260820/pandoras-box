"use strict";

// Behavioural tests for the owner API PayPal billing lifecycle.
//
// The real billing block of supabase/functions/pandora-owner-api/index.ts is
// transpiled and executed against an in-memory Supabase double and a PayPal
// double at the fetch() boundary, so every PayPal request the owner API would
// send is counted. No real credentials, tokens or network are involved.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const vm = require("node:vm");
const ts = require("typescript");

const ownerApiPath = path.join(__dirname, "..", "supabase/functions/pandora-owner-api/index.ts");
const ownerApi = fs.readFileSync(ownerApiPath, "utf8");
const blockStart = ownerApi.indexOf("type BillingEnv =");
assert.ok(blockStart > 0, "billing block start marker missing");
const billingSource = ownerApi.slice(blockStart) +
  "\n;globalThis.__billing={billingCancel,billingReconcile,billingWebhook,BILLING_ERROR_RESPONSES};\n";
const billingJs = ts.transpileModule(billingSource, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None },
}).outputText;

const ORG = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const USER = "a0d6f184-3039-4735-8d11-63ce403636e2";
const SUB = "I-DEULPR0J35DH";
const PAYPAL_PLAN = "P-LAUNCH-TEST";
const FAKE_TOKEN = "fake-paypal-access-token-for-tests";
const FAKE_CLIENT_SECRET = "fake-client-secret-for-tests";
const LIVE = "pandora_customer_subscriptions";
const LIVE_SESSIONS = "pandora_paypal_billing_sessions";
const SANDBOX = "pandora_paypal_sandbox_subscriptions";
const SANDBOX_SESSIONS = "pandora_paypal_sandbox_billing_sessions";

function clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }

// Minimal PostgREST-style builder over in-memory rows.
function fakeSupabase(tables, writes) {
  function builder(table) {
    const state = { op: "select", filters: [], order: null, limit: null, payload: null, returning: false };
    const rows = () => (tables[table] ||= []);
    const match = (row) => state.filters.every((f) => f(row));
    const run = () => {
      if (state.op === "select") {
        let out = rows().filter(match).map(clone);
        if (state.order) {
          const [col, asc] = state.order;
          out.sort((a, b) => (a[col] > b[col] ? 1 : a[col] < b[col] ? -1 : 0) * (asc ? 1 : -1));
        }
        if (state.limit != null) out = out.slice(0, state.limit);
        return out;
      }
      if (state.op === "update") {
        const hit = rows().filter(match);
        for (const row of hit) Object.assign(row, clone(state.payload));
        writes.push({ table, op: "update", payload: clone(state.payload), count: hit.length });
        return hit.map(clone);
      }
      if (state.op === "upsert") {
        const payload = clone(state.payload);
        const existing = rows().find((r) => r.organization_id === payload.organization_id);
        if (existing) Object.assign(existing, payload); else rows().push(payload);
        writes.push({ table, op: "upsert", payload: clone(payload), count: 1 });
        return [payload];
      }
      if (state.op === "insert") {
        const payload = { id: "row-" + (rows().length + 1), ...clone(state.payload) };
        rows().push(payload);
        writes.push({ table, op: "insert", payload: clone(payload), count: 1 });
        return [payload];
      }
      throw new Error("unsupported op");
    };
    const api = {
      select() { if (state.op !== "select") state.returning = true; return api; },
      update(payload) { state.op = "update"; state.payload = payload; return api; },
      upsert(payload) { state.op = "upsert"; state.payload = payload; return api; },
      insert(payload) { state.op = "insert"; state.payload = payload; return api; },
      eq(col, val) { state.filters.push((r) => String(r[col]) === String(val)); return api; },
      neq(col, val) { state.filters.push((r) => String(r[col]) !== String(val)); return api; },
      in(col, vals) { state.filters.push((r) => vals.map(String).includes(String(r[col]))); return api; },
      not(col, op, val) {
        assert.equal(op, "is"); assert.equal(val, null);
        state.filters.push((r) => r[col] != null); return api;
      },
      order(col, opts) { state.order = [col, opts?.ascending !== false]; return api; },
      limit(n) { state.limit = n; return api; },
      async maybeSingle() { const out = run(); return { data: out[0] ?? null, error: null }; },
      async single() { const out = run(); return out[0] ? { data: out[0], error: null } : { data: null, error: { code: "PGRST116" } }; },
      then(resolve, reject) { try { resolve({ data: run(), error: null }); } catch (e) { reject(e); } },
    };
    return api;
  }
  return {
    from: (table) => builder(table),
    rpc: async (name, args) => {
      assert.equal(name, "pandora_paypal_secret");
      if (/secret/.test(args.p_name)) return { data: FAKE_CLIENT_SECRET, error: null };
      return { data: "fake-" + args.p_name, error: null };
    },
  };
}

// PayPal double. Behaves like PayPal: cancel on an APPROVAL_PENDING
// subscription returns 404 INVALID_RESOURCE_ID ('The specified resource does
// not exist.'); cancel on ACTIVE returns 204.
function fakePaypal(initialStatus, { afterCancel = "CANCELLED", cancelHttp = 204, nextBilling = "2026-11-08T10:00:00Z" } = {}) {
  const pp = { status: initialStatus, calls: [] };
  pp.fetch = async (url, init = {}) => {
    const u = new URL(String(url));
    const method = String(init.method || "GET").toUpperCase();
    const headers = new Headers(init.headers || {});
    pp.calls.push({ method, host: u.host, path: u.pathname, requestId: headers.get("paypal-request-id") });
    const json = (status, body) => new Response(body == null ? null : JSON.stringify(body), { status, headers: body == null ? {} : { "content-type": "application/json" } });
    if (u.pathname === "/v1/oauth2/token") return json(200, { access_token: FAKE_TOKEN });
    if (u.pathname === "/v1/notifications/verify-webhook-signature") return json(200, { verification_status: "SUCCESS" });
    let m = u.pathname.match(/^\/v1\/billing\/subscriptions\/([^/]+)\/cancel$/);
    if (m && method === "POST") {
      if (pp.status !== "ACTIVE" && pp.status !== "SUSPENDED") {
        return json(404, { name: "RESOURCE_NOT_FOUND", message: "The specified resource does not exist.", debug_id: "ca47769d0cff3", details: [{ issue: "INVALID_RESOURCE_ID" }] });
      }
      if (cancelHttp === 204) pp.status = afterCancel;
      return json(cancelHttp, cancelHttp === 204 ? null : { name: "INTERNAL_SERVER_ERROR", debug_id: "dbg-test" });
    }
    m = u.pathname.match(/^\/v1\/billing\/subscriptions\/([^/]+)$/);
    if (m && method === "GET") {
      return json(200, {
        id: m[1], status: pp.status, plan_id: PAYPAL_PLAN, custom_id: "session-1",
        start_time: "2026-10-08T19:04:03Z", create_time: "2026-10-08T19:04:03Z",
        billing_info: pp.status === "ACTIVE" ? { next_billing_time: nextBilling } : {},
      });
    }
    return json(500, { name: "UNEXPECTED_TEST_PATH" });
  };
  pp.cancelPosts = () => pp.calls.filter((c) => c.method === "POST" && c.path.endsWith("/cancel"));
  pp.reads = () => pp.calls.filter((c) => c.method === "GET" && c.path.startsWith("/v1/billing/subscriptions/"));
  return pp;
}

function harness({ env = "sandbox", paypal, tables }) {
  const writes = [];
  const logs = [];
  const db = fakeSupabase(tables, writes);
  const context = {
    console: { log: (...a) => logs.push(a.join(" ")), error: (...a) => logs.push(a.join(" ")), warn: (...a) => logs.push(a.join(" ")) },
    fetch: paypal.fetch, Response, Request, Headers, URL, AbortSignal, btoa, TextEncoder, crypto: globalThis.crypto,
    JSON, Date, Math, Number, String, Object, Array, Promise, Error, Set, Map, RegExp, Boolean, Symbol,
    SUPABASE_URL: "https://example.supabase.co",
    ALLOWED_ORIGINS: new Set(["https://example.test"]),
    createOperationalAdminClient: () => db,
    asRecord: (v) => (v && typeof v === "object" && !Array.isArray(v) ? v : {}),
    textValue: (v, f = "") => (typeof v === "string" && v.trim() ? v.trim() : f),
    sha256Hex: async () => "0".repeat(64),
  };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(billingJs, context, { filename: "owner-api-billing.js" });
  const user = { organizationId: ORG, userId: USER, aal: "aal2" };
  return { billing: context.__billing, user, writes, logs, tables, env };
}

function baseTables({ subscription = null, session = null, env = "sandbox" } = {}) {
  const subs = env === "sandbox" ? SANDBOX : LIVE;
  const sessions = env === "sandbox" ? SANDBOX_SESSIONS : LIVE_SESSIONS;
  return {
    [subs]: subscription ? [subscription] : [],
    [sessions]: session ? [session] : [],
    pandora_runtime_provider_configs: [{ config_key: "mode", config_value: "live", active: true, provider: "paypal" }],
    pandora_service_plans: [{ id: "plan-launch", code: "launch", name: "Launch", state: "active", currency: "USD", monthly_fee_micros: 49000000, paypal_product_id: "PROD-1", paypal_plan_id: PAYPAL_PLAN }],
    pandora_paypal_catalog_bindings: [{ environment: "sandbox", plan_code: "launch", paypal_product_id: "PROD-1", paypal_plan_id: PAYPAL_PLAN }],
  };
}

const pendingSession = (env = "sandbox") => ({
  id: "session-1", organization_id: ORG, plan_code: "launch", paypal_subscription_id: SUB,
  status: "approval_pending", created_at: "2026-10-08T19:04:03Z", ...(env === "sandbox" ? { environment: "sandbox" } : {}),
});
const verifiedActive = (env = "sandbox") => ({
  organization_id: ORG, plan_id: "plan-launch", state: "active", currency: "USD", monthly_fee_micros: 49000000,
  starts_on: "2026-10-08", ends_on: null, renews_on: "2026-11-08", source_kind: "provider_verified",
  provider_reference: SUB, verified_at: "2026-10-09T00:00:00Z",
  ...(env === "sandbox" ? { environment: "sandbox", provider_status: "ACTIVE" } : { request_admission_enabled: true, request_admission_started_at: "2026-10-08T19:10:00Z" }),
});
const activeSession = (env = "sandbox") => ({ ...pendingSession(env), status: "active" });

function subRow(h) { return (h.tables[h.env === "sandbox" ? SANDBOX : LIVE] || [])[0] || null; }
function sessionRow(h) { return (h.tables[h.env === "sandbox" ? SANDBOX_SESSIONS : LIVE_SESSIONS] || [])[0] || null; }
function assertNoSecrets(value, logs = []) {
  const text = JSON.stringify(value) + "\n" + logs.join("\n");
  assert.doesNotMatch(text, new RegExp(FAKE_TOKEN));
  assert.doesNotMatch(text, new RegExp(FAKE_CLIENT_SECRET));
  assert.doesNotMatch(text, /fake-paypal_client_id/);
  assert.doesNotMatch(text, /Bearer|Basic /);
}

for (const env of ["sandbox", "live"]) {
  test(`[${env}] APPROVAL_PENDING checkout: cancel is BLOCKED (AWAITING_BUYER_APPROVAL), no PayPal cancel is sent, nothing recorded as cancelled`, async () => {
    const paypal = fakePaypal("APPROVAL_PENDING");
    const h = harness({ env, paypal, tables: baseTables({ env, session: pendingSession(env) }) });
    const result = await h.billing.billingCancel(env, h.user, { reason: "owner test" });
    assert.equal(paypal.cancelPosts().length, 0, "no POST /cancel may reach PayPal while APPROVAL_PENDING");
    assert.equal(result.status, "blocked");
    assert.equal(result.reason, "AWAITING_BUYER_APPROVAL");
    assert.equal(result.cancelled, false);
    assert.equal(result.cancelRequested, false);
    assert.equal(result.verified, false);
    assert.equal(result.providerStatus, "APPROVAL_PENDING");
    assert.equal(subRow(h), null, "no subscription row may be created");
    assert.equal(sessionRow(h).status, "approval_pending", "checkout must not be marked cancelled or cancel_requested");
    assert.equal(h.writes.length, 0, "a blocked cancel writes nothing");
    assertNoSecrets(result, h.logs);
  });

  test(`[${env}] verified row but PayPal reads back APPROVAL_PENDING: cancel is BLOCKED, no POST /cancel, row untouched`, async () => {
    const paypal = fakePaypal("APPROVAL_PENDING");
    const h = harness({ env, paypal, tables: baseTables({ env, subscription: verifiedActive(env), session: activeSession(env) }) });
    const result = await h.billing.billingCancel(env, h.user, {});
    assert.equal(paypal.cancelPosts().length, 0);
    assert.equal(result.status, "blocked");
    assert.equal(result.reason, "AWAITING_BUYER_APPROVAL");
    assert.equal(result.cancelled, false);
    assert.equal(subRow(h).state, "active");
    assert.equal(h.writes.length, 0);
  });

  test(`[${env}] APPROVAL_PENDING: reconcile returns NOT VERIFIED and writes nothing`, async () => {
    const paypal = fakePaypal("APPROVAL_PENDING");
    const h = harness({ env, paypal, tables: baseTables({ env, session: pendingSession(env) }) });
    const result = await h.billing.billingReconcile(env, h.user);
    assert.equal(result.verified, false);
    assert.equal(result.state, "approval_pending");
    assert.equal(result.reason, "AWAITING_BUYER_APPROVAL");
    assert.equal(paypal.cancelPosts().length, 0);
    assert.equal(subRow(h), null);
    assert.equal(h.writes.length, 0);
  });

  test(`[${env}] happy path: ACTIVE readback -> one POST /cancel (idempotency key kept) -> CANCELLED readback -> recorded cancelled`, async () => {
    const paypal = fakePaypal("ACTIVE", { afterCancel: "CANCELLED" });
    const h = harness({ env, paypal, tables: baseTables({ env, subscription: verifiedActive(env), session: activeSession(env) }) });
    const result = await h.billing.billingCancel(env, h.user, { reason: "owner test" });
    const posts = paypal.cancelPosts();
    assert.equal(posts.length, 1);
    assert.equal(posts[0].requestId, "pandora-cancel-" + SUB);
    assert.equal(posts[0].host, env === "sandbox" ? "api-m.sandbox.paypal.com" : "api-m.paypal.com");
    const order = paypal.calls.filter((c) => c.path !== "/v1/oauth2/token").map((c) => c.method + " " + c.path);
    assert.deepEqual(order, [
      "GET /v1/billing/subscriptions/" + SUB,
      "POST /v1/billing/subscriptions/" + SUB + "/cancel",
      "GET /v1/billing/subscriptions/" + SUB,
    ]);
    assert.equal(result.status, "cancelled");
    assert.equal(result.cancelled, true);
    assert.equal(result.verified, true);
    assert.equal(result.providerStatus, "CANCELLED");
    const row = subRow(h);
    assert.equal(row.state, "cancelled");
    assert.equal(row.source_kind, "provider_verified");
    assert.equal(row.renews_on, null);
    assert.equal(row.ends_on, "2026-11-08", "paid-through date comes from PayPal's ACTIVE readback");
    if (env === "live") assert.equal(row.request_admission_enabled, false);
    else assert.equal(row.provider_status, "CANCELLED");
    assert.equal(sessionRow(h).status, "cancelled");
    assertNoSecrets(result, h.logs);
  });

  test(`[${env}] negative: ACTIVE -> POST /cancel accepted -> readback still ACTIVE -> NOT recorded as cancelled (unconfirmed)`, async () => {
    const paypal = fakePaypal("ACTIVE", { afterCancel: "ACTIVE" });
    const h = harness({ env, paypal, tables: baseTables({ env, subscription: verifiedActive(env), session: activeSession(env) }) });
    const result = await h.billing.billingCancel(env, h.user, {});
    assert.equal(paypal.cancelPosts().length, 1);
    assert.equal(paypal.reads().length, 2, "readback after the cancel is mandatory");
    assert.equal(result.status, "cancel_unconfirmed");
    assert.equal(result.cancelled, false);
    assert.equal(result.cancelRequested, true);
    assert.equal(result.verified, false);
    assert.equal(result.providerStatus, "ACTIVE");
    assert.equal(subRow(h).state, "active", "never record cancelled without a CANCELLED readback");
    assert.equal(sessionRow(h).status, "cancel_requested", "recorded as unconfirmed, not cancelled");
    assert.ok(!h.writes.some((w) => w.payload && w.payload.state === "cancelled"));
    assert.ok(!h.writes.some((w) => w.payload && w.payload.status === "cancelled"));
  });
}

test("PayPal rejects the cancel (non-2xx) and still reads ACTIVE: error, nothing recorded", async () => {
  const paypal = fakePaypal("ACTIVE", { cancelHttp: 500 });
  const h = harness({ env: "sandbox", paypal, tables: baseTables({ subscription: verifiedActive(), session: activeSession() }) });
  await assert.rejects(h.billing.billingCancel("sandbox", h.user, {}), /PAYPAL_CANCEL_FAILED/);
  assert.equal(paypal.cancelPosts().length, 1);
  assert.equal(subRow(h).state, "active");
  assert.equal(sessionRow(h).status, "active");
  assert.ok(!h.writes.some((w) => w.payload && (w.payload.state === "cancelled" || w.payload.status === "cancelled")));
  assertNoSecrets({}, h.logs);
});

test("a subscription PLP has not provider-verified is never cancelled at PayPal, even if PayPal reads ACTIVE", async () => {
  const paypal = fakePaypal("ACTIVE");
  const h = harness({ env: "sandbox", paypal, tables: baseTables({ session: pendingSession() }) });
  const result = await h.billing.billingCancel("sandbox", h.user, {});
  assert.equal(paypal.cancelPosts().length, 0);
  assert.equal(result.status, "blocked");
  assert.equal(result.reason, "RECONCILIATION_REQUIRED");
  assert.equal(h.writes.length, 0);

  const manual = { ...verifiedActive("live"), source_kind: "manual", verified_at: null };
  const paypal2 = fakePaypal("ACTIVE");
  const h2 = harness({ env: "live", paypal: paypal2, tables: baseTables({ env: "live", subscription: manual }) });
  const result2 = await h2.billing.billingCancel("live", h2.user, {});
  assert.equal(paypal2.cancelPosts().length, 0);
  assert.equal(result2.status, "blocked");
  assert.equal(result2.reason, "RECONCILIATION_REQUIRED");
});

test("approval -> reconcile ACTIVE marks provider_verified -> only then cancel -> CANCELLED readback recorded", async () => {
  const paypal = fakePaypal("APPROVAL_PENDING");
  const h = harness({ env: "sandbox", paypal, tables: baseTables({ session: pendingSession() }) });
  const blocked = await h.billing.billingCancel("sandbox", h.user, {});
  assert.equal(blocked.reason, "AWAITING_BUYER_APPROVAL");
  assert.equal((await h.billing.billingReconcile("sandbox", h.user)).verified, false);
  paypal.status = "ACTIVE"; // buyer approves at PayPal
  const reconciled = await h.billing.billingReconcile("sandbox", h.user);
  assert.equal(reconciled.verified, true);
  assert.equal(reconciled.state, "active");
  assert.equal(subRow(h).source_kind, "provider_verified");
  assert.equal(paypal.cancelPosts().length, 0, "nothing was cancelled before approval");
  const cancelled = await h.billing.billingCancel("sandbox", h.user, {});
  assert.equal(paypal.cancelPosts().length, 1);
  assert.equal(cancelled.status, "cancelled");
  assert.equal(subRow(h).state, "cancelled");
  // Replay is idempotent: already recorded cancelled, no second PayPal cancel.
  const replay = await h.billing.billingCancel("sandbox", h.user, {});
  assert.equal(replay.status, "cancelled");
  assert.equal(paypal.cancelPosts().length, 1);
});

test("reconcile never writes provider_verified state for a status PayPal has not activated", async () => {
  const paypal = fakePaypal("APPROVAL_PENDING");
  const h = harness({ env: "live", paypal, tables: baseTables({ env: "live", subscription: verifiedActive("live") }) });
  const result = await h.billing.billingReconcile("live", h.user);
  assert.equal(result.verified, false);
  assert.equal(h.writes.length, 0);
  assert.equal(subRow(h).state, "active");
});

function webhookRequest(eventType, id = "WH-" + eventType) {
  return new Request("https://example.supabase.co/functions/v1/pandora-owner-api/billing/paypal/webhook", {
    method: "POST",
    headers: {
      "paypal-transmission-id": "t-1", "paypal-transmission-time": "2026-10-09T00:00:00Z",
      "paypal-cert-url": "https://api.paypal.com/cert", "paypal-auth-algo": "SHA256withRSA", "paypal-transmission-sig": "sig",
    },
    body: JSON.stringify({ id, event_type: eventType, resource: { id: SUB, status: "CANCELLED", plan_id: PAYPAL_PLAN } }),
  });
}

test("webhook: a CANCELLED event is not recorded as cancelled while PayPal still reads back ACTIVE", async () => {
  const paypal = fakePaypal("ACTIVE");
  const tables = baseTables({ env: "live", subscription: verifiedActive("live"), session: { ...activeSession("live"), requested_by: USER } });
  tables.pandora_paypal_billing_webhook_events = [];
  const h = harness({ env: "live", paypal, tables });
  const response = await h.billing.billingWebhook(webhookRequest("BILLING.SUBSCRIPTION.CANCELLED"));
  assert.equal(response.status, 200);
  assert.equal(subRow(h).state, "active");
  assert.equal(paypal.cancelPosts().length, 0);
});

test("webhook: an ACTIVATED event is not recorded while PayPal still reads back APPROVAL_PENDING", async () => {
  const paypal = fakePaypal("APPROVAL_PENDING");
  const tables = baseTables({ env: "live", session: { ...pendingSession("live"), requested_by: USER } });
  tables.pandora_paypal_billing_webhook_events = [];
  const h = harness({ env: "live", paypal, tables });
  await assert.rejects(h.billing.billingWebhook(webhookRequest("BILLING.SUBSCRIPTION.ACTIVATED")), /PAYPAL_SUBSCRIPTION_NOT_CONFIRMED/);
  assert.equal(subRow(h), null);
  assert.equal(tables.pandora_paypal_billing_webhook_events[0].processing_status, "failed");
});

test("webhook: a CANCELLED event with a CANCELLED readback is recorded as cancelled", async () => {
  const paypal = fakePaypal("CANCELLED");
  const tables = baseTables({ env: "live", subscription: verifiedActive("live"), session: { ...activeSession("live"), requested_by: USER } });
  tables.pandora_paypal_billing_webhook_events = [];
  const h = harness({ env: "live", paypal, tables });
  const response = await h.billing.billingWebhook(webhookRequest("BILLING.SUBSCRIPTION.CANCELLED"));
  assert.equal(response.status, 200);
  assert.equal(subRow(h).state, "cancelled");
});

test("owner API billing block keeps PayPal secrets out of code, responses and logs", () => {
  const block = ownerApi.slice(blockStart);
  assert.doesNotMatch(block, /decrypted_secret/);
  assert.match(block, /paypal_client_id_sandbox/);
  assert.match(block, /"paypal-request-id":"pandora-cancel-"\+subId/);
  assert.doesNotMatch(block, /console\.(log|error)\([^)]*(token|clientSecret|access_token)/i);
});
