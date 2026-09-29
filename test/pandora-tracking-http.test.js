"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const express = require("express");
const {
  createPandoraTrackingRouter,
  _trackingInternals: {
    buildDestinationUrl,
    createClickId,
    parseBearerKey,
    parseConsentFlags,
    parseSchemaVersion,
    parseTestMarker,
    sanitizeIncomingQuery,
    sanitizeMetadata,
    sha256,
  },
} = require("../src/pandora-tracking-http.js");

test("tracking router constructs without production credentials", () => {
  assert.doesNotThrow(() => createPandoraTrackingRouter({
    environment: {},
    fetchFn: async () => {
      throw new Error("network should not be reached during construction");
    },
  }));
});


test("tracking click IDs are opaque fixed-size identifiers", () => {
  assert.match(createClickId(), /^pdc_[0-9a-f]{32}$/);
});

test("tracking query sanitizer drops all incoming attribution and arbitrary input", () => {
  assert.deepEqual(sanitizeIncomingQuery({
    utm_source: "meta",
    fbclid: "abc",
    sub1: "owner",
    password: "must-not-pass",
    nested: { bad: true },
  }), {});
});

test("tracking destination preserves configured query and adds only click attribution", () => {
  const result = new URL(buildDestinationUrl(
    "https://example.com/offer?reviewed=keep",
    { utm_source: "incoming", fbclid: "fb-1" },
    { source: "campaign-source", medium: "paid-social", campaign: "owners" },
    "pdc_0123456789abcdef0123456789abcdef",
  ));
  assert.equal(result.searchParams.get("reviewed"), "keep");
  assert.equal(result.searchParams.get("pcid"), "pdc_0123456789abcdef0123456789abcdef");
  assert.equal(result.searchParams.has("utm_source"), false);
  assert.equal(result.searchParams.has("fbclid"), false);
  assert.throws(
    () => buildDestinationUrl("https://user:secret@example.com/", {}, {}, createClickId()),
    (error) => error.code === "campaign_destination_invalid",
  );
});

test("tracking API keys are accepted only in the opaque bearer format", () => {
  const key = "ptk_" + "a".repeat(64);
  assert.equal(parseBearerKey("Bearer " + key), key);
  assert.equal(parseBearerKey("Bearer not-a-key"), null);
  assert.equal(parseBearerKey(key), null);
});

test("tracking rejects caller-defined metadata and accepts only absent or empty objects", () => {
  assert.deepEqual(sanitizeMetadata(undefined), {});
  assert.deepEqual(sanitizeMetadata({}), {});
  for (const value of [{ ok: true }, [], "metadata", false, null]) {
    assert.throws(() => sanitizeMetadata(value), (error) => error.code === "metadata_not_allowed");
  }
});

test("tracking hashes are deterministic and non-plaintext", () => {
  const digest = sha256("private-input");
  assert.match(digest, /^[0-9a-f]{64}$/);
  assert.notEqual(digest, "private-input");
  assert.equal(digest, sha256("private-input"));
});


test("tracking event schema version is explicit and bounded", () => {
  assert.equal(parseSchemaVersion(undefined), 1);
  assert.equal(parseSchemaVersion(1), 1);
  assert.throws(() => parseSchemaVersion(2), (error) => error.code === "schema_version_invalid");
  assert.throws(() => parseSchemaVersion("1"), (error) => error.code === "schema_version_invalid");
});

test("tracking consent flags are closed-schema booleans with fail-safe defaults", () => {
  assert.deepEqual(parseConsentFlags(undefined), { analytics: false, marketing: false });
  assert.deepEqual(parseConsentFlags({ analytics: true, marketing: false }), { analytics: true, marketing: false });
  assert.throws(() => parseConsentFlags({ analytics: true }), (error) => error.code === "consent_invalid");
  assert.throws(() => parseConsentFlags({ analytics: true, marketing: false, extra: true }), (error) => error.code === "consent_invalid");
  assert.throws(() => parseConsentFlags({ analytics: "yes", marketing: false }), (error) => error.code === "consent_invalid");
});

test("tracking test marker is boolean-only and defaults false", () => {
  assert.equal(parseTestMarker(undefined), false);
  assert.equal(parseTestMarker(false), false);
  assert.equal(parseTestMarker(true), true);
  assert.throws(() => parseTestMarker("true"), (error) => error.code === "is_test_invalid");
});

const TENANT_ID = "11111111-1111-4111-8111-111111111111";
const CAMPAIGN_ID = "22222222-2222-4222-8222-222222222222";
const API_KEY_ID = "33333333-3333-4333-8333-333333333333";
const API_KEY = "ptk_" + "a".repeat(64);

