const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync, readdirSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const Ajv2020 = require('ajv/dist/2020.js');
const {
  CANONICAL_RECEIPT_AUTHORITY,
  REQUIRED_CHECKS,
  canonicalReceiptPayloadSha256,
  findEvidencePrivacyLeaks,
  validateBusinessValidationEvidence,
} = require('../src/projectos/business-validation-evidence.js');

const ROOT = path.join(__dirname, '..');
const KIT = path.join(ROOT, 'docs', 'business-validation');

function text(name) {
  return readFileSync(path.join(KIT, name), 'utf8');
}

function json(name) {
  return JSON.parse(text(name));
}

function sha256(name) {
  return createHash('sha256').update(readFileSync(path.join(KIT, name))).digest('hex');
}

function paidPilotEvidence() {
  const privacy = {
    containsRawTranscript: false,
    containsContactDetails: false,
    containsPersonalIdentifiers: false,
    containsSecrets: false,
    containsCustomerRecords: false,
    containsFinancialDocuments: false,
  };
  const sourceSha = '1'.repeat(40);
  const sourceTreeSha = '2'.repeat(40);
  const productionDeploymentId = 'dpl-production-0001';
  const rollbackDeploymentId = 'dpl-rollback-0001';
  const restorationReceiptId = '33333333-3333-4333-8333-333333333333';
  const apkSha256 = '4'.repeat(64);
  const sourceMigrationChainSha256 = '5'.repeat(64);
  const appliedVersionChainSha256 = '6'.repeat(64);
  const requiredChecks = REQUIRED_CHECKS.map((check, index) => ({
    name: check.name,
    providerContext: check.providerContext,
    authority: check.authority,
    conclusion: 'success',
    sourceSha,
    checkRunId: 101 + index,
    checkSuiteId: 201 + index,
    appId: check.appId,
    providerEvidenceRef: `provider-evidence:${String(index + 1).repeat(64)}`,
  }));
  const payload = {
    schemaVersion: '1.0.0',
    kind: 'canonical_status_release_receipt',
    authoritative: true,
    status: 'current',
    verifiedAt: '2026-08-23T15:59:30.000Z',
    capturedAt: '2026-08-23T15:59:45.000Z',
    expiresAt: '2026-08-23T16:05:00.000Z',
    source: {
      repository: 'banataosystems/Pandoras-box',
      branch: 'main',
      sha: sourceSha,
      treeSha: sourceTreeSha,
    },
    requiredChecks,
    independentReview: {
      authority: 'INDEPENDENT_REVIEWER',
      receiptId: '77777777-7777-4777-8777-777777777777',
      receiptSha256: '7'.repeat(64),
      reviewerKeyFingerprint: '8'.repeat(64),
      sourceSha,
      sourceTreeSha,
      productionDeploymentId,
      rollbackDeploymentId,
      supabaseMigrationChainSha256: sourceMigrationChainSha256,
      reviewedAt: '2026-08-23T15:57:00.000Z',
    },
    productionDeployment: {
      authority: 'VERCEL_PROVIDER',
      deploymentId: productionDeploymentId,
      sourceSha,
      observedAt: '2026-08-23T15:40:00.000Z',
    },
    rollbackRehearsal: {
      authority: 'VERCEL_PROVIDER',
      candidateDeploymentId: productionDeploymentId,
      candidateSourceSha: sourceSha,
      rollbackDeploymentId,
      rollbackSourceSha: '3'.repeat(40),
      transitionReceiptId: '22222222-2222-4222-8222-222222222222',
      transitionReceiptSha256: '9'.repeat(64),
      transitionObservedAt: '2026-08-23T15:45:00.000Z',
      restorationReceiptId,
      restorationReceiptSha256: 'a'.repeat(64),
      restorationObservedAt: '2026-08-23T15:48:00.000Z',
      restoredDeploymentId: productionDeploymentId,
      restoredSourceSha: sourceSha,
    },
    supabaseMigrationChain: {
      authority: 'SUPABASE_PROVIDER',
      receiptId: '44444444-4444-4444-8444-444444444444',
      receiptSha256: 'b'.repeat(64),
      sourceSha,
      sourceTreeSha,
      sourceChainSha256: sourceMigrationChainSha256,
      expectedAppliedVersionChainSha256: appliedVersionChainSha256,
      appliedVersionChainSha256,
      observedAt: '2026-08-23T15:42:00.000Z',
    },
    androidArtifact: {
      authority: 'GITHUB_ACTIONS_PROVIDER',
      artifactName: 'pandora-android-apk',
      artifactId: 8080,
      packageName: 'com.banataosystems.pandora_mobile',
      apkSha256,
      githubArtifactDigestSha256: 'c'.repeat(64),
      sourceSha,
      sourceTreeSha,
      checkRunId: requiredChecks[4].checkRunId,
      checkSuiteId: requiredChecks[4].checkSuiteId,
      providerEvidenceRef: `provider-evidence:${'d'.repeat(64)}`,
    },
    physicalJourney: {
      authority: 'PHYSICAL_ANDROID_OBSERVER',
      storageAuthority: 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
      sourceSha,
      sourceTreeSha,
      productionDeploymentId,
      restorationReceiptId,
      apkSha256,
      wifi: {
        network: 'wifi',
        receiptId: '55555555-5555-4555-8555-555555555555',
        receiptSha256: 'e'.repeat(64),
        sourceSha,
        sourceTreeSha,
        productionDeploymentId,
        restorationReceiptId,
        apkSha256,
        observedAt: '2026-08-23T15:50:00.000Z',
        capturedAt: '2026-08-23T15:51:00.000Z',
      },
      mobileData: {
        network: 'mobile_data',
        receiptId: '66666666-6666-4666-8666-666666666666',
        receiptSha256: 'f'.repeat(64),
        sourceSha,
        sourceTreeSha,
        productionDeploymentId,
        restorationReceiptId,
        apkSha256,
        observedAt: '2026-08-23T15:53:00.000Z',
        capturedAt: '2026-08-23T15:54:00.000Z',
      },
    },
  };
  const receiptSha256 = canonicalReceiptPayloadSha256(payload);
  return {
    schemaVersion: '1.0.0',
    recordType: 'pilot',
    pilotId: 'BV-PILOT-0001',
    accountCode: 'BV-A-ACCT0001',
    observedAt: '2026-08-23T16:00:00.000Z',
    state: 'paid',
    scope: {
      locations: 1,
      workflows: 1,
      maxOperatingUsers: 3,
      liveMeasurementDays: 30,
      intakeMethodCode: 'owner_queue',
    },
    technicalGate: {
      passed: true,
      canonicalReceipt: {
        receiptId: '11111111-1111-4111-8111-111111111111',
        authority: CANONICAL_RECEIPT_AUTHORITY,
        providerEvidenceRef: `provider-evidence:${receiptSha256}`,
        receiptSha256,
        payload,
      },
    },
    commercialAuthorization: {
      ownerAuthorized: true,
      termsEvidenceRef: `approved-store:${'d'.repeat(32)}`,
    },
    price: { currency: 'PHP', amount: 15000, status: 'accepted' },
    payment: {
      state: 'paid',
      amount: 15000,
      providerEvidenceRef: `provider-evidence:${'e'.repeat(64)}`,
    },
    outcome: {
      activationState: 'not_started',
      eligibleAttempts: 0,
      successfulOutcomes: 0,
      failedOutcomes: 0,
      retries: 0,
      manualRescues: 0,
      supportMinutes: 0,
      continuationDecision: 'pending',
      customerDecisionEvidenceRef: null,
      evidenceRefs: [],
    },
    economics: {
      state: 'not_measured',
      currency: 'PHP',
      inferenceCost: null,
      runtimeCost: null,
      thirdPartyCost: null,
      variableSupportCost: null,
      evidenceRefs: [],
    },
    privacy,
  };
}

