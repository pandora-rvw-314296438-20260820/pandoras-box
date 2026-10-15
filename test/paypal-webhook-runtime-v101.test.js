import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
const base = new URL("../ops/supabase/runtime-patches/pandora-owner-api-v101-plp-paypal-webhook-source/", import.meta.url);
const manifest = JSON.parse(await readFile(new URL("manifest.json", base), "utf8"));
const source = await readFile(new URL("index.ts", base), "utf8");
test("webhook route dispatch is before owner authentication", () => {
  const route = source.indexOf('if (route === "/billing/paypal/webhook")');
  const auth = source.indexOf("const context = await authenticate(req);");
  assert.notEqual(route, -1); assert.notEqual(auth, -1); assert.ok(route < auth);
});
test("body is byte-limited and passed raw to the database verifier", () => {
  assert.match(source, /readWebhookRawBody\(req, 131072\)/);
  assert.match(source, /received > maxBytes/);
  assert.match(source, /p_raw_body: rawBody/);
  assert.doesNotMatch(source, /Object\.fromEntries\(req\.headers\.entries\(\)\)/);
});
test("only PayPal signature headers are forwarded", () => {
  for (const name of ["paypal-auth-algo","paypal-cert-url","paypal-transmission-id","paypal-transmission-sig","paypal-transmission-time"]) assert.ok(source.includes('"' + name + '"'));
  assert.match(source, /pandora_plp_paypal_webhook_ingest_v1/);
});
test("source files match their manifest hashes and byte lengths", async () => {
  for (const file of manifest.files) {
    const bytes = await readFile(new URL(file.name, base));
    assert.equal(bytes.length, file.bytes, file.name + " byte length");
    assert.equal(createHash("sha256").update(bytes).digest("hex"), file.sha256, file.name + " SHA-256");
  }
});
