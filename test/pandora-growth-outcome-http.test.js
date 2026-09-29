"use strict";

const assert = require("node:assert/strict");
const express = require("express");
const test = require("node:test");
const { createPandoraTrackingRouter } = require("../src/pandora-tracking-http.js");

const ORG = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const PROJECT = "ee282126-3f61-4058-8c92-2fedbfcecf1f";
const TENANT = "326b51af-0445-4e96-bf31-d346bab05220";
const API_KEY_ID = "33333333-3333-4333-8333-333333333333";
const API_KEY = "ptk_" + "a".repeat(64);
const POLICY = "privacy-test-v1";

function response(payload, status = 200) {
  return new Response(payload === null ? null : JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function outcome() {
  return {
    schema_version: 1,
    event_name: "payment_settled",
    event_id: "event:payment:1",
    outcome_id: "outcome:payment:1",
    acquisition_path: "self_serve",
    organization_id: ORG,
    tracking_tenant_id: TENANT,
    project_id: PROJECT,
    journey_id: "journey:1",
    subject_id: "subject:1",
    occurred_at: "2026-09-29T01:00:00.000Z",
    delivery_source: "server",
    is_test: false,
    evidence: {
      payment_ref: "payment:1",
      settlement_ref: "settlement:1",
    },
    attribution: { kind: "unattributed" },
    money: { amount_minor: 14900000, currency: "PHP" },
  };
}

function fixture(calls, { privacy = false, duplicate = false } = {}) {
  return async (url, options = {}) => {
    const target = new URL(url);
    const resource = target.pathname.replace(/^\/rest\/v1\//, "");
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({ resource, method: options.method || "GET", body, search: target.search });

    if (resource === "pandora_tracking_api_keys" && options.method !== "PATCH") {
      return response([{
        id: API_KEY_ID,
        tenant_id: TENANT,
        scopes: ["outcome:write"],
        status: "active",
        expires_at: null,
      }]);
    }
    if (resource.startsWith("pandora_tracking_api_keys?") && options.method === "PATCH") {
      return response(null, 204);
    }
    if (resource === "pandora_tracking_tenants") {
      return response([{ id: TENANT, organization_id: ORG, project_id: PROJECT, status: "active" }]);
    }
    if (resource === "pandora_growth_privacy_authorizations") {
      return response(privacy ? [{
        policy_version: POLICY,
        allowed_flows: ["server_outcomes"],
        expires_at: null,
      }] : []);
    }
    if (resource === "rpc/pandora_ingest_growth_outcome_v1") {
      return response([{
        ok: true,
        duplicate,
        receiptId: "44444444-4444-4444-8444-444444444444",
        trackingEventId: "55555555-5555-4555-8555-555555555555",
        moneyProjection: "minor_units_only",
      }]);
    }
    if (options.method === "PATCH") return response(null, 204);
    return response(null, 404);
  };
}

async function withApp(fetchFn, run) {
  const app = express();
  app.use(createPandoraTrackingRouter({
    environment: {
      SUPABASE_URL: "https://fixture.supabase.test",
      SUPABASE_SERVICE_ROLE_KEY: "fixture",
    },
    fetchFn,
  }));
  const server = await new Promise((resolve) => {
    const active = app.listen(0, "127.0.0.1", () => resolve(active));
  });
  try {
    const address = server.address();
    await run("http://127.0.0.1:" + address.port);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve())
    );
  }
}

test("authoritative outcome intake is held without explicit privacy policy", async () => {
  const calls = [];
  await withApp(fixture(calls), async (base) => {
    const res = await fetch(base + "/api/tracking/outcome", {
      method: "POST",
      headers: {
        authorization: "Bearer " + API_KEY,
        "content-type": "application/json",
        "x-pandora-privacy-policy": POLICY,
      },
      body: JSON.stringify(outcome()),
    });
    assert.equal(res.status, 403);
    assert.equal((await res.json()).error, "privacy_authorization_required");
  });
  assert.equal(calls.some((call) => call.resource === "rpc/pandora_ingest_growth_outcome_v1"), false);
});

test("authorized outcome is normalized and persisted through the atomic RPC", async () => {
  const calls = [];
  await withApp(fixture(calls, { privacy: true }), async (base) => {
    const res = await fetch(base + "/api/tracking/outcome", {
      method: "POST",
      headers: {
        authorization: "Bearer " + API_KEY,
        "content-type": "application/json",
        "x-pandora-privacy-policy": POLICY,
      },
      body: JSON.stringify(outcome()),
    });
    assert.equal(res.status, 201);
    const payload = await res.json();
    assert.equal(payload.ok, true);
    assert.equal(payload.duplicate, false);
    assert.equal(payload.money_projection, "minor_units_only");
  });
  const rpc = calls.find((call) => call.resource === "rpc/pandora_ingest_growth_outcome_v1");
  assert.ok(rpc);
  assert.equal(rpc.body.p_policy_version, POLICY);
  assert.equal(rpc.body.p_event.organization_id, ORG);
  assert.equal(rpc.body.p_event.tracking_tenant_id, TENANT);
  assert.equal(rpc.body.p_event.is_test, false);
  assert.deepEqual(rpc.body.p_event.money, { amount_minor: 14900000, currency: "PHP" });
  assert.match(rpc.body.p_claim_sha256, /^[0-9a-f]{64}$/);
});

test("exact outcome replay returns duplicate without changing semantic money", async () => {
  const calls = [];
  await withApp(fixture(calls, { privacy: true, duplicate: true }), async (base) => {
    const res = await fetch(base + "/api/tracking/outcome", {
      method: "POST",
      headers: {
        authorization: "Bearer " + API_KEY,
        "content-type": "application/json",
        "x-pandora-privacy-policy": POLICY,
      },
      body: JSON.stringify(outcome()),
    });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).duplicate, true);
  });
});

test("caller cannot change trusted organization/project scope", async () => {
  const calls = [];
  const forged = outcome();
  forged.organization_id = "11111111-1111-4111-8111-111111111111";
  await withApp(fixture(calls, { privacy: true }), async (base) => {
    const res = await fetch(base + "/api/tracking/outcome", {
      method: "POST",
      headers: {
        authorization: "Bearer " + API_KEY,
        "content-type": "application/json",
        "x-pandora-privacy-policy": POLICY,
      },
      body: JSON.stringify(forged),
    });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, "scope_mismatch");
  });
});
