'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const resolver = require('../src/resolution/intent-capability-resolver.js');

const {
  ACTION_MODES,
  DOMAINS,
  EXECUTION_BOUNDARIES,
  MODEL_CAPABILITY_KEYS,
  RESOLVER_CONTRACT_VERSION,
  resolveIntentCapabilities,
} = resolver;

function resolve(request, extra = {}) {
  return resolveIntentCapabilities({ request, ...extra });
}

test('contract exposes frozen universal domains, effects and M1 to M3 vocabulary', () => {
  assert.equal(RESOLVER_CONTRACT_VERSION, 'pandora-intent-capability-resolution-v1');
  assert.deepEqual(DOMAINS, [
    'communication', 'research', 'coding_building', 'files', 'device_operations',
    'business', 'travel', 'scheduling', 'future_capability', 'general_assistance',
  ]);
  assert.deepEqual(ACTION_MODES, ['no_action', 'read_only', 'state_change']);
  assert.deepEqual(EXECUTION_BOUNDARIES, ['device', 'pandora_trusted_cloud', 'external_provider']);
  assert.ok(MODEL_CAPABILITY_KEYS.includes('coding'));
  assert.ok(MODEL_CAPABILITY_KEYS.includes('toolCalling'));
});

test('representative prompts resolve across universal domains', () => {
  const cases = [
    ['Draft an email to Aaron about the Globe intro', 'communication'],
    ['Research the latest solar battery options and compare evidence', 'research'],
    ['Build a booking system for my restaurant', 'coding_building'],
    ['Read this PDF and summarize it', 'files'],
    ['Turn off Bluetooth on my phone', 'device_operations'],
    ['Analyze restaurant pricing and customer retention', 'business'],
    ['Compare flights and hotels for a trip to Tokyo', 'travel'],
    ['Schedule a meeting for tomorrow', 'scheduling'],
    ['Plan a future capability so Pandora can control another device later', 'future_capability'],
    ['Help me think through whether I should change my morning routine', 'general_assistance'],
  ];
  for (const [request, expected] of cases) {
    assert.equal(resolve(request).intent, expected, request);
  }
});

test('ordinary create/build vocabulary never silently becomes software work', () => {
  const cases = [
    'Create a workout plan for next week',
    'Build a better morning routine',
    'Create a marketing strategy for my restaurant',
  ];
  for (const request of cases) {
    const result = resolve(request);
    assert.notEqual(result.intent, 'coding_building', request);
    assert.equal(result.routingEvidence.builderDefaultPrevented, true, request);
    assert.equal(result.capabilityToolConstraints.forbidAutomaticProjectCreation, true);
  }
});

test('selected project is ignored for unrelated user intent', () => {
  const selectedProject = { id: 'pandoras-box' };
  for (const request of [
    'Draft a reply to Jacqueline about the meeting',
    'Compare flights to Oslo',
    'Turn off Bluetooth on my phone',
    'Research the latest solar battery options',
  ]) {
    const result = resolve(request, { selectedProject });
    assert.equal(result.contextBinding.kind, 'none', request);
    assert.equal(result.routingEvidence.projectContextUsed, false, request);
    assert.equal(result.routingEvidence.projectContextIgnoredAsIrrelevant, true, request);
  }
});

test('genuine selected-project software change binds project and requires governed mutation controls', () => {
  const result = resolve('Fix checkout in this app', { selectedProject: { id: 'bok' } });
  assert.equal(result.intent, 'coding_building');
  assert.equal(result.actionMode, 'state_change');
  assert.deepEqual(result.contextBinding, {
    kind: 'project',
    projectId: 'bok',
    reason: 'explicit_software_project_context',
  });
  assert.equal(result.capabilityToolConstraints.requireGovernedMutationBoundary, true);
  assert.equal(result.capabilityToolConstraints.requireReadbackAfterStateChange, true);
  assert.equal(result.capabilityToolConstraints.reuseIdempotencyOnRetry, true);
});

test('selected-project shorthand action may resolve to software without making project context a global default', () => {
  const result = resolve('Build it according to the approved plan', { selectedProject: { id: 'pandora' } });
  assert.equal(result.intent, 'coding_building');
  assert.equal(result.actionMode, 'state_change');
  assert.deepEqual(result.contextBinding, {
    kind: 'project',
    projectId: 'pandora',
    reason: 'selected_project_action_reference',
  });
});

