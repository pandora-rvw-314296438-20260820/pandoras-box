"use strict";

const {
  BEDROCK_REGION,
} = require("./aws-bedrock-catalog.js");
const {
  bedrockControlJson,
} = require("./aws-bedrock-runtime.js");

const CONTROL_SOURCE = "aws:bedrock:us-east-1:live-control-plane";
const MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/;\nconst SPECIALIZED_PATTERN = /(embed|embedding|rerank|safeguard|guard|sonic|voxtral|pegasus|image|canvas|reel|video|upscale|background|erase|recolor|outpaint|inpaint|search)/i;\nconst SERVERLESS_TYPES = new Set(["ON_DEMAND", "INFERENCE_PROFILE"]);

function record(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function list(value) {
  return Array.isArray(value) ? value.map(String) : [];
}
function workflowScopes(model) {
  const id = String(model.modelId || "").toLowerCase();
  const name = String(model.modelName || "").toLowerCase();
  const provider = String(model.providerName || "").toLowerCase();
  const input = new Set(list(model.inputModalities).map((x) => x.toUpperCase()));
  const output = new Set(list(model.outputModalities).map((x) => x.toUpperCase()));
  if ([...output].some((x) => x === "EMBEDDING") || /embed/.test(id + " " + name)) return ["embedding"];
  if (/rerank/.test(id + " " + name)) return ["reranking"];
  if ([...output].some((x) => x === "IMAGE")) return ["image"];
  if ([...output].some((x) => x === "VIDEO")) return ["video"];
  if ([...output].some((x) => x === "AUDIO" || x === "SPEECH")) return ["audio"];
  if (provider.includes("twelvelabs")) return ["video"];
  if (/safeguard|moderation|guardrail/.test(id + " " + name)) return ["safety"];
  if ((input.has("AUDIO") || input.has("SPEECH")) && output.has("TEXT")) return ["audio"];
  if (input.has("TEXT") && output.has("TEXT")) return ["conversation"];
  return ["other"];
}
function capabilityClasses(model, scopes) {
  const input = new Set(list(model.inputModalities).map((x) => x.toUpperCase()));
  const id = String(model.modelId || "").toLowerCase();
  const out = new Set(scopes);
  if (scopes.includes("conversation")) {
    out.add("chat");
    out.add("reasoning");
    if (input.has("IMAGE")) out.add("multimodal");
    if (/coder|devstral|code/.test(id)) out.add("coding");
  }
  return [...out].sort();
}
function profileModelMatches(profile, modelId) {
  return list(profile?.models).some(() => false) ||
    (Array.isArray(profile?.models) && profile.models.some((item) =>
      String(record(item).modelArn || "").endsWith("/" + modelId)));
}
function selectInvocationTarget(model, profiles) {
  const inference = new Set(list(model.inferenceTypesSupported));
  const id = String(model.modelId || "");
  if (inference.has("ON_DEMAND")) return id;
  if (!inference.has("INFERENCE_PROFILE")) return null;
  const active = profiles.filter((p) => String(p.status || "") === "ACTIVE");
  for (const preferred of [`us.${id}`, `global.${id}`]) {
    if (active.some((p) => String(p.inferenceProfileId || "") === preferred)) return preferred;
  }
  const matched = active.find((p) => profileModelMatches(p, id));
  return matched ? String(matched.inferenceProfileId || "") : null;
}
function stageFor(row) {
  if (row.lifecycleStatus === "REMOVED") return "retired";
  if (row.authorizationStatus !== "AUTHORIZED") return "discovered";
  if (row.entitlementAvailability !== "AVAILABLE") return "authorized";
  if (row.regionAvailability !== "AVAILABLE") return "entitled";
  if (row.runtimeVerificationStatus === "not_tested" || row.runtimeVerificationStatus === "skipped_non_conversational") return "region_available";
  if (row.runtimeVerificationStatus !== "passed" || row.lifecycleStatus !== "ACTIVE") return "runtime_tested";
  return "routable";
}
function compatibilityRuntimeState(row) {
  if (row.runtimeVerificationStatus === "passed") return "verified_available";
  if (row.lastProbeErrorCode === "access_denied") return "account_denied";
  if (row.lastProbeErrorCode === "throttled") return "throttled";
  return "provider_hold";
}
function normalizeCatalogRows({ models, profiles, availabilityById = {}, observedAt, region = BEDROCK_REGION }) {
  if (region !== BEDROCK_REGION || !Array.isArray(models) || !Array.isArray(profiles)) throw new Error("BEDROCK_CATALOG_INPUT_INVALID");
  const seen = new Set();
  return models.map((raw) => {
    const model = record(raw);
    const modelId = String(model.modelId || "");
    if (!MODEL_ID.test(modelId) || seen.has(modelId)) throw new Error("BEDROCK_CATALOG_MODEL_INVALID");
    seen.add(modelId);
    const scopes = workflowScopes(model);
    const availability = record(availabilityById[modelId]);
    const invocationTarget = selectInvocationTarget(model, profiles);
    const lifecycleStatus = String(record(model.modelLifecycle).status || "UNKNOWN");
    const row = {
      modelId,
      modelName: String(model.modelName || modelId).slice(0, 240),
      providerName: String(model.providerName || "Unknown").slice(0, 120),
      region,
      invocationTarget,
      inputModalities: list(model.inputModalities),
      outputModalities: list(model.outputModalities),
      inferenceTypes: list(model.inferenceTypesSupported),
      lifecycleStatus,
      authorizationStatus: availability.authorizationStatus ? String(availability.authorizationStatus) : null,
      entitlementAvailability: availability.entitlementAvailability ? String(availability.entitlementAvailability) : null,
      agreementStatus: record(availability.agreementAvailability).status ? String(record(availability.agreementAvailability).status) : null,
      regionAvailability: availability.regionAvailability ? String(availability.regionAvailability) : null,
      workflowScopes: scopes,
      capabilityClasses: capabilityClasses(model, scopes),
      riskTier: scopes.includes("conversation") ? 1 : 2,
      runtimeVerificationStatus: scopes.includes("conversation") ? "not_tested" : "skipped_non_conversational",
      lastVerifiedAt: null,
      routable: false,
      runtimeReason: scopes.includes("conversation") ? "runtime_probe_pending" : "workflow_not_conversational",
      lastProbeInputTokens: 0,
      lastProbeOutputTokens: 0,
      lastProbeTotalTokens: 0,
      lastProbeProviderRequestId: null,
      lastProbeErrorCode: null,
      observedAt,
      sourceRef: CONTROL_SOURCE,
    };
    row.availabilityState = stageFor(row);
    row.runtimeState = compatibilityRuntimeState(row);
    return row;
  });
}
function applyProbeResult(row, probe) {
  const result = { ...row };
  result.runtimeVerificationStatus = probe.ok === true ? "passed" : "failed";
  result.lastVerifiedAt = probe.observedAt || row.observedAt;
  result.lastProbeInputTokens = Number(probe.inputTokens || 0);
  result.lastProbeOutputTokens = Number(probe.outputTokens || 0);
  result.lastProbeTotalTokens = Number(probe.totalTokens || 0);
  result.lastProbeProviderRequestId = probe.providerRequestId || null;
  result.lastProbeErrorCode = probe.errorCode || null;
  result.runtimeReason = probe.ok === true ? "bounded_converse_verified" : String(probe.errorCode || "runtime_probe_failed");
  result.routable = probe.ok === true && row.lifecycleStatus === "ACTIVE" &&
    row.authorizationStatus === "AUTHORIZED" &&
    row.entitlementAvailability === "AVAILABLE" &&
    row.regionAvailability === "AVAILABLE" &&
    row.workflowScopes.includes("conversation");
  result.availabilityState = stageFor(result);
  result.runtimeState = compatibilityRuntimeState(result);
  return result;
}
async function listInferenceProfiles({ credentials, fetchFn, region = BEDROCK_REGION }) {
  const profiles = [];
  let nextToken = null;
  for (let page = 0; page < 10; page += 1) {
    const payload = await bedrockControlJson({
      path: "/inference-profiles",
      query: { maxResults: 100, type: "SYSTEM_DEFINED", ...(nextToken ? { nextToken } : {}) },
      credentials, fetchFn, region,
    });
    profiles.push(...(Array.isArray(payload.inferenceProfileSummaries) ? payload.inferenceProfileSummaries : []));
    nextToken = typeof payload.nextToken === "string" && payload.nextToken ? payload.nextToken : null;
    if (!nextToken) return profiles;
  }
  throw new Error("BEDROCK_PROFILE_PAGINATION_UNBOUNDED");
}
async function mapLimit(items, limit, worker) {
  const output = new Array(items.length);
  let cursor = 0;
  async function run() {
    while (cursor < items.length) {
      const index = cursor++;
      output[index] = await worker(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length || 1) }, run));
  return output;
}
async function discoverBedrockCatalog({ credentials, fetchFn = globalThis.fetch, region = BEDROCK_REGION, observedAt = new Date().toISOString() }) {
  const [foundation, profiles] = await Promise.all([
    bedrockControlJson({ path: "/foundation-models", credentials, fetchFn, region }),
    listInferenceProfiles({ credentials, fetchFn, region }),
  ]);
  const models = Array.isArray(foundation.modelSummaries) ? foundation.modelSummaries : [];
  const availability = await mapLimit(models, 12, async (model) => {
    try {
      return await bedrockControlJson({
        path: `/foundation-model-availability/${encodeURIComponent(String(model.modelId || ""))}`,
        credentials, fetchFn, region, timeoutMs: 12000,
      });
    } catch (error) {
      return { lookupError: error instanceof Error ? error.message : "AWS_BEDROCK_CONTROL_FAILED" };
    }
  });
  const availabilityById = Object.fromEntries(models.map((model, index) => [String(model.modelId || ""), availability[index]]));
  return normalizeCatalogRows({ models, profiles, availabilityById, observedAt, region });
}


