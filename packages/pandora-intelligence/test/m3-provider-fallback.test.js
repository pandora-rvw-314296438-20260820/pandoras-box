'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ModelCapabilityRegistry,
  ModelRouter,
  createModelRequest,
  createRoutingPolicy,
  createSessionRoutingState,
  modelAttemptKey,
} = require('../dist/index.js');

function model(provider, modelId, boundary = 'external_provider') {
  return { provider, modelId, executionBoundary: boundary, capabilities: { classification: true, reasoning: true }, latencyClass: 'standard', costClass: 'medium', reliabilityClass: 'high', maxContextTokens: 128000, outputModes: ['text','tool_proposals'], enabled: true, metadata: {} };
}
function request(requestId = 'req-fallback', overrides = {}) {
  return createModelRequest({ requestId, task: 'classify_task', outputMode: 'text', context: {}, requiredCapabilities: ['classification'], budget: { maxAttempts: 3 }, metadata: {}, ...overrides });
}
function success(provider, confidence = null) {
  return { async execute(req, declaration) { return { provider, model: declaration.modelId, output: provider, metadata: confidence == null ? {} : { confidence }, observedRequestId: req.requestId }; } };
}
function failure(code, retryable, calls) {
  return { async execute(req) { calls.push(req.requestId); throw Object.assign(new Error(code), { code, retryable }); } };
}
function router(adapters, boundaries = {}) {
  const registry = new ModelCapabilityRegistry();
  registry.register(model('p1','m1',boundaries.p1 || 'external_provider'));
  registry.register(model('p2','m2',boundaries.p2 || 'external_provider'));
  return new ModelRouter({ registry, adapters });
}

test('provider outage fallback is bounded and preserves one request identity across attempts', async () => {
  const failed = [], succeeded = [];
  const r = router({ p1: failure('provider_unavailable', true, failed), p2: { async execute(req, declaration) { succeeded.push(req.requestId); return { provider: 'p2', model: declaration.modelId, output: 'ok' }; } } });
  const result = await r.execute(request(), { preferredProvider: 'p1', maxProviderAttempts: 2 });
  assert.equal(result.routedProvider, 'p2');
  assert.deepEqual(failed, ['req-fallback']);
  assert.deepEqual(succeeded, ['req-fallback']);
  assert.equal(result.routingDecision.attempts.length, 2);
  assert.equal(result.routingDecision.attempts[0].attemptKey, modelAttemptKey('req-fallback','p1','m1'));
  assert.equal(result.routingDecision.attempts[1].attemptKey, modelAttemptKey('req-fallback','p2','m2'));
  assert.equal(result.fallbackUsed, true);
});

test('unsupported capability and invalid structured output can fall back, authentication cannot', async () => {
  for (const [code, retryable] of [['unsupported_capability', false], ['structured_output_invalid', true]]) {
    const calls = [];
    const r = router({ p1: failure(code, retryable, calls), p2: success('p2') });
    const result = await r.execute(request(`req-${code}`), { preferredProvider: 'p1' });
    assert.equal(result.routedProvider, 'p2');
    assert.equal(calls.length, 1);
  }
  let p2Calls = 0;
  const authRouter = router({ p1: failure('authentication_failed', false, []), p2: { async execute() { p2Calls += 1; return { provider: 'p2', model: 'm2', output: 'unexpected' }; } } });
  await assert.rejects(() => authRouter.execute(request('req-auth'), { preferredProvider: 'p1' }), (error) => error.code === 'authentication_failed');
  assert.equal(p2Calls, 0);
});

test('low-confidence fallback requires a trusted evaluator and ignores model self-confidence by itself', async () => {
  const r = router({ p1: success('p1', 0.01), p2: success('p2', 0.99) });
  const withoutEvaluator = await r.execute(request('req-self-confidence'), { preferredProvider: 'p1' });
  assert.equal(withoutEvaluator.routedProvider, 'p1');
  const withEvaluator = await r.execute(request('req-trusted-confidence'), {
    preferredProvider: 'p1',
    resultEvaluator: async (result) => ({ accepted: result.provider === 'p2', code: 'low_confidence', reason: 'trusted evaluator threshold' }),
  });
  assert.equal(withEvaluator.routedProvider, 'p2');
  assert.equal(withEvaluator.routingDecision.attempts[0].code, 'low_confidence');
});

test('sticky session automatically enters recovery only after eligible provider failure', async () => {
  const r = router({ p1: failure('timeout', true, []), p2: success('p2') });
  const session = createSessionRoutingState({ provider: 'p1', model: 'm1', stickinessMode: 'sticky', recoveryEpoch: 4 });
  assert.deepEqual(r.candidates(request('req-session'), { session, preferredProvider: 'p1' }).map((item) => item.provider), ['p1']);
  const result = await r.execute(request('req-session'), { session, preferredProvider: 'p1' });
  assert.equal(result.routedProvider, 'p2');
  assert.equal(result.routingDecision.recoveryRequired, true);
  assert.equal(result.nextSessionState.stickinessMode, 'recovering');
  assert.equal(result.nextSessionState.recoveryEpoch, 5);
});

test('privacy boundary remains hard during fallback and never calls an excluded provider', async () => {
  let externalCalls = 0;
  const r = router({ p1: failure('provider_unavailable', true, []), p2: { async execute() { externalCalls += 1; return { provider: 'p2', model: 'm2', output: 'forbidden' }; } } }, { p1: 'device', p2: 'external_provider' });
  const policy = createRoutingPolicy({ policyVersion: 'device-only', allowedExecutionBoundaries: ['device'] });
  await assert.rejects(() => r.execute(request('req-private'), { policy, preferredProvider: 'p1' }), (error) => error.code === 'provider_unavailable');
  assert.equal(externalCalls, 0);
});

test('attempt history is request-bound and prevents duplicate provider/model attempts on resume', async () => {
  let p1Calls = 0;
  const r = router({ p1: { async execute() { p1Calls += 1; return { provider: 'p1', model: 'm1', output: 'duplicate' }; } }, p2: success('p2') });
  const history = [{ requestId: 'req-resume', attemptKey: modelAttemptKey('req-resume','p1','m1'), provider: 'p1', model: 'm1', code: 'timeout', retryable: true }];
  const result = await r.execute(request('req-resume'), { preferredProvider: 'p1', attemptHistory: history });
  assert.equal(result.routedProvider, 'p2');
  assert.equal(p1Calls, 0);
  await assert.rejects(() => r.execute(request('req-other'), { attemptHistory: history }), /requestId does not match/);
});
