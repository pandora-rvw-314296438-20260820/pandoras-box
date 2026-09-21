"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  createPandoraTrackingRouter,
  _trackingInternals: {
    buildDestinationUrl,
    createClickId,
    parseBearerKey,
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

test("tracking query sanitizer keeps attribution fields and drops arbitrary input", () => {
  assert.deepEqual(
    sanitizeIncomingQuery({
      utm_source: "meta",
      fbclid: "abc",
      sub1: "owner",
      password: "must-not-pass",
      nested: { bad: true },
    }),
    {
      utm_source: "meta",
      fbclid: "abc",
      sub1: "owner",
    },
  );
});

test("tracking destination preserves explicit landing params and adds click attribution", () => {
  const result = new URL(buildDestinationUrl(
    "https://example.com/offer?utm_source=existing",
    { utm_source: "incoming", fbclid: "fb-1" },
    {
      source: "campaign-source",
      medium: "paid-social",
      campaign: "owners",
      content: "video-a",
      term: null,
    },
    "pdc_0123456789abcdef0123456789abcdef",
  ));
  assert.equal(result.searchParams.get("utm_source"), "existing");
  assert.equal(result.searchParams.get("utm_medium"), "paid-social");
  assert.equal(result.searchParams.get("utm_campaign"), "owners");
  assert.equal(result.searchParams.get("utm_content"), "video-a");
  assert.equal(result.searchParams.get("fbclid"), "fb-1");
  assert.equal(result.searchParams.get("pcid"), "pdc_0123456789abcdef0123456789abcdef");
});

test("tracking API keys are accepted only in the opaque bearer format", () => {
  const key = "ptk_" + "a".repeat(64);
  assert.equal(parseBearerKey("Bearer " + key), key);
  assert.equal(parseBearerKey("Bearer not-a-key"), null);
  assert.equal(parseBearerKey(key), null);
});

test("tracking metadata is bounded to primitive values", () => {
  const metadata = sanitizeMetadata({
    ok: true,
    amount: 12.5,
    note: "hello",
    nested: { reject: true },
    list: [1, 2],
  });
  assert.deepEqual(metadata, { ok: true, amount: 12.5, note: "hello" });
});

test("tracking hashes are deterministic and non-plaintext", () => {
  const digest = sha256("private-input");
  assert.match(digest, /^[0-9a-f]{64}$/);
  assert.notEqual(digest, "private-input");
  assert.equal(digest, sha256("private-input"));
});


test("tracking server APIs expose Vercel-safe non-reserved route aliases", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "pandora-tracking-http.js"), "utf8");
  for (const route of [
    "/tracking/health",
    "/tracking/event",
    "/tracking/conversion",
    "/tracking/cost",
    "/tracking/report",
  ]) {
    assert.ok(source.includes(route), route + " must be mounted");
  }
  assert.ok(source.includes("/api/tracking/health"), "legacy local API alias remains available");
});