function response(payload, status = 200) {
  return new Response(payload === null ? null : JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function storageFixture(calls) {
  return async (url, options = {}) => {
    const resource = new URL(url).pathname.replace(/^\/rest\/v1\//, "");
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({ resource, method: options.method || "GET", body });
    if (resource === "pandora_tracking_clicks" && options.method === "POST") return response(null, 201);
    if (resource === "pandora_tracking_events" && options.method === "POST") {
      return response([{ id: "44444444-4444-4444-8444-444444444444" }], 201);
    }
    if (resource === "pandora_tracking_costs" && options.method === "POST") return response(null, 201);
    if (resource === "pandora_tracking_campaigns") return response([{
      id: CAMPAIGN_ID, tenant_id: TENANT_ID,
      destination_url: "https://example.com/offer?reviewed=keep",
      source: "campaign-source", medium: "paid-social", campaign: "owners",
      content: "video-a", term: null, status: "active", metadata: {},
    }]);
    if (resource === "pandora_tracking_tenants") return response([{ status: "active" }]);
    if (resource === "pandora_tracking_clicks") {
      return response([{ tenant_id: TENANT_ID, campaign_id: CAMPAIGN_ID }]);
    }
    if (resource === "pandora_tracking_api_keys" && options.method !== "PATCH") {
      return response([{
        id: API_KEY_ID, tenant_id: TENANT_ID,
        scopes: ["conversion:write", "cost:write"], status: "active", expires_at: null,
      }]);
    }
    if (options.method === "PATCH") return response(null, 204);
    return response(null, 404);
  };
}

async function withTrackingApp(fetchFn, run) {
  const app = express();
  app.use(createPandoraTrackingRouter({
    environment: { SUPABASE_URL: "https://fixture.supabase.test", SUPABASE_SERVICE_ROLE_KEY: "fixture" },
    fetchFn,
  }));
  const server = await new Promise((resolve) => {
    const active = app.listen(0, "127.0.0.1", () => resolve(active));
  });
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

test("redirect route neither stores nor forwards incoming tracking and identity canaries", async () => {
  const calls = [];
  await withTrackingApp(storageFixture(calls), async (baseUrl) => {
    const result = await fetch(
      baseUrl + "/t/owners?utm_source=raw-utm&fbclid=fb-secret&sub1=owner-42",
      {
        redirect: "manual",
        headers: {
          "user-agent": "UA-CANARY",
          referer: "https://referrer.example/private?q=canary",
          "x-forwarded-for": "203.0.113.9",
        },
      },
    );
    assert.equal(result.status, 302);
    const destination = new URL(result.headers.get("location"));
    assert.equal(destination.searchParams.get("reviewed"), "keep");
    assert.match(destination.searchParams.get("pcid"), /^pdc_[0-9a-f]{32}$/);
    for (const key of ["utm_source", "fbclid", "sub1", "utm_medium", "utm_campaign"]) {
      assert.equal(destination.searchParams.has(key), false);
    }
  });

  const click = calls.find((call) => call.resource === "pandora_tracking_clicks");
  assert.ok(click);
  assert.equal(click.body.landing_url, "https://example.com/offer");
  assert.deepEqual(click.body.platform_click_ids, {});
  assert.deepEqual(click.body.query_params, {});
  assert.deepEqual(click.body.metadata, { collector: "vercel" });
  assert.equal(click.body.is_test, false);
  for (const key of ["referrer", "user_agent", "ip_hash", "visitor_hash"]) {
    assert.equal(click.body[key], null);
  }
  const durable = JSON.stringify(click.body);
  for (const canary of ["raw-utm", "fb-secret", "owner-42", "UA-CANARY", "203.0.113.9", "referrer.example"]) {
    assert.equal(durable.includes(canary), false);
  }
});

test("event route preserves FB-017 consent, test marker, and event meaning with empty metadata", async () => {
  const calls = [];
  await withTrackingApp(storageFixture(calls), async (baseUrl) => {
    const result = await fetch(baseUrl + "/api/tracking/event", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        click_id: "pdc_" + "b".repeat(32),
        event_name: "landing.viewed",
        event_type: "event",
        schema_version: 1,
        consent: { analytics: true, marketing: false },
        is_test: true,
        metadata: {},
      }),
    });
    assert.equal(result.status, 202);
  });
  const event = calls.find((call) => call.resource === "pandora_tracking_events");
  assert.deepEqual({
    event_type: event.body.event_type,
    event_name: event.body.event_name,
    schema_version: event.body.schema_version,
    consent: event.body.consent,
    is_test: event.body.is_test,
    metadata: event.body.metadata,
  }, {
    event_type: "event", event_name: "landing.viewed", schema_version: 1,
    consent: { analytics: true, marketing: false }, is_test: true, metadata: {},
  });
});

test("all write routes reject nonempty metadata and unsupported top-level fields", async () => {
  const cases = [
    ["/api/tracking/event", null, {
      click_id: "pdc_" + "c".repeat(32), event_name: "page.viewed", event_type: "event",
    }],
    ["/api/tracking/conversion", API_KEY, {
      event_type: "lead", event_name: "lead.created", external_event_id: "registered-id",
    }],
    ["/api/tracking/cost", API_KEY, {
      provider: "meta", external_record_id: "registered-cost", bucket_date: "2026-09-29",
      currency: "USD",
    }],
  ];
  for (const [path, apiKey, baseBody] of cases) {
    for (const patch of [
      { metadata: { canary: "reject-me" } },
      { metadata: null },
      { metadata: [] },
      { metadata: "reject-me" },
      { surprise: "reject-me" },
    ]) {
      const calls = [];
      await withTrackingApp(storageFixture(calls), async (baseUrl) => {
        const result = await fetch(baseUrl + path, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...(apiKey ? { authorization: "Bearer " + apiKey } : {}),
          },
          body: JSON.stringify({ ...baseBody, ...patch }),
        });
        assert.equal(result.status, 400, path + " accepted " + Object.keys(patch)[0]);
        const payload = await result.json();
        assert.ok(["metadata_not_allowed", "unsupported_field"].includes(payload.error));
      });
      assert.equal(calls.some((call) =>
        ["pandora_tracking_events", "pandora_tracking_costs"].includes(call.resource)
        && call.method === "POST"
      ), false);
    }
  }
});

