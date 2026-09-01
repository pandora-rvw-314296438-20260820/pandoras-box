'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

const CORPUS_VERSION = 'pandora-kimi-corpus-v1';
const HARNESS_VERSION = 'pandora-kimi-evaluation-v1';
const SCORING_VERSION = 'pandora-kimi-scoring-v1';
const PROMOTION_GATE_VERSION = 'pandora-kimi-promotion-v1';
const RESULT_STATUSES = Object.freeze(['PASS', 'FAIL', 'HOLD']);
const FAILURE_CLASSES = Object.freeze([
  'provider_network', 'timeout', 'rate_limit', 'malformed_output', 'incorrect_answer',
  'tool_error', 'deterministic_validation', 'verifier_rejection', 'policy_rejection',
  'infrastructure', 'authentication', 'authorization',
]);

/** @param {unknown} value @returns {value is Record<string, any>} */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field @returns {string} */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}
/** @param {unknown} value @param {string} field @param {number | null} [fallback] @returns {number | null} */
function finiteNonNegative(value, field, fallback = null) {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError(`${field} must be non-negative`);
  return value;
}
/** @param {unknown} value @returns {number} */
function clamp01(value) { return Math.max(0, Math.min(1, Number(value))); }

/** @param {Record<string, any>} input */
function createBenchmarkCase(input) {
  if (!isRecord(input)) throw new TypeError('benchmark case must be an object');
  assertNoCredentialMaterial(input);
  const taskClass = requiredText(input.taskClass, 'taskClass');
  const validators = Array.isArray(input.deterministicValidators) ? input.deterministicValidators.map(String) : [];
  const riskClass = requiredText(input.riskClass ?? 'low', 'riskClass');
  const allowedTools = Array.isArray(input.allowedTools) ? input.allowedTools.map(String) : [];
  const providerSpecific = input.providerSpecific === true;
  if (!providerSpecific && (input.provider === 'gemini' || input.provider === 'kimi')) {
    throw new Error('provider-neutral benchmark case cannot select a provider');
  }
  return Object.freeze({
    caseId: requiredText(input.caseId, 'caseId'),
    version: requiredText(input.version ?? CORPUS_VERSION, 'version'),
    taskClass,
    input: input.input ?? null,
    context: Object.freeze(isRecord(input.context) ? input.context : {}),
    expectedContract: Object.freeze(isRecord(input.expectedContract) ? input.expectedContract : {}),
    allowedTools: Object.freeze(allowedTools),
    structuredOutputSchema: input.structuredOutputSchema ?? null,
    latencyBudgetMs: finiteNonNegative(input.latencyBudgetMs, 'latencyBudgetMs'),
    costBudgetUsd: finiteNonNegative(input.costBudgetUsd, 'costBudgetUsd'),
    riskClass,
    deterministicValidators: Object.freeze(validators),
    expectedInvariants: Object.freeze(Array.isArray(input.expectedInvariants) ? input.expectedInvariants.map(String) : []),
    reviewerRubric: Object.freeze(isRecord(input.reviewerRubric) ? input.reviewerRubric : {}),
    provenance: requiredText(input.provenance ?? 'synthetic-sanitized', 'provenance'),
    capabilityRequirements: Object.freeze(Array.isArray(input.capabilityRequirements) ? input.capabilityRequirements.map(String) : []),
    providerSpecific,
  });
}

/** @param {Array<Record<string, any>>} cases @param {{knownValidators?: string[], version?: string}} [options] */
function validateCorpus(cases, options = {}) {
  if (!Array.isArray(cases) || cases.length === 0) throw new Error('benchmark corpus must contain cases');
  const knownValidators = new Set(options.knownValidators ?? []);
  const requireKnownValidators = knownValidators.size > 0;
  const ids = new Set();
  const normalized = cases.map((item) => createBenchmarkCase(item));
  for (const item of normalized) {
    if (ids.has(item.caseId)) throw new Error(`duplicate benchmark case id: ${item.caseId}`);
    ids.add(item.caseId);
    if (item.version !== (options.version ?? CORPUS_VERSION)) throw new Error(`benchmark case ${item.caseId} has unexpected version ${item.version}`);
    if (requireKnownValidators) {
      for (const validator of item.deterministicValidators) {
        if (!knownValidators.has(validator)) throw new Error(`benchmark case ${item.caseId} references unknown validator ${validator}`);
      }
    }
  }
  return Object.freeze(normalized);
}

