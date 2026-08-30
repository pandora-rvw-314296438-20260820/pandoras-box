
'use strict';

/** @type {Readonly<Record<string, number>>} */
const COST_RANK = Object.freeze({ low: 1, medium: 2, high: 3 });
/** @type {Readonly<Record<string, number>>} */
const RELIABILITY_RANK = Object.freeze({ experimental: 1, standard: 2, high: 3 });

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

/** @param {Record<string, unknown>} input */
function createRoutingPolicy(input = {}) {
  const maxCostClass = rankedValue(input.maxCostClass, COST_RANK, 'maxCostClass');
  const minReliabilityClass = rankedValue(input.minReliabilityClass, RELIABILITY_RANK, 'minReliabilityClass');
  const maxEstimatedCostUsd = input.maxEstimatedCostUsd == null ? null : Number(input.maxEstimatedCostUsd);
  if (maxEstimatedCostUsd != null && (!Number.isFinite(maxEstimatedCostUsd) || maxEstimatedCostUsd < 0)) throw new TypeError('maxEstimatedCostUsd must be non-negative');
  return Object.freeze({
    allowedProviders: Object.freeze(stringList(input.allowedProviders, 'allowedProviders')),
    deniedProviders: Object.freeze(stringList(input.deniedProviders, 'deniedProviders')),
    allowedModels: Object.freeze(stringList(input.allowedModels, 'allowedModels')),
    deniedModels: Object.freeze(stringList(input.deniedModels, 'deniedModels')),
    maxCostClass,
    minReliabilityClass,
    maxEstimatedCostUsd,
    requireIndependentVerifier: input.requireIndependentVerifier === true,
    builderProvider: typeof input.builderProvider === 'string' && input.builderProvider.trim() ? input.builderProvider.trim() : null,
    builderModel: typeof input.builderModel === 'string' && input.builderModel.trim() ? input.builderModel.trim() : null,
    qualityWeight: finiteOrDefault(input.qualityWeight, 1),
    successWeight: finiteOrDefault(input.successWeight, 1),
    latencyWeight: finiteOrDefault(input.latencyWeight, 0.15),
    costWeight: finiteOrDefault(input.costWeight, 0.15),
    performance: normalizePerformance(input.performance),
  });
}

/** @param {unknown} value @param {number} fallback */
function finiteOrDefault(value, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError('routing weights must be non-negative finite numbers');
  return value;
}

/** @param {unknown} value */
function normalizePerformance(value) {
  if (value == null) return Object.freeze({});
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('performance must be an object');
  const input = /** @type {Record<string, unknown>} */ (value);
  /** @type {Record<string, Readonly<Record<string, number>>>} */
  const output = {};
  for (const [key, metricValue] of Object.entries(input)) {
    if (!metricValue || typeof metricValue !== 'object' || Array.isArray(metricValue)) throw new TypeError(`performance.${key} must be an object`);
    const metrics = /** @type {Record<string, unknown>} */ (metricValue);
    output[key] = Object.freeze({
      quality: boundedMetric(metrics.quality, `performance.${key}.quality`),
      successRate: boundedMetric(metrics.successRate, `performance.${key}.successRate`),
      latencyScore: boundedMetric(metrics.latencyScore, `performance.${key}.latencyScore`),
      costScore: boundedMetric(metrics.costScore, `performance.${key}.costScore`),
    });
  }
  return Object.freeze(output);
}

/** @param {unknown} value @param {string} field */
function boundedMetric(value, field) {
  if (value == null) return 0;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new TypeError(`${field} must be between 0 and 1`);
  return value;
}

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>} policy */
function modelAllowed(model, policy) {
  const provider = String(model.provider);
  const modelId = String(model.modelId);
  const allowedProviders = /** @type {readonly string[]} */ (policy.allowedProviders ?? []);
  const deniedProviders = /** @type {readonly string[]} */ (policy.deniedProviders ?? []);
  const allowedModels = /** @type {readonly string[]} */ (policy.allowedModels ?? []);
  const deniedModels = /** @type {readonly string[]} */ (policy.deniedModels ?? []);
  if (allowedProviders.length && !allowedProviders.includes(provider)) return false;
  if (deniedProviders.includes(provider)) return false;
  if (allowedModels.length && !allowedModels.includes(modelId) && !allowedModels.includes(`${provider}:${modelId}`)) return false;
  if (deniedModels.includes(modelId) || deniedModels.includes(`${provider}:${modelId}`)) return false;
  if (typeof policy.maxCostClass === 'string' && (COST_RANK[String(model.costClass)] ?? 99) > (COST_RANK[policy.maxCostClass] ?? 0)) return false;
  if (typeof policy.minReliabilityClass === 'string' && (RELIABILITY_RANK[String(model.reliabilityClass)] ?? 0) < (RELIABILITY_RANK[policy.minReliabilityClass] ?? 99)) return false;
  if (policy.requireIndependentVerifier === true) {
    if (policy.builderProvider === provider && (!policy.builderModel || policy.builderModel === modelId)) return false;
  }
  return true;
}

/** @param {Readonly<Record<string, unknown>>[]} models @param {Readonly<Record<string, unknown>>|null|undefined} policy */
function applyRoutingPolicy(models, policy) {
  if (!policy) return models.slice();
  return models.filter((model) => modelAllowed(model, policy));
}

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>|null|undefined} policy */
function routingPolicyScore(model, policy) {
  if (!policy) return 0;
  const performance = policy.performance && typeof policy.performance === 'object'
    ? /** @type {Readonly<Record<string, Readonly<Record<string, number>>>>} */ (policy.performance)
    : {};
  const metrics = performance[`${String(model.provider)}:${String(model.modelId)}`];
  if (!metrics) return 0;
  const qualityWeight = typeof policy.qualityWeight === 'number' ? policy.qualityWeight : 1;
  const successWeight = typeof policy.successWeight === 'number' ? policy.successWeight : 1;
  const latencyWeight = typeof policy.latencyWeight === 'number' ? policy.latencyWeight : 0.15;
  const costWeight = typeof policy.costWeight === 'number' ? policy.costWeight : 0.15;
  return metrics.quality * qualityWeight * 100
    + metrics.successRate * successWeight * 100
    + metrics.latencyScore * latencyWeight * 100
    + metrics.costScore * costWeight * 100;
}

module.exports = {
  applyRoutingPolicy,
  createRoutingPolicy,
  modelAllowed,
  routingPolicyScore,
};
