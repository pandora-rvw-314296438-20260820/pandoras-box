'use strict';

const DEFAULT_HALF_LIFE_MS = 24 * 60 * 60 * 1000;
const DEFAULT_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field @param {number|null} fallback */
function nonNegativeNumber(value, field, fallback = null) {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError(`${field} must be a non-negative finite number`);
  return value;
}
/** @param {unknown} value @param {string} field @param {number} fallback */
function nonNegativeInteger(value, field, fallback) {
  if (value == null) return fallback;
  if (!Number.isInteger(value) || Number(value) < 0) throw new TypeError(`${field} must be a non-negative integer`);
  return Number(value);
}
/** @param {unknown} value @param {string} field @param {number} fallback */
function fraction(value, field, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new TypeError(`${field} must be between 0 and 1`);
  return value;
}
/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => {
    if (typeof item !== 'string' || !item.trim()) throw new TypeError(`${field}[${index}] must be a non-empty string`);
    return item.trim();
  });
}

/** @param {unknown} value */
function normalizeAdaptiveConfig(value) {
  const input = isRecord(value) ? /** @type {Record<string, unknown>} */ (value) : {};
  const halfLifeMs = nonNegativeNumber(input.halfLifeMs, 'adaptive.halfLifeMs', DEFAULT_HALF_LIFE_MS);
  const windowMs = nonNegativeNumber(input.windowMs, 'adaptive.windowMs', DEFAULT_WINDOW_MS);
  if (halfLifeMs === 0) throw new TypeError('adaptive.halfLifeMs must be greater than zero');
  if (windowMs === 0) throw new TypeError('adaptive.windowMs must be greater than zero');
  return Object.freeze({
    enabled: input.enabled === true,
    windowMs,
    halfLifeMs,
    minSamples: nonNegativeInteger(input.minSamples, 'adaptive.minSamples', 20),
    versionMismatchWeight: fraction(input.versionMismatchWeight, 'adaptive.versionMismatchWeight', 0.25),
    explorationCap: fraction(input.explorationCap, 'adaptive.explorationCap', 0),
    explorationEligibleTasks: Object.freeze(stringList(input.explorationEligibleTasks, 'adaptive.explorationEligibleTasks')),
    highRiskTasks: Object.freeze(stringList(input.highRiskTasks, 'adaptive.highRiskTasks')),
  });
}


/** @param {unknown} value */
function normalizeCircuitBreakerConfig(value) {
  const input = isRecord(value) ? /** @type {Record<string, unknown>} */ (value) : {};
  const consecutiveFailureLimit = input.consecutiveFailureLimit == null ? null : nonNegativeInteger(input.consecutiveFailureLimit, 'circuitBreaker.consecutiveFailureLimit', 0);
  if (consecutiveFailureLimit === 0) throw new TypeError('circuitBreaker.consecutiveFailureLimit must be greater than zero');
  return Object.freeze({
    enabled: input.enabled === true,
    minSamples: nonNegativeInteger(input.minSamples, 'circuitBreaker.minSamples', 20),
    consecutiveFailureLimit,
    successRateFloor: input.successRateFloor == null ? null : fraction(input.successRateFloor, 'circuitBreaker.successRateFloor', 0),
    timeoutRateCeiling: input.timeoutRateCeiling == null ? null : fraction(input.timeoutRateCeiling, 'circuitBreaker.timeoutRateCeiling', 0),
    serverErrorRateCeiling: input.serverErrorRateCeiling == null ? null : fraction(input.serverErrorRateCeiling, 'circuitBreaker.serverErrorRateCeiling', 0),
    cooldownMs: nonNegativeNumber(input.cooldownMs, 'circuitBreaker.cooldownMs', 0),
  });
}

/** @param {unknown} value */
function normalizeHealthSignals(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('healthSignals must be an object');
  /** @type {Record<string, Readonly<Record<string, unknown>>>} */
  const output = {};
  for (const [key, raw] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(raw)) throw new TypeError(`healthSignals.${key} must be an object`);
    const item = /** @type {Record<string, unknown>} */ (raw);
    const state = item.state == null ? 'closed' : String(item.state);
    if (!['closed','open','half_open'].includes(state)) throw new TypeError(`healthSignals.${key}.state is invalid`);
    const openedAtMs = item.openedAt == null ? null : Date.parse(String(item.openedAt));
    if (openedAtMs != null && !Number.isFinite(openedAtMs)) throw new TypeError(`healthSignals.${key}.openedAt must be a valid timestamp`);
    output[key] = Object.freeze({
      state,
      openedAtMs,
      probeSucceeded: item.probeSucceeded === true ? true : item.probeSucceeded === false ? false : null,
      sampleCount: nonNegativeInteger(item.sampleCount, `healthSignals.${key}.sampleCount`, 0),
      consecutiveRetryableFailures: nonNegativeInteger(item.consecutiveRetryableFailures, `healthSignals.${key}.consecutiveRetryableFailures`, 0),
      successRate: item.successRate == null ? null : fraction(item.successRate, `healthSignals.${key}.successRate`, 0),
      timeoutRate: item.timeoutRate == null ? null : fraction(item.timeoutRate, `healthSignals.${key}.timeoutRate`, 0),
      serverErrorRate: item.serverErrorRate == null ? null : fraction(item.serverErrorRate, `healthSignals.${key}.serverErrorRate`, 0),
    });
  }
  return Object.freeze(output);
}

