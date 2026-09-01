'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const evaluation = require('../src/evaluation/kimi-program.js');
const corpus = require('../src/evaluation/corpus-v1.js');
const thresholds = require('../src/evaluation/promotion-thresholds-v1.js');

const { CASES, KNOWN_VALIDATORS } = corpus;

test('benchmark corpus v1 is sanitized, versioned, unique, and validator-bound', () => {
  const normalized = evaluation.validateCorpus(CASES, { version: corpus.CORPUS_VERSION, knownValidators: KNOWN_VALIDATORS });
  assert.equal(normalized.length, 15);
  assert.equal(new Set(normalized.map((item) => item.caseId)).size, 15);
  assert.equal(normalized.filter((item) => item.taskClass === 'coding').length, 4);
  assert.equal(normalized.filter((item) => item.taskClass === 'long_context').length, 3);
  assert.equal(normalized.filter((item) => item.taskClass === 'structured_output').length, 3);
  assert.equal(normalized.filter((item) => item.taskClass === 'multimodal').length, 2);
  assert.ok(normalized.every((item) => item.provenance === 'synthetic-sanitized'));
});

test('benchmark rejects duplicate ids, unknown validators, and credential-bearing fixtures', () => {
  assert.throws(() => evaluation.validateCorpus([CASES[0], CASES[0]], { knownValidators: KNOWN_VALIDATORS }), /duplicate/);
  assert.throws(() => evaluation.validateCorpus([{ ...CASES[0], caseId: 'bad-validator', deterministicValidators: ['not_registered'] }], { knownValidators: KNOWN_VALIDATORS }), /unknown validator/);
  assert.throws(() => evaluation.createBenchmarkCase({ ...CASES[0], caseId: 'bad-secret', githubToken: 'not-a-real-token' }), /credential material rejected/);
});

test('quality scoring cannot average away hard functional failures', () => {
  const result = evaluation.scoreQuality({ deterministic: { tests: 1, schema: 1 }, review: { clarity: 1 }, hardFailures: ['tests_failed'] });
  assert.equal(result.score, 0);
  assert.equal(result.hardFailure, true);
  assert.equal(result.components.deterministic, 1);
});

test('latency, reliability, confidence and Chat D cost adapter preserve components', async () => {
  assert.equal(evaluation.scoreReliability({ apiCompleted: true, validOutput: true, toolValid: true, verifierPassed: true, attempts: 1 }).score, 1);
  assert.ok(evaluation.scoreReliability({ apiCompleted: true, validOutput: true, toolValid: true, verifierPassed: true, attempts: 3 }).score < 1);
  const latency = evaluation.scoreLatency({ ttftMs: 100, firstUsableMs: 400, totalMs: 900, budgetMs: 1000 });
  assert.equal(latency.components.ttftMs, 100);
  assert.equal(latency.score, 1);
  const seen = [];
  const cost = await evaluation.scoreCost({ provider: 'candidate', model: 'm1', inputTokens: 1000, outputTokens: 200, budgetUsd: 0.10, estimator: async (request) => { seen.push(request); return { status: 'estimated', estimatedCostUsd: 0.04, billedCostUsd: null, pricingVersion: 'test-v1' }; } });
  assert.equal(seen.length, 1);
  assert.equal(cost.components.pricingVersion, 'test-v1');
  assert.equal(cost.components.billedCostUsd, null);
  assert.equal(evaluation.sampleConfidence(4), 'insufficient');
  assert.equal(evaluation.sampleConfidence(30), 'moderate');
});

test('shadow evaluation is disabled by default and cannot receive executable tools', async () => {
  let calls = 0;
  const disabled = new evaluation.ShadowEvaluationRunner({ executeCandidate: async () => { calls += 1; return {}; } });
  const held = await disabled.run([CASES[0]], { knownValidators: KNOWN_VALIDATORS });
  assert.equal(held.status, 'HOLD');
  assert.equal(calls, 0);

  let observedPolicy = null;
  const runner = new evaluation.ShadowEvaluationRunner({
    enabled: true,
    limits: { maxCases: 2, maxProviderCalls: 1, maxTokens: 1000, maxEstimatedCostUsd: 1 },
    executeCandidate: async (request) => {
      observedPolicy = request.toolPolicy;
      return { provider: 'fixture', model: 'fixture-v1', output: { proposal: 'captured-only' }, usage: { totalTokens: 100, estimatedCostUsd: 0.01 } };
    },
  });
  const result = await runner.run(CASES.slice(0, 2), { knownValidators: KNOWN_VALIDATORS });
  assert.equal(observedPolicy.mode, 'disabled');
  assert.equal(observedPolicy.sideEffectsAllowed, false);
  assert.deepEqual(observedPolicy.allowedTools, []);
  assert.equal(result.usage.calls, 1);
  assert.equal(result.status, 'HOLD');
  assert.equal(result.reason, 'budget_exhausted');
});

test('shadow dry-run makes no provider call', async () => {
  let calls = 0;
  const runner = new evaluation.ShadowEvaluationRunner({ enabled: true, executeCandidate: async () => { calls += 1; return {}; } });
  const result = await runner.run(CASES.slice(0, 2), { dryRun: true, knownValidators: KNOWN_VALIDATORS });
  assert.equal(calls, 0);
  assert.equal(result.results.length, 2);
  assert.ok(result.results.every((item) => item.reason === 'dry_run'));
});

test('comparison matrix contains measured evidence only and exposes sample confidence', () => {
  const matrix = evaluation.buildComparisonMatrix([
    { measured: true, taskClass: 'coding', provider: 'gemini', modelVersion: 'g-test', quality: 0.9, reliability: 1, latencyMs: 1000, estimatedCostUsd: 0.02, verifierPassed: true },
    { measured: false, taskClass: 'coding', provider: 'kimi', quality: 1 },
  ], { sourceSha: 'abc' });
  assert.equal(matrix.rows.length, 1);
  assert.equal(matrix.rows[0].provider, 'gemini');
  assert.equal(matrix.rows[0].sampleCount, 1);
  assert.equal(matrix.rows[0].confidence, 'insufficient');
});

test('promotion gate holds sparse evidence, hard-fails security regression, and passes complete evidence', () => {
  const t = thresholds.BY_TASK_CLASS.structured_output;
  assert.equal(evaluation.evaluatePromotionGate({ sampleCount: 2, quality: 1, reliability: 1, structuredOutputValidity: 1, verifierPassRate: 1, latencyMs: 1, estimatedCostUsd: 0.01, fallbackRate: 0, securityRegressions: 0 }, t).status, 'HOLD');
  assert.equal(evaluation.evaluatePromotionGate({ sampleCount: 100, securityRegressions: 1 }, t).status, 'FAIL');
  assert.equal(evaluation.evaluatePromotionGate({ sampleCount: 100, quality: 0.99, reliability: 0.999, structuredOutputValidity: 1, verifierPassRate: 0.99, latencyMs: 1000, estimatedCostUsd: 0.01, fallbackRate: 0, securityRegressions: 0 }, t).status, 'PASS');
});