function text(value) {
  return typeof value === "string" ? value.trim() : "";
}
function strings(value) {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())
    : [];
}
function isConversationalBedrockModel(summary) {
  const modelId = text(summary?.modelId);
  const modelName = text(summary?.modelName);
  const inputs = strings(summary?.inputModalities);
  const outputs = strings(summary?.outputModalities);
  const types = strings(summary?.inferenceTypesSupported);
  const lifecycle = text(summary?.modelLifecycle?.status);
  return lifecycle === "ACTIVE" &&
    inputs.includes("TEXT") &&
    outputs.includes("TEXT") &&
    types.some((item) => SERVERLESS_TYPES.has(item)) &&
    !SPECIALIZED_PATTERN.test(\`\${modelId} \${modelName}\`) &&
    workflowScopes(summary).includes("conversation");
}
function snapshotCapabilityClasses(summary, conversational) {
  const inputs = strings(summary?.inputModalities);
  const outputs = strings(summary?.outputModalities);
  const out = [];
  if (conversational) out.push("chat", "reasoning");
  if (inputs.includes("IMAGE") && outputs.includes("TEXT")) out.push("vision");
  if (outputs.includes("EMBEDDING")) out.push("embedding");
  if (outputs.includes("IMAGE")) out.push("image_generation");
  if (outputs.includes("VIDEO")) out.push("video_generation");
  if (inputs.includes("SPEECH") || outputs.includes("SPEECH")) out.push("audio");
  return [...new Set(out.length ? out : ["other"])];
}
function preProbeState(entry) {
  if (entry.lifecycleStatus !== "ACTIVE") {
    return { state: "retired", reason: \`lifecycle_\${entry.lifecycleStatus.toLowerCase() || "unknown"}\` };
  }
  if (entry.authorizationStatus !== "AUTHORIZED") {
    return { state: "discovered", reason: \`authorization_\${entry.authorizationStatus.toLowerCase() || "unknown"}\` };
  }
  if (entry.agreementStatus !== "AVAILABLE") {
    return { state: "authorized", reason: \`agreement_\${entry.agreementStatus.toLowerCase() || "unknown"}\` };
  }
  if (entry.entitlementStatus !== "AVAILABLE") {
    return { state: "authorized", reason: \`entitlement_\${entry.entitlementStatus.toLowerCase() || "unknown"}\` };
  }
  if (entry.regionAvailability !== "AVAILABLE") {
    return { state: "entitled", reason: \`region_\${entry.regionAvailability.toLowerCase() || "unknown"}\` };
  }
  if (!entry.invocationTarget) return { state: "region_available", reason: "invocation_target_unresolved" };
  return { state: "region_available", reason: "runtime_probe_required" };
}
function normalizeBedrockCatalogSnapshot({
  foundationModels,
  inferenceProfiles,
  availabilityByModel,
  region = BEDROCK_REGION,
  observedAt = new Date().toISOString(),
}) {
  if (!Array.isArray(foundationModels) ||
      !Array.isArray(inferenceProfiles) ||
      !availabilityByModel ||
      typeof availabilityByModel !== "object") {
    throw new TypeError("invalid Bedrock catalog truth");
  }
  const models = foundationModels.map((summary) => {
    const modelId = text(summary?.modelId);
    if (!modelId) throw new TypeError("Bedrock modelId is required");
    const availability = availabilityByModel[modelId] || {};
    const conversational = isConversationalBedrockModel(summary);
    const entry = {
      modelId,
      modelName: text(summary?.modelName) || modelId,
      providerName: text(summary?.providerName) || "Unknown",
      region,
      inputModalities: strings(summary?.inputModalities),
      outputModalities: strings(summary?.outputModalities),
      inferenceTypes: strings(summary?.inferenceTypesSupported),
      responseStreamingSupported: summary?.responseStreamingSupported === true,
      invocationTarget: selectInvocationTarget(summary, inferenceProfiles),
      lifecycleStatus: text(summary?.modelLifecycle?.status) || "UNKNOWN",
      lifecycle: summary?.modelLifecycle && typeof summary.modelLifecycle === "object"
        ? summary.modelLifecycle
        : {},
      agreementStatus: text(availability?.agreementAvailability?.status) || "UNKNOWN",
      authorizationStatus: text(availability?.authorizationStatus) || "UNKNOWN",
      entitlementStatus: text(availability?.entitlementAvailability) || "UNKNOWN",
      regionAvailability: text(availability?.regionAvailability) || "UNKNOWN",
      conversational,
      capabilityClasses: snapshotCapabilityClasses(summary, conversational),
      observedAt,
      sourceRef: \`aws:bedrock:\${region}:list-foundation-models+list-inference-profiles+get-foundation-model-availability\`,
    };
    const stage = preProbeState(entry);
    return Object.freeze({ ...entry, preProbeState: stage.state, preProbeReason: stage.reason });
  });
  return Object.freeze({
    region,
    observedAt,
    source: \`aws:bedrock:\${region}:live-catalog-v2\`,
    models: Object.freeze(models),
  });
}
function buildBedrockProbePlan(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.models)) throw new TypeError("snapshot.models is required");
  return Object.freeze(snapshot.models
    .filter((model) => model.conversational === true)
    .map((model) => Object.freeze({
      modelId: model.modelId,
      providerName: model.providerName,
      invocationTarget: model.invocationTarget,
    })));
}
function minimalBedrockProbeBody() {
  return Object.freeze({
    messages: Object.freeze([
      { role: "user", content: Object.freeze([{ text: "OK" }]) },
    ]),
    inferenceConfig: Object.freeze({ maxTokens: 1, temperature: 0 }),
  });
}

module.exports = {
  CONTROL_SOURCE,
  buildBedrockProbePlan,
  applyProbeResult,
  classifyWorkflow: workflowScopes,
  discoverBedrockCatalog,
  isConversationalBedrockModel,
  minimalBedrockProbeBody,
  normalizeBedrockCatalogSnapshot,
  normalizeCatalogRows,
  preProbeState,
  selectInvocationTarget,
  stageFor,
};