function trustedCanonicalStatusOptions(record) {
  const trusted = structuredClone(record.technicalGate.canonicalReceipt);
  return {
    verifyCanonicalStatusReceipt(candidate) {
      if (candidate.receiptId !== trusted.receiptId
        || candidate.receiptSha256 !== trusted.receiptSha256
        || candidate.providerEvidenceRef !== trusted.providerEvidenceRef) {
        return { verified: false };
      }
      return {
        verified: true,
        authority: trusted.authority,
        receiptId: trusted.receiptId,
        receiptSha256: trusted.receiptSha256,
        providerEvidenceRef: trusted.providerEvidenceRef,
        verifiedAt: trusted.payload.verifiedAt,
      };
    },
  };
}

function resealCanonicalReceipt(record) {
  const receipt = record.technicalGate.canonicalReceipt;
  receipt.receiptSha256 = canonicalReceiptPayloadSha256(receipt.payload);
  receipt.providerEvidenceRef = `provider-evidence:${receipt.receiptSha256}`;
  return record;
}

test('business-validation handoff is bound to current source truth without false commercial proof', () => {
  const provenance = json('SOURCE_PROVENANCE.json');
  const experiments = json('experiment-ledger.json');
  const handoff = text('CURRENT_HANDOFF.md');

  assert.equal(provenance.currentKnownTruth.main.sha, '5a630893f2102064dcb2c7c72a3374042e6b4542');
  assert.equal(provenance.currentKnownTruth.pullRequestTriage.denominator, 41);
  assert.equal(provenance.currentKnownTruth.pullRequestTriage.state, 'triage_decisions_complete');
  assert.equal(provenance.currentKnownTruth.production.sourceSha, 'bbfb769d475107badb5d7beafede6c775325e98a');
  assert.equal(provenance.currentKnownTruth.production.deploymentId, 'dpl_GCaZeb57HaEhCdGMDfDq9uMQQpPY');
  assert.equal(provenance.currentKnownTruth.production.replacementDeploymentRollbackBinding, 'pending_provider_readback');
  assert.equal(provenance.currentKnownTruth.physicalAndroidJourney.wifi, 'pending_exact_proof');
  assert.equal(provenance.currentKnownTruth.physicalAndroidJourney.mobileData, 'pending_exact_proof');

  assert.deepEqual(experiments.commercialProof, {
    problemValidation: 'not_currently_proven',
    willingnessToPay: 'not_currently_proven',
    paidPilot: 'not_currently_proven',
    retention: 'not_measurable',
    unitEconomics: 'not_measurable',
    currentExternalEvidenceState: 'unverified_operator_observation_zero_substantive_replies_offline_state_unknown',
  });
  assert.match(
    handoff,
    /Outbound\/customer-contact activity performed by this consolidation:\*\* none/,
  );
  assert.match(
    handoff,
    /Read-only provider activity:\*\* one operator-observed Gmail mailbox query/,
  );
  assert.match(
    handoff,
    /sent no message, contacted no customer, and produced no persisted opaque provider receipt/,
  );
  assert.match(handoff, /untested, unquoted, unaccepted, and not authorized/);
  assert.match(handoff, /dated commercial-evidence handoff/);
  assert.match(handoff, /authenticated `\/api\/operator\/status`/);
  assert.equal(provenance.snapshot.authority, 'dated_commercial_evidence_snapshot');
  assert.equal(provenance.snapshot.liveOperationalStatusAuthority, '/api/operator/status');
  assert.equal(provenance.currentKnownTruth.commercialReadbackAfterHistoricalSnapshot.authority, 'unverified_operator_observation');
  assert.equal(provenance.currentKnownTruth.commercialReadbackAfterHistoricalSnapshot.receiptState, 'opaque_provider_receipt_not_persisted');
});

