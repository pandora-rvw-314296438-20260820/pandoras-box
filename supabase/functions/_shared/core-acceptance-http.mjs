import {
  assertRuntimeRequestBinding,
  resolveCoreRuntimeProfile,
  runtimeBindingHeaders,
} from "./core-acceptance-profile.mjs";

function denied(code = "CORE_RUNTIME_OPERATION_DENIED") {
  return Object.assign(new Error(code), { code, status: 400, retryable: false, crossProviderEligible: false });
}

// Resolve the actual server environment before invoking any authentication,
// service-role, worker or provider transport. Binding metadata is additional
// provenance; the wrapped handler still performs its normal authentication.
export async function withCoreRuntimeBinding(request, environment, role, handler) {
  let profile;
  try {
    profile = await resolveCoreRuntimeProfile(environment, { role });
    // A browser preflight has no application headers. Its existing CORS handler
    // decides whether the proposed method/origin is allowed; no work is admitted.
    if (request.method !== "OPTIONS") assertRuntimeRequestBinding(profile, request.headers);
  } catch (error) {
    const code = /^CORE_RUNTIME_(?:PROFILE_INVALID|TARGET_MISMATCH|BINDING_MISMATCH)$/.test(error?.code || "")
      ? error.code : "CORE_RUNTIME_PROFILE_INVALID";
    return Response.json({ ok: false, code, retryable: false }, {
      status: 400, headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" },
    });
  }
  const response = await handler(request, profile);
  for (const [name, value] of Object.entries(runtimeBindingHeaders(profile))) response.headers.set(name, value);
  return response;
}

export function assertAcceptanceOrganization(profile, organizationId) {
  if (profile?.acceptance && organizationId !== profile.organizationId) throw denied("CORE_RUNTIME_TARGET_MISMATCH");
}

export function assertAcceptanceOperation(profile, operation, role) {
  if (!profile?.acceptance) return;
  const allowed = { control: "bedrock_chat_ticket_claim", bridge: "bedrock-chat", provider: "bedrock" };
  if (!Object.hasOwn(allowed, role) || operation !== allowed[role]) throw denied();
}

// No synthetic Memory receipt and no fallback to the production Memory bridge.
// An acceptance journey can prove graceful degradation, not Memory integration.
export function acceptanceMemoryDegradation(profile) {
  return profile?.acceptance ? {
    state: "degraded", reason: "acceptance_memory_not_configured",
    receiptRef: null, contextSha256: null, policyMemory: [], advisoryMemory: [], memoryItemIds: [],
    authorizationGranted: false,
  } : null;
}

export async function loadRuntimeProviderConfigs(profile, loaders) {
  const names = ["gemini", "kimi", "openai", "openrouter", "bedrock"];
  return await Promise.all(names.map(name => {
    if (profile?.acceptance && name !== "bedrock") return {
      enabled: false, routingEligible: false, allowedModels: [], tasks: [], preferredTasks: [], fallbackEnabled: false,
    };
    return loaders[name]();
  }));
}