/** @param {Record<string, any>} [input] */
function scoreQuality(input = {}) {
  const deterministic = isRecord(input.deterministic) ? input.deterministic : {};
  const review = isRecord(input.review) ? input.review : {};
  const hardFailures = Array.isArray(input.hardFailures) ? input.hardFailures.map(String) : [];
  const deterministicChecks = Object.values(deterministic).map(Number).filter(Number.isFinite).map(clamp01);
  const reviewChecks = Object.values(review).map(Number).filter(Number.isFinite).map(clamp01);
  const deterministicScore = deterministicChecks.length ? deterministicChecks.reduce((a, b) => a + b, 0) / deterministicChecks.length : null;
  const reviewScore = reviewChecks.length ? reviewChecks.reduce((a, b) => a + b, 0) / reviewChecks.length : null;
  const hardFailure = hardFailures.length > 0;
  const components = Object.freeze({ deterministic: deterministicScore, review: reviewScore, hardFailures: Object.freeze(hardFailures) });
  if (hardFailure) return Object.freeze({ version: SCORING_VERSION, score: 0, hardFailure: true, components });
  const present = [deterministicScore, reviewScore].filter((value) => value != null);
  const score = present.length ? present.reduce((a, b) => a + b, 0) / present.length : null;
  return Object.freeze({ version: SCORING_VERSION, score, hardFailure: false, components });
}

/** @param {Record<string, any>} [input] */
function scoreReliability(input = {}) {
  const attempts = Math.max(1, Number(input.attempts ?? 1));
  const validOutput = input.validOutput !== false;
  const apiCompleted = input.apiCompleted !== false;
  const toolValid = input.toolValid !== false;
  const verifierPassed = input.verifierPassed !== false;
  const retryPenalty = Math.min(0.4, Math.max(0, attempts - 1) * 0.1);
  const components = Object.freeze({ apiCompleted, validOutput, toolValid, verifierPassed, attempts });
  const base = [apiCompleted, validOutput, toolValid, verifierPassed].filter(Boolean).length / 4;
  return Object.freeze({ version: SCORING_VERSION, score: clamp01(base - retryPenalty), components });
}

/** @param {Record<string, any>} [input] */
function scoreLatency(input = {}) {
  const totalMs = finiteNonNegative(input.totalMs, 'totalMs', 0);
  const budgetMs = finiteNonNegative(input.budgetMs, 'budgetMs', null);
  const ttftMs = finiteNonNegative(input.ttftMs, 'ttftMs', null);
  const firstUsableMs = finiteNonNegative(input.firstUsableMs, 'firstUsableMs', null);
  const score = budgetMs && budgetMs > 0 ? clamp01(1 - Math.max(0, totalMs - budgetMs) / budgetMs) : null;
  return Object.freeze({ version: SCORING_VERSION, score, components: Object.freeze({ ttftMs, firstUsableMs, totalMs, budgetMs }) });
}

/** @param {Record<string, any>} [input] */
async function scoreCost(input = {}) {
  if (typeof input.estimator !== 'function') throw new TypeError('Chat D cost estimator interface is required');
  const estimate = await input.estimator(Object.freeze({
    provider: input.provider,
    model: input.model,
    revision: input.revision ?? null,
    inputTokens: Number(input.inputTokens ?? 0),
    cachedInputTokens: Number(input.cachedInputTokens ?? 0),
    outputTokens: Number(input.outputTokens ?? 0),
    at: input.at ?? new Date().toISOString(),
  }));
  const estimatedCostUsd = estimate && Number.isFinite(Number(estimate.estimatedCostUsd)) ? Number(estimate.estimatedCostUsd) : null;
  const budgetUsd = finiteNonNegative(input.budgetUsd, 'budgetUsd', null);
  const score = estimatedCostUsd == null || !budgetUsd ? null : clamp01(1 - Math.max(0, estimatedCostUsd - budgetUsd) / budgetUsd);
  return Object.freeze({
    version: SCORING_VERSION,
    score,
    components: Object.freeze({ estimatedCostUsd, billedCostUsd: estimate?.billedCostUsd ?? null, pricingVersion: estimate?.pricingVersion ?? null, status: estimate?.status ?? 'unavailable', budgetUsd }),
  });
}

/** @param {unknown} sampleCount */
function sampleConfidence(sampleCount) {
  const count = Math.max(0, Number(sampleCount ?? 0));
  if (count < 5) return 'insufficient';
  if (count < 30) return 'low';
  if (count < 100) return 'moderate';
  return 'high';
}

