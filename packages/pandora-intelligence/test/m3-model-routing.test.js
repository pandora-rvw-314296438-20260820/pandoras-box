'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  GEMINI_MODEL_CAPABILITY_DECLARATIONS,
  KIMI_K3_CAPABILITY_DECLARATION,
  ModelCapabilityRegistry,
  ModelRouter,
  OPENAI_MODEL_CAPABILITY_DECLARATIONS,
  createModelRequest,
  createRoutingPolicy,
} = require('../dist/index.js');

function request(overrides = {}) {
  return createModelRequest({
    requestId: 'req-m3-routing',
    task: 'classify_task',
    outputMode: 'text',
    context: {},
    requiredCapabilities: ['classification'],
    budget: { maxAttempts: 2 },
    metadata: {},
    ...overrides,
  });
}

function syntheticModel(provider, modelId, overrides = {}) {
  return {
    provider,
    modelId,
    capabilities: { classification: true, reasoning: true },
    executionBoundary: 'external_provider',
    latencyClass: 'standard',
    costClass: 'medium',
    reliabilityClass: 'high',
    maxContextTokens: 128000,
    outputModes: ['text'],
    enabled: true,
    metadata: {},
    ...overrides,
  };
}

function adapter(provider) {
  return { async execute(_request, declaration) { return { provider, model: declaration.modelId, output: `${provider}:${declaration.modelId}` }; } };
}

test('registry validates explicit privacy boundaries and defaults legacy declarations to external provider', () => {
  const registry = new ModelCapabilityRegistry();
  const legacy = registry.register(syntheticModel('legacy', 'v1', { executionBoundary: undefined }));
  assert.equal(legacy.executionBoundary, 'external_provider');
  const local = registry.register(syntheticModel('local', 'v1', { executionBoundary: 'device' }));
  assert.equal(local.executionBoundary, 'device');
  assert.throws(() => registry.register(syntheticModel('bad', 'v1', { executionBoundary: 'unknown-zone' })), /executionBoundary/);
});

test('privacy boundary is a hard task constraint and overrides provider preference', async () => {
  const registry = new ModelCapabilityRegistry();
  registry.register(syntheticModel('openai', 'external-fast', { executionBoundary: 'external_provider', latencyClass: 'interactive', costClass: 'low' }));
  registry.register(syntheticModel('edge', 'private-local', { executionBoundary: 'device', latencyClass: 'interactive', costClass: 'low' }));
  const router = new ModelRouter({ registry, adapters: { openai: adapter('openai'), edge: adapter('edge') } });
  const policy = createRoutingPolicy({ policyVersion: 'privacy-v1', taskExecutionBoundaries: { classify_task: ['device'] } });
  const result = await router.execute(request(), { policy, preferredProvider: 'openai' });
  assert.equal(result.routedProvider, 'edge');
  assert.equal(result.routingDecision.selectedExecutionBoundary, 'device');
  const blocked = result.routingDecision.excludedCandidates.find((item) => item.provider === 'openai');
  assert.ok(blocked);
  assert.ok(blocked.reasons.includes('privacy_boundary_not_allowed'));
  assert.equal(blocked.executionBoundary, 'external_provider');
});

test('quality, latency, cost and availability hard floors remove unsuitable candidates before scoring', () => {
  const registry = new ModelCapabilityRegistry();
  registry.register(syntheticModel('quality', 'low-quality'));
  registry.register(syntheticModel('latency', 'too-slow'));
  registry.register(syntheticModel('cost', 'too-expensive'));
  registry.register(syntheticModel('available', 'good'));
  registry.register(syntheticModel('missing-adapter', 'offline'));
  const router = new ModelRouter({ registry, adapters: { quality: adapter('quality'), latency: adapter('latency'), cost: adapter('cost'), available: adapter('available') } });
  const policy = createRoutingPolicy({
    policyVersion: 'quality-latency-cost-v1',
    minObservedQuality: 0.9,
    maxLatencyMs: 500,
    maxEstimatedCostUsd: 0.01,
    hardFloorMinSamples: 20,
    performance: {
      'quality:low-quality': { quality: 0.5, successRate: 1, latencyScore: 1, costScore: 1, sampleCount: 50, p95LatencyMs: 100, estimatedCostUsd: 0.001 },
      'latency:too-slow': { quality: 1, successRate: 1, latencyScore: 0.1, costScore: 1, sampleCount: 50, p95LatencyMs: 900, estimatedCostUsd: 0.001 },
      'cost:too-expensive': { quality: 1, successRate: 1, latencyScore: 1, costScore: 0.1, sampleCount: 50, p95LatencyMs: 100, estimatedCostUsd: 0.02 },
      'available:good': { quality: 1, successRate: 1, latencyScore: 1, costScore: 1, sampleCount: 50, p95LatencyMs: 100, estimatedCostUsd: 0.001 },
      'missing-adapter:offline': { quality: 1, successRate: 1, latencyScore: 1, costScore: 1, sampleCount: 50, p95LatencyMs: 100, estimatedCostUsd: 0.001 },
    },
  });
  const detailed = router.candidatesDetailed(request(), { policy });
  assert.deepEqual(detailed.candidates.map((item) => item.model.modelId), ['good']);
  const reasons = Object.fromEntries(detailed.excluded.map((item) => [item.model, item.reasons]));
  assert.ok(reasons['low-quality'].includes('observed_quality_floor'));
  assert.ok(reasons['too-slow'].includes('latency_ceiling'));
  assert.ok(reasons['too-expensive'].includes('estimated_cost_ceiling'));
  assert.ok(reasons.offline.includes('adapter_unavailable'));
});

test('current Gemini and OpenAI profiles route through one registry and future providers remain additive', async () => {
  const registry = new ModelCapabilityRegistry();
  for (const item of GEMINI_MODEL_CAPABILITY_DECLARATIONS) registry.register(item);
  for (const item of OPENAI_MODEL_CAPABILITY_DECLARATIONS) registry.register(item);
  registry.register(KIMI_K3_CAPABILITY_DECLARATION);
  registry.register(syntheticModel('future-provider', 'future-v1', { executionBoundary: 'pandora_trusted_cloud', costClass: 'low' }));
  const router = new ModelRouter({ registry, adapters: { gemini: adapter('gemini'), openai: adapter('openai'), 'future-provider': adapter('future-provider') } });
  const openai = await router.execute(request({ budget: { maxAttempts: 1 } }), { preferredProvider: 'openai' });
  assert.equal(openai.routedProvider, 'openai');
  assert.equal(openai.routingDecision.selectedExecutionBoundary, 'external_provider');
  const gemini = await router.execute(request({ requestId: 'req-gemini', budget: { maxAttempts: 1 } }), { preferredProvider: 'gemini' });
  assert.equal(gemini.routedProvider, 'gemini');
  assert.equal(KIMI_K3_CAPABILITY_DECLARATION.executionBoundary, 'external_provider');
  const futurePolicy = createRoutingPolicy({ allowedExecutionBoundaries: ['pandora_trusted_cloud'] });
  const future = await router.execute(request({ requestId: 'req-future', budget: { maxAttempts: 1 } }), { policy: futurePolicy });
  assert.equal(future.routedProvider, 'future-provider');
});