test('PR 61 provenance remains exact and historical rather than current authority', () => {
  const provenance = json('SOURCE_PROVENANCE.json');
  assert.equal(provenance.historicalSource.pullRequest, 61);
  assert.equal(provenance.historicalSource.exactHead, '48dc181db42ed8459f604911b93a6339a1514059');
  assert.equal(provenance.historicalSource.authority, 'historical_evidence_only');

  const expected = new Map([
    ['COMMERCIAL_EVIDENCE_BASELINE.md', '2fa1f01f8c5702573823e92ecf06f6e977632f973fc7b2ced2e596031f80c446'],
    ['W8-E002-outreach-register.csv', 'aaabfeec0793988a2ae08a6bbbd63b7aaa407369c8121947b922fcc640406bfe'],
    ['experiment-ledger.csv', '5ad5b198d54985bd7412c5e81fa33b65d7cdaa33b5978fb42180b02d443cdfe4'],
    ['interview-evidence.schema.json', 'c57fbce993a4b687e57035207420af646af93ef23793119ad49408086773ed3d'],
    ['outcome-contribution-ledger.csv', '7f58535b0b1630594763a60ec96d5306690b24fb9bce3e9a07f788f0d4887688'],
    ['target-account-hypotheses.csv', 'f86796518dc5f9a78e9067ca7c8080e3c20764adec9e840a5af8db83023ada19'],
    ['ARTIFACT_MANIFEST.sha256', '9eb50af4c0b8bbf0bcabe603c9bccc634b0c2542681bf5ed2c84870cd7c46e38'],
  ]);
  assert.equal(provenance.historicalSource.artifacts.length, expected.size);
  for (const artifact of provenance.historicalSource.artifacts) {
    assert.equal(artifact.sha256, expected.get(path.basename(artifact.path)));
  }
});

