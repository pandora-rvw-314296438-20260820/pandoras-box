'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const corpus = require('../src/evaluation/corpus-v1.js');
const registry = require('../src/evaluation/validator-registry-v1.js');

test('every corpus validator resolves to the authoritative deterministic registry', () => {
  for (const benchmarkCase of corpus.CASES) {
    for (const validator of benchmarkCase.deterministicValidators) {
      assert.ok(registry.VALIDATOR_REGISTRY[validator], `${benchmarkCase.caseId}:${validator}`);
      assert.equal(registry.VALIDATOR_REGISTRY[validator].deterministic, true);
    }
  }
});

test('builtin JSON parse and schema checks produce exact PASS/FAIL evidence', async () => {
  const benchmarkCase = corpus.CASES.find((item) => item.caseId === 'structured-json-001');
  const good = await registry.runDeterministicValidators(benchmarkCase, { taskClass: 'coding', confidence: 0.9 });
  assert.deepEqual(good.map((item) => item.status), ['PASS', 'PASS']);
  const malformed = await registry.runDeterministicValidators(benchmarkCase, '{bad json');
  assert.equal(malformed[0].status, 'FAIL');
  const extra = await registry.runDeterministicValidators(benchmarkCase, { taskClass: 'coding', confidence: 0.9, unexpected: true });
  assert.equal(extra[1].status, 'FAIL');
});

test('tool allowlist is deterministic and blocks unsupported tool proposals', async () => {
  const benchmarkCase = corpus.CASES.find((item) => item.caseId === 'structured-tool-002');
  const allowed = await registry.runDeterministicValidators(benchmarkCase, { tool: 'repository_read', arguments: {} });
  assert.equal(allowed.find((item) => item.validator === 'tool_allowlist').status, 'PASS');
  const denied = await registry.runDeterministicValidators(benchmarkCase, { tool: 'repository_write', arguments: {} });
  assert.equal(denied.find((item) => item.validator === 'tool_allowlist').status, 'FAIL');
});

test('external deterministic checks fail closed when their executor is unavailable', async () => {
  const benchmarkCase = corpus.CASES.find((item) => item.caseId === 'coding-function-001');
  const blocked = await registry.runDeterministicValidators(benchmarkCase, { patch: 'synthetic' });
  assert.ok(blocked.every((item) => item.status === 'BLOCKED'));
  const passed = await registry.runDeterministicValidators(benchmarkCase, { patch: 'synthetic' }, {
    externalValidators: {
      unit_tests: async () => ({ status: 'PASS', evidenceRef: 'sandbox:test:unit' }),
      forbidden_change_scan: async () => ({ status: 'PASS', evidenceRef: 'sandbox:test:diff' }),
    },
  });
  assert.ok(passed.every((item) => item.status === 'PASS'));
});
