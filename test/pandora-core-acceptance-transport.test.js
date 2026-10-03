"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { Readable } = require("node:stream");
const { EventEmitter } = require("node:events");
const { readFileSync } = require("node:fs");
const path = require("node:path"), vm = require("node:vm"), ts = require("typescript");
const { createBedrockChatHandler } = require("../src/providers/aws-bedrock-chat-http.js");
const vector = require("../apps/pandora-mobile/test/fixtures/core_acceptance_profile_v1.json");
const helpers = import("../supabase/functions/_shared/core-acceptance-profile.mjs");
const bridgeOrigin = "https://mcpmaster-abcdef123-mbanatao.vercel.app";
const ticket = "a".repeat(64);
const body = { messages: [{ role: "user", content: [{ text: "Hi" }] }], system: "Be concise.", maxTokens: 256 };
function environment() {
  return { PANDORA_RUNTIME_PROFILE: vector.canonical.profile,
    PANDORA_ACCEPTANCE_SOURCE_SHA: vector.canonical.sourceSha,
    PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF: vector.canonical.supabaseProjectRef,
    PANDORA_ACCEPTANCE_ORGANIZATION_ID: vector.canonical.organizationId,
    PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256: vector.canonical.publishableKeySha256,
    PANDORA_ACCEPTANCE_CONFIG_SHA256: vector.configSha256 };
}
function request(headers, value = { ticket }) {
  const req = Readable.from([JSON.stringify(value)]); req.method = "POST"; req.headers = headers; return req;
}
class Reply extends EventEmitter {
  constructor() { super(); this.headers = {}; this.writes = []; this.writableEnded = false; this.destroyed = false; }
  status(code) { this.statusCode = code; return this; }
  setHeader(name, value) { this.headers[name] = value; }
  flushHeaders() { this.headersSent = true; }
  write(value) { this.headersSent = true; this.writes.push(value); return true; }
  json(value) { this.jsonBody = value; this.end(); return this; }
  end() { this.writableEnded = true; this.emit("close"); }
  response() { return new Response(this.jsonBody ? JSON.stringify(this.jsonBody) : this.writes.join(""), { status: this.statusCode, headers: this.headers }); }
}
async function edge(env, fetch) {
  const shared = await helpers;
  function load(filename) {
    if (filename.endsWith("core-acceptance-profile.mjs")) return shared;
    const source = ts.transpileModule(readFileSync(filename, "utf8"), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
    const exports = {};
    vm.runInNewContext(source, { exports, require: name => load(path.resolve(path.dirname(filename), name)),
      Deno: { env: { toObject: () => env } }, fetch, TextEncoder, TextDecoder, ReadableStream, Response,
      AbortSignal, AbortController, URL, crypto: globalThis.crypto, setInterval, clearInterval }, { filename });
    return exports;
  }
  return load(path.resolve(__dirname, "../supabase/functions/pandora-intelligence-chat/bedrock.ts"));
}

test("acceptance streams through the same isolated ticket store with exact response bindings", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await helpers;
  const env = environment(), profile = await resolveCoreRuntimeProfile(env, { role: "bridge" }), headers = runtimeBindingHeaders(profile);
  let tickets = 0, claims = 0, providers = 0; const deltas = [];
  const handler = createBedrockChatHandler({ environment: env, resolveWorkloadToken: async () => "fixture-oidc",
    fetchFn: async (url, init) => {
      claims++; assert.equal(url, `${vector.canonical.supabaseUrl}/functions/v1/mcpmaster-supabase-control`);
      assert.equal(init.headers.authorization, "Bearer fixture-oidc");
      for (const [key, value] of Object.entries(headers)) assert.equal(init.headers[key], value);
      assert.equal(JSON.parse(init.body).action, "bedrock_chat_ticket_claim");
      return Response.json({ ok: true, operations: { modelId: "fixture-model", invocationTarget: "fixture-target", requestBody: { ...body, stream: true },
        organizationId: profile.organizationId, configSha256: profile.configSha256, sourceSha: profile.sourceSha } }, { headers });
    }, converse: async options => {
      providers++; assert.deepEqual(options.messages, body.messages); assert.equal(options.stream, true);
      assert.equal(await options.resolveWorkloadToken(), "fixture-oidc");
      await options.onDelta('{"reply":"'); await options.onDelta('Hello"}');
      return { modelId: "fixture-model", text: '{"reply":"Hello"}', streaming: true, providerHttpStatus: 200, providerRequestId: "fixture-provider-request" };
    } });
  const client = await edge({ ...env, SUPABASE_URL: vector.canonical.supabaseUrl, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: bridgeOrigin }, async (url, init) => {
    assert.equal(url, `${bridgeOrigin}/api/operations-inference?operation=bedrock-chat`);
    assert.deepEqual(Object.keys(JSON.parse(init.body)), ["ticket"]);
    const reply = new Reply(); await handler(request(init.headers), reply);
    for (const [key, value] of Object.entries(headers)) assert.equal(reply.headers[key], value);
    return reply.response();
  });
  const result = await client.bedrockCall({ rpc: async (name, args) => {
    tickets++; assert.equal(name, "pandora_issue_core_acceptance_bedrock_chat_ticket_v1"); assert.equal(args.p_body.stream, true);
    assert.equal(args.p_organization_id, profile.organizationId); assert.equal(args.p_config_sha256, profile.configSha256); assert.equal(args.p_source_sha, profile.sourceSha);
    return { data: { ticket } };
  } }, "fixture-model", body, { stream: true, onDelta: async text => deltas.push(text) });
  assert.deepEqual(deltas, ['{"reply":"', 'Hello"}']); assert.equal(result.valueRaw.reply, "Hello");
  assert.equal(result.body.providerRequestId, "fixture-provider-request"); assert.deepEqual([tickets, claims, providers], [1, 1, 1]);
});