test('historical outreach is complete, de-identified, and cannot imply a current reply', () => {
  const ledger = json('historical-outreach-ledger.json');
  const records = ledger.records;
  assert.equal(ledger.authority, 'historical_evidence_only');
  assert.equal(records.length, 11);
  assert.equal(new Set(records.map((record) => record.accountCode)).size, 11);
  assert.equal(records.filter((record) => record.outreachObservation === 'INVITATION_SENT').length, 10);
  assert.equal(records.filter((record) => record.deliveryObservation === 'HARD_BOUNCE_550_5_1_1').length, 1);
  assert.equal(records.filter((record) => record.interviewObservation === 'AWAITING_SUBSTANTIVE_REPLY').length, 10);
  assert.equal(ledger.summaryAtSnapshot.replacementAttempts, 1);
  assert.equal(ledger.summaryAtSnapshot.substantiveRepliesObserved, 0);
  assert.equal(ledger.summaryAtSnapshot.completedInterviewsObserved, 0);
  assert.equal(ledger.currentState.replyState, 'unverified_operator_observation_zero_substantive_replies');
  assert.equal(ledger.currentState.receiptState, 'opaque_provider_receipt_not_persisted');
  assert.equal(ledger.currentState.offlineInterviewState, 'unknown');
  assert.equal(ledger.currentState.labeledThreadsRead, 11);
  assert.equal(ledger.currentState.automatedHardBounceResponses, 1);

  const allowedKeys = [
    'accountCode',
    'deliveryObservation',
    'evidenceLevel',
    'interviewObservation',
    'outreachObservation',
    'providerEvidenceDigest',
    'subsegment',
  ];
  for (const record of records) {
    assert.deepEqual(Object.keys(record).sort(), allowedKeys);
    assert.match(record.accountCode, /^W8-TA-[0-9]{3}$/);
    assert.match(record.providerEvidenceDigest, /^[0-9a-f]{64}$/);
  }
  assert.doesNotMatch(JSON.stringify(records), /publicBusinessName|sourceUrl|mailbox|messageBody|freeTextNotes/i);
  assert.doesNotMatch(JSON.stringify(records), /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
});

test('current experiments keep interviews, offers, and payments unclaimed and gated', () => {
  const experiments = json('experiment-ledger.json').experiments;
  const interviews = experiments.find((entry) => entry.id === 'BV-E001');
  const offer = experiments.find((entry) => entry.id === 'BV-E002');
  const pilot = experiments.find((entry) => entry.id === 'BV-E003');

  assert.equal(interviews.currentKitRecords, 0);
  assert.equal(interviews.externalOrOfflineState, 'zero_email_replies_observed_offline_interviews_unknown');
  assert.equal(interviews.sampleTarget, 10);
  assert.equal(offer.state, 'blocked');
  assert.equal(offer.currentKitOfferRecords, 0);
  assert.equal(offer.startingPriceHypothesis.status, 'untested_unquoted_unauthorized');
  assert.ok(offer.blockedBy.includes('physical_android_wifi_and_mobile_data_proof'));
  assert.equal(pilot.state, 'not_started');
  assert.equal(pilot.currentKitPaymentRecords, 0);
  assert.equal(pilot.externalOrOfflineState, 'unknown_not_read_back');
});

test('evidence schema excludes raw customer material and binds paid claims to proof', () => {
  const schema = json('evidence.schema.json');
  const interview = schema.$defs.interview;
  const pilot = schema.$defs.pilot;
  const privacy = schema.$defs.privacyFlags;

  assert.equal(interview.additionalProperties, false);
  assert.equal(interview.properties.consentState.const, 'documented');
  assert.equal(interview.properties.recentWorkflowWindowDays.maximum, 30);
  assert.equal(pilot.additionalProperties, false);
  assert.ok(pilot.required.includes('economics'));
  assert.equal(pilot.properties.scope.properties.locations.const, 1);
  assert.equal(pilot.properties.scope.properties.workflows.const, 1);
  assert.equal(pilot.properties.scope.properties.maxOperatingUsers.maximum, 5);
  assert.equal(pilot.properties.scope.properties.liveMeasurementDays.maximum, 30);
  assert.deepEqual(pilot.properties.technicalGate.required, ['passed', 'canonicalReceipt']);
  const canonicalReceipt = schema.$defs.canonicalStatusReleaseReceipt;
  assert.equal(canonicalReceipt.additionalProperties, false);
  assert.equal(canonicalReceipt.properties.authority.const, 'AUTHENTICATED_CANONICAL_STATUS');
  assert.equal(canonicalReceipt.properties.providerEvidenceRef.$ref, '#/$defs/providerBackedEvidenceRef');
  const canonicalPayload = canonicalReceipt.properties.payload;
  assert.equal(canonicalPayload.properties.authoritative.const, true);
  assert.equal(canonicalPayload.properties.status.const, 'current');
  assert.ok(canonicalPayload.required.includes('verifiedAt'));
  assert.deepEqual(
    canonicalPayload.properties.requiredChecks.prefixItems.map((item) => item.allOf[1].properties.name.const),
    REQUIRED_CHECKS.map((check) => check.name),
  );
  assert.deepEqual(
    canonicalPayload.properties.requiredChecks.prefixItems.map(
      (item) => item.allOf[1].properties.providerContext.const,
    ),
    REQUIRED_CHECKS.map((check) => check.providerContext),
  );
  assert.equal(canonicalPayload.properties.requiredChecks.items, false);
  assert.ok(canonicalPayload.required.includes('independentReview'));
  assert.ok(canonicalPayload.required.includes('rollbackRehearsal'));
  assert.ok(canonicalPayload.required.includes('supabaseMigrationChain'));
  assert.ok(canonicalPayload.required.includes('androidArtifact'));
  assert.ok(canonicalPayload.required.includes('physicalJourney'));
  for (const flag of privacy.required) assert.equal(privacy.properties[flag].const, false);

  const serializedPaymentRules = JSON.stringify(pilot.properties.payment.allOf);
  const serializedPilotRules = JSON.stringify(pilot.allOf);
  assert.match(serializedPaymentRules, /providerEvidenceRef/);
  assert.match(serializedPaymentRules, /exclusiveMinimum/);
  assert.match(serializedPilotRules, /ownerAuthorized/);
  assert.match(serializedPilotRules, /passed/);
  assert.match(schema.$defs.opaqueEvidenceRef.pattern, /approved-store/);
  assert.doesNotMatch(schema.$defs.opaqueEvidenceRef.pattern, /[@#/:].*\{1,300\}/);
  assert.match(schema.$defs.providerBackedEvidenceRef.pattern, /provider-evidence/);
  assert.doesNotMatch(schema.$defs.providerBackedEvidenceRef.pattern, /sha256:/);
  assert.doesNotMatch(schema.$defs.providerBackedEvidenceRef.pattern, /approved-store/);

  const validateSchema = new Ajv2020({ strict: false, validateFormats: false }).compile(schema);
  const validPilot = paidPilotEvidence();
  assert.equal(validateSchema(validPilot), true, JSON.stringify(validateSchema.errors));

  const duplicateCheck = structuredClone(validPilot);
  duplicateCheck.technicalGate.canonicalReceipt.payload.requiredChecks[1] = structuredClone(
    duplicateCheck.technicalGate.canonicalReceipt.payload.requiredChecks[0],
  );
  assert.equal(validateSchema(duplicateCheck), false);

  const wrongExternalProvider = structuredClone(validPilot);
  wrongExternalProvider.technicalGate.canonicalReceipt.payload.requiredChecks[1].providerContext = 'Vercel Agent Review';
  assert.equal(validateSchema(wrongExternalProvider), false);

  const missingRestoration = structuredClone(validPilot);
  delete missingRestoration.technicalGate.canonicalReceipt.payload.rollbackRehearsal.restorationReceiptId;
  assert.equal(validateSchema(missingRestoration), false);

  const hiddenPaidClaim = structuredClone(validPilot);
  hiddenPaidClaim.state = 'draft';
  hiddenPaidClaim.technicalGate = { passed: false, canonicalReceipt: null };
  hiddenPaidClaim.commercialAuthorization = { ownerAuthorized: false, termsEvidenceRef: null };
  assert.equal(validateSchema(hiddenPaidClaim), false);
});

test('paid-pilot runtime validation requires exact technical and commercial proof', () => {
  const valid = paidPilotEvidence();
  const trustedOptions = trustedCanonicalStatusOptions(valid);
  assert.equal(validateBusinessValidationEvidence(valid, trustedOptions), valid);

  assert.throws(
    () => validateBusinessValidationEvidence(structuredClone(valid)),
    /trusted authenticated canonical-status verifier required/,
  );

  const hiddenPaidClaim = structuredClone(valid);
  hiddenPaidClaim.state = 'draft';
  hiddenPaidClaim.technicalGate = { passed: false, canonicalReceipt: null };
  hiddenPaidClaim.commercialAuthorization = { ownerAuthorized: false, termsEvidenceRef: null };
  assert.throws(
    () => validateBusinessValidationEvidence(hiddenPaidClaim),
    /technicalGate\.passed: must be true/,
  );

  const forgedIdentity = structuredClone(valid);
  forgedIdentity.technicalGate.canonicalReceipt.receiptId = '99999999-9999-4999-8999-999999999999';
  assert.throws(
    () => validateBusinessValidationEvidence(forgedIdentity, trustedOptions),
    /did not verify this exact receipt identity and digest/,
  );

  const rejected = [
    [
      (record) => { [record.technicalGate.canonicalReceipt.payload.requiredChecks[0], record.technicalGate.canonicalReceipt.payload.requiredChecks[1]] = [record.technicalGate.canonicalReceipt.payload.requiredChecks[1], record.technicalGate.canonicalReceipt.payload.requiredChecks[0]]; },
      /exact successful provider check binding required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.productionDeployment.sourceSha = '6'.repeat(40); },
      /exact source\/deployment provider binding required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.rollbackRehearsal.rollbackDeploymentId = record.technicalGate.canonicalReceipt.payload.productionDeployment.deploymentId; },
      /distinct rollback and exact candidate restoration receipt required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.physicalJourney.restorationReceiptId = '88888888-8888-4888-8888-888888888888'; },
      /journey must bind restored production/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.supabaseMigrationChain.appliedVersionChainSha256 = '7'.repeat(64); },
      /matching expected\/provider-applied version-chain receipt required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.physicalJourney.mobileData.apkSha256 = '6'.repeat(64); },
      /exact physical mobile_data receipt binding required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.independentReview.sourceTreeSha = '6'.repeat(40); },
      /exact independent-review receipt binding required/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.expiresAt = '2026-08-23T15:59:59.000Z'; },
      /stale or out-of-order/,
    ],
    [
      (record) => { record.technicalGate.canonicalReceipt.payload.physicalJourney.wifi.observedAt = '2026-08-23T15:47:00.000Z'; },
      /stale or out-of-order/,
    ],
    [
      (record) => { record.commercialAuthorization.termsEvidenceRef = null; },
      /accepted owner terms proof required/,
    ],
    [
      (record) => { record.price.amount = 0; },
      /paid pilot price must be positive/,
    ],
    [
      (record) => { record.payment.state = 'requested'; },
      /requires paid state/,
    ],
    [
      (record) => { record.payment.providerEvidenceRef = `sha256:${'f'.repeat(64)}`; },
      /provider-backed paid receipt required/,
    ],
    [
      (record) => { record.payment.providerEvidenceRef = 'approved-store:payment-receipt'; },
      /provider-backed paid receipt required/,
    ],
  ];

  for (const [mutate, expected] of rejected) {
    const candidate = structuredClone(valid);
    mutate(candidate);
    resealCanonicalReceipt(candidate);
    assert.throws(
      () => validateBusinessValidationEvidence(candidate, trustedCanonicalStatusOptions(candidate)),
      expected,
    );
  }
});

