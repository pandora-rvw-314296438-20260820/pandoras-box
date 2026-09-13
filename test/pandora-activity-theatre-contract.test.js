import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const machinePath = new URL('../docs/architecture/pandora-activity-theatre-contract-v1.json', import.meta.url);
const documentPath = new URL('../docs/architecture/PANDORA_ACTIVITY_THEATRE_CONTRACT_V1.md', import.meta.url);
const contract = JSON.parse(fs.readFileSync(machinePath, 'utf8'));
const document = fs.readFileSync(documentPath, 'utf8');

test('M0-004 contract is frozen and neutrally owned', () => {
  assert.equal(contract.schemaVersion, 'pandora-activity-theatre-contract-v1');
  assert.equal(contract.status, 'frozen');
  assert.equal(contract.ownership.package, '@pandora/activity-theatre');
  assert.equal(contract.ownership.neutral, true);
  assert.equal(contract.ownership.projectRuntimeDoesNotOwnUniversalContract, true);
  assert.equal(contract.ownership.buildTheatreRelation, 'specialized_projection');
});

test('only meaningful real events may be admitted', () => {
  assert.equal(contract.eventAdmission.meaningfulRealEventsOnly, true);
  assert.equal(contract.eventAdmission.syntheticProgressForbidden, true);
  assert.equal(contract.eventAdmission.fakePercentagesForbidden, true);
  assert.equal(contract.eventAdmission.inventedStagesForbidden, true);
  assert.equal(contract.eventAdmission.sourceEventOrTypedEvidenceRequired, true);
  assert.equal(contract.eventAdmission.admissionAuthority, 'single_writer_per_job_epoch');
  assert.equal(contract.eventAdmission.writerHandoffRequiresEpochAdvance, true);
});

test('identity, clocks and lineage survive replay/offline sync', () => {
  for (const key of ['jobIdRequired', 'eventIdRequired', 'sequenceRequired', 'writerEpochRequired']) {
    assert.equal(contract.identity[key], true, key);
  }
  assert.equal(contract.identity.attemptIdDoesNotReplaceJobId, true);
  assert.equal(contract.identity.identitySurvivesReconnectReplayAndOfflineSync, true);
  assert.equal(contract.time.occurredAtRequired, true);
  assert.equal(contract.time.admittedAtRequired, true);
  assert.equal(contract.time.observedAtRequiredForProvenance, true);
  assert.equal(contract.time.admittedAtCannotPrecedeOccurredAt, true);
  assert.equal(contract.time.timelineSequenceIsCanonicalOrdering, true);
});

test('provenance uses typed evidence and attempt success is not job success', () => {
  assert.equal(contract.provenance.typedEvidenceReferences, true);
  assert.ok(contract.provenance.allowedEvidenceTypes.includes('verification_receipt'));
  assert.ok(contract.provenance.allowedEvidenceTypes.includes('user_control'));
  assert.equal(contract.provenance.providerAttemptSuccessDoesNotImplyJobResult, true);
  assert.equal(contract.provenance.verificationEvidenceRequiredForResult, true);
});

test('paused/resuming and terminal-state semantics are explicit', () => {
  for (const state of ['paused', 'resuming', 'needs_you', 'retrying', 'fallback', 'result', 'failed', 'cancelled']) {
    assert.ok(contract.states.public.includes(state), state);
  }
  assert.deepEqual(contract.states.terminal, ['result', 'failed', 'cancelled']);
  assert.equal(contract.states.postTerminalEventsForbidden, true);
  assert.equal(contract.states.resultRequiresVerifiedOverallJobOutcome, true);
  assert.equal(contract.controls.requestedControlIsNotAcceptedControl, true);
  assert.equal(contract.controls.resumingRequiresPriorPausedState, true);
  assert.equal(contract.controls.controlReadbackRequiredWhenAcceptanceIsAmbiguous, true);
});

test('Needs You remains a real user boundary under M0-003', () => {
  assert.equal(contract.needsYou.realUserBoundaryOnly, true);
  assert.equal(contract.needsYou.requiresExactRequiredAction, true);
  assert.equal(contract.needsYou.allowedReasonsMustConformToStandingAuthorityPolicy, true);
  assert.equal(contract.needsYou.routineWaitingIsNotNeedsYou, true);
  assert.equal(contract.needsYou.providerFallbackInsideAuthorityIsNotNeedsYou, true);
  assert.equal(contract.needsYou.voluntaryPauseIsNotNeedsYou, true);
});

test('retry/fallback and replay preserve truth and idempotency', () => {
  assert.equal(contract.retryAndFallback.retryRequiresPriorAttemptEvidence, true);
  assert.equal(contract.retryAndFallback.authorityScopeMayNotExpand, true);
  assert.equal(contract.retryAndFallback.consequentialRetryReusesIdempotencyIdentity, true);
  assert.equal(contract.retryAndFallback.ambiguousEffectRequiresReadbackBeforeRetry, true);
  assert.equal(contract.replay.durableReplayRequired, true);
  assert.equal(contract.replay.gapDetectionRequired, true);
  assert.equal(contract.replay.reconnectMayNotInventMissingEvents, true);
  assert.equal(contract.replay.offlineSyncPreservesOriginalOccurrenceTimeAndIdentity, true);
});

test('privacy and verified completion fail closed', () => {
  for (const key of ['rawPromptsForbiddenInPublicProjection', 'rawToolArgsForbiddenInPublicProjection', 'credentialsSecretsTokensOtpsForbidden', 'privateProviderPayloadsForbidden', 'publicFieldsFailClosedOnCredentialLikeMaterial']) {
    assert.equal(contract.privacy[key], true, key);
  }
  assert.equal(contract.verification.overallJobResultRequiresVerifierOrEquivalentReadback, true);
  assert.equal(contract.verification.providerSuccessAloneInsufficient, true);
  assert.equal(contract.verification.modelClaimAloneInsufficient, true);
  assert.equal(contract.verification.authorizationIsNotCompletion, true);
  assert.equal(contract.verification.physicalDeviceSuccessRequiresPhysicalEvidence, true);
});

test('Build Theatre is a specialized projection and downstream ownership stays separate', () => {
  assert.equal(contract.buildTheatre.specializedProjectionOnly, true);
  assert.equal(contract.buildTheatre.usesSameCanonicalEvents, true);
  assert.equal(contract.buildTheatre.mayNotFabricateBuildProgress, true);
  for (const key of ['M1-004', 'M1-005', 'M1-007', 'M2-001', 'M2-002', 'M2-003', 'M2-005', 'M2-006']) {
    assert.equal(typeof contract.handoffs[key], 'string');
    assert.ok(contract.handoffs[key].length > 0);
  }
  for (const phrase of ['Fake percentages', 'single-writer', 'provider-attempt success', 'Build Theatre is a specialized projection', 'Physical-device success requires physical evidence']) {
    assert.ok(document.toLowerCase().includes(phrase.toLowerCase()), phrase);
  }
});