class ShadowEvaluationRunner {
  /** @param {{executeCandidate: (request: Record<string, any>) => Promise<Record<string, any>>, limits?: Record<string, any>, enabled?: boolean}} input */
  constructor({ executeCandidate, limits = {}, enabled = false }) {
    if (typeof executeCandidate !== 'function') throw new TypeError('executeCandidate is required');
    this.executeCandidate = executeCandidate;
    this.enabled = enabled === true;
    this.limits = Object.freeze({
      maxCases: Math.max(1, Number(limits.maxCases ?? 20)),
      maxProviderCalls: Math.max(1, Number(limits.maxProviderCalls ?? 20)),
      maxTokens: Math.max(1, Number(limits.maxTokens ?? 200000)),
      maxEstimatedCostUsd: finiteNonNegative(limits.maxEstimatedCostUsd, 'maxEstimatedCostUsd', 5),
    });
  }

  /** @param {Array<Record<string, any>>} cases @param {{dryRun?: boolean, corpusVersion?: string, knownValidators?: string[]}} [options] */
  async run(cases, options = {}) {
    if (!this.enabled && options.dryRun !== true) return Object.freeze({ status: 'HOLD', reason: 'shadow_disabled', results: Object.freeze([]), usage: Object.freeze({ calls: 0, tokens: 0, estimatedCostUsd: 0 }) });
    const corpus = validateCorpus(cases, { version: options.corpusVersion ?? CORPUS_VERSION, knownValidators: options.knownValidators ?? [] });
    const selected = corpus.slice(0, this.limits.maxCases);
    const results = [];
    let calls = 0, tokens = 0, estimatedCostUsd = 0;
    for (const benchmarkCase of selected) {
      if (calls >= this.limits.maxProviderCalls || tokens >= this.limits.maxTokens || estimatedCostUsd >= this.limits.maxEstimatedCostUsd) break;
      const request = Object.freeze({
        benchmarkCase,
        shadow: true,
        toolPolicy: Object.freeze({ mode: 'disabled', allowedTools: Object.freeze([]), sideEffectsAllowed: false }),
        metadata: Object.freeze({ evaluationOnly: true, exposeToUser: false }),
      });
      if (options.dryRun === true) {
        results.push(Object.freeze({ caseId: benchmarkCase.caseId, status: 'HOLD', reason: 'dry_run' }));
        continue;
      }
      calls += 1;
      const raw = await this.executeCandidate(request);
      assertNoCredentialMaterial(raw);
      const usage = isRecord(raw?.usage) ? raw.usage : {};
      const resultTokens = Number(usage.totalTokens ?? (Number(usage.inputTokens ?? 0) + Number(usage.outputTokens ?? 0))) || 0;
      const resultCost = Number(usage.estimatedCostUsd ?? 0) || 0;
      tokens += resultTokens;
      estimatedCostUsd += resultCost;
      results.push(Object.freeze({ caseId: benchmarkCase.caseId, status: 'PASS', provider: raw?.provider ?? null, model: raw?.model ?? null, output: raw?.output ?? null, usage: Object.freeze({ totalTokens: resultTokens, estimatedCostUsd: resultCost }) }));
    }
    const budgetExhausted = calls >= this.limits.maxProviderCalls || tokens >= this.limits.maxTokens || estimatedCostUsd >= this.limits.maxEstimatedCostUsd;
    return Object.freeze({ status: budgetExhausted ? 'HOLD' : 'PASS', reason: budgetExhausted ? 'budget_exhausted' : null, results: Object.freeze(results), usage: Object.freeze({ calls, tokens, estimatedCostUsd }) });
  }
}