test('business evidence privacy linter rejects contact material and non-opaque refs', () => {
  const emailLeak = paidPilotEvidence();
  emailLeak.outcome.summary = 'Send the receipt to person@example.com';
  assert.match(findEvidencePrivacyLeaks(emailLeak).join('\n'), /email address detected/);
  assert.throws(() => validateBusinessValidationEvidence(emailLeak), /email address detected/);

  const phoneLeak = paidPilotEvidence();
  phoneLeak.contactPhone = '+63 917 555 0123';
  assert.throws(() => validateBusinessValidationEvidence(phoneLeak), /phone number detected/);

  const unsafeRef = paidPilotEvidence();
  unsafeRef.commercialAuthorization.termsEvidenceRef = 'approved-store:person@example.com';
  assert.throws(
    () => validateBusinessValidationEvidence(unsafeRef),
    /must be an opaque evidence reference/,
  );
});

test('business-validation manifest covers every durable kit artifact exactly', () => {
  const manifestLines = text('ARTIFACT_MANIFEST.sha256').trim().split(/\r?\n/);
  const entries = new Map(manifestLines.map((line) => {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$/.exec(line);
    assert.ok(match, `invalid manifest line: ${line}`);
    return [match[2], match[1]];
  }));
  const expectedFiles = [
    'CURRENT_HANDOFF.md',
    'SOURCE_PROVENANCE.json',
    'evidence.schema.json',
    'experiment-ledger.json',
    'historical-outreach-ledger.json',
  ];
  assert.deepEqual([...entries.keys()].sort(), expectedFiles);
  assert.deepEqual(
    readdirSync(KIT).sort(),
    ['ARTIFACT_MANIFEST.sha256', ...expectedFiles].sort(),
  );
  for (const name of expectedFiles) assert.equal(entries.get(name), sha256(name));
});
