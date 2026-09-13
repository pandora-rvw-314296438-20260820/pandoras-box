'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ModelCapabilityRegistry,
  ModelRouter,
  createModelRequest,
  createSessionRoutingState,
} = require('../dist/index.js');

function model(provider, modelId, boundary) {
  return {
    provider, modelId, executionBoundary: boundary,
    capabilities: { classification: true, reasoning: true },
    latencyClass: 'standard', costClass: 'medium', reliabilityClass: 'high',
    maxContextTokens: 128000, outputModes: ['text'], enabled: true, metadata: {},
  };
}
function adapter(provider) {
  return { async execute(_request, declaration) { return { provider, model: declaration.modelId, output: 'ok' }; } };
}
function request() {
  return createModelRequest({ requestId: 'req-m1-m3', task: 'classify_task', outputMode: 'text', context: {}, requiredCapabilities: [], budget: { maxAttempts: 2 }, metadata: {} });
}
function resolution(overrides = {}) {
  const base = {
    contractVersion: 'pandora-intent-capability-resolution-v1',
    intent: 'research', requestedOutcome: 'Route safely', requiredCapabilities: ['research.web'], actionMode: 'read_only',
    riskAuthority: { consequential: false, consequenceSignals: [], authorityRequirement: 'none_required', authorityDecisionOwner: 'pandora-standing-authority-policy-v1', resolverGrantsAuthority: false },
    privacyExecution: { allowedExecutionBoundaries: ['device'], preferredExecution: 'device_first', resolverClaimsProviderCompliance: false },
    executionCharacteristics: { preferredPlacement: 'device_first', requiresDevicePresence: false, allowCloudReasoning: false, allowCloudSideEffects: false },
    contextBinding: { kind: 'none', projectId: null, reason: null }, confidence: 0.99,
    ambiguity: { needsClarification: false, reason: null, alternatives: [] },
    capabilityToolConstraints: { forbidAutomaticProjectCreation: true, requireGovernedMutationBoundary: false, requireReadbackAfterStateChange: false, reuseIdempotencyOnRetry: false, forbidCredentialExposure: true, providerNeutral: true, allowedEffectClass: 'read_only' },
    modelRoutingConstraints: { requiredModelCapabilities: ['classification'], allowedExecutionBoundaries: ['device'], providerPreference: null, modelPreference: null, modelSelectionOwner: 'M3' },
    routingEvidence: { matchedSignals: ['research'], candidateDomains: [{ domain: 'research', score: 1 }], builderDefaultPrevented: true, projectContextUsed: false, projectContextIgnoredAsIrrelevant: false },
  };
  return { ...base, ...overrides };
}
function router() {
  const registry = new ModelCapabilityRegistry();
  registry.register(model('openai', 'external-fast', 'external_provider'));
  registry.register(model('edge', 'device-safe', 'device'));
  return new ModelRouter({ registry, adapters: { openai: adapter('openai'), edge: adapter('edge') } });
}

test('M1 privacy/capability handoff is a hard ceiling over provider preference', async () => {
  const result = await router().executeResolved(request(), resolution(), { preferredProvider: 'openai' });
  assert.equal(result.routedProvider, 'edge');
  assert.equal(result.routingDecision.intentResolution.contractVersion, 'pandora-intent-capability-resolution-v1');
  assert.deepEqual(result.routingDecision.intentResolution.allowedExecutionBoundaries, ['device']);
  assert.equal(result.routingDecision.intentResolution.resolverGrantsAuthority, false);
});

test('M1 cannot select a provider or grant authority', async () => {
  const base = resolution();
  await assert.rejects(() => router().executeResolved(request(), resolution({ riskAuthority: { ...base.riskAuthority, resolverGrantsAuthority: true } })), /must never grant authority/);
  await assert.rejects(() => router().executeResolved(request(), resolution({ modelRoutingConstraints: { ...base.modelRoutingConstraints, providerPreference: 'openai' } })), /must not choose provider or model preferences/);
});

test('state-change handoff fails closed without readback/idempotency invariants', async () => {
  const base = resolution();
  const unsafe = resolution({
    actionMode: 'state_change',
    riskAuthority: { ...base.riskAuthority, consequential: true, authorityRequirement: 'explicit_current_or_matching_standing_policy' },
    capabilityToolConstraints: { ...base.capabilityToolConstraints, allowedEffectClass: 'state_change', requireGovernedMutationBoundary: true, requireReadbackAfterStateChange: false, reuseIdempotencyOnRetry: true },
  });
  await assert.rejects(() => router().executeResolved(request(), unsafe), /require provider readback/);
});

test('hard M1 privacy change overrides sticky provider continuity', async () => {
  const session = createSessionRoutingState({ provider: 'openai', model: 'external-fast', stickinessMode: 'sticky', recoveryEpoch: 2 });
  const result = await router().executeResolved(request(), resolution(), { session, preferredProvider: 'openai' });
  assert.equal(result.routedProvider, 'edge');
  assert.equal(result.routingDecision.intentResolution.hardConstraintRecovery, true);
  assert.equal(result.nextSessionState.stickinessMode, 'recovering');
  assert.equal(result.nextSessionState.recoveryEpoch, 3);
});