test("invalid Edge profile is rejected before ticket issuance or bridge fetch", async () => {
  for (const env of [{ ...environment(), SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co", PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: bridgeOrigin },
    { ...environment(), SUPABASE_URL: vector.canonical.supabaseUrl, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: "https://mcpmaster.vercel.app" },
    { SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co", PANDORA_ACCEPTANCE_CONFIG_SHA256: "" }]) {
    let calls = 0; const client = await edge(env, async () => { calls++; });
    await assert.rejects(client.bedrockCall({ rpc: async () => { calls++; } }, "fixture-model", body), /CORE_RUNTIME_/);
    assert.equal(calls, 0);
  }
});

test("bridge rejects absent/mismatched incoming bindings before workload identity or network access", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await helpers;
  const env = environment(), headers = runtimeBindingHeaders(await resolveCoreRuntimeProfile(env, { role: "bridge" }));
  for (const incoming of [{}, { ...headers, "x-pandora-source-sha": "f".repeat(40) }]) {
    let calls = 0; const handler = createBedrockChatHandler({ environment: env, fetchFn: async () => { calls++; }, resolveWorkloadToken: async () => { calls++; }, converse: async () => { calls++; } });
    const reply = new Reply(); await handler(request(incoming), reply);
    assert.equal(calls, 0); assert.equal(reply.statusCode, 400); assert.equal(reply.jsonBody.error.retryable, false);
    for (const [key, value] of Object.entries(headers)) assert.equal(reply.headers[key], value);
  }
});

test("a missing or different control response binding cannot authorize provider invocation", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await helpers;
  const env = environment(), headers = runtimeBindingHeaders(await resolveCoreRuntimeProfile(env, { role: "bridge" }));
  for (const returned of [{}, { ...headers, "x-pandora-config-sha256": "f".repeat(64) }]) {
    let provider = 0, claims = 0;
    const handler = createBedrockChatHandler({ environment: env, resolveWorkloadToken: async () => "fixture-oidc",
      fetchFn: async () => { claims++; return Response.json({ ok: true, operations: { modelId: "fixture-model", invocationTarget: "fixture-target", requestBody: body } }, { headers: returned }); },
      converse: async () => { provider++; } });
    const reply = new Reply(); await handler(request(headers), reply);
    assert.equal(claims, 1); assert.equal(provider, 0); assert.equal(reply.statusCode, 400);
    assert.equal(reply.jsonBody.error.retryable, false);
  }
});

test("Edge rejects wrong response binding before consuming buffered content or any streamed delta", async () => {
  const env = { ...environment(), SUPABASE_URL: vector.canonical.supabaseUrl, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: bridgeOrigin };
  for (const stream of [false, true]) {
    let deltas = 0;
    const client = await edge(env, async () => new Response(stream ? 'data: {"type":"delta","text":"must-not-escape"}\n\n' : '{"ok":true,"body":{"text":"must-not-escape"}}', { headers: { "content-type": stream ? "text/event-stream" : "application/json" } }));
    await assert.rejects(client.bedrockCall({ rpc: async () => ({ data: { ticket } }) }, "fixture-model", body, { stream, onDelta: async () => { deltas++; } }), error => {
      assert.equal(error.message, "CORE_RUNTIME_BINDING_MISMATCH"); assert.equal(error.crossProviderEligible, false); return true;
    }); assert.equal(deltas, 0);
  }
});

test("matching headers cannot substitute for the database-bound ticket organization, config or source", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await helpers;
  const env = environment(), profile = await resolveCoreRuntimeProfile(env, { role: "bridge" }), headers = runtimeBindingHeaders(profile);
  const valid = { modelId: "fixture-model", invocationTarget: "fixture-target", requestBody: body,
    organizationId: profile.organizationId, configSha256: profile.configSha256, sourceSha: profile.sourceSha };
  for (const key of ["organizationId", "configSha256", "sourceSha"]) {
    for (const value of [undefined, "wrong-binding"]) {
      let providers = 0;
      const handler = createBedrockChatHandler({ environment: env, resolveWorkloadToken: async () => "fixture-oidc",
        fetchFn: async () => Response.json({ ok: true, operations: { ...valid, [key]: value } }, { headers }),
        converse: async () => { providers++; } });
      const reply = new Reply(); await handler(request(headers), reply);
      assert.equal(providers, 0); assert.equal(reply.statusCode, 400); assert.equal(reply.jsonBody.error.retryable, false);
    }
  }
});