/** @param {Readonly<Record<string, unknown>>} signal @param {Readonly<Record<string, unknown>>} config @param {number} nowMs */
function evaluateCircuitBreaker(signal, config, nowMs = Date.now()) {
  const current = typeof signal.state === 'string' ? signal.state : 'closed';
  if (config.enabled !== true) return Object.freeze({ state: current, reason: 'configured_state' });
  const cooldownMs = Number(config.cooldownMs ?? 0);
  const openedAtMs = typeof signal.openedAtMs === 'number' ? signal.openedAtMs : null;
  if (current === 'open') {
    if (openedAtMs != null && nowMs >= openedAtMs + cooldownMs) return Object.freeze({ state: 'half_open', reason: 'cooldown_elapsed' });
    return Object.freeze({ state: 'open', reason: 'cooldown_active' });
  }
  if (current === 'half_open') {
    if (signal.probeSucceeded === true) return Object.freeze({ state: 'closed', reason: 'probe_succeeded' });
    if (signal.probeSucceeded === false) return Object.freeze({ state: 'open', reason: 'probe_failed' });
    return Object.freeze({ state: 'half_open', reason: 'probe_pending' });
  }
  const failureLimit = typeof config.consecutiveFailureLimit === 'number' ? config.consecutiveFailureLimit : null;
  if (failureLimit != null && Number(signal.consecutiveRetryableFailures ?? 0) >= failureLimit) return Object.freeze({ state: 'open', reason: 'consecutive_retryable_failures' });
  const sampleCount = Number(signal.sampleCount ?? 0);
  if (sampleCount >= Number(config.minSamples ?? 20)) {
    if (typeof config.successRateFloor === 'number' && typeof signal.successRate === 'number' && signal.successRate < config.successRateFloor) return Object.freeze({ state: 'open', reason: 'success_rate_floor' });
    if (typeof config.timeoutRateCeiling === 'number' && typeof signal.timeoutRate === 'number' && signal.timeoutRate > config.timeoutRateCeiling) return Object.freeze({ state: 'open', reason: 'timeout_rate_ceiling' });
    if (typeof config.serverErrorRateCeiling === 'number' && typeof signal.serverErrorRate === 'number' && signal.serverErrorRate > config.serverErrorRateCeiling) return Object.freeze({ state: 'open', reason: 'server_error_rate_ceiling' });
  }
  return Object.freeze({ state: 'closed', reason: 'healthy' });
}

/** @param {unknown} value */
function normalizePerformance(value) {
  if (value == null) return Object.freeze({});
  if (!isRecord(value)) throw new TypeError('performance must be an object');
  /** @type {Record<string, Readonly<Record<string, unknown>>>} */
  const output = {};
  for (const [key, metricValue] of Object.entries(/** @type {Record<string, unknown>} */ (value))) {
    if (!isRecord(metricValue)) throw new TypeError(`performance.${key} must be an object`);
    const metrics = /** @type {Record<string, unknown>} */ (metricValue);
    const observedAtMs = metrics.observedAt == null ? null : Date.parse(String(metrics.observedAt));
    if (observedAtMs != null && !Number.isFinite(observedAtMs)) throw new TypeError(`performance.${key}.observedAt must be a valid timestamp`);
    output[key] = Object.freeze({
      quality: fraction(metrics.quality, `performance.${key}.quality`, 0),
      successRate: fraction(metrics.successRate, `performance.${key}.successRate`, 0),
      latencyScore: fraction(metrics.latencyScore, `performance.${key}.latencyScore`, 0),
      costScore: fraction(metrics.costScore, `performance.${key}.costScore`, 0),
      sampleCount: nonNegativeInteger(metrics.sampleCount, `performance.${key}.sampleCount`, 0),
      p95LatencyMs: nonNegativeNumber(metrics.p95LatencyMs, `performance.${key}.p95LatencyMs`, null),
      estimatedCostUsd: nonNegativeNumber(metrics.estimatedCostUsd, `performance.${key}.estimatedCostUsd`, null),
      effectiveEstimatedCostUsd: nonNegativeNumber(metrics.effectiveEstimatedCostUsd, `performance.${key}.effectiveEstimatedCostUsd`, null),
      observedAtMs,
      modelVersion: typeof metrics.modelVersion === 'string' && metrics.modelVersion.trim() ? metrics.modelVersion.trim() : null,
    });
  }
  return Object.freeze(output);
}

