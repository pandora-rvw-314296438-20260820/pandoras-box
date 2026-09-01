'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');
const { modelEligibility, reasoningPolicyFor, routingPolicyScoreDetailed } = require('./policy.js');
const { createRecoveryRoutingState, createSessionRoutingState, sessionCompatibility } = require('./session.js');

/** @type {Readonly<Record<string, number>>} */
const RELIABILITY_RANK = Object.freeze({ high: 3, standard: 2, experimental: 1 });
/** @type {Readonly<Record<string, number>>} */
const COST_RANK = Object.freeze({ low: 1, medium: 2, high: 3 });
const FALLBACK_CODES = Object.freeze(new Set(['provider_unavailable', 'timeout', 'rate_limited']));

/** @typedef {{provider:string,model:string,code?:string|null,retryable?:boolean,recoveryEpoch?:number}} AttemptRecord */
/** @typedef {{preferredProvider?:string, preferredModel?:string, minContext?:number, policy?:Readonly<Record<string, unknown>>, session?:Readonly<Record<string,unknown>>|null, allowRecoveryBoundary?:boolean, attemptHistory?:readonly AttemptRecord[], cohortKey?:string|null, nowMs?:number, allowCircuitProbe?:boolean, maxProviderAttempts?:number, costEstimator?:(model:Readonly<Record<string,unknown>>,request:Readonly<Record<string,unknown>>)=>number|null}} RouterOptions */

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field */
function requiredText(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }
/** @param {Readonly<Record<string,unknown>>} model */
function modelKey(model) { return `${String(model.provider)}:${String(model.modelId)}`; }
/** @param {Readonly<Record<string,unknown>>} model */
function modelVersion(model) {
  if (typeof model.modelVersion === 'string' && model.modelVersion.trim()) return model.modelVersion.trim();
  if (isRecord(model.metadata)) {
    const metadata = /** @type {Readonly<Record<string,unknown>>} */ (model.metadata);
    if (typeof metadata.modelVersion === 'string' && metadata.modelVersion.trim()) return metadata.modelVersion.trim();
  }
  return null;
}
/** @param {unknown} value */
function positiveIntegerOrNull(value) { return Number.isInteger(value) && Number(value) > 0 ? Number(value) : null; }

/** @param {unknown} error */
function fallbackEligible(error) {
  if (!isRecord(error)) return false;
  const failure = /** @type {Readonly<Record<string,unknown>>} */ (error);
  return failure.retryable === true && typeof failure.code === 'string' && FALLBACK_CODES.has(failure.code);
}

class ModelRouter {
  /** @param {{registry:{findCompatible:(requirements:{required?:string[],outputMode?:string,minContext?:number})=>Readonly<Record<string,unknown>>[],list?:()=>Readonly<Record<string,unknown>>[]}, adapters?:Record<string,{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}>}} options */
  constructor({ registry, adapters = {} }) {
    if (!registry || typeof registry.findCompatible !== 'function') throw new TypeError('model capability registry is required');
    this.registry = registry;
    /** @type {Map<string,{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}>} */
    this.adapters = new Map();
    for (const [provider, adapter] of Object.entries(adapters)) this.registerAdapter(provider, adapter);
  }

  /** @param {string} provider @param {{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}} adapter */
  registerAdapter(provider, adapter) {
    const name = requiredText(provider, 'provider');
    if (!adapter || typeof adapter.execute !== 'function') throw new TypeError('provider adapter.execute is required');
    this.adapters.set(name, adapter);
    return this;
  }

