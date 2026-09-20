import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const machinePath = new URL('../docs/architecture/pandora-universal-architecture-v1.json', import.meta.url);
const documentPath = new URL('../docs/architecture/PANDORA_UNIVERSAL_ARCHITECTURE_V1.md', import.meta.url);

const [machineRaw, document] = await Promise.all([
  readFile(machinePath, 'utf8'),
  readFile(documentPath, 'utf8'),
]);
const contract = JSON.parse(machineRaw);

test('freezes the canonical Pandora interaction flow', () => {
  assert.equal(contract.schemaVersion, 'pandora-universal-architecture-v1');
  assert.equal(contract.status, 'frozen');
  assert.deepEqual(contract.canonicalFlow, [
    'user',
    'pandora',
    'pandora_ai',
    'capability_router',
    'device_cloud_models_services',
    'activity_theatre',
    'verified_result',
    'memory',
    'learning_anticipation_optimization',
  ]);
  assert.match(document, /You → Pandora → Pandora AI → capability router/);
});

test('keeps universal control surfaces out of builder-first mode', () => {
  assert.deepEqual(contract.controlSurfaces.primary, ['text_chat', 'natural_language_voice']);
  assert.equal(contract.controlSurfaces.sameRuntime, true);
  assert.equal(contract.controlSurfaces.builderDefault, false);
  assert.match(document, /Software building is one capability among many/i);
  assert.match(document, /Projects are optional correlation\/workspace context/i);
});

test('makes Pandora job identity neutral to projects, providers, devices and attempts', () => {
  assert.equal(contract.jobIdentity.owner, 'pandora');
  assert.equal(contract.jobIdentity.scope, 'provider_project_device_neutral');
  assert.equal(contract.jobIdentity.createdAt, 'meaningful_work_admission');
  assert.equal(contract.jobIdentity.conversationIdsAreCorrelationOnly, true);
  assert.equal(contract.jobIdentity.projectIdsAreOptionalCorrelationOnly, true);
  assert.equal(contract.jobIdentity.attemptIdsAreNotJobIds, true);
  assert.ok(contract.jobIdentity.attemptIdentifiers.includes('execution_plan_id'));
  assert.ok(contract.jobIdentity.attemptIdentifiers.includes('device_operation_id'));
});

test('routes capabilities before provider selection without self-authorization', () => {
  assert.equal(contract.capabilityRouting.projectRequired, false);
  assert.equal(contract.capabilityRouting.softwareBuildIsOneCapability, true);
  assert.equal(contract.capabilityRouting.resolverOwnsCapabilitySelection, true);
  assert.equal(contract.capabilityRouting.modelsMayProposeButDoNotSelfAuthorize, true);
  assert.deepEqual(contract.capabilityRouting.selectionDimensions, [
    'capability',
    'quality',
    'latency',
    'reliability',
    'cost',
    'privacy',
    'availability',
    'verified_historical_performance',
  ]);
});

test('requires governed execution, ambiguity readback and duplicate-side-effect protection', () => {
  assert.equal(contract.executionFabric.governedDefault, true);
  assert.equal(contract.executionFabric.pandoraForGovernedProviderWork, true);
  assert.equal(contract.executionFabric.deviceAgentForPhoneWork, true);
  assert.equal(contract.executionFabric.edgeRuntimeForLocalWork, true);
  assert.equal(contract.executionFabric.directProviderWritesAreFallbackOnly, true);
  assert.equal(contract.executionFabric.ambiguousWriteRequiresReadbackBeforeRetry, true);
  assert.equal(contract.executionFabric.consequentialSideEffectsRequireIdempotency, true);
  assert.match(document, /ambiguous write outcome must be reconciled by provider readback before any retry/i);
});

test('makes Activity Theatre universal truth and Build Theatre a specialized projection', () => {
  assert.equal(contract.activityTheatre.ownership, 'pandora_neutral_runtime_contract');
  assert.equal(contract.activityTheatre.meaningfulEventsOnly, true);
  assert.equal(contract.activityTheatre.truthfulAndInterruptible, true);
  assert.equal(contract.activityTheatre.durableStableReplayIdentity, true);
  assert.equal(contract.activityTheatre.buildTheatreRelation, 'specialized_projection');
  assert.equal(contract.activityTheatre.terminalResultRequiresVerifiedOutcome, true);
  assert.equal(contract.activityTheatre.attemptSuccessDoesNotImplyJobResult, true);
  assert.equal(contract.activityTheatre.rawSecretsPromptsToolArgsLogsForbiddenInPublicProjection, true);
});

test('requires verified outcome truth before Pandora claims completion', () => {
  assert.equal(contract.result.verifiedBeforeCompletionClaim, true);
  assert.equal(contract.result.providerSuccessAloneIsInsufficient, true);
  assert.equal(contract.result.rollbackEvidenceRequiredWhenApplicable, true);
  assert.match(document, /Pandora may claim completion only after the applicable outcome is verified/i);
});

test('keeps Memory classes distinct and prediction separate from permission', () => {
  assert.equal(contract.memoryHandoff.afterVerifiedOutcome, true);
  assert.deepEqual(contract.memoryHandoff.classesRemainDistinct, [
    'facts',
    'patterns',
    'policies',
    'procedures',
    'failures',
    'outcomes',
    'provider_performance',
  ]);
  assert.equal(contract.memoryHandoff.predictionNeverBecomesPermission, true);
  assert.equal(contract.memoryHandoff.newAuthoritativeEvidenceOverridesStaleMemory, true);
});

test('preserves device, security and downstream ownership boundaries', () => {
  assert.equal(contract.deviceAndEdge.deviceAgentMediatesPhoneCapabilities, true);
  assert.equal(contract.deviceAndEdge.remoteModelsDoNotReceiveUnrestrictedRoot, true);
  assert.equal(contract.deviceAndEdge.localJobsWorkOfflineWhenCapabilityAllows, true);
  assert.equal(contract.deviceAndEdge.jobAndEventIdentitySurvivesOfflineToCloudSync, true);
  assert.equal(contract.deviceAndEdge.oemSpecificBehaviorBehindAdapters, true);
  assert.equal(contract.deviceAndEdge.protectedAppsRemainProtected, true);
  assert.equal(contract.security.credentialsNeverEnterModelContext, true);
  assert.equal(contract.security.standingAuthorityDoesNotEqualUnlimitedAuthority, true);
  assert.equal(contract.security.authorizationScopeIsServerSide, true);
  for (const key of ['M0-003', 'M0-004', 'M0-005', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7']) {
    assert.equal(typeof contract.handoffs[key], 'string');
    assert.ok(contract.handoffs[key].length > 0);
  }
});
