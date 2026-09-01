'use strict';

const {
  deterministicCohortBucket,
  evidenceWeight,
  evaluateCircuitBreaker,
  explorationEnabledForRequest,
  normalizeAdaptiveConfig,
  normalizeCircuitBreakerConfig,
  normalizeHealthSignals,
  normalizePerformance,
  reasoningPolicyFor,
  trafficPreference,
  weightedPerformanceScore,
} = require('./adaptive.js');

/** @type {Readonly<Record<string, number>>} */
const COST_RANK = Object.freeze({ low: 1, medium: 2, high: 3 });
/** @type {Readonly<Record<string, number>>} */
const RELIABILITY_RANK = Object.freeze({ experimental: 1, standard: 2, high: 3 });
const CIRCUIT_STATES = Object.freeze(['closed', 'open', 'half_open']);

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => {
    if (typeof item !== 'string' || !item.trim()) throw new TypeError(`${field}[${index}] must be a non-empty string`);
    return item.trim();
  });
}
/** @param {unknown} value @param {Readonly<Record<string, number>>} ranks @param {string} field */
function rankedValue(value, ranks, field) {
  if (value == null) return null;
  if (typeof value !== 'string' || typeof ranks[value] !== 'number') throw new TypeError(`${field} is invalid`);
  return value;
}
/** @param {unknown} value @param {number} fallback */
function finiteOrDefault(value, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError('routing weights must be non-negative finite numbers');
  return value;
}
/** @param {unknown} value @param {string} field */
function nonNegativeNumberOrNull(value, field) {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError(`${field} must be a non-negative finite number`);
  return value;
}
/** @param {unknown} value @param {string} field */
function fractionOrNull(value, field) {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new TypeError(`${field} must be between 0 and 1`);
  return value;
}
/** @param {unknown} value @param {string} field @param {number} fallback */
function nonNegativeInteger(value, field, fallback) {
  if (value == null) return fallback;
  if (!Number.isInteger(value) || Number(value) < 0) throw new TypeError(`${field} must be a non-negative integer`);
  return Number(value);
}
/** @param {unknown} value @param {string} field @param {string} fallback */
function textOrDefault(value, field, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} must be a non-empty string`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function normalizeControls(value, field) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError(`${field} must be an object`);
  /** @type {Record<string, Readonly<Record<string, unknown>>>} */
  const output = {};
  for (const [key, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!key.trim() || !isRecord(raw)) throw new TypeError(`${field}.${key} must be an object`);
    const item = /** @type {Record<string, unknown>} */ (raw);
    output[key] = Object.freeze({
      enabled: item.enabled !== false,
      killSwitch: item.killSwitch === true,
      quarantined: item.quarantined === true,
      allowedTasks: Object.freeze(stringList(item.allowedTasks, `${field}.${key}.allowedTasks`)),
      deniedTasks: Object.freeze(stringList(item.deniedTasks, `${field}.${key}.deniedTasks`)),
    });
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeCircuits(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('circuits must be an object');
  /** @type {Record<string, Readonly<Record<string, unknown>>>} */
  const output = {};
  for (const [key, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`circuits.${key} must be an object`);
    const item = /** @type {Record<string, unknown>} */ (raw);
    const state = item.state == null ? 'closed' : String(item.state);
    if (!CIRCUIT_STATES.includes(state)) throw new TypeError(`circuits.${key}.state is invalid`);
    output[key] = Object.freeze({ state, probeAllowed: item.probeAllowed === true, observedAt: typeof item.observedAt === 'string' ? item.observedAt : null });
  }
  return Object.freeze(output);
}

/** @param {unknown} value @param {string} field */
function normalizeNestedStringMap(value, field) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError(`${field} must be an object`);
  /** @type {Record<string, Readonly<Record<string, string>>>} */
  const output = {};
  for (const [outerKey, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`${field}.${outerKey} must be an object`);
    /** @type {Record<string, string>} */
    const inner = {};
    for (const [innerKey, innerValue] of Object.entries(/** @type {Record<string, unknown>} */ (raw))) {
      if (typeof innerValue !== 'string' || !innerValue.trim()) throw new TypeError(`${field}.${outerKey}.${innerKey} must be a non-empty string`);
      inner[innerKey] = innerValue.trim();
    }
    output[outerKey] = Object.freeze(inner);
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeTrafficWeights(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('trafficWeights must be an object');
  /** @type {Record<string, Readonly<Record<string, number>>>} */
  const output = {};
  for (const [task, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`trafficWeights.${task} must be an object`);
    /** @type {Record<string, number>} */
    const weights = {};
    let total = 0;
    for (const [candidate, weight] of Object.entries(/** @type {Record<string, unknown>} */ (raw))) {
      if (typeof weight !== 'number' || !Number.isFinite(weight) || weight < 0 || weight > 1) throw new TypeError(`trafficWeights.${task}.${candidate} must be between 0 and 1`);
      weights[candidate] = weight;
      total += weight;
    }
    if (total > 1.0000001) throw new TypeError(`trafficWeights.${task} total must not exceed 1`);
    output[task] = Object.freeze(weights);
  }
  return Object.freeze(output);
}


/** @param {unknown} value */
function normalizeTaskWeights(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('taskWeights must be an object');
  /** @type {Record<string, Readonly<Record<string, number>>>} */
  const output = {};
  for (const [task, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`taskWeights.${task} must be an object`);
    const item = /** @type {Record<string, unknown>} */ (raw);
    output[task] = Object.freeze({
      qualityWeight: finiteOrDefault(item.qualityWeight, 1),
      successWeight: finiteOrDefault(item.successWeight, 1),
      latencyWeight: finiteOrDefault(item.latencyWeight, 0.15),
      costWeight: finiteOrDefault(item.costWeight, 0.15),
    });
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeTaskPreferences(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('taskPreferences must be an object');
  /** @type {Record<string, Readonly<Record<string, string|null>>>} */
  const output = {};
  for (const [task, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`taskPreferences.${task} must be an object`);
    const item = /** @type {Record<string, unknown>} */ (raw);
    output[task] = Object.freeze({
      preferredProvider: typeof item.preferredProvider === 'string' && item.preferredProvider.trim() ? item.preferredProvider.trim() : null,
      preferredModel: typeof item.preferredModel === 'string' && item.preferredModel.trim() ? item.preferredModel.trim() : null,
    });
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeSlaFallbackOrder(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('slaFallbackOrder must be an object');
  /** @type {Record<string, readonly string[]>} */
  const output = {};
  for (const [task, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) output[task] = Object.freeze(stringList(raw, `slaFallbackOrder.${task}`));
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeActiveModelVersions(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('activeModelVersions must be an object');
  /** @type {Record<string, string>} */
  const output = {};
  for (const [key, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (typeof raw !== 'string' || !raw.trim()) throw new TypeError(`activeModelVersions.${key} must be a non-empty string`);
    output[key] = raw.trim();
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeReasoningPolicies(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('reasoningPolicies must be an object');
  /** @type {Record<string, Readonly<Record<string,string>>>} */
  const output = {};
  for (const [task, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`adaptive.reasoningPolicies.${task} must be an object`);
    /** @type {Record<string, string>} */
    const mapping = {};
    for (const [candidate, policy] of Object.entries(/** @type {Record<string, unknown>} */ (raw))) {
      if (typeof policy !== 'string' || !policy.trim()) throw new TypeError(`adaptive.reasoningPolicies.${task}.${candidate} must be a non-empty string`);
      mapping[candidate] = policy.trim();
    }
    output[task] = Object.freeze(mapping);
  }
  return Object.freeze(output);
}

/** @param {unknown} value */
function normalizeHealthSignalMap(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('healthSignals must be an object');
  /** @type {Record<string, Readonly<Record<string, unknown>>>} */
  const output = {};
  for (const [key, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) output[key] = normalizeHealthSignals(raw);
  return Object.freeze(output);
}

/** @param {Record<string, unknown>} input */
function createRoutingPolicy(input = {}) {
  const maxCostClass = rankedValue(input.maxCostClass, COST_RANK, 'maxCostClass');
  const minReliabilityClass = rankedValue(input.minReliabilityClass, RELIABILITY_RANK, 'minReliabilityClass');
  const maxEstimatedCostUsd = nonNegativeNumberOrNull(input.maxEstimatedCostUsd, 'maxEstimatedCostUsd');
  const maxLatencyMs = nonNegativeNumberOrNull(input.maxLatencyMs, 'maxLatencyMs');
  const minObservedSuccessRate = fractionOrNull(input.minObservedSuccessRate, 'minObservedSuccessRate');
  const minObservedQuality = fractionOrNull(input.minObservedQuality, 'minObservedQuality');
  return Object.freeze({
    policyVersion: textOrDefault(input.policyVersion, 'policyVersion', 'stable-v1'),
    allowedProviders: Object.freeze(stringList(input.allowedProviders, 'allowedProviders')),
    deniedProviders: Object.freeze(stringList(input.deniedProviders, 'deniedProviders')),
    allowedModels: Object.freeze(stringList(input.allowedModels, 'allowedModels')),
    deniedModels: Object.freeze(stringList(input.deniedModels, 'deniedModels')),
    providerControls: normalizeControls(input.providerControls, 'providerControls'),
    modelControls: normalizeControls(input.modelControls, 'modelControls'),
    circuits: normalizeCircuits(input.circuits),
    circuitBreaker: normalizeCircuitBreakerConfig(input.circuitBreaker),
    healthSignals: normalizeHealthSignalMap(input.healthSignals),
    maxCostClass, minReliabilityClass, maxEstimatedCostUsd, maxLatencyMs, minObservedSuccessRate, minObservedQuality,
    hardFloorMinSamples: nonNegativeInteger(input.hardFloorMinSamples, 'hardFloorMinSamples', 20),
    requireIndependentVerifier: input.requireIndependentVerifier === true,
    builderProvider: typeof input.builderProvider === 'string' && input.builderProvider.trim() ? input.builderProvider.trim() : null,
    builderModel: typeof input.builderModel === 'string' && input.builderModel.trim() ? input.builderModel.trim() : null,
    qualityWeight: finiteOrDefault(input.qualityWeight, 1),
    successWeight: finiteOrDefault(input.successWeight, 1),
    latencyWeight: finiteOrDefault(input.latencyWeight, 0.15),
    costWeight: finiteOrDefault(input.costWeight, 0.15),
    taskWeights: normalizeTaskWeights(input.taskWeights),
    performance: normalizePerformance(input.performance),
    taskPreferences: normalizeTaskPreferences(input.taskPreferences),
    trafficWeights: normalizeTrafficWeights(input.trafficWeights),
    slaFallbackOrder: normalizeSlaFallbackOrder(input.slaFallbackOrder),
    activeModelVersions: normalizeActiveModelVersions(input.activeModelVersions),
    adaptive: normalizeAdaptiveConfig({ ...(isRecord(input.adaptive) ? input.adaptive : {}), reasoningPolicies: normalizeReasoningPolicies(isRecord(input.adaptive) ? input.adaptive.reasoningPolicies : null) }),
  });
}

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>} policy */
function controlFor(model, policy) {
  const provider = String(model.provider), modelId = String(model.modelId);
  const providerControls = isRecord(policy.providerControls) ? /** @type {Readonly<Record<string, Readonly<Record<string, unknown>>>>} */ (policy.providerControls) : {};
  const modelControls = isRecord(policy.modelControls) ? /** @type {Readonly<Record<string, Readonly<Record<string, unknown>>>>} */ (policy.modelControls) : {};
  return {
    provider: providerControls[provider] ?? {},
    model: modelControls[`${provider}:${modelId}`] ?? modelControls[modelId] ?? {},
  };
}

/** @param {Readonly<Record<string, unknown>> item @param {string} task @param {string} prefix @param {string[]} reasons */
function applyControl(item, task, prefix, reasons) {
  if (item.enabled === false) reasons.push(`${prefix}_disabled`);
  if (item.killSwitch === true) reasons.push(`${prefix}_kill_switch`);
  if (item.quarantined === true) reasons.push(`${prefix}_quarantined`);
  const allowedTasks = Array.isArray(item.allowedTasks) ? item.allowedTasks : [];
  const deniedTasks = Array.isArray(item.deniedTasks) ? item.deniedTasks : [];
  if (allowedTasks.length && !allowedTasks.includes(task) && !allowedTasks.includes('*')) reasons.push(`${prefix}_task_not_allowed`);
  if (deniedTasks.includes(task) || deniedTasks.includes('*')) reasons.push(`${prefix}_task_denied`);
}

/** @param {Readonly<Record<string, unknown>> model @param {Readonly<Record<string, unknown>> policy @param {{task?:string,estimatedCostUsd?:number|null,requestMaxCostUsd?:number|null,allowCircuitProbe?:boolean,nowMs?:number}} context */
function modelEligibility(model, policy, context = {}) {
  const provider = String(model.provider), modelId = String(model.modelId), task = context.task ?? '*';
  /** @type {string[]} */
  const reasons = [];
  const allowedProviders = /** @type {readonly string[]} */ (policy.allowedProviders ?? []);
  const deniedProviders = /** @type {readonly string[]} */ (policy.deniedProviders ?? []);
  const allowedModels = /** @type {readonly string[]} */ (policy.allowedModels ?? []);
  const deniedModels = /** @type {readonly string[]} */ (policy.deniedModels ?? []);
  if (allowedProviders.length && !allowedProviders.includes(provider)) reasons.push('provider_not_allowed');
  if (deniedProviders.includes(provider)) reasons.push('provider_denied');
  if (allowedModels.length && !allowedModels.includes(modelId) && !allowedModels.includes(`${provider}:${modelId}`)) reasons.push('model_not_allowed');
  if (deniedModels.includes(modelId) || deniedModels.includes(`${provider}:${modelId}`)) reasons.push('model_denied');
  const controls = controlFor(model, policy);
  applyControl(controls.provider, task, 'provider', reasons);
  applyControl(controls.model, task, 'model', reasons);

  const circuits = isRecord(policy.circuits) ? /** @type {Readonly<Record<string, Readonly<Record<string, unknown>>>>} */ (policy.circuits) : {};
  const explicitCircuit = circuits[`${provider}:${modelId}`] ?? circuits[ provider ] ?? null;
  const healthSignals = isRecord(policy.healthSignals) ? /** @type {Readonly<Record<string, Readonly<Record<string, unknown>>>>} */ (policy.healthSignals) : {};
  const healthSignal = healthSignals[`${provider}:${modelId}`] ?? healthSignals[provider] ?? null;
  const breakerConfig = isRecord(policy.circuitBreaker) ? /** @type {Readonly<Record<string, unknown>>} */ (policy.circuitBreaker) : {};
  const automaticCircuit = healthSignal ? evaluateCircuitBreaker(healthSignal, breakerConfig, context.nowMs ?? Date.now()) : null;
  const circuitState = explicitCircuit?.state ?? automaticCircuit?.state ?? 'closed';
  const probeAllowed = explicitCircuit?.probeAllowed === true || (automaticCircuit?.state === 'half_open' && healthSignal?.state === 'open');
  if (circuitState === 'open') reasons.push('circuit_open');
  if (circuitState === 'half_open' && !(context.allowCircuitProbe === true && probeAllowed)) reasons.push('circuit_probe_required');

  if (typeof policy.maxCostClass === 'string' && (COST_RANK[String(model.costClass)] ?? 99) > (COST_RANK[policy.maxCostClass] ?? 0)) reasons.push('cost_class_ceiling');
  if (typeof policy.minReliabilityClass === 'string' && (RELIABILITY_RANK[String(model.reliabilityClass)] ?? 0) < (RELIABILITY_RANK[policy.minReliabilityClass] ?? 99)) reasons.push('reliability_class_floor');
  if (policy.requireIndependentVerifier === true && policy.builderProvider === provider && (!policy.builderModel || policy.builderModel === modelId)) reasons.push('independent_verifier_required');

  const metrics = performanceFor(model, policy);
  const sampleCount = metrics ? Number(metrics.sampleCount ?? 0) : 0;
  const hardFloorMinSamples = Number(policy.hardFloorMinSamples ?? 20);
  if (metrics && sampleCount >= hardFloorMinSamples) {
    if (typeof policy.minObservedSuccessRate === 'number' && Number(metrics.successRate ?? 0) < policy.minObservedSuccessRate) reasons.push('observed_reliability_floor');
    if (typeof policy.minObservedQuality === 'number' && Number(metrics.quality ?? 0) < policy.minObservedQuality) reasons.push('observed_quality_floor');
    if (typeof policy.maxLatencyMs === 'number' && typeof metrics.p95LatencyMs === 'number' && metrics.p95LatencyMs > policy.maxLatencyMs) reasons.push('latency_ceiling');
  }

  const estimates = [context.estimatedCostUsd, metrics?.effectiveEstimatedCostUsd, metrics?.estimatedCostUsd].filter((value) => typeof value === 'number');
  const estimatedCostUsd = estimates.length ? Number(estimates[0]) : null;
  const ceilings = [context.requestMaxCostUsd, policy.maxEstimatedCostUsd].filter((value) => typeof value === 'number').map(Number);
  const costCeiling = ceilings.length ? Math.min(...ceilings) : null;
  if (estimatedCostUsd != null && costCeiling != null && estimatedCostUsd > costCeiling) reasons.push('estimated_cost_ceiling');
  return Object.freeze({ allowed: reasons.length === 0, reasons: Object.freeze(reasons), metrics, estimatedCostUsd, costCeiling, circuitState });
}

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>} policy */
function modelAllowed(model, policy) { return modelEligibility(model, policy).allowed; }
/** @param {Readonly<Record<string, unknown>>[]} models @param {Readonly<Record<string, unknown>>|null|undefined} policy */
function applyRoutingPolicy(models, policy) { if (!policy) return models.slice(); return models.filter((model) => modelAllowed(model, policy)); }

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>|null|undefined} policy @param {{task?:string,nowMs?:number,cohortKey?:string|null}} context */
function routingPolicyScoreDetailed(model, policy, context = {}) {
  if (!policy) return Object.freeze({ total: 0, performance: 0, preference: 0, traffic: 0, exploration: 0, sla: 0, evidenceWeight: 0 });
  const task = context.task ?? '*';
  const key = `${String(model.provider)}:${String(model.modelId)}`;
  const metrics = performanceFor(model, policy);
  const activeVersions = isRecord(policy.activeModelVersions) ? /** @type {Readonly<Record<string,string>>} */ (policy.activeModelVersions) : {};
  const activeVersion = activeVersions[key] ?? null;
  const nowMs = context.nowMs ?? Date.now();
  const adaptive = isRecord(policy.adaptive) ? /** @type {Readonly<Record<string,unknown>>} */ (policy.adaptive) : {};
  const weight = metrics ? evidenceWeight(metrics, adaptive, nowMs, activeVersion) : 0;
  const taskWeights = isRecord(policy.taskWeights) ? /** @type {Readonly<Record<string,Readonly<Record<string,number>>>>} */ (policy.taskWeights) : {};
  const effectiveWeights = taskWeights[task] ?? taskWeights['*'] ?? policy;
  const performance = metrics ? weightedPerformanceScore(metrics, effectiveWeights, weight) : 0;

  const taskPreferences = isRecord(policy.taskPreferences) ? /** @type {Readonly<Record<string,Readonly<Record<string,string|null>>>>} */ (policy.taskPreferences) : {};
  const preferencePolicy = taskPreferences[task] ?? taskPreferences['*'] ?? null;
  let preference = 0;
  if (preferencePolicy?.preferredProvider === model.provider) preference += 1000;
  if (preferencePolicy?.preferredModel === model.modelId || preferencePolicy?.preferredModel === key) preference += 2000;

  const selectedTraffic = trafficPreference(policy, task, context.cohortKey ?? null);
  const traffic = selectedTraffic === key || selectedTraffic === model.modelId || selectedTraffic === model.provider ? 500 : 0;

  let exploration = 0;
  if (explorationEnabledForRequest(adaptive, task, context.cohortKey ?? null) && metrics && Number(metrics.sampleCount ?? 0) < Number(adaptive.minSamples ?? 20)) exploration = 25;

  const orders = isRecord(policy.slaFallbackOrder) ? /** @type {Readonly<Record<string,readonly string[]>>} */ (policy.slaFallbackOrder) : {};
  const order = orders[task] ?? orders['*'] ?? [];
  const index = order.findIndex((candidate) => candidate === key || candidate === model.modelId || candidate === model.provider);
  const sla = index < 0 ? 0 : Math.max(0, 100 - index * 10);

  return Object.freeze({ total: performance + preference + traffic + exploration + sla, performance, preference, traffic, included_candidates, sla, evidenceWeight: weight });
}

/** @param {Readonly<Record<string, unknown>> model @param {Readonly<Record<string, unknown>>|null|undefined} policy */
function routingPolicyScore(model, policy) { return routingPolicyScoreDetailed(model, policy).total; }

module.exports = {
  CIRCUIT_STATES,
  deterministicCohortBucket,
  evidenceWeight,
  evaluateCircuitBreaker,
  explorationEnabledForRequest,
  normalizeAdaptiveConfig,
  normalizeCircuitBreakerConfig,
  normalizeHealthSignals,
  applyRoutingPolicy,
  createRoutingPolicy,
  modelAllowed,
  modelEligibility,
  reasoningPolicyFor,
  trafficPreference,
  routingPolicyScore,
  routingPolicyScoreDetailed,
};