  /** @param {Record<string,unknown>} request @param {RouterOptions} options */
  candidatesDetailed(request, options = {}) {
    assertNoCredentialMaterial(request);
    if (options.policy) assertNoCredentialMaterial(options.policy);
    if (options.session) assertNoCredentialMaterial(options.session);
    const required = Array.isArray(request.requiredCapabilities) ? request.requiredCapabilities.map(String) : [];
    const compatible = this.registry.findCompatible({ required, outputMode: String(request.outputMode ?? 'structured'), minContext: options.minContext });
    const compatibleKeys = new Set(compatible.map(modelKey));
    /** @type {{provider:string,model:string,reasons:readonly string[]}[]} */
    const excluded = [];
    if (typeof this.registry.list === 'function') {
      for (const model of this.registry.list()) {
        if (!compatibleKeys.has(modelKey(model))) excluded.push(Object.freeze({ provider: String(model.provider), model: String(model.modelId), reasons: Object.freeze(['capability_incompatible']) }));
      }
    }
    const priorAttempts = Array.isArray(options.attemptHistory) ? options.attemptHistory : [];
    const attempted = new Set(priorAttempts.map((item) => `${item.provider}:${item.model}`));
    const task = String(request.task ?? '*');
    const budget = isRecord(request.budget) ? /** @type {Readonly<Record<string,unknown>>} */ (request.budget) : {};
    const requestMaxCostUsd = typeof budget.maxCostUsd === 'number' ? budget.maxCostUsd : null;
    /** @type {{model:Readonly<Record<string,unknown>>,score:number,scoreComponents:Readonly<Record<string,number>>,recoveryRequired:boolean,reasoningPolicy:string|null,eligibility:Readonly<Record<string,unknown>>}[]} */
    const eligible = [];

    for (const model of compatible) {
      const provider = String(model.provider);
      const key = modelKey(model);
      /** @type {string[]} */
      const reasons = [];
      if (!this.adapters.has(provider)) reasons.push('adapter_unavailable');
      if (attempted.has(key)) reasons.push('already_attempted');
      let estimatedCostUsd = null;
      if (typeof options.costEstimator === 'function') {
        const estimate = options.costEstimator(model, request);
        if (estimate != null && (typeof estimate !== 'number' || !Number.isFinite(estimate) || estimate < 0)) throw new TypeError('costEstimator must return a non-negative finite number or null');
        estimatedCostUsd = estimate;
      }
      const policyEligibility = options.policy
        ? modelEligibility(model, options.policy, { task, estimatedCostUsd, requestMaxCostUsd, allowCircuitProbe: options.allowCircuitProbe, nowMs: options.nowMs })
        : Object.freeze({ allowed: true, reasons: Object.freeze([]), metrics: null, estimatedCostUsd, costCeiling: requestMaxCostUsd, circuitState: 'closed' });
      reasons.push(.../** @type {readonly string[]} */ (policyEligibility.reasons ?? []));
      const sessionResult = sessionCompatibility(model, options.session);
      let recoveryRequired = false;
      if (!sessionResult.compatible) {
        recoveryRequired = true;
        if (options.allowRecoveryBoundary !== true) reasons.push(String(sessionResult.reason ?? 'session_incompatible'));
      }
      if (reasons.length) {
        excluded.push(Object.freeze({ provider, model: String(model.modelId), reasons: Object.freeze([...new Set(reasons)]) }));
        continue;
      }
      const policyScore = routingPolicyScoreDetailed(model, options.policy, { task, nowMs: options.nowMs, cohortKey: options.cohortKey ?? null });
      const base = score(model, options);
      const total = base + policyScore.total;
      const reasoningPolicy = options.policy ? reasoningPolicyFor(options.policy, model, task) : null;
      eligible.push({
        model,
        score: total,
        scoreComponents: Object.freeze({ base, policy: policyScore.total, performance: policyScore.performance, preference: policyScore.preference, traffic: policyScore.traffic, exploration: policyScore.exploration, sla: policyScore.sla, evidenceWeight: policyScore.evidenceWeight }),
        recoveryRequired,
        reasoningPolicy,
        eligibility: policyEligibility,
      });
    }
    eligible.sort((a, b) => Number(a.recoveryRequired) - Number(b.recoveryRequired) || b.score - a.score || modelKey(a.model).localeCompare(modelKey(b.model)));
    return Object.freeze({ candidates: Object.freeze(eligible), excluded: Object.freeze(excluded), compatibleCount: compatible.length });
  }

  /** @param {Record<string,unknown>} request @param {RouterOptions} options */
  candidates(request, options = {}) { return this.candidatesDetailed(request, options).candidates.map(item => item.model); }

