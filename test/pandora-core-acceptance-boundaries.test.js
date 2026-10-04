"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");

const root = path.join(__dirname, "..");
const fixture = JSON.parse(fs.readFileSync(path.join(root, "apps/pandora-mobile/test/fixtures/core_acceptance_profile_v1.json"), "utf8"));
const fields = fixture.canonical;
let profileApi, boundary, policy;
test.before(async () => {
  profileApi = await import("../supabase/functions/_shared/core-acceptance-profile.mjs");
  boundary = await import("../supabase/functions/_shared/core-acceptance-http.mjs");
  policy = await import("../supabase/functions/mcpmaster-supabase-control/identity-policy.mjs");
});
function environment() {
  return {
    PANDORA_RUNTIME_PROFILE: fields.profile, PANDORA_ACCEPTANCE_SOURCE_SHA: fields.sourceSha,
    PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF: fields.supabaseProjectRef,
    PANDORA_ACCEPTANCE_ORGANIZATION_ID: fields.organizationId,
    PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256: fields.publishableKeySha256,
    PANDORA_ACCEPTANCE_CONFIG_SHA256: fixture.configSha256,
    PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: "https://mcpmaster-123abc456-mbanatao.vercel.app",
    SUPABASE_URL: fields.supabaseUrl, SUPABASE_ANON_KEY: "unit_anon_placeholder",
    SUPABASE_SERVICE_ROLE_KEY: "unit_service_placeholder",
  };
}
function headers() {
  return { "x-pandora-runtime-profile": fields.profile, "x-pandora-config-sha256": fixture.configSha256,
    "x-pandora-source-sha": fields.sourceSha, "x-organization-id": fields.organizationId };
}
function request(body = {}, extra = {}) {
  return new Request(fields.supabaseUrl + "/functions/v1/fixture", {
    method: "POST", headers: { ...headers(), "content-type": "application/json", ...extra }, body: JSON.stringify(body),
  });
}
function loadEdge(relative, env, overrides = {}) {
  let handler, network = 0;
  const source = fs.readFileSync(path.join(root, relative), "utf8");
  const chat = relative.includes("pandora-intelligence-chat");
  const code = ts.transpileModule(source + (chat ? "\nexports.memory=canonicalMemoryOptional;exports.growthMemory=hydrateGrowthMemoryContext;exports.normalize=enterpriseInput;" : ""), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const exports = {};
  const noop = new Proxy({}, { get: () => () => null });
  const context = {
    exports, Request, Response, Headers, URL, URLSearchParams, TextEncoder, TextDecoder, AbortSignal,
    crypto: globalThis.crypto, setTimeout, clearTimeout, console: { error() {} },
    fetch: async (...args) => { network++; return overrides.fetch?.(...args) ?? Response.json({}); },
    Deno: { env: { get: name => env[name], toObject: () => ({ ...env }) }, serve: value => { handler = value; } },
    require(specifier) {
      if (specifier.includes("core-acceptance-http")) return boundary;
      if (specifier.includes("identity-policy")) return policy;
      if (specifier.includes("supabase-js")) return { createClient() { network++; throw Error("UNEXPECTED_AUTH_TRANSPORT"); } };
      if (specifier.includes("gemini-worker-gateway")) return { handleGeminiWorkerRequest: overrides.gemini ?? (() => null) };
      if (specifier.startsWith("npm:jose")) return overrides.jose ?? noop;
      return noop;
    },
  };
  vm.runInNewContext(code, context, { filename: relative });
  return { handler, exports, network: () => network };
}

test("actual chat entrypoint denies mismatched profile, target and request metadata before auth/network", async () => {
  for (const [env, extra] of [
    [{ ...environment(), SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co" }, {}],
    [{ ...environment(), PANDORA_ACCEPTANCE_CONFIG_SHA256: "b".repeat(64) }, {}],
    [environment(), { "x-pandora-source-sha": "b".repeat(40) }],
  ]) {
    const edge = loadEdge("supabase/functions/pandora-intelligence-chat/index.ts", env);
    const result = await edge.handler(request({}, extra));
    assert.equal(result.status, 400); assert.equal(edge.network(), 0);
    assert.equal((await result.json()).retryable, false);
  }
});

test("actual chat rejects a foreign organization before auth or turn admission", async () => {
  const edge = loadEdge("supabase/functions/pandora-intelligence-chat/index.ts", environment());
  const result = await edge.handler(request({ message: "Hi" }, { "x-organization-id": "20000000-0000-4000-8000-000000000001" }));
  assert.ok(result.status >= 400); assert.equal(edge.network(), 0);
});

test("actual Memory preparation returns explicit acceptance degradation with zero HTTP calls", async () => {
  const edge = loadEdge("supabase/functions/pandora-intelligence-chat/index.ts", environment());
  const profile = await profileApi.resolveCoreRuntimeProfile(environment(), { role: "chat" });
  const result = await edge.exports.memory(request({}, { authorization: "Bearer unit_fixture" }), fields.organizationId, "Hi", profile);
  assert.equal(result.reason, "acceptance_memory_not_configured");
  assert.equal(result.authorizationGranted, false); assert.equal(result.receiptRef, null);
  assert.equal(edge.network(), 0);
  const production = await profileApi.resolveCoreRuntimeProfile({ SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co" }, { role: "chat" });
  assert.equal(boundary.acceptanceMemoryDegradation(production), null);
  const absent = await edge.exports.memory(request(), fields.organizationId, "Hi", production);
  assert.equal(absent.reason, "auth_missing"); assert.equal(edge.network(), 0);
});

test("marketing Memory hydration also degrades before forwarding auth, while the production path remains intact", async () => {
  const calls = [];
  const edge = loadEdge("supabase/functions/pandora-intelligence-chat/index.ts", environment(), {
    fetch: async (url, init) => { calls.push({ url, authorization: init.headers.authorization }); return Response.json({}, { status: 401 }); },
  });
  const context = edge.exports.normalize({ surface: "enterprise_marketing", route: "/enterprise/marketing", identityScope: "pandora_organization" });
  const profile = await profileApi.resolveCoreRuntimeProfile(environment(), { role: "chat" });
  const source = fs.readFileSync(path.join(root, "supabase/functions/pandora-intelligence-chat/core-owner-commands.ts"), "utf8");
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText,
    { exports, require: () => ({}), console: { error() {} } });
  const actor = { rpc: async () => ({ data: { organization_id: profile.organizationId, actor_role: "owner", scope_kind: "platform",
    adapter_key: "pandora_core_v1", core_role: "owner", can_execute_core: true, requires_operator_entry: false } }) };
  const scope = await exports.authorizeCoreChatRequest(actor, profile.organizationId, "owner", context, null);
  assert.equal(scope.kind, "none");
  const authorized = request({}, { authorization: "Bearer synthetic_unit_session" });
  const result = await edge.exports.growthMemory(authorized, profile.organizationId, scope.context, "What can you do?", profile);
  assert.equal(result.growthMemorySourceHealth.reason, "acceptance_memory_not_configured");
  assert.equal(result.growthMemoryContextSha256, null); assert.equal(result.growthApprovedMemory.length, 0); assert.deepEqual(calls, []);
  const production = await profileApi.resolveCoreRuntimeProfile({ SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co" }, { role: "chat" });
  const unchanged = await edge.exports.growthMemory(authorized, profile.organizationId, scope.context, "What can you do?", production);
  assert.equal(unchanged.growthMemorySourceHealth.reason, "upstream_unavailable");
  assert.deepEqual(calls, [{ url: "https://mcpmaster.vercel.app/api/growth/memory-context", authorization: "Bearer synthetic_unit_session" }]);
});

test("acceptance routing never even loads inherited non-Bedrock provider settings", async () => {
  const profile = await profileApi.resolveCoreRuntimeProfile(environment(), { role: "chat" });
  const calls = [];
  const loaders = Object.fromEntries(["gemini", "kimi", "openai", "openrouter", "bedrock"].map(name =>
    [name, async () => { calls.push(name); return { enabled: true, routingEligible: true, model: name }; }]));
  const configs = await boundary.loadRuntimeProviderConfigs(profile, loaders);
  assert.deepEqual(calls, ["bedrock"]); assert.ok(configs.slice(0, 4).every(item => item.enabled === false));
  assert.throws(() => boundary.assertAcceptanceOperation(profile, "gemini", "provider"), /OPERATION_DENIED/);
  calls.length = 0;
  await boundary.loadRuntimeProviderConfigs({ acceptance: false }, loaders);
  assert.deepEqual(calls, ["gemini", "kimi", "openai", "openrouter", "bedrock"]);
});

const claims = { iss: "https://oidc.vercel.com/mbanatao", aud: "https://vercel.com/mbanatao",
  sub: "owner:mbanatao:project:mcpmaster:environment:production", owner: "mbanatao", project: "mcpmaster",
  environment: "production", owner_id: "team_3yw1CN59ce4pj5SwyQGCAqN3", project_id: "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk" };
function control(env = environment(), claimOverrides = {}) {
  const counters = { gemini: 0, jwt: 0, rpc: [] };
  const edge = loadEdge("supabase/functions/mcpmaster-supabase-control/index.ts", env, {
    gemini: () => { counters.gemini++; return null; },
    jose: { decodeJwt: () => ({ ...claims, ...claimOverrides }), createRemoteJWKSet: () => ({}),
      jwtVerify: async () => { counters.jwt++; return { payload: { ...claims, ...claimOverrides } }; } },
    fetch: async (url, init) => { counters.rpc.push({ url, body: JSON.parse(init.body) });
      return Response.json({ organizationId: fields.organizationId, configSha256: fixture.configSha256, sourceSha: fields.sourceSha }); },
  });
  return { ...edge, counters };
}

test("actual control profile guard precedes the Gemini gateway and all OIDC/network work", async () => {
  const edge = control({ ...environment(), SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co" });
  const result = await edge.handler(request({ action: "gemini" }, { authorization: "Bearer unit_fixture" }));
  assert.equal(result.status, 400); assert.equal(edge.counters.gemini, 0); assert.equal(edge.counters.jwt, 0); assert.equal(edge.network(), 0);
});

test("actual acceptance control only claims a bound ticket after unchanged workload policy checks", async () => {
  const edge = control();
  for (const action of ["gemini", "get_supabase_control_accounts", "bedrock_catalog_sync_claim", "operations_worker_claim"]) {
    const denied = await edge.handler(request({ action }, { authorization: "Bearer unit_fixture" }));
    assert.equal(denied.status, 400); assert.equal(edge.counters.rpc.length, 0);
  }
  const result = await edge.handler(request({ action: "bedrock_chat_ticket_claim", tokenSha256: "a".repeat(64),
    organizationId: "caller_override", configSha256: "b".repeat(64) }, { authorization: "Bearer unit_fixture" }));
  assert.equal(result.status, 200); assert.equal(edge.counters.gemini, 0); assert.equal(edge.counters.rpc.length, 1);
  assert.equal(edge.counters.rpc[0].url, fields.supabaseUrl + "/rest/v1/rpc/pandora_claim_core_acceptance_bedrock_chat_ticket_v1");
  assert.deepEqual(edge.counters.rpc[0].body, { p_token_sha256: "a".repeat(64), p_organization_id: fields.organizationId,
    p_config_sha256: fixture.configSha256, p_source_sha: fields.sourceSha });
  assert.equal(result.headers.get("x-pandora-config-sha256"), fixture.configSha256);
  assert.equal((await result.json()).operations.organizationId, fields.organizationId);
});

test("metadata cannot authorize a preview, foreign workload or unsigned request", async () => {
  for (const changed of [{ environment: "preview" }, { project_id: "untrusted" }, { sub: "other" }]) {
    const edge = control(environment(), changed);
    const result = await edge.handler(request({ action: "bedrock_chat_ticket_claim", tokenSha256: "a".repeat(64) }, { authorization: "Bearer unit_fixture" }));
    assert.equal(result.status, 401); assert.equal(edge.counters.rpc.length, 0);
  }
  const edge = control();
  const result = await edge.handler(request({ action: "bedrock_chat_ticket_claim", tokenSha256: "a".repeat(64) }));
  assert.equal(result.status, 401); assert.equal(edge.counters.jwt, 0); assert.equal(edge.counters.rpc.length, 0);
});
