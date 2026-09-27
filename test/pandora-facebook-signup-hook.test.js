"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createHmac } = require("node:crypto");

const policy = import("../supabase/functions/pandora-facebook-signup-hook/policy.mjs");
const now = Date.parse("2026-09-27T08:00:00.000Z");
const key = Buffer.alloc(32, 0x71);
const secret = "v1,whsec_" + key.toString("base64");
const facebook = {
  metadata: { name: "before-user-created" },
  user: {
    email: "client@example.test",
    is_anonymous: false,
    app_metadata: { provider: "facebook", providers: ["facebook"] },
    user_metadata: {},
  },
};

function signedRequest(event, options = {}) {
  const body = options.body ?? JSON.stringify(event);
  const signatureBody = options.signedBody ?? body;
  const id = options.id ?? "msg_signup_policy_fixture";
  const timestamp = String(options.timestamp ?? Math.floor(now / 1000));
  const signature = createHmac("sha256", options.key ?? key)
    .update(id + "." + timestamp + "." + signatureBody)
    .digest("base64");
  const headers = new Headers({
    "content-type": "application/json",
    "webhook-id": id,
    "webhook-timestamp": timestamp,
    "webhook-signature": options.signature ?? "v1," + signature,
  });
  if (options.removeHeader) headers.delete(options.removeHeader);
  return new Request("https://example.test/functions/v1/pandora-facebook-signup-hook", {
    method: "POST",
    headers,
    body,
  });
}
async function decide(request, suppliedSecret = secret) {
  const { handleFacebookSignupHook } = await policy;
  return handleFacebookSignupHook(request, suppliedSecret, now);
}

test("valid, freshly signed Facebook signup with an email is allowed", async () => {
  const response = await decide(signedRequest(facebook));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {});
  assert.equal(response.headers.get("cache-control"), "no-store");
});

for (const provider of ["email", "github", "google", "phone"]) {
  test("signed new " + provider + " account is denied", async () => {
    const event = structuredClone(facebook);
    event.user.app_metadata = { provider, providers: [provider] };
    const response = await decide(signedRequest(event));
    assert.equal(response.status, 403);
  });
}

test("reject missing or malformed Facebook email and anonymous signup", async () => {
  for (const email of ["", "client@example.test whitespace", null]) {
    const event = structuredClone(facebook);
    event.user.email = email;
    assert.equal((await decide(signedRequest(event))).status, 403);
  }
  const anonymous = structuredClone(facebook);
  anonymous.user.is_anonymous = true;
  assert.equal((await decide(signedRequest(anonymous))).status, 403);
});

test("do not trust user_metadata.provider or a mismatch in server-assigned providers", async () => {
  for (const appMetadata of [
    { provider: "github", providers: ["github"] },
    { provider: "facebook", providers: ["facebook", "github"] },
    { provider: "facebook", providers: ["github"] },
    {},
  ]) {
    const event = structuredClone(facebook);
    event.user.app_metadata = appMetadata;
    event.user.user_metadata = { provider: "facebook" };
    assert.equal((await decide(signedRequest(event))).status, 403);
  }
});

test("wrong event type never grants signup", async () => {
  const event = structuredClone(facebook);
  event.metadata.name = "after-user-created";
  assert.equal((await decide(signedRequest(event))).status, 403);
});

test("unsigned, forged, altered-body, and wrong-key requests fail closed", async () => {
  assert.equal((await decide(signedRequest(facebook, { removeHeader: "webhook-signature" }))).status, 401);
  assert.equal((await decide(signedRequest(facebook, { key: Buffer.alloc(32, 0x72) }))).status, 401);
  const altered = JSON.stringify({ ...facebook, user: { ...facebook.user, email: "other@example.test" } });
  assert.equal((await decide(signedRequest(facebook, { body: altered, signedBody: JSON.stringify(facebook) }))).status, 401);
  assert.equal((await decide(signedRequest(facebook, { signature: "v1,bad" }))).status, 401);
});

test("stale and future-signed requests fail closed", async () => {
  for (const timestamp of [Math.floor(now / 1000) - 301, Math.floor(now / 1000) + 301]) {
    assert.equal((await decide(signedRequest(facebook, { timestamp }))).status, 401);
  }
});

test("missing hook secret fails closed", async () => {
  assert.equal((await decide(signedRequest(facebook), "")).status, 503);
});

test("oversized payload and invalid method fail closed", async () => {
  const huge = signedRequest(facebook, { body: "x".repeat(32_769) });
  assert.equal((await decide(huge)).status, 413);
  assert.equal((await decide(new Request("https://example.test/", { method: "GET" }))).status, 405);
});

test("signed malformed JSON fails closed", async () => {
  assert.equal((await decide(signedRequest(facebook, { body: "not JSON" }))).status, 400);
});

test("signature rotation format accepts a correct v1 signature among invalid signatures", async () => {
  const base = signedRequest(facebook);
  const headers = new Headers(base.headers);
  headers.set("webhook-signature", "v1,invalid " + headers.get("webhook-signature"));
  const request = new Request(base.url, { method: "POST", headers, body: JSON.stringify(facebook) });
  assert.equal((await decide(request)).status, 200);
});
