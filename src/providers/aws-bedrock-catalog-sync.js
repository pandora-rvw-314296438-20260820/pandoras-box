"use strict";

const SPECIALIZED_PATTERN = /(embed|embedding|rerank|safeguard|guard|sonic|voxtral|pegasus|image|canvas|reel|video|upscale|background|erase|recolor|outpaint|inpaint|search)/i;
const SERVERLESS_TYPES = new Set(["ON_DEMAND", "INFERENCE_PROFILE"]);

function text(value) { return typeof value === "string" ? value.trim() : ""; }
function strings(value) { return Array.isArray(value) ? value.filter((x) => typeof x === "string" && x.trim()).map((x) => x.trim()) : []; }
function activeProfilesForModel(modelId, inferenceProfiles) {
  const suffix = `foundation-model/${modelId}`;
  return inferenceProfiles
    .filter((profile) => profile && profile.status === "ACTIVE" && strings(profile.models?.map?.((m) => m?.modelArn)).some((arn) => arn.endsWith(suffix)))
    .map((profile) => text(profile.inferenceProfileId))
    .filter(Boolean);
}
function selectInvocationTarget(summary, inferenceProfiles) {
  const modelId = text(summary?.modelId);
  const types = strings(summary?.inferenceTypesSupported);
  if (types.includes("ON_DEMAND")) return modelId || null;
  const profiles = activeProfilesForModel(modelId, inferenceProfiles);
  return profiles.find((id) => id.startsWith("us.")) || profiles.find((id) => id.startsWith("global.")) || profiles[0] || null;
}
function isConversationalBedrockModel(summary) {
  const modelId = text(summary?.modelId), modelName = text(summary?.modelName);
  const inputs = strings(summary?.inputModalities), outputs = strings(summary?.outputModalities), types = strings(summary?.inferenceTypesSupported);
  const lifecycle = text(summary?.modelLifecycle?.status);
  return lifecycle === "ACTIVE" && inputs.includes("TEXT") && outputs.includes("TEXT") && types.some((x) => SERVERLESS_TYPES.has(x)) && !SPECIALIZED_PATTERN.test(`${modelId} ${modelName}`);
}
function capabilityClasses(summary, conversational) {
  const inputs = strings(summary?.inputModalities), outputs = strings(summary?.outputModalities);
  const out = [];
  if (conversational) out.push("chat", "reasoning");
  if (inputs.includes("IMAGE") && outputs.includes("TEXT")) out.push("vision");
  if (outputs.includes("EMBEDDING")) out.push("embedding");
  if (outputs.includes("IMAGE")) out.push("image_generation");
  if (outputs.includes("VIDEO")) out.push("video_generation");
  if (inputs.includes("SPEECH") || outputs.includes("SPEECH")) out.push("audio");
  return [...new Set(out.length ? out : ["other"] )];
}
function preProbeState(entry) {
  if (entry.lifecycleStatus !== "ACTIVE") return { state: "retired", reason: `lifecycle_${entry.lifecycleStatus.toLowerCase() || "unknown"}` };
  if (entry.authorizationStatus !== "AUTHORIZED") return { state: "discovered", reason: `authorization_${entry.authorizationStatus.toLowerCase() || "unknown"}` };
  if (entry.agreementStatus !== "AVAILABLE") return { state: "authorized", reason: `agreement_${entry.agreementStatus.toLowerCase() || "unknown"}` };
  if (entry.entitlementStatus !== "AVAILABLE") return { state: "authorized", reason: `entitlement_${entry.entitlementStatus.toLowerCase() || "unknown"}` };
  if (entry.regionAvailability !== "AVAILABLE") return { state: "entitled", reason: `region_${entry.regionAvailability.toLowerCase() || "unknown"}` };
  if (!entry.invocationTarget) return { state: "region_available", reason: "invocation_target_unresolved" };
  return { state: "region_available", reason: "runtime_probe_required" };
}
function normalizeBedrockCatalogSnapshot({ foundationModels, inferenceProfiles, availabilityByModel, region = "us-east-1", observedAt = new Date().toISOString() }) {
  if (!Array.isArray(foundationModels) || !Array.isArray(inferenceProfiles) || !availabilityByModel || typeof availabilityByModel !== "object") throw new TypeError("invalid Bedrock catalog truth");
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
      lifecycle: summary?.modelLifecycle && typeof summary.modelLifecycle === "object" ? summary.modelLifecycle : {},
      agreementStatus: text(availability?.agreementAvailability?.status) || "UNKNOWN",
      authorizationStatus: text(availability?.authorizationStatus) || "UNKNOWN",
      entitlementStatus: text(availability?.entitlementAvailability) || "UNKNOWN",
      regionAvailability: text(availability?.regionAvailability) || "UNKNOWN",
      conversational,
      capabilityClasses: capabilityClasses(summary, conversational),
      observedAt,
      sourceRef: `aws:bedrock:${region}:list-foundation-models+list-inference-profiles+get-foundation-model-availability`,
    };
    const stage = preProbeState(entry);
    return Object.freeze({ ...entry, preProbeState: stage.state, preProbeReason: stage.reason });
  });
  return Object.freeze({ region, observedAt, source: `aws:bedrock:${region}:live-catalog-v2`, models: Object.freeze(models) });
}
function buildBedrockProbePlan(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.models)) throw new TypeError("snapshot.models is required");
  return Object.freeze(snapshot.models.filter((model) => model.conversational === true).map((model) => Object.freeze({ modelId: model.modelId, providerName: model.providerName, invocationTarget: model.invocationTarget })));
}
function minimalBedrockProbeBody(modelId = "") {
  const normalized = String(modelId || "").trim().toLowerCase();
  const maxTokens = normalized === "moonshotai.kimi-k3" ? 16 : 1;
  return Object.freeze({
    messages: Object.freeze([
      { role: "user", content: Object.freeze([{ text: "OK" }]) },
    ]),
    inferenceConfig: Object.freeze({ maxTokens }),
  });
}
module.exports = { buildBedrockProbePlan, isConversationalBedrockModel, minimalBedrockProbeBody, normalizeBedrockCatalogSnapshot, preProbeState, selectInvocationTarget };