/** @param {Array<Record<string, any>>} results @param {Record<string, any>} [metadata] */
function buildComparisonMatrix(results, metadata = {}) {
  if (!Array.isArray(results)) throw new TypeError('results must be an array');
  const groups = new Map();
  for (const result of results) {
    if (!isRecord(result) || result.measured !== true) continue;
    const taskClass = requiredText(result.taskClass, 'taskClass');
    const provider = requiredText(result.provider, 'provider');
    const key = `${taskClass}:${provider}`;
    const bucket = groups.get(key) ?? { taskClass, provider, quality: [], reliability: [], latency: [], cost: [], verifierPass: [], modelVersions: new Set() };
    if (Number.isFinite(result.quality)) bucket.quality.push(Number(result.quality));
    if (Number.isFinite(result.reliability)) bucket.reliability.push(Number(result.reliability));
    if (Number.isFinite(result.latencyMs)) bucket.latency.push(Number(result.latencyMs));
    if (Number.isFinite(result.estimatedCostUsd)) bucket.cost.push(Number(result.estimatedCostUsd));
    if (typeof result.verifierPassed === 'boolean') bucket.verifierPass.push(result.verifierPassed ? 1 : 0);
    if (result.modelVersion) bucket.modelVersions.add(String(result.modelVersion));
    groups.set(key, bucket);
  }
  const rows = [...groups.values()].map((bucket) => Object.freeze({
    taskClass: bucket.taskClass,
    provider: bucket.provider,
    sampleCount: Math.max(bucket.quality.length, bucket.reliability.length, bucket.latency.length, bucket.cost.length),
    confidence: sampleConfidence(Math.max(bucket.quality.length, bucket.reliability.length, bucket.latency.length, bucket.cost.length)),
    quality: average(bucket.quality), reliability: average(bucket.reliability), latencyMs: average(bucket.latency), estimatedCostUsd: average(bucket.cost), verifierPassRate: average(bucket.verifierPass),
    modelVersions: Object.freeze([...bucket.modelVersions]),
  }));
  return Object.freeze({ corpusVersion: metadata.corpusVersion ?? CORPUS_VERSION, harnessVersion: HARNESS_VERSION, scoringVersion: SCORING_VERSION, sourceSha: metadata.sourceSha ?? null, generatedAt: metadata.generatedAt ?? new Date().toISOString(), rows: Object.freeze(rows) });
}

/** @param {Record<string, any>} metrics @param {Record<string, any>} thresholds */
function evaluatePromotionGate(metrics, thresholds) {
  if (!isRecord(metrics) || !isRecord(thresholds)) throw new TypeError('metrics and thresholds are required');
  const reasons = [];
  let status = 'PASS';
  const securityRegressions = Number(metrics.securityRegressions ?? 0);
  if (securityRegressions > 0) return Object.freeze({ version: PROMOTION_GATE_VERSION, status: 'FAIL', reasons: Object.freeze(['security_regression']) });
  const checks = [
    ['sampleCount', 'minSampleCount', 'below_minimum_sample'],
    ['quality', 'minQuality', 'quality_below_floor'],
    ['reliability', 'minReliability', 'reliability_below_floor'],
    ['structuredOutputValidity', 'minStructuredOutputValidity', 'structured_output_below_floor'],
    ['verifierPassRate', 'minVerifierPassRate', 'verifier_pass_below_floor'],
  ];
  for (const [metricKey, thresholdKey, reason] of checks) {
    if (thresholds[thresholdKey] == null) continue;
    if (!Number.isFinite(Number(metrics[metricKey])) || Number(metrics[metricKey]) < Number(thresholds[thresholdKey])) {
      reasons.push(reason);
      if (metricKey === 'sampleCount') status = 'HOLD'; else if (status !== 'HOLD') status = 'FAIL';
    }
  }
  const ceilings = [
    ['latencyMs', 'maxLatencyMs', 'latency_above_ceiling'],
    ['estimatedCostUsd', 'maxEstimatedCostUsd', 'cost_above_ceiling'],
    ['fallbackRate', 'maxFallbackRate', 'fallback_above_ceiling'],
  ];
  for (const [metricKey, thresholdKey, reason] of ceilings) {
    if (thresholds[thresholdKey] == null) continue;
    if (!Number.isFinite(Number(metrics[metricKey]))) { reasons.push(`${metricKey}_unmeasured`); status = 'HOLD'; }
    else if (Number(metrics[metricKey]) > Number(thresholds[thresholdKey])) { reasons.push(reason); if (status !== 'HOLD') status = 'FAIL'; }
  }
  if (!reasons.length) status = 'PASS';
  if (!RESULT_STATUSES.includes(status)) throw new Error('invalid promotion gate status');
  return Object.freeze({ version: PROMOTION_GATE_VERSION, status, reasons: Object.freeze(reasons) });
}

/** @param {number[]} values */
function average(values) { return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null; }

module.exports = {
  CORPUS_VERSION, HARNESS_VERSION, SCORING_VERSION, PROMOTION_GATE_VERSION, FAILURE_CLASSES,
  createBenchmarkCase, validateCorpus, scoreQuality, scoreReliability, scoreLatency, scoreCost,
  sampleConfidence, ShadowEvaluationRunner, buildComparisonMatrix, evaluatePromotionGate,
};