/** @param {string} seed */
function deterministicCohortBucket(seed) {
  if (typeof seed !== 'string' || !seed.trim()) throw new TypeError('cohort seed is required');
  let hash = 0x811c9dc5;
  for (const ch of seed) {
    hash ^= ch.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash / 0x100000000;
}

/** @param {Readonly<Record<string, unknown>>} metrics @param {Readonly<Record<string, unknown>>} adaptive @param {number} nowMs @param {string|null} activeModelVersion */
function evidenceWeight(metrics, adaptive, nowMs, activeModelVersion = null) {
  if (adaptive.enabled !== true) return 1;
  const sampleCount = Number(metrics.sampleCount ?? 0);
  const minSamples = Number(adaptive.minSamples ?? 20);
  const confidence = minSamples <= 0 ? 1 : Math.min(1, sampleCount / minSamples);
  const observedAtMs = typeof metrics.observedAtMs === 'number' ? metrics.observedAtMs : null;
  if (observedAtMs == null) return 0;
  const age = Math.max(0, nowMs - observedAtMs);
  const windowMs = Number(adaptive.windowMs ?? DEFAULT_WINDOW_MS);
  if (age > windowMs) return 0;
  const halfLifeMs = Number(adaptive.halfLifeMs ?? DEFAULT_HALF_LIFE_MS);
  const recency = Math.exp(-Math.LN2 * age / halfLifeMs);
  const evidenceVersion = typeof metrics.modelVersion === 'string' ? metrics.modelVersion : null;
  const versionWeight = activeModelVersion && evidenceVersion && activeModelVersion !== evidenceVersion
    ? Number(adaptive.versionMismatchWeight ?? 0.25)
    : 1;
  return confidence * recency * versionWeight;
}

/** @param {Readonly<Record<string, unknown>>} metrics @param {Readonly<Record<string, unknown>>} weights @param {number} weight */
function weightedPerformanceScore(metrics, weights, weight = 1) {
  return (
    Number(metrics.quality ?? 0) * Number(weights.qualityWeight ?? 1) * 100
    + Number(metrics.successRate ?? 0) * Number(weights.successWeight ?? 1) * 100
    + Number(metrics.latencyScore ?? 0) * Number(weights.latencyWeight ?? 0.15) * 100
    + Number(metrics.costScore ?? 0) * Number(weights.costWeight ?? 0.15) * 100
  ) * weight;
}

/** @param {Readonly<Record<string, unknown>>} policy @param {string} task @param {string|null} cohortKey */
function trafficPreference(policy, task, cohortKey) {
  if (!cohortKey || !isRecord(policy.trafficWeights)) return null;
  const all = /** @type {Record<string, unknown>} */ (policy.trafficWeights);
  const taskWeights = isRecord(all[task]) ? /** @type {Record<string, unknown>} */ (all[task]) : isRecord(all['*']) ? /** @type {Record<string, unknown>} */ (all['*']) : null;
  if (!taskWeights) return null;
  const entries = Object.entries(taskWeights).filter(([, value]) => typeof value === 'number' && value > 0);
  let total = 0;
  for (const [, value] of entries) total += Number(value);
  if (total > 1.0000001) throw new TypeError(`trafficWeights.${task} total must not exceed 1`);
  const bucket = deterministicCohortBucket(`${cohortKey}:${task}`);
  let cursor = 0;
  for (const [candidateKey, rawWeight] of entries) {
    cursor += Number(rawWeight);
    if (bucket < cursor) return candidateKey;
  }
  return null;
}

/** @param {Readonly<Record<string, unknown>>} adaptive @param {string} task @param {string|null} cohortKey */
function explorationEnabledForRequest(adaptive, task, cohortKey) {
  if (adaptive.enabled !== true || !cohortKey) return false;
  const cap = Number(adaptive.explorationCap ?? 0);
  if (cap <= 0) return false;
  const highRisk = /** @type {readonly string[]} */ (adaptive.highRiskTasks ?? []);
  if (highRisk.includes(task)) return false;
  const allowed = /** @type {readonly string[]} */ (adaptive.explorationEligibleTasks ?? []);
  if (allowed.length && !allowed.includes(task)) return false;
  return deterministicCohortBucket(`${cohortKey}:${task}:explore`) < cap;
}

/** @param {Readonly<Record<string, unknown>>} policy @param {Readonly<Record<string, unknown>>} model @param {string} task */
function reasoningPolicyFor(policy, model, task) {
  if (!isRecord(policy.reasoningPolicies)) return null;
  const policies = /** @type {Record<string, unknown>} */ (policy.reasoningPolicies);
  const taskPolicy = isRecord(policies[task]) ? /** @type {Record<string, unknown>} */ (policies[task]) : isRecord(policies['*']) ? /** @type {Record<string, unknown>} */ (policies['*']) : null;
  if (!taskPolicy) return null;
  const key = `${String(model.provider)}:${String(model.modelId)}`;
  const value = taskPolicy[key] ?? taskPolicy[String(model.provider)] ?? taskPolicy['*'];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

module.exports = {
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
};
