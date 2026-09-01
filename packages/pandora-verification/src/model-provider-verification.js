'use strict';

const { assertNoCredentialMaterial } = require('../../pandora-intelligence/src/security/secret-boundary.js');

const POLICY_VERSION = 'pandora-cross-provider-verification-v1';
const BUDGET_VERSION = 'pandora-verifier-budget-v1';
const HIGH_RISK_TASKS = Object.freeze([
  'production_code_change','database_migration','security_configuration','provider_security_boundary',
  'financial_action','publish_go_live','destructive_action','permission_change','legal_compliance_output',
  'irreversible_automation','infrastructure_change',
]);
const VERIFICATION_LEVELS = Object.freeze({
  0: 'deterministic_only', 1: 'same_provider_secondary', 2: 'different_model',
  3: 'different_provider', 4: 'different_provider_plus_deterministic_and_human_approval',
});
const DECISIONS = Object.freeze(['PASS','FAIL','REPAIR','HOLD']);

function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}
function finite(value, fallback = 0) { return Number.isFinite(Number(value)) ? Number(value) : fallback; }

function createVerifierIdentity(input) {
  if (!isRecord(input)) throw new TypeError('verifier identity must be an object');
  return Object.freeze({ provider: requiredText(input.provider, 'provider'), model: requiredText(input.model, 'model'), revision: input.revision ? String(input.revision) : null });
}

function requiredVerificationLevel(taskClass, riskClass = null) {
  if (riskClass === 'critical') return 4;
  if (riskClass === 'high' || HIGH_RISK_TASKS.includes(String(taskClass))) return 3;
  if (riskClass === 'medium') return 2;
  return 0;
}

function createVerificationBudget(input = {}) {
  return Object.freeze({
    version: BUDGET_VERSION,
    maxVerifierCalls: Math.max(0, Math.floor(finite(input.maxVerifierCalls, 1))),
    maxTokens: Math.max(0, Math.floor(finite(input.maxTokens, 20000))),
    maxEstimatedCostUsd: Math.max(0, finite(input.maxEstimatedCostUsd, 0.25)),
    maxLatencyMs: Math.max(0, finite(input.maxLatencyMs, 60000)),
    maxRemediationCycles: Math.max(0, Math.floor(finite(input.maxRemediationCycles, 1))),
  });
}

function selectIndependentVerifier(builder, candidates, level) {
  const builderIdentity = createVerifierIdentity(builder);
  const normalized = (candidates ?? []).map(createVerifierIdentity);
  const eligible = normalized.filter((candidate) => {
    if (level >= 3) return candidate.provider !== builderIdentity.provider;
    if (level >= 2) return candidate.provider !== builderIdentity.provider || candidate.model !== builderIdentity.model;
    return true;
  });
  return eligible[0] ?? null;
}

function summarizeDeterministicEvidence(evidence = []) {
  const normalized = (Array.isArray(evidence) ? evidence : []).map((item) => Object.freeze({
    validator: requiredText(item.validator, 'validator'),
    status: requiredText(item.status, 'status').toUpperCase(),
    evidenceRef: item.evidenceRef ? String(item.evidenceRef) : null,
    summary: item.summary ? String(item.summary) : null,
  }));
  const failed = normalized.filter((item) => item.status === 'FAIL');
  const blocked = normalized.filter((item) => item.status === 'BLOCKED' || item.status === 'INCONCLUSIVE');
  return Object.freeze({ evidence: Object.freeze(normalized), failed: Object.freeze(failed), blocked: Object.freeze(blocked) });
}

function buildVerifierInput(input) {
  const payload = Object.freeze({
    taskSpec: input.taskSpec ?? null,
    producedResult: input.producedResult ?? null,
    deterministicEvidence: input.deterministicEvidence ?? [],
    constraints: input.constraints ?? [],
    actionEvidence: input.actionEvidence ?? [],
    builder: createVerifierIdentity(input.builder),
    verifier: createVerifierIdentity(input.verifier),
    policyVersion: POLICY_VERSION,
  });
  assertNoCredentialMaterial(payload);
  return payload;
}

class IndependentProviderVerifier {
  constructor({ executeVerifier, repairBuilder = null, telemetrySink = null }) {
    if (typeof executeVerifier !== 'function') throw new TypeError('executeVerifier is required');
    if (repairBuilder != null && typeof repairBuilder !== 'function') throw new TypeError('repairBuilder must be a function');
    if (telemetrySink != null && typeof telemetrySink !== 'function') throw new TypeError('telemetrySink must be a function');
    this.executeVerifier = executeVerifier;
    this.repairBuilder = repairBuilder;
    this.telemetrySink = telemetrySink;
  }