test('software planning never authorizes mutation merely because action words appear', () => {
  for (const request of [
    'Create an implementation roadmap to deploy this website',
    'Explain how to fix the checkout bug',
  ]) {
    const result = resolve(request, { selectedProject: { id: 'pandora' } });
    assert.equal(result.intent, 'coding_building', request);
    assert.notEqual(result.actionMode, 'state_change', request);
    assert.equal(result.capabilityToolConstraints.requireGovernedMutationBoundary, false, request);
  }
});

test('M1 emits model constraints without choosing provider or model', () => {
  const result = resolve('Fix checkout in this app', { selectedProject: { id: 'bok' } });
  assert.ok(result.modelRoutingConstraints.requiredModelCapabilities.includes('coding'));
  assert.ok(result.modelRoutingConstraints.requiredModelCapabilities.includes('toolCalling'));
  assert.equal(result.modelRoutingConstraints.providerPreference, null);
  assert.equal(result.modelRoutingConstraints.modelPreference, null);
  assert.equal(result.modelRoutingConstraints.modelSelectionOwner, 'M3');
});

test('device side effects require device presence and forbid cloud side effects', () => {
  const result = resolve('Turn off Bluetooth on my phone');
  assert.equal(result.intent, 'device_operations');
  assert.equal(result.actionMode, 'state_change');
  assert.equal(result.privacyExecution.preferredExecution, 'device');
  assert.equal(result.executionCharacteristics.preferredPlacement, 'device');
  assert.equal(result.executionCharacteristics.requiresDevicePresence, true);
  assert.equal(result.executionCharacteristics.allowCloudSideEffects, false);
});

test('confidential local file work narrows model execution boundaries', () => {
  const result = resolve('Read this confidential local-only PDF and summarize it');
  assert.equal(result.intent, 'files');
  assert.deepEqual(result.privacyExecution.allowedExecutionBoundaries, ['device', 'pandora_trusted_cloud']);
  assert.deepEqual(result.modelRoutingConstraints.allowedExecutionBoundaries, ['device', 'pandora_trusted_cloud']);
  assert.equal(result.privacyExecution.resolverClaimsProviderCompliance, false);
});

test('risk signals never become authority grants', () => {
  const result = resolve('Publish the website to production', { selectedProject: { id: 'pandora' } });
  assert.equal(result.intent, 'coding_building');
  assert.equal(result.actionMode, 'state_change');
  assert.equal(result.riskAuthority.consequential, true);
  assert.ok(result.riskAuthority.consequenceSignals.includes('public_release'));
  assert.equal(result.riskAuthority.authorityRequirement, 'explicit_current_or_matching_standing_policy');
  assert.equal(result.riskAuthority.authorityDecisionOwner, 'pandora-standing-authority-policy-v1');
  assert.equal(result.riskAuthority.resolverGrantsAuthority, false);
});

test('routing evidence remains bounded and provider-neutral', () => {
  const result = resolve('Research current Android privacy options for confidential files');
  assert.ok(result.routingEvidence.matchedSignals.length <= 24);
  assert.ok(result.routingEvidence.candidateDomains.length <= 5);
  assert.equal(Object.prototype.hasOwnProperty.call(result.routingEvidence, 'provider'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(result.routingEvidence, 'model'), false);
  assert.equal(result.capabilityToolConstraints.providerNeutral, true);
  assert.equal(result.capabilityToolConstraints.forbidCredentialExposure, true);
});

test('invalid input fails closed and machine schema aligns with resolver ownership boundaries', () => {
  assert.throws(() => resolveIntentCapabilities(null), TypeError);
  assert.throws(() => resolveIntentCapabilities({ request: '   ' }), TypeError);

  const schemaPath = path.resolve(__dirname, '../../../docs/architecture/pandora-intent-capability-resolution-v1.schema.json');
  const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  assert.equal(schema.properties.contractVersion.const, RESOLVER_CONTRACT_VERSION);
  assert.deepEqual(schema.properties.intent.enum, DOMAINS);
  assert.deepEqual(schema.properties.actionMode.enum, ACTION_MODES);
  assert.deepEqual(
    schema.properties.privacyExecution.properties.allowedExecutionBoundaries.items.enum,
    EXECUTION_BOUNDARIES,
  );
  assert.deepEqual(
    schema.properties.modelRoutingConstraints.properties.requiredModelCapabilities.items.enum,
    MODEL_CAPABILITY_KEYS,
  );
  assert.equal(schema.properties.modelRoutingConstraints.properties.modelSelectionOwner.const, 'M3');
  assert.equal(schema.properties.modelRoutingConstraints.properties.providerPreference.type, 'null');
  assert.equal(schema.properties.modelRoutingConstraints.properties.modelPreference.type, 'null');
  assert.equal(schema.properties.riskAuthority.properties.resolverGrantsAuthority.const, false);
});