test("production bridge rejects acceptance markers and acceptance errors never echo a ticket", async () => {
  let network = 0;
  const handler = createBedrockChatHandler({ environment: {}, fetchFn: async () => { network++; }, resolveWorkloadToken: async () => { network++; } });
  const reply = new Reply(); await handler(request({ "x-pandora-runtime-profile": "core_acceptance_v1" }), reply);
  assert.equal(network, 0); assert.equal(reply.statusCode, 400); assert.doesNotMatch(JSON.stringify(reply.jsonBody), new RegExp(ticket));
});

test("acceptance disconnect fences a late isolated ticket claim before provider invocation", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await helpers;
  const env = environment(), profile = await resolveCoreRuntimeProfile(env, { role: "bridge" }), headers = runtimeBindingHeaders(profile);
  let entered, release, providers = 0, claimSignal;
  const claimEntered = new Promise(resolve => { entered = resolve; });
  const claimReply = new Promise(resolve => { release = resolve; });
  const handler = createBedrockChatHandler({ environment: env, resolveWorkloadToken: async () => "fixture-oidc",
    fetchFn: async (_url, init) => { claimSignal = init.signal; entered(); return claimReply; },
    converse: async () => { providers++; } });
  const reply = new Reply(), running = handler(request(headers), reply);
  await claimEntered; reply.destroyed = true; reply.emit("close"); await running;
  assert.equal(claimSignal.aborted, true);
  release(Response.json({ ok: true, operations: { modelId: "fixture-model", invocationTarget: "fixture-target", requestBody: body,
    organizationId: profile.organizationId, configSha256: profile.configSha256, sourceSha: profile.sourceSha } }, { headers }));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(providers, 0); assert.deepEqual(reply.writes, []); assert.equal(reply.jsonBody, undefined);
});
