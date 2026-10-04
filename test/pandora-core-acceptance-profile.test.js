"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const vector = require("../apps/pandora-mobile/test/fixtures/core_acceptance_profile_v1.json");
const modulePromise = import("../supabase/functions/_shared/core-acceptance-profile.mjs");
const bridge = "https://mcpmaster-abcdef123-mbanatao.vercel.app";
function environment() {
  return { PANDORA_RUNTIME_PROFILE: vector.canonical.profile,
    PANDORA_ACCEPTANCE_SOURCE_SHA: vector.canonical.sourceSha,
    PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF: vector.canonical.supabaseProjectRef,
    PANDORA_ACCEPTANCE_ORGANIZATION_ID: vector.canonical.organizationId,
    PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256: vector.canonical.publishableKeySha256,
    PANDORA_ACCEPTANCE_CONFIG_SHA256: vector.configSha256 };
}

test("ordered acceptance config matches the shared Dart/Python golden bytes and hash", async () => {
  const { canonicalAcceptanceConfig, resolveCoreRuntimeProfile } = await modulePromise;
  const config = canonicalAcceptanceConfig(vector.canonical);
  assert.deepEqual(config, vector.canonical);
  assert.equal(JSON.stringify(config), vector.canonicalJson);
  assert.equal(createHash("sha256").update(JSON.stringify(config)).digest("hex"), vector.configSha256);
  const profile = await resolveCoreRuntimeProfile(environment(), { role: "build" });
  assert.equal(profile.configSha256, vector.configSha256);
  assert.equal(profile.memoryMode, "unavailable");
  assert.equal(profile.controlUrl, `${config.supabaseUrl}/functions/v1/mcpmaster-supabase-control`);
  assert.ok(Object.isFrozen(profile));
});

test("production defaults preserve canonical transports and have no acceptance markers", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders } = await modulePromise;
  for (const mode of [undefined, "production"]) {
    const profile = await resolveCoreRuntimeProfile(mode ? { PANDORA_RUNTIME_PROFILE: mode } : {}, { role: "bridge" });
    assert.equal(profile.acceptance, false);
    assert.equal(profile.bedrockChatUrl, "https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-chat");
    assert.equal(profile.controlUrl, "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control");
    assert.deepEqual(runtimeBindingHeaders(profile), {});
    assert.equal(profile.memoryMode, "canonical");
  }
});

test("production bridge and build ignore unrelated generic Supabase URL without changing their fixed Core target", async () => {
  const { resolveCoreRuntimeProfile, assertRuntimeRequestBinding } = await modulePromise;
  for (const role of ["bridge", "build"]) {
    for (const url of ["https://unrelated.example.invalid", "", vector.canonical.supabaseUrl]) {
      const profile = await resolveCoreRuntimeProfile({ SUPABASE_URL: url }, { role });
      assert.equal(profile.supabaseUrl, "https://jcyqixttuebxqqfkjonq.supabase.co");
      assert.equal(profile.controlUrl, "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control");
      assert.equal(profile.bedrockChatUrl, "https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-chat");
      assert.throws(() => assertRuntimeRequestBinding(profile, { "x-pandora-runtime-profile": "core_acceptance_v1" }), /CORE_RUNTIME_BINDING_MISMATCH/);
      await assert.rejects(resolveCoreRuntimeProfile({ SUPABASE_URL: url, PANDORA_ACCEPTANCE_CONFIG_SHA256: "" }, { role }), /CORE_RUNTIME_PROFILE_INVALID/);
    }
  }
  for (const role of ["chat", "control"])
    await assert.rejects(resolveCoreRuntimeProfile({ SUPABASE_URL: "https://unrelated.example.invalid" }, { role }), /CORE_RUNTIME_TARGET_MISMATCH/);
});