  /** @param {Record<string,unknown>} request @param {RouterOptions} options */
  async execute(request, options = {}) {
    assertNoCredentialMaterial(request);
    const detailed = this.candidatesDetailed(request, options);
    if (!detailed.candidates.length) {
      const error = Object.assign(new Error('no compatible model provider is available'), { code: 'unsupported_capability', retryable: false, routingDecision: Object.freeze({ policyVersion: options.policy?.policyVersion ?? null, excludedCandidates: detailed.excluded }) });
      throw error;
    }
    const budget = isRecord(request.budget) ? /** @type {Readonly<Record<string,unknown>>} */ (request.budget) : {};
    const budgetMax = positiveIntegerOrNull(budget.maxAttempts) ?? detailed.candidates.length;
    const remaining = Number.isInteger(budget.remainingAttempts) && Number(budget.remainingAttempts) >= 0 ? Number(budget.remainingAttempts) : budgetMax;
    const optionMax = positiveIntegerOrNull(options.maxProviderAttempts) ?? budgetMax;
    const maxNewAttempts = Math.min(budgetMax, remaining, optionMax);
    if (maxNewAttempts <= 0) throw Object.assign(new Error('model routing attempt budget exhausted'), { code: 'budget_exhausted', retryable: false });

    /** @type {AttemptRecord[]} */
    const attempts = Array.isArray(options.attemptHistory) ? options.attemptHistory.map(item => ({ ...item })) : [];
    let newAttempts = 0;
    /** @type {unknown} */
    let lastFailure = null;
    for (const candidate of detailed.candidates) {
      if (newAttempts >= maxNewAttempts) break;
      const declaration = candidate.model;
      const provider = String(declaration.provider);
      const model = String(declaration.modelId);
      const adapter = this.adapters.get(provider);
      if (!adapter) continue;
      newAttempts += 1;
      try {
        const result = await adapter.execute(request, /** @type {Record<string,unknown>} */ (declaration));
        assertNoCredentialMaterial(result);
        if (!isRecord(result)) throw Object.assign(new Error('provider adapter returned an invalid normalized result'), { code: 'provider_error', retryable: false });
        const normalized = /** @type {Record<string, unknown>} */ (result);
        attempts.push({ provider, model, code: null, retryable: false, recoveryEpoch: candidate.recoveryRequired ? Number(options.session?.recoveryEpoch ?? 0) + 1 : Number(options.session?.recoveryEpoch ?? 0) });
        const policyVersion = typeof options.policy?.policyVersion === 'string' ? options.policy.policyVersion : null;
        let nextSessionState = options.session ?? null;
        if (!options.session || options.session.stickinessMode === 'unassigned') {
          nextSessionState = createSessionRoutingState({ provider, model, modelVersion: modelVersion(declaration), routingPolicyVersion: policyVersion, reasoningPolicy: candidate.reasoningPolicy, stickinessMode: 'sticky', recoveryEpoch: Number(options.session?.recoveryEpoch ?? 0) });
        } else if (candidate.recoveryRequired) {
          nextSessionState = createRecoveryRoutingState(options.session, Object.freeze({ ...declaration, modelVersion: modelVersion(declaration) }), policyVersion, candidate.reasoningPolicy);
        }
        const audit = Object.freeze({
          routingPolicyVersion: policyVersion,
          selectedProvider: provider,
          selectedModel: model,
          selectedReasoningPolicy: candidate.reasoningPolicy,
          recoveryRequired: candidate.recoveryRequired,
          recoveryEpoch: Number(nextSessionState?.recoveryEpoch ?? 0),
          stickinessMode: nextSessionState?.stickinessMode ?? null,
          fallbackUsed: newAttempts > 1 || (options.attemptHistory?.length ?? 0) > 0,
          attempts: Object.freeze(attempts.map(item => Object.freeze({ ...item }))),
          eligibleCandidates: Object.freeze(detailed.candidates.map(item => Object.freeze({ provider: String(item.model.provider), model: String(item.model.modelId), recoveryRequired: item.recoveryRequired, score: item.score, scoreComponents: item.scoreComponents }))),
          excludedCandidates: detailed.excluded,
          cohortApplied: typeof options.cohortKey === 'string' && options.cohortKey.length > 0,
        });
        assertNoCredentialMaterial(audit);
        return Object.freeze({ ...normalized, routedProvider: provider, routedModel: model, fallbackUsed: audit.fallbackUsed, attempts: newAttempts, routingDecision: audit, nextSessionState });
      } catch (error) {
        lastFailure = error;
        const failure = /** @type {Readonly<Record<string,unknown>>} */ (isRecord(error) ? error : {});
        const code = typeof failure.code === 'string' ? failure.code : 'provider_error';
        attempts.push({ provider, model, code, retryable: failure.retryable === true, recoveryEpoch: Number(options.session?.recoveryEpoch ?? 0) });
        if (!fallbackEligible(error)) throw error;
        if (options.session && candidate.recoveryRequired === false && options.allowRecoveryBoundary !== true) throw error;
      }
    }
    if (lastFailure) throw lastFailure;
    throw Object.assign(new Error('model routing attempt budget exhausted'), { code: 'budget_exhausted', retryable: false });
  }
}

/** @param {Readonly<Record<string,unknown>>} model @param {RouterOptions} options */
function score(model, options) {
  let value = 0;
  if (options.preferredProvider && model.provider === options.preferredProvider) value += 1000;
  if (options.preferredModel && (model.modelId === options.preferredModel || `${String(model.provider)}:${String(model.modelId)}` === options.preferredModel)) value += 2000;
  value += (RELIABILITY_RANK[String(model.reliabilityClass)] ?? 0) * 100;
  value -= (COST_RANK[String(model.costClass)] ?? 9) * 10;
  if (model.latencyClass === 'interactive') value += 5;
  return value;
}

module.exports = { FALLBACK_CODES, ModelRouter, createRecoveryRoutingState, createSessionRoutingState, fallbackEligible, score, sessionCompatibility };
