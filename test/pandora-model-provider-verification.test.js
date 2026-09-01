'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const verification = require('../packages/pandora-verification/src/model-provider-verification.js');

const gemini = Object.freeze({ provider: 'gemini', model: 'gemini-test' });
const kimi = Object.freeze({ provider: 'kimi', model: 'kimi-test' });
const passEvidence = Object.freeze([{ validator: 'unit_tests', status: 'PASS', evidenceRef: 'evidence:test:1' }]);

test('high-risk policy requires different-provider verification', () => {
  assert.equal(verification.requiredVerificationLevel('database_migration'), 3);
  assert.equal(verification.requiredVerificationLevel('ordinary_answer'), 0);
  assert.equal(verification.selectIndependentVerifier(gemini, [gemini, kimi], 3).provider, 'kimi');
  assert.equal(verification.selectIndependentVerifier(kimi, [kimi, gemini], 3).provider, 'gemini');
  assert.equal(verification.selectIndependentVerifier(gemini, [gemini], 3), null);
});

test('Gemini builder uses Kimi verifier with explicit identity separation', async () => {
  let seen;
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async (request) => { seen = request; return { decision: 'PASS', usage: { totalTokens: 100, estimatedCostUsd: 0.01 }, latencyMs: 50 }; } });
  const result = await engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [kimi], producedResult: { patch: 'synthetic' }, taskSpec: { acceptance: ['tests pass'] }, deterministicEvidence: passEvidence });
  assert.equal(result.decision, 'PASS');
  assert.equal(result.builder.provider, 'gemini');
  assert.equal(result.verifier.provider, 'kimi');
  assert.equal(result.independentProvider, true);
  assert.equal(seen.toolPolicy.sideEffectsAllowed, false);
  assert.equal(Object.hasOwn(seen.input, 'hiddenReasoning'), false);
});

test('Kimi builder uses Gemini verifier symmetrically', async () => {
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => ({ decision: 'PASS' }) });
  const result = await engine.verify({ taskClass: 'security_configuration', builder: kimi, verifierCandidates: [gemini], producedResult: { configuration: 'synthetic' }, deterministicEvidence: passEvidence });
  assert.equal(result.decision, 'PASS');
  assert.equal(result.builder.provider, 'kimi');
  assert.equal(result.verifier.provider, 'gemini');
});

test('same-provider verifier is rejected as independent and missing verifier holds', async () => {
  let calls = 0;
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => { calls += 1; return { decision: 'PASS' }; } });
  const result = await engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [gemini], producedResult: {}, deterministicEvidence: passEvidence });
  assert.equal(result.decision, 'HOLD');
  assert.equal(result.reason, 'no_independent_verifier');
  assert.equal(calls, 0);
});

test('deterministic failure cannot be overridden by model approval', async () => {
  let calls = 0;
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => { calls += 1; return { decision: 'PASS' }; } });
  const result = await engine.verify({ taskClass: 'database_migration', builder: gemini, verifierCandidates: [kimi], producedResult: {}, deterministicEvidence: [{ validator: 'migration_preflight', status: 'FAIL', evidenceRef: 'fixture:fail' }] });
  assert.equal(result.decision, 'FAIL');
  assert.equal(result.reason, 'deterministic_failure');
  assert.equal(calls, 0);
});

test('low-risk legacy path remains deterministic-only without a second provider', async () => {
  let calls = 0;
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => { calls += 1; return { decision: 'PASS' }; } });
  const result = await engine.verify({ taskClass: 'ordinary_answer', builder: gemini, verifierCandidates: [], producedResult: {}, deterministicEvidence: passEvidence });
  assert.equal(result.decision, 'PASS');
  assert.equal(result.reason, 'deterministic_pass');
  assert.equal(calls, 0);
});

test('repair disagreement is bounded and reverified by the independent provider', async () => {
  let verifierCalls = 0, repairs = 0;
  const engine = new verification.IndependentProviderVerifier({
    executeVerifier: async () => { verifierCalls += 1; return verifierCalls === 1 ? { decision: 'REPAIR', finding: 'synthetic defect' } : { decision: 'PASS' }; },
    repairBuilder: async () => { repairs += 1; return { patch: 'repaired synthetic artifact' }; },
  });
  const result = await engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [kimi], producedResult: { patch: 'initial' }, deterministicEvidence: passEvidence, budget: { maxVerifierCalls: 2, maxRemediationCycles: 1 } });
  assert.equal(result.decision, 'PASS');
  assert.equal(verifierCalls, 2);
  assert.equal(repairs, 1);
  assert.equal(result.remediationCycles, 1);
});

test('verification budgets hard-stop disagreement loops', async () => {
  let calls = 0;
  const engine = new verification.IndependentProviderVerifier({
    executeVerifier: async () => { calls += 1; return { decision: 'REPAIR', usage: { totalTokens: 500 }, latencyMs: 10 }; },
    repairBuilder: async () => ({ repaired: true }),
  });
  const result = await engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [kimi], producedResult: {}, deterministicEvidence: passEvidence, budget: { maxVerifierCalls: 1, maxRemediationCycles: 5, maxTokens: 10000, maxEstimatedCostUsd: 10, maxLatencyMs: 10000 } });
  assert.equal(result.decision, 'HOLD');
  assert.equal(result.reason, 'verification_budget_exhausted');
  assert.equal(calls, 1);
});

test('verifier input rejects credential-bearing artifacts and telemetry is safe/minimal', async () => {
  const records = [];
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => ({ decision: 'PASS' }), telemetrySink: async (record) => records.push(record) });
  await assert.rejects(() => engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [kimi], producedResult: { githubToken: 'fake-value' }, deterministicEvidence: passEvidence }), /credential material rejected/);
  const ok = await engine.verify({ taskClass: 'production_code_change', builder: gemini, verifierCandidates: [kimi], producedResult: { result: 'safe' }, deterministicEvidence: passEvidence });
  assert.equal(ok.decision, 'PASS');
  assert.equal(records.length, 1);
  assert.equal(Object.hasOwn(records[0], 'producedResult'), false);
  assert.equal(Object.hasOwn(records[0], 'taskSpec'), false);
});


test('critical verification requires human approval after independent verifier pass', async () => {
  const engine = new verification.IndependentProviderVerifier({ executeVerifier: async () => ({ decision: 'PASS' }) });
  const held = await engine.verify({ taskClass: 'infrastructure_change', riskClass: 'critical', builder: gemini, verifierCandidates: [kimi], producedResult: {}, deterministicEvidence: passEvidence });
  assert.equal(verification.requiredVerificationLevel('infrastructure_change', 'critical'), 4);
  assert.equal(held.decision, 'HOLD');
  assert.equal(held.reason, 'human_approval_required');
  const passed = await engine.verify({ taskClass: 'infrastructure_change', riskClass: 'critical', builder: gemini, verifierCandidates: [kimi], producedResult: {}, deterministicEvidence: passEvidence, humanApproval: true });
  assert.equal(passed.decision, 'PASS');
});