test("partial, orphan, unknown and explicitly empty acceptance settings fail closed", async () => {
  const { resolveCoreRuntimeProfile } = await modulePromise;
  for (const invalid of [
    { PANDORA_RUNTIME_PROFILE: "" }, { PANDORA_RUNTIME_PROFILE: "preview" },
    { PANDORA_ACCEPTANCE_SOURCE_SHA: "" }, { ...environment(), PANDORA_RUNTIME_PROFILE: "production" },
    { ...environment(), PANDORA_ACCEPTANCE_EXTRA: "" },
    ...Object.keys(environment()).filter(key => key !== "PANDORA_RUNTIME_PROFILE").map(key => { const env = environment(); delete env[key]; return env; }),
    ...Object.keys(environment()).map(key => ({ ...environment(), [key]: "" })),
  ]) await assert.rejects(resolveCoreRuntimeProfile(invalid, { role: "bridge" }), /CORE_RUNTIME_/);
});

test("main, Memory, malformed refs, mismatched digest and rewritten derived targets are rejected", async () => {
  const { resolveCoreRuntimeProfile, canonicalAcceptanceConfig } = await modulePromise;
  for (const ref of ["jcyqixttuebxqqfkjonq", "ivmvufhcsezyhczzondn", "ABCDEFGHIJKLMNOPQRST", "localhost", "abcdefghijklmnopqrst.evil"])
    await assert.rejects(resolveCoreRuntimeProfile({ ...environment(), PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF: ref }, { role: "build" }), /CORE_RUNTIME_/);
  for (const [key, value] of [["PANDORA_ACCEPTANCE_CONFIG_SHA256", "0".repeat(64)], ["PANDORA_ACCEPTANCE_SOURCE_SHA", "f".repeat(40)],
    ["PANDORA_ACCEPTANCE_ORGANIZATION_ID", "10000000-0000-4000-8000-000000000002"], ["PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256", "f".repeat(64)]])
    await assert.rejects(resolveCoreRuntimeProfile({ ...environment(), [key]: value }, { role: "bridge" }), /CORE_RUNTIME_/);
  for (const key of ["supabaseUrl", "ownerApiBaseUrl", "projectRuntimeApiBaseUrl", "memoryMode"])
    assert.throws(() => canonicalAcceptanceConfig({ ...vector.canonical, [key]: "https://wrong.example" }), /CORE_RUNTIME_TARGET_MISMATCH/);
});

test("actual Supabase target is required on Edge and checked whenever supplied", async () => {
  const { resolveCoreRuntimeProfile } = await modulePromise;
  for (const role of ["control", "chat"])
    await assert.rejects(resolveCoreRuntimeProfile(environment(), { role }), /CORE_RUNTIME_TARGET_MISMATCH/);
  for (const role of ["control", "chat", "bridge", "build"])
    await assert.rejects(resolveCoreRuntimeProfile({ ...environment(), SUPABASE_URL: "https://jcyqixttuebxqqfkjonq.supabase.co" }, { role }), /CORE_RUNTIME_TARGET_MISMATCH/);
  await assert.rejects(resolveCoreRuntimeProfile({ SUPABASE_URL: vector.canonical.supabaseUrl }, { role: "control" }), /CORE_RUNTIME_TARGET_MISMATCH/);
  const profile = await resolveCoreRuntimeProfile({ ...environment(), SUPABASE_URL: vector.canonical.supabaseUrl }, { role: "control" });
  assert.equal(profile.supabaseProjectRef, vector.canonical.supabaseProjectRef);
});