  async verify(input) {
    if (!isRecord(input)) throw new TypeError('verification input is required');
    const builder = createVerifierIdentity(input.builder);
    const level = input.level == null ? requiredVerificationLevel(input.taskClass, input.riskClass) : Number(input.level);
    if (!VERIFICATION_LEVELS[level]) throw new TypeError('invalid verification level');
    const deterministic = summarizeDeterministicEvidence(input.deterministicEvidence);
    if (deterministic.failed.length) return this.finish(input, builder, null, 'FAIL', 'deterministic_failure', 0, 0, 0, 0);
    if (level === 0) {
      const decision = deterministic.blocked.length ? 'HOLD' : 'PASS';
      return this.finish(input, builder, null, decision, decision === 'PASS' ? 'deterministic_pass' : 'deterministic_inconclusive', 0, 0, 0, 0);
    }

    const verifier = selectIndependentVerifier(builder, input.verifierCandidates ?? [], level);
    if (!verifier) return this.finish(input, builder, null, 'HOLD', 'no_independent_verifier', 0, 0, 0, 0);
    if (level >= 3 && verifier.provider === builder.provider) throw new Error('independent provider verification requires different providers');

    const budget = createVerificationBudget(input.budget ?? {});
    let calls = 0, tokens = 0, cost = 0, latency = 0, remediationCycles = 0;
    let artifact = input.producedResult ?? null;
    while (true) {
      if (calls >= budget.maxVerifierCalls || tokens >= budget.maxTokens || cost >= budget.maxEstimatedCostUsd || latency >= budget.maxLatencyMs) {
        return this.finish(input, builder, verifier, 'HOLD', 'verification_budget_exhausted', calls, tokens, cost, latency, remediationCycles);
      }
      const verifierInput = buildVerifierInput({ ...input, producedResult: artifact, builder, verifier, deterministicEvidence: deterministic.evidence });
      const response = await this.executeVerifier(Object.freeze({ verifier, input: verifierInput, toolPolicy: Object.freeze({ mode: 'disabled', sideEffectsAllowed: false }) }));
      assertNoCredentialMaterial(response);
      calls += 1;
      tokens += finite(response?.usage?.totalTokens, finite(response?.usage?.inputTokens) + finite(response?.usage?.outputTokens));
      cost += finite(response?.usage?.estimatedCostUsd);
      latency += finite(response?.latencyMs);
      const decision = String(response?.decision ?? '').toUpperCase();
      if (!DECISIONS.includes(decision)) return this.finish(input, builder, verifier, 'HOLD', 'invalid_verifier_decision', calls, tokens, cost, latency, remediationCycles);
      if (decision === 'PASS') return this.finish(input, builder, verifier, 'PASS', 'verifier_pass', calls, tokens, cost, latency, remediationCycles);
      if (decision === 'FAIL') return this.finish(input, builder, verifier, 'FAIL', 'verifier_fail', calls, tokens, cost, latency, remediationCycles);
      if (decision === 'HOLD') return this.finish(input, builder, verifier, 'HOLD', 'verifier_hold', calls, tokens, cost, latency, remediationCycles);
      if (!this.repairBuilder || remediationCycles >= budget.maxRemediationCycles) return this.finish(input, builder, verifier, 'HOLD', 'remediation_exhausted', calls, tokens, cost, latency, remediationCycles);
      remediationCycles += 1;
      artifact = await this.repairBuilder(Object.freeze({ builder, taskSpec: input.taskSpec ?? null, producedResult: artifact, verifierFinding: response?.finding ?? null, deterministicEvidence: deterministic.evidence }));
      assertNoCredentialMaterial(artifact);
    }
  }

  async finish(input, builder, verifier, decision, reason, calls, tokens, cost, latency, remediationCycles = 0) {
    const record = Object.freeze({
      policyVersion: POLICY_VERSION, taskClass: input.taskClass ?? null, riskClass: input.riskClass ?? null,
      builder, verifier, decision, reason, verifierCalls: calls, totalTokens: tokens,
      estimatedCostUsd: cost, latencyMs: latency, remediationCycles,
      independentProvider: verifier ? verifier.provider !== builder.provider : false,
      timestamp: new Date().toISOString(),
    });
    if (this.telemetrySink) await this.telemetrySink(record);
    return record;
  }
}

module.exports = Object.freeze({
  POLICY_VERSION, BUDGET_VERSION, HIGH_RISK_TASKS, VERIFICATION_LEVELS,
  createVerifierIdentity, requiredVerificationLevel, createVerificationBudget,
  selectIndependentVerifier, summarizeDeterministicEvidence, buildVerifierInput, IndependentProviderVerifier,
});