test("authenticated conversion and cost routes preserve typed measurements with empty metadata", async () => {
  const calls = [];
  await withTrackingApp(storageFixture(calls), async (baseUrl) => {
    const headers = {
      authorization: "Bearer " + API_KEY,
      "content-type": "application/json",
    };
    const conversion = await fetch(baseUrl + "/api/tracking/conversion", {
      method: "POST",
      headers,
      body: JSON.stringify({
        event_type: "sale",
        event_name: "purchase",
        external_event_id: "registered-event",
        value: 125.5,
        currency: "USD",
        schema_version: 1,
        consent: { analytics: true, marketing: false },
        is_test: false,
      }),
    });
    assert.equal(conversion.status, 201);
    const cost = await fetch(baseUrl + "/api/tracking/cost", {
      method: "POST",
      headers,
      body: JSON.stringify({
        provider: "meta",
        external_record_id: "registered-cost",
        bucket_date: "2026-09-29",
        spend: 50,
        impressions: 1000,
        provider_clicks: 40,
        currency: "USD",
      }),
    });
    assert.equal(cost.status, 200);
  });

  const conversion = calls.find((call) =>
    call.resource === "pandora_tracking_events" && call.method === "POST"
  ).body;
  assert.deepEqual({
    event_type: conversion.event_type,
    event_name: conversion.event_name,
    external_event_id: conversion.external_event_id,
    value: conversion.value,
    currency: conversion.currency,
    schema_version: conversion.schema_version,
    consent: conversion.consent,
    is_test: conversion.is_test,
    metadata: conversion.metadata,
  }, {
    event_type: "sale", event_name: "purchase", external_event_id: "registered-event",
    value: 125.5, currency: "USD", schema_version: 1,
    consent: { analytics: true, marketing: false }, is_test: false, metadata: {},
  });
  const cost = calls.find((call) =>
    call.resource === "pandora_tracking_costs" && call.method === "POST"
  ).body;
  assert.deepEqual({
    external_record_id: cost.external_record_id,
    spend: cost.spend,
    impressions: cost.impressions,
    provider_clicks: cost.provider_clicks,
    currency: cost.currency,
    metadata: cost.metadata,
  }, {
    external_record_id: "registered-cost", spend: 50, impressions: 1000,
    provider_clicks: 40, currency: "USD", metadata: {},
  });
});

test("controlled-test campaign marks redirect clicks as test traffic", async () => {
  const calls = [];
  const fixture = async (url, options = {}) => {
    const resource = new URL(url).pathname.replace(/^\/rest\/v1\//, "");
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({ resource, method: options.method || "GET", body });
    if (resource === "pandora_tracking_clicks" && options.method === "POST") return response(null, 201);
    if (resource === "pandora_tracking_campaigns") return response([{
      id: CAMPAIGN_ID, tenant_id: TENANT_ID,
      destination_url: "https://example.com/test", source: "meta", medium: "paid-social",
      campaign: "controlled", content: null, term: null, status: "active",
      metadata: { purpose: "controlled-test", business_kpi: false },
    }]);
    if (resource === "pandora_tracking_tenants") return response([{ status: "active" }]);
    return response(null, 404);
  };
  await withTrackingApp(fixture, async (baseUrl) => {
    const result = await fetch(baseUrl + "/t/controlled-test", { redirect: "manual" });
    assert.equal(result.status, 302);
  });
  const click = calls.find((call) => call.resource === "pandora_tracking_clicks" && call.method === "POST");
  assert.equal(click.body.is_test, true);
  assert.deepEqual(click.body.metadata, { collector: "vercel" });
});