test("only chat receives a receipt-bound immutable bridge origin, outside the base digest", async () => {
  const { resolveCoreRuntimeProfile } = await modulePromise;
  const env = { ...environment(), SUPABASE_URL: vector.canonical.supabaseUrl, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: bridge };
  const profile = await resolveCoreRuntimeProfile(env, { role: "chat", expectedBridgeOrigin: bridge });
  assert.equal(profile.bedrockChatUrl, `${bridge}/api/operations-inference?operation=bedrock-chat`);
  assert.equal(profile.configSha256, vector.configSha256);
  for (const value of ["https://mcpmaster.vercel.app", "https://mcpmaster-git-review-mbanatao.vercel.app", "http://mcpmaster-abcdef123-mbanatao.vercel.app",
    bridge + "/", bridge + "?ticket=x", bridge + "#x", bridge.replace("https://", "https://user@"), "https://wrong.example"])
    await assert.rejects(resolveCoreRuntimeProfile({ ...env, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: value }, { role: "chat" }), /CORE_RUNTIME_/);
  await assert.rejects(resolveCoreRuntimeProfile(env, { role: "chat", expectedBridgeOrigin: bridge.replace("abcdef123", "123abcdef") }), /CORE_RUNTIME_TARGET_MISMATCH/);
  const control = await resolveCoreRuntimeProfile(env, { role: "control", expectedBridgeOrigin: bridge });
  assert.equal(control.configSha256, profile.configSha256);
  assert.equal(control.bridgeOrigin, null); assert.equal(control.bedrockChatUrl, null);
  await assert.rejects(resolveCoreRuntimeProfile({ ...env, PANDORA_ACCEPTANCE_BRIDGE_ORIGIN: "https://mcpmaster.vercel.app" }, { role: "control" }), /CORE_RUNTIME_TARGET_MISMATCH/);
  for (const role of ["bridge", "build"])
    await assert.rejects(resolveCoreRuntimeProfile(env, { role }), /CORE_RUNTIME_PROFILE_INVALID/);
});

test("request and response metadata require all exact values and cannot opt production into acceptance", async () => {
  const { resolveCoreRuntimeProfile, runtimeBindingHeaders, assertRuntimeRequestBinding } = await modulePromise;
  const acceptance = await resolveCoreRuntimeProfile(environment(), { role: "bridge" });
  const production = await resolveCoreRuntimeProfile({}, { role: "bridge" });
  const headers = runtimeBindingHeaders(acceptance);
  assert.doesNotThrow(() => assertRuntimeRequestBinding(acceptance, new Headers(headers)));
  assert.doesNotThrow(() => assertRuntimeRequestBinding(acceptance, Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toUpperCase(), v]))));
  for (const name of Object.keys(headers)) {
    const missing = { ...headers }; delete missing[name];
    for (const values of [missing, { ...headers, [name]: "" }, { ...headers, [name]: [headers[name]] }, { ...headers, [name.toUpperCase()]: headers[name] }, { ...headers, [name]: headers[name] + ", " + headers[name] }])
      assert.throws(() => assertRuntimeRequestBinding(acceptance, values), /CORE_RUNTIME_BINDING_MISMATCH/);
    assert.throws(() => assertRuntimeRequestBinding(production, { [name]: "" }), /CORE_RUNTIME_BINDING_MISMATCH/);
  }
  assert.doesNotThrow(() => assertRuntimeRequestBinding(production, {}));
});

test("canonical fields and outgoing binding identities reject trailing LF and CRLF", async () => {
  const { canonicalAcceptanceConfig, resolveCoreRuntimeProfile, runtimeBindingHeaders, assertRuntimeRequestBinding } = await modulePromise;
  const profile = await resolveCoreRuntimeProfile(environment(), { role: "bridge" });
  for (const suffix of ["\n", "\r\n"]) {
    for (const key of ["sourceSha", "supabaseProjectRef", "publishableKeySha256", "organizationId"])
      assert.throws(() => canonicalAcceptanceConfig({ ...vector.canonical, [key]: vector.canonical[key] + suffix }), /CORE_RUNTIME_PROFILE_INVALID/);
    for (const key of ["PANDORA_ACCEPTANCE_SOURCE_SHA", "PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF", "PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256", "PANDORA_ACCEPTANCE_CONFIG_SHA256", "PANDORA_ACCEPTANCE_ORGANIZATION_ID"]) {
      const env = environment();
      await assert.rejects(resolveCoreRuntimeProfile({ ...env, [key]: env[key] + suffix }, { role: "build" }), /CORE_RUNTIME_PROFILE_INVALID/);
    }
    for (const key of ["sourceSha", "configSha256"])
      assert.throws(() => runtimeBindingHeaders({ ...profile, [key]: profile[key] + suffix }), /CORE_RUNTIME_PROFILE_INVALID/);
    const headers = runtimeBindingHeaders(profile);
    for (const key of Object.keys(headers))
      assert.throws(() => assertRuntimeRequestBinding(profile, { ...headers, [key]: headers[key] + suffix }), /CORE_RUNTIME_BINDING_MISMATCH/);
  }
});
