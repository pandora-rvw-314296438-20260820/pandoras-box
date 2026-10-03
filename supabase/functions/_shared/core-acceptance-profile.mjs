// Server-owned target configuration. These metadata bindings never authorize a
// caller: the normal user JWT, one-time ticket and workload OIDC checks remain.
const MAIN_REF = "jcyqixttuebxqqfkjonq";
const MEMORY_REF = "ivmvufhcsezyhczzondn";
const MAIN_URL = `https://${MAIN_REF}.supabase.co`;
const MAIN_BRIDGE = "https://mcpmaster.vercel.app";
const ACCEPTANCE = "core_acceptance_v1";
const KEYS = ["SUPABASE_PROJECT_REF", "ORGANIZATION_ID", "SOURCE_SHA", "PUBLISHABLE_KEY_SHA256", "CONFIG_SHA256", "BRIDGE_ORIGIN"];
const MARKERS = ["x-pandora-runtime-profile", "x-pandora-config-sha256", "x-pandora-source-sha"];
const shaPattern = /^[0-9a-f]{64}$/;
function denied(code = "CORE_RUNTIME_PROFILE_INVALID") {
  return Object.assign(new Error(code), { code, status: 400, retryable: false, crossProviderEligible: false });
}
function record(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function exact(value, pattern) {
  if (typeof value !== "string") return false;
  const match = pattern.exec(value);
  return match !== null && match[0].length === value.length;
}
function origin(value) {
  if (typeof value !== "string") throw denied();
  let url; try { url = new URL(value); } catch { throw denied(); }
  // Only an immutable deployment URL is eligible, never a project/branch alias.
  // Its exact ownership and deployment identity must additionally be read back
  // by the deployment producer and bound in the acceptance receipt.
  if (url.origin !== value || url.protocol !== "https:" || url.port || url.username || url.password ||
      !/^mcpmaster-[a-z0-9]{9}-[a-z0-9]+(?:-[a-z0-9]+)*\.vercel\.app$/.test(url.hostname) ||
      url.hostname.includes("-git-")) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
  return value;
}

/** The insertion order is a cross-runtime configuration-digest contract. */
export function canonicalAcceptanceConfig(fields) {
  if (!record(fields) || (fields.profile !== undefined && fields.profile !== ACCEPTANCE) ||
      !exact(fields.sourceSha, /^[0-9a-f]{40}$/) || !exact(fields.supabaseProjectRef, /^[a-z0-9]{20}$/) ||
      [MAIN_REF, MEMORY_REF].includes(fields.supabaseProjectRef) || !exact(fields.publishableKeySha256, shaPattern) ||
      !exact(fields.organizationId, /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)) throw denied();
  const supabaseUrl = `https://${fields.supabaseProjectRef}.supabase.co`;
  const config = {
    profile: ACCEPTANCE,
    sourceSha: fields.sourceSha,
    supabaseProjectRef: fields.supabaseProjectRef,
    supabaseUrl,
    publishableKeySha256: fields.publishableKeySha256,
    organizationId: fields.organizationId,
    ownerApiBaseUrl: `${supabaseUrl}/functions/v1/pandora-owner-api`,
    projectRuntimeApiBaseUrl: `${supabaseUrl}/functions/v1/pandora-project-runtime`,
    memoryMode: "unavailable",
  };
  for (const key of ["supabaseUrl", "ownerApiBaseUrl", "projectRuntimeApiBaseUrl", "memoryMode"])
    if (fields[key] !== undefined && fields[key] !== config[key]) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
  return Object.freeze(config);
}

export async function resolveCoreRuntimeProfile(env, { role, expectedBridgeOrigin } = {}) {
  if (!record(env) || !["bridge", "chat", "control", "build"].includes(role)) throw denied();
  const present = (key) => env[key] !== undefined;
  const acceptanceKeys = Object.keys(env).filter(key => key.startsWith("PANDORA_ACCEPTANCE_"));
  const mode = env.PANDORA_RUNTIME_PROFILE === undefined ? "production" : env.PANDORA_RUNTIME_PROFILE;
  if (!["production", ACCEPTANCE].includes(mode)) throw denied();
  if (mode === "production") {
    if (acceptanceKeys.length || expectedBridgeOrigin !== undefined) throw denied();
    // The production bridge has always used its fixed Core control target,
    // independently of generic Vercel application Supabase settings.
    if (["chat", "control"].includes(role) && env.SUPABASE_URL !== MAIN_URL) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
    return Object.freeze({ profile: mode, acceptance: false, sourceSha: null, configSha256: null,
      supabaseProjectRef: MAIN_REF, supabaseUrl: MAIN_URL, publishableKeySha256: null, organizationId: null,
      ownerApiBaseUrl: `${MAIN_URL}/functions/v1/pandora-owner-api`,
      projectRuntimeApiBaseUrl: `${MAIN_URL}/functions/v1/pandora-project-runtime`, memoryMode: "canonical",
      bridgeOrigin: MAIN_BRIDGE, bedrockChatUrl: `${MAIN_BRIDGE}/api/operations-inference?operation=bedrock-chat`,
      controlUrl: `${MAIN_URL}/functions/v1/mcpmaster-supabase-control` });
  }
  if (acceptanceKeys.some(key => !KEYS.some(suffix => key === `PANDORA_ACCEPTANCE_${suffix}`))) throw denied();
  const config = canonicalAcceptanceConfig({
    sourceSha: env.PANDORA_ACCEPTANCE_SOURCE_SHA,
    supabaseProjectRef: env.PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF,
    publishableKeySha256: env.PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256,
    organizationId: env.PANDORA_ACCEPTANCE_ORGANIZATION_ID,
  });
  if (!exact(env.PANDORA_ACCEPTANCE_CONFIG_SHA256, shaPattern)) throw denied();
  const bytes = new TextEncoder().encode(JSON.stringify(config));
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  const configSha256 = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
  if (configSha256 !== env.PANDORA_ACCEPTANCE_CONFIG_SHA256) throw denied();
  if ((["chat", "control"].includes(role) && !present("SUPABASE_URL")) ||
      (present("SUPABASE_URL") && env.SUPABASE_URL !== config.supabaseUrl)) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
  let bridgeOrigin = null;
  if (role === "chat") {
    bridgeOrigin = origin(env.PANDORA_ACCEPTANCE_BRIDGE_ORIGIN);
    if (expectedBridgeOrigin !== undefined && bridgeOrigin !== origin(expectedBridgeOrigin)) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
  } else if (role === "control" && present("PANDORA_ACCEPTANCE_BRIDGE_ORIGIN")) {
    // Supabase secrets are shared across the project's Edge functions. Control
    // validates the chat-only destination but must never use it for routing.
    const sharedOrigin = origin(env.PANDORA_ACCEPTANCE_BRIDGE_ORIGIN);
    if (expectedBridgeOrigin !== undefined && sharedOrigin !== origin(expectedBridgeOrigin)) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
  } else if (present("PANDORA_ACCEPTANCE_BRIDGE_ORIGIN") || expectedBridgeOrigin !== undefined) throw denied();
  return Object.freeze({ ...config, acceptance: true, configSha256, bridgeOrigin,
    bedrockChatUrl: bridgeOrigin ? `${bridgeOrigin}/api/operations-inference?operation=bedrock-chat` : null,
    controlUrl: `${config.supabaseUrl}/functions/v1/mcpmaster-supabase-control` });
}

function marker(headers, name) {
  if (headers && typeof headers.get === "function") return headers.get(name);
  if (!record(headers)) return null;
  const keys = Object.keys(headers).filter(key => key.toLowerCase() === name);
  if (!keys.length) return null;
  if (keys.length !== 1 || typeof headers[keys[0]] !== "string") throw denied("CORE_RUNTIME_BINDING_MISMATCH");
  return headers[keys[0]];
}

export function runtimeBindingHeaders(profile) {
  if (profile?.profile === "production" && profile.acceptance === false) return {};
  if (profile?.profile !== ACCEPTANCE || profile.acceptance !== true ||
      !exact(profile.configSha256, shaPattern) || !exact(profile.sourceSha, /^[0-9a-f]{40}$/)) throw denied();
  return { [MARKERS[0]]: profile.profile, [MARKERS[1]]: profile.configSha256, [MARKERS[2]]: profile.sourceSha };
}

export function assertRuntimeRequestBinding(profile, headers) {
  const expected = runtimeBindingHeaders(profile);
  for (const key of MARKERS) {
    const actual = marker(headers, key);
    if (profile.acceptance ? actual !== expected[key] : actual !== null) throw denied("CORE_RUNTIME_BINDING_MISMATCH");
  }
}
