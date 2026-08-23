const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');
const Ajv2020 = require('ajv/dist/2020').default;
const addFormats = require('ajv-formats').default;

const {
  buildCanonicalStatusPack,
  canonicalStatusHash,
  canonicalStatusSemanticsValid,
  refreshCanonicalStatusPack,
} = require('../dist/projectos/canonical-status-pack.js');
const {
  GITHUB_ACTIONS_APP_ID,
  REQUIRED_CHECK_IDENTITIES,
  REPOSITORY_CHECK_IDENTITIES,
  REQUIRED_CHECK_WORKFLOW_PATHS,
  evaluateSupabaseReceiptBinding,
  readAllGitHubPulls,
  readGitHubStatus,
  readMobileArtifactProviderReadback,
  readSourceArtifactProviderReadback,
} = require('../dist/projectos/canonical-status-provider.js');
const registry = require('../docs/status/OPEN_PR_TRIAGE.json');

const MAIN_SHA = '5a630893f2102064dcb2c7c72a3374042e6b4542';
const TREE_SHA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const AUTHORITY_HASH = 'b'.repeat(64);
const HISTORICAL_HASH = 'c'.repeat(64);
const SOURCE_ARTIFACT_ID = '123456789';
const SOURCE_ARTIFACT_SHA256 = '7'.repeat(64);
const MOBILE_ARTIFACT_ID = '987654321';
const MOBILE_ARTIFACT_SHA256 = 'c'.repeat(64);
const MOBILE_APK_SHA256 = 'd'.repeat(64);
const TRUSTED_EXTERNAL_REVIEW_APP_ID = 424242;
const statusSchema = JSON.parse(readFileSync(
  require.resolve('../docs/status/CANONICAL_STATUS_PACK.schema.json'),
  'utf8',
));
const statusSchemaAjv = new Ajv2020({
  strict: true,
  strictTuples: false,
  allowUnionTypes: true,
});
addFormats(statusSchemaAjv);
const validateStatusSchema = statusSchemaAjv.compile(statusSchema);

function triage() {
  return structuredClone(registry);
}

function evidence() {
  return {
    memory: {
      ok: true,
      healthStatus: 'projectos-connected',
      contextState: 'healthy',
      fresh: true,
      approvedRecordIds: ['record-1'],
      conflicts: [],
    },
    github: {
      ok: true,
      repository: 'banataosystems/Pandoras-box',
      mainSha: MAIN_SHA,
      mainTreeSha: TREE_SHA,
      openPullRequestCount: 2,
      triageInventoryCount: 41,
      triageExactHeadMatches: true,
      exactIntegrationChecks: 'success',
      protectionHasExactCheckIdentities: true,
      protectedMainPolicyExact: true,
      trustedExternalReviewConfigured: true,
      trustedExternalReviewAppId: TRUSTED_EXTERNAL_REVIEW_APP_ID,
      trustedExternalReviewVerified: true,
      sourceArtifactProviderReadback: {
        verified: true,
        provider: 'github',
        observedAt: '2026-08-23T13:49:00.000Z',
        artifactId: SOURCE_ARTIFACT_ID,
        artifactUrl: `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${SOURCE_ARTIFACT_ID}`,
        artifactName: `canonical-release-source-${MAIN_SHA}`,
        artifactSha256: SOURCE_ARTIFACT_SHA256,
        runId: 9001,
        runAttempt: 1,
        workflowId: 7001,
        workflowPath: '.github/workflows/canonical-release-evidence.yml',
        event: 'push',
        jobId: 6001,
        checkRunId: 5001,
        checkSuiteId: 8001,
        sourceSha: MAIN_SHA,
        sourceTreeSha: TREE_SHA,
      },
      mobileArtifactProviderReadback: {
        verified: true,
        provider: 'github',
        observedAt: '2026-08-23T13:56:00.000Z',
        artifactId: MOBILE_ARTIFACT_ID,
        artifactUrl: `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${MOBILE_ARTIFACT_ID}`,
        artifactName: `pandora-mobile-android-validation-${MAIN_SHA}`,
        artifactSha256: MOBILE_ARTIFACT_SHA256,
        apkSha256: MOBILE_APK_SHA256,
        artifactCreatedAt: '2026-08-23T13:30:00.000Z',
        artifactExpiresAt: '2026-09-06T13:30:00.000Z',
        runId: 9002,
        runAttempt: 1,
        runCompletedAt: '2026-08-23T13:34:00.000Z',
        workflowId: 7002,
        workflowPath: '.github/workflows/pandora-mobile-integration.yml',
        event: 'push',
        jobId: 6002,
        checkRunId: 5002,
        checkSuiteId: 8002,
        sourceSha: MAIN_SHA,
        sourceTreeSha: TREE_SHA,
        productionOrigin: 'https://mcpmaster.vercel.app',
        receiptCapturedAt: '2026-08-23T13:55:00.000Z',
      },
    },
    vercel: {
      ok: true,
      providerReadback: true,
      gitRepository: 'banataosystems/Pandoras-box',
      sourceSha: MAIN_SHA,
      deploymentId: 'dpl_current',
      rollbackDeploymentId: 'dpl_rollback',
      rollbackSourceSha: 'f'.repeat(40),
      rollbackVerified: true,
      rollbackVerifiedCandidateDeploymentId: 'dpl_current',
      rollbackRestoredDeploymentId: 'dpl_current',
      productionObservedAt: '2026-08-23T13:35:00.000Z',
      rollbackTransitionEvidenceId: '33333333-3333-4333-8333-333333333333',
      rollbackTransitionExternalId: 'dpl_rollback',
      rollbackTransitionSourceUrl: 'https://api.vercel.com/v13/deployments/dpl_rollback?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
      rollbackTransitionAliasSourceUrl: 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
      rollbackTransitionAliasPreResponseSha256: '1'.repeat(64),
      rollbackTransitionAliasPreObservedAt: '2026-08-23T13:40:00.000Z',
      rollbackTransitionRouteProbeContract: 'canonical_routes_v1',
      rollbackTransitionRouteProbeSha256: '2'.repeat(64),
      rollbackTransitionRouteProbeObservedAt: '2026-08-23T13:41:00.000Z',
      rollbackTransitionAliasPostResponseSha256: '3'.repeat(64),
      rollbackTransitionAliasPostObservedAt: '2026-08-23T13:42:00.000Z',
      rollbackTransitionObservedAt: '2026-08-23T13:43:00.000Z',
      rollbackRestorationEvidenceId: '44444444-4444-4444-8444-444444444444',
      rollbackRestorationExternalId: 'dpl_current',
      rollbackRestorationSourceUrl: 'https://api.vercel.com/v13/deployments/dpl_current?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
      rollbackRestorationAliasSourceUrl: 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
      rollbackRestorationAliasPreResponseSha256: '4'.repeat(64),
      rollbackRestorationAliasPreObservedAt: '2026-08-23T13:45:00.000Z',
      rollbackRestorationRouteProbeContract: 'canonical_routes_v1',
      rollbackRestorationRouteProbeSha256: '5'.repeat(64),
      rollbackRestorationRouteProbeObservedAt: '2026-08-23T13:46:00.000Z',
      rollbackRestorationAliasPostResponseSha256: '6'.repeat(64),
      rollbackRestorationAliasPostObservedAt: '2026-08-23T13:47:00.000Z',
      rollbackRestorationObservedAt: '2026-08-23T13:48:00.000Z',
      productionAlias: 'mcpmaster.vercel.app',
      productionAliasSourceUrl: 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
      productionAliasLiveRead: true,
      productionTarget: 'production',
      productionVerified: true,
      productionVerifiedDeploymentId: 'dpl_current',
    },
    supabase: {
      ok: true,
      projectStatus: 'ACTIVE_HEALTHY',
      managementApiVersionReadback: true,
      providerDatabaseReceiptReadback: true,
      sourceArtifactDatabaseReceiptPresent: true,
      sourceArtifactBoundToLiveVersions: true,
      exactAppliedBytesProven: false,
      providerReadback: false,
      sourceSha: MAIN_SHA,
      migrationVersionParity: 'match',
      migrationByteParity: 'not_provider_reconstructable',
      migrationParity: 'source_artifact_bound_to_live_versions',
      expectedSourceChainSha256: 'e'.repeat(64),
      sourceArtifactChainSha256: 'e'.repeat(64),
      sourceArtifactExternalId: SOURCE_ARTIFACT_ID,
      sourceArtifactSha256: SOURCE_ARTIFACT_SHA256,
      sourceArtifactSourceTreeSha: TREE_SHA,
      expectedAppliedChainSha256: '8'.repeat(64),
      appliedChainSha256: '8'.repeat(64),
      providerDatabaseCapturedVersionChainSha256: '8'.repeat(64),
    },
    android: {
      ok: true,
      authority: 'PHYSICAL_ANDROID_OBSERVER',
      storageAuthority: 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
      providerReadback: true,
      sourceSha: MAIN_SHA,
      sourceTreeSha: TREE_SHA,
      deploymentId: 'dpl_current',
      artifactSha256: MOBILE_APK_SHA256,
      productionOrigin: 'https://mcpmaster.vercel.app',
      ciArtifactDatabaseReceipt: {
        databaseCaptured: true,
        storageAuthority: 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
        externalId: MOBILE_ARTIFACT_ID,
        sourceUrl: `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${MOBILE_ARTIFACT_ID}`,
        artifactName: `pandora-mobile-android-validation-${MAIN_SHA}`,
        artifactSha256: MOBILE_ARTIFACT_SHA256,
        apkSha256: MOBILE_APK_SHA256,
        sourceSha: MAIN_SHA,
        sourceTreeSha: TREE_SHA,
        productionOrigin: 'https://mcpmaster.vercel.app',
        wifiEvidenceId: '11111111-1111-4111-8111-111111111111',
        mobileDataEvidenceId: '22222222-2222-4222-8222-222222222222',
        capturedAt: '2026-08-23T13:55:00.000Z',
      },
      deviceIdHash: '9'.repeat(64),
      packageName: 'com.banataosystems.pandora_mobile',
      ownerPlanId: '88888888-8888-4888-8888-888888888888',
      ownerDispatchId: '99999999-9999-4999-8999-999999999999',
      workerEvidenceSha256: '1'.repeat(64),
      verificationEvidenceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      reviewerRuntimeProofId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      wifi: {
        network: 'wifi',
        verified: true,
        receiptId: '11111111-1111-4111-8111-111111111111',
        receiptSha256: '2'.repeat(64),
        observerId: 'physical-android-01',
        observerKeyFingerprint: '3'.repeat(64),
        signatureBasisSha256: '4'.repeat(64),
        providerObservationIndex: 1,
        observedAt: '2026-08-23T13:50:00.000Z',
        capturedAt: '2026-08-23T13:50:10.000Z',
        artifactSha256: MOBILE_APK_SHA256,
        completedSteps: [
          'owner_authenticate',
          'submit_owner_command',
          'observe_durable_dispatch',
          'observe_worker_01_claim',
          'observe_exact_provider_result',
          'observe_proof_in_owner_read',
        ],
      },
      mobileData: {
        network: 'mobile_data',
        verified: true,
        receiptId: '22222222-2222-4222-8222-222222222222',
        receiptSha256: '5'.repeat(64),
        observerId: 'physical-android-01',
        observerKeyFingerprint: '3'.repeat(64),
        signatureBasisSha256: '6'.repeat(64),
        providerObservationIndex: 2,
        observedAt: '2026-08-23T13:55:00.000Z',
        capturedAt: '2026-08-23T13:55:00.000Z',
        artifactSha256: MOBILE_APK_SHA256,
        completedSteps: [
          'owner_authenticate',
          'submit_owner_command',
          'observe_durable_dispatch',
          'observe_worker_01_claim',
          'observe_exact_provider_result',
          'observe_proof_in_owner_read',
        ],
      },
    },
    independentReview: {
      ok: true,
      verified: true,
      authority: 'INDEPENDENT_REVIEWER',
      receiptId: '55555555-5555-4555-8555-555555555555',
      receiptSha256: 'a'.repeat(64),
      sourceSha: MAIN_SHA,
      sourceTreeSha: TREE_SHA,
      productionDeploymentId: 'dpl_current',
      rollbackDeploymentId: 'dpl_rollback',
      supabaseMigrationChainSha256: 'e'.repeat(64),
      reviewerKeyFingerprint: 'b'.repeat(64),
      reviewedAt: '2026-08-23T13:56:00.000Z',
      capturedAt: '2026-08-23T13:56:10.000Z',
    },
    ownerAuthorization: {
      ok: true,
      verified: true,
      authority: 'OWNER_AUTHORIZATION',
      receiptId: '66666666-6666-4666-8666-666666666666',
      ownerUserId: '77777777-7777-4777-8777-777777777777',
      sourceSha: MAIN_SHA,
      productionDeploymentId: 'dpl_current',
      reviewReceiptId: '55555555-5555-4555-8555-555555555555',
      reviewReceiptSha256: 'a'.repeat(64),
      authorizedAt: '2026-08-23T13:57:00.000Z',
      capturedAt: '2026-08-23T13:57:10.000Z',
      aal: 'aal2',
      sessionId: '88888888-8888-4888-8888-888888888888',
      mfaVerifiedAt: '2026-08-23T13:56:45.000Z',
    },
  };
}

test('canonical status becomes authoritative only when every exact proof binds', () => {
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: evidence(),
  });

  assert.equal(pack.authoritative, true);
  assert.equal(pack.status, 'current');
  assert.deepEqual(pack.proofLadder, {
    documented: true,
    implemented: true,
    tested: true,
    deployed: true,
    productionVerified: true,
  });
  assert.deepEqual(pack.progress, { completed: 5, total: 5, percent: 100 });
  assert.equal(pack.canonicalJsonSha256, canonicalStatusHash(pack));
  assert.equal(validateStatusSchema(pack), true, JSON.stringify(validateStatusSchema.errors));
  assert.equal(canonicalStatusSemanticsValid(pack), true);
  assert.deepEqual(
    pack.goals.map(({ id, state }) => ({ id, state })),
    [
      { id: 'canonical-status', state: 'complete' },
      { id: 'pr-triage-41', state: 'complete' },
      { id: 'owner-worker-clean-main', state: 'complete' },
      { id: 'exact-release-binding', state: 'complete' },
      { id: 'physical-android', state: 'complete' },
      { id: 'commercial-pilot', state: 'ready' },
    ],
  );
});

test('canonical status schema and semantic verifier reject forged current truth', () => {
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: evidence(),
  });

  const contradictory = structuredClone(pack);
  contradictory.blockers.push('forged-blocker');
  contradictory.canonicalJsonSha256 = canonicalStatusHash(contradictory);
  assert.equal(validateStatusSchema(contradictory), false);

  const incompleteProof = structuredClone(pack);
  incompleteProof.proofLadder.tested = false;
  incompleteProof.canonicalJsonSha256 = canonicalStatusHash(incompleteProof);
  assert.equal(validateStatusSchema(incompleteProof), false);

  const malformedAuthority = structuredClone(pack);
  malformedAuthority.authority = 'self-authored';
  malformedAuthority.canonicalJsonSha256 = canonicalStatusHash(malformedAuthority);
  assert.equal(validateStatusSchema(malformedAuthority), false);

  const contradictoryEvidence = structuredClone(pack);
  contradictoryEvidence.evidence.github.exactIntegrationChecks = 'failure';
  contradictoryEvidence.canonicalJsonSha256 = canonicalStatusHash(contradictoryEvidence);
  assert.equal(validateStatusSchema(contradictoryEvidence), false);

  const wrongTriage = structuredClone(pack);
  wrongTriage.pullRequests.observedRegistryItems = 40;
  wrongTriage.canonicalJsonSha256 = canonicalStatusHash(wrongTriage);
  assert.equal(validateStatusSchema(wrongTriage), false);

  const hiddenField = structuredClone(pack);
  hiddenField.releaseReady = true;
  hiddenField.canonicalJsonSha256 = canonicalStatusHash(hiddenField);
  assert.equal(validateStatusSchema(hiddenField), false);

  const reversedExpiry = structuredClone(pack);
  reversedExpiry.expiresAt = '2026-08-23T13:59:59.000Z';
  reversedExpiry.canonicalJsonSha256 = canonicalStatusHash(reversedExpiry);
  assert.equal(canonicalStatusSemanticsValid(reversedExpiry), false);

  const forgedHash = structuredClone(pack);
  forgedHash.canonicalJsonSha256 = '0'.repeat(64);
  assert.equal(canonicalStatusSemanticsValid(forgedHash), false);
});

test('source/deployment mismatch is conflicted and cannot inherit later proof', () => {
  const conflicted = evidence();
  conflicted.vercel.sourceSha = 'd'.repeat(40);
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: conflicted,
  });

  assert.equal(pack.authoritative, false);
  assert.equal(pack.status, 'conflicted');
  assert.equal(pack.proofLadder.deployed, false);
  assert.equal(pack.proofLadder.productionVerified, false);
  assert.deepEqual(pack.conflicts.map((entry) => entry.id), ['source-deployment-sha-mismatch']);
});

test('missing rollback and unverified migrations remain explicit blockers', () => {
  const incomplete = evidence();
  incomplete.vercel.rollbackDeploymentId = null;
  incomplete.supabase.migrationParity = 'unverified';
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: incomplete,
  });

  assert.equal(pack.status, 'stale');
  assert.ok(pack.blockers.includes('supabase-migration-parity-unverified'));
  assert.ok(pack.blockers.includes('vercel-source-deployment-rollback-binding-unproven'));
});

test('failed exact-integration checks can never produce an authoritative pack', () => {
  const failed = evidence();
  failed.github.exactIntegrationChecks = 'failure';
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: failed,
  });

  assert.equal(pack.proofLadder.tested, false);
  assert.equal(pack.authoritative, false);
  assert.ok(pack.blockers.includes('github-exact-integration-checks-not-green'));
});

test('weakened protected-main policy can never satisfy the tested gate', () => {
  const weakened = evidence();
  weakened.github.protectedMainPolicyExact = false;
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: weakened,
  });

  assert.equal(pack.proofLadder.tested, false);
  assert.equal(pack.authoritative, false);
  assert.ok(pack.blockers.includes('github-protected-main-policy-not-exact'));
});

test('trusted external review is separate from candidate-controlled GitHub Actions', () => {
  const unconfigured = evidence();
  unconfigured.github.trustedExternalReviewConfigured = false;
  unconfigured.github.trustedExternalReviewAppId = null;
  unconfigured.github.trustedExternalReviewVerified = false;
  const unconfiguredPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: unconfigured,
  });
  assert.equal(unconfiguredPack.proofLadder.tested, false);
  assert.ok(unconfiguredPack.blockers.includes(
    'github-trusted-external-review-authority-unconfigured',
  ));

  const actionsSpoof = evidence();
  actionsSpoof.github.trustedExternalReviewAppId = GITHUB_ACTIONS_APP_ID;
  const spoofedPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: actionsSpoof,
  });
  assert.equal(spoofedPack.proofLadder.tested, false);
  assert.ok(spoofedPack.blockers.includes('github-trusted-external-review-not-green'));
});

test('deployment authority requires fresh GitHub source-artifact provider readback', () => {
  const missing = evidence();
  missing.github.sourceArtifactProviderReadback = {
    verified: false,
    provider: 'github',
    reason: 'provider_read_unavailable',
  };
  const missingPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: missing,
  });
  assert.equal(missingPack.proofLadder.tested, true);
  assert.equal(missingPack.proofLadder.deployed, false);
  assert.ok(missingPack.blockers.includes('github-source-artifact-provider-readback-unverified'));

  const digestMismatch = evidence();
  digestMismatch.github.sourceArtifactProviderReadback.artifactSha256 = '6'.repeat(64);
  const mismatchPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: digestMismatch,
  });
  assert.equal(mismatchPack.proofLadder.deployed, false);
});

test('proof stages are monotonic and cannot skip a missing authority document', () => {
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: null,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: evidence(),
  });

  assert.deepEqual(pack.proofLadder, {
    documented: false,
    implemented: false,
    tested: false,
    deployed: false,
    productionVerified: false,
  });
  assert.equal(pack.authoritative, false);
});

test('rollback and production deployments must be distinct', () => {
  const duplicated = evidence();
  duplicated.vercel.rollbackDeploymentId = duplicated.vercel.deploymentId;
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: duplicated,
  });

  assert.equal(pack.proofLadder.deployed, false);
  assert.equal(pack.authoritative, false);
});

test('Vercel cannot self-attest the physical Android journey', () => {
  const missingDevice = evidence();
  missingDevice.android.providerReadback = false;
  const pack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: missingDevice,
  });

  assert.equal(pack.proofLadder.productionVerified, false);
  assert.equal(pack.authoritative, false);
  assert.ok(pack.blockers.includes('physical-android-wifi-mobile-data-proof-unverified'));
});

test('physical Android proof requires the fresh exact GitHub mobile artifact', () => {
  const missingArtifact = evidence();
  missingArtifact.github.mobileArtifactProviderReadback = {
    verified: false,
    provider: 'github',
    reason: 'provider_read_unavailable',
  };
  const missingPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: missingArtifact,
  });
  assert.equal(missingPack.proofLadder.deployed, true);
  assert.equal(missingPack.proofLadder.productionVerified, false);
  assert.ok(missingPack.blockers.includes('github-mobile-artifact-provider-readback-unverified'));

  const wrongApk = evidence();
  wrongApk.github.mobileArtifactProviderReadback.apkSha256 = '0'.repeat(64);
  const wrongApkPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: wrongApk,
  });
  assert.equal(wrongApkPack.proofLadder.productionVerified, false);
});

test('mutable legacy Android evidence and unordered networks are never release authority', () => {
  const legacy = evidence();
  delete legacy.android.storageAuthority;
  delete legacy.android.ciArtifactDatabaseReceipt.storageAuthority;
  const legacyPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: legacy,
  });
  assert.equal(legacyPack.authoritative, false);
  assert.equal(legacyPack.proofLadder.productionVerified, false);

  const unordered = evidence();
  unordered.android.mobileData.observedAt =
    unordered.android.wifi.observedAt;
  const unorderedPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: unordered,
  });
  assert.equal(unorderedPack.authoritative, false);
  assert.equal(unorderedPack.proofLadder.productionVerified, false);
});

test('final review and AAL2 owner authorization are exact post-journey gates', () => {
  const staleReview = evidence();
  staleReview.independentReview.reviewedAt = '2026-08-23T13:54:00.000Z';
  const staleReviewPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: staleReview,
  });
  assert.equal(staleReviewPack.proofLadder.productionVerified, false);
  assert.ok(staleReviewPack.blockers.includes('independent-review-receipt-unverified'));

  const wrongOwnerBinding = evidence();
  wrongOwnerBinding.ownerAuthorization.reviewReceiptSha256 = '0'.repeat(64);
  const wrongOwnerPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: wrongOwnerBinding,
  });
  assert.equal(wrongOwnerPack.authoritative, false);
  assert.ok(wrongOwnerPack.blockers.includes('owner-authorization-receipt-unverified'));

  const staleMfa = evidence();
  staleMfa.ownerAuthorization.mfaVerifiedAt = '2026-08-23T13:51:59.000Z';
  const staleMfaPack = buildCanonicalStatusPack({
    generatedAt: '2026-08-23T14:00:00.000Z',
    expiresAt: '2026-08-23T14:05:00.000Z',
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    evidence: staleMfa,
  });
  assert.equal(staleMfaPack.authoritative, false);
  assert.ok(staleMfaPack.blockers.includes('owner-authorization-receipt-unverified'));
});

test('provider failures return one non-authoritative pack instead of cached status', async () => {
  const pack = await refreshCanonicalStatusPack({
    now: () => new Date('2026-08-23T14:00:00.000Z'),
    authorityPolicySha256: AUTHORITY_HASH,
    historicalSurfaceRegistrySha256: HISTORICAL_HASH,
    triage: triage(),
    readers: {
      memory: async () => { throw new Error('secret-bearing provider failure'); },
      github: async () => evidence().github,
      vercel: async () => evidence().vercel,
      supabase: async () => evidence().supabase,
      android: async () => evidence().android,
      independentReview: async () => evidence().independentReview,
      ownerAuthorization: async () => evidence().ownerAuthorization,
    },
  });

  assert.equal(pack.status, 'unavailable');
  assert.deepEqual(pack.unknowns, ['memory']);
  assert.equal(JSON.stringify(pack).includes('secret-bearing'), false);
  assert.equal(pack.evidence.memory.errorCode, 'MEMORY_STATUS_UNAVAILABLE');
  assert.equal(validateStatusSchema(pack), true, JSON.stringify(validateStatusSchema.errors));
  assert.equal(canonicalStatusSemanticsValid(pack), true);
});

test('a stored Supabase byte claim is never relabeled as provider readback', () => {
  const binding = evaluateSupabaseReceiptBinding({
    receipt: {
      providerReadback: true,
      sourceSha: MAIN_SHA,
      sourceChainSha256: 'e'.repeat(64),
      exactAppliedBytesProven: true,
    },
    projectRef: 'jcyqixttuebxqqfkjonq',
    sourceSha: MAIN_SHA,
    expectedVersions: ['20260823153552'],
    expectedVersionChainSha256: '8'.repeat(64),
    expectedSourceChainSha256: 'e'.repeat(64),
  });

  assert.deepEqual(binding, {
    sourceArtifactDatabaseReceiptPresent: false,
    providerDatabaseReceiptReadback: false,
    sourceArtifactBoundToCapturedVersions: false,
  });
});

test('GitHub provider readback binds the source artifact to one successful protected-main run', async () => {
  const artifactId = '123456789';
  const artifactSha256 = 'd'.repeat(64);
  const artifactUrl = `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${artifactId}`;
  let runEvent = 'push';
  let artifactExpiresAt = '2099-09-06T13:30:00.000Z';
  let linkedCheckConclusion = 'success';
  const fetchFn = async (url) => {
    let body;
    if (String(url) === artifactUrl) {
      body = {
        id: Number(artifactId),
        url: artifactUrl,
        name: `canonical-release-source-${MAIN_SHA}`,
        expired: false,
        digest: `sha256:${artifactSha256}`,
        created_at: '2026-08-23T13:30:00.000Z',
        expires_at: artifactExpiresAt,
        workflow_run: {
          id: 9001,
          head_sha: MAIN_SHA,
          head_branch: 'main',
          repository_id: 55,
          head_repository_id: 55,
        },
      };
    } else if (String(url).endsWith('/actions/runs/9001')) {
      body = {
        id: 9001,
        event: runEvent,
        head_branch: 'main',
        head_sha: MAIN_SHA,
        head_commit: { id: MAIN_SHA, tree_id: TREE_SHA },
        status: 'completed',
        conclusion: 'success',
        path: '.github/workflows/canonical-release-evidence.yml@main',
        workflow_id: 7001,
        check_suite_id: 8001,
        run_attempt: 2,
        updated_at: '2026-08-23T13:34:00.000Z',
        repository: { id: 55, full_name: 'banataosystems/Pandoras-box' },
        head_repository: { id: 55, full_name: 'banataosystems/Pandoras-box' },
      };
    } else if (String(url).endsWith('/actions/runs/9001/attempts/2/jobs?per_page=100')) {
      body = {
        total_count: 1,
        jobs: [{
          id: 6001,
          run_id: 9001,
          name: 'canonical-release-source-contract',
          head_sha: MAIN_SHA,
          status: 'completed',
          conclusion: 'success',
          check_run_url: 'https://api.github.com/repos/banataosystems/Pandoras-box/check-runs/5001',
        }],
      };
    } else if (String(url).endsWith('/check-runs/5001')) {
      body = {
        id: 5001,
        url: 'https://api.github.com/repos/banataosystems/Pandoras-box/check-runs/5001',
        name: 'canonical-release-source-contract',
        app: { id: GITHUB_ACTIONS_APP_ID },
        head_sha: MAIN_SHA,
        status: 'completed',
        conclusion: linkedCheckConclusion,
        check_suite: { id: 8001 },
      };
    } else {
      throw new Error(`unexpected artifact read: ${url}`);
    }
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const options = {
    origin: 'https://api.github.com',
    headers: { authorization: 'Bearer test' },
    fetchFn,
    releaseEvidence: {
      supabase: {
        sourceArtifactDatabaseReceipt: {
          databaseCaptured: true,
          externalId: artifactId,
          sourceUrl: artifactUrl,
          artifactSha256,
          sourceSha: MAIN_SHA,
          sourceTreeSha: TREE_SHA,
        },
        providerDatabaseReceipt: {
          databaseReadback: true,
          capturedAt: '2026-08-23T13:55:00.000Z',
        },
      },
    },
    mainSha: MAIN_SHA,
    mainTreeSha: TREE_SHA,
    canonicalCheck: {
      id: 5001,
      name: 'canonical-release-source-contract',
      app: { id: GITHUB_ACTIONS_APP_ID },
      head_sha: MAIN_SHA,
      status: 'completed',
      conclusion: 'success',
      check_suite: { id: 8001 },
    },
  };

  const verified = await readSourceArtifactProviderReadback(options);
  assert.equal(verified.verified, true);
  assert.equal(verified.artifactId, artifactId);
  assert.equal(verified.artifactSha256, artifactSha256);
  assert.equal(verified.sourceSha, MAIN_SHA);
  assert.equal(verified.sourceTreeSha, TREE_SHA);
  assert.equal(verified.runId, 9001);
  assert.equal(verified.runAttempt, 2);

  runEvent = 'pull_request';
  const wrongEvent = await readSourceArtifactProviderReadback(options);
  assert.deepEqual(wrongEvent, {
    verified: false,
    provider: 'github',
    reason: 'workflow_run_identity_mismatch',
  });

  runEvent = 'push';
  linkedCheckConclusion = 'failure';
  assert.equal(
    (await readSourceArtifactProviderReadback(options)).reason,
    'workflow_job_check_identity_mismatch',
  );

  linkedCheckConclusion = 'success';
  artifactExpiresAt = '2026-08-23T13:30:00.000Z';
  assert.equal(
    (await readSourceArtifactProviderReadback(options)).reason,
    'artifact_identity_mismatch',
  );
});

test('GitHub provider readback binds the physical APK receipt to one exact mobile CI artifact', async () => {
  const artifactUrl = `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${MOBILE_ARTIFACT_ID}`;
  let artifactDigest = `sha256:${MOBILE_ARTIFACT_SHA256}`;
  let runEvent = 'push';
  let jobCheckRunId = 5002;
  const fetchFn = async (url) => {
    let body;
    if (String(url) === artifactUrl) {
      body = {
        id: Number(MOBILE_ARTIFACT_ID),
        url: artifactUrl,
        name: `pandora-mobile-android-validation-${MAIN_SHA}`,
        expired: false,
        digest: artifactDigest,
        created_at: '2026-08-23T13:30:00.000Z',
        expires_at: '2099-09-06T13:30:00.000Z',
        workflow_run: {
          id: 9002,
          head_sha: MAIN_SHA,
          head_branch: 'main',
          repository_id: 55,
          head_repository_id: 55,
        },
      };
    } else if (String(url).endsWith('/actions/runs/9002')) {
      body = {
        id: 9002,
        event: runEvent,
        head_branch: 'main',
        head_sha: MAIN_SHA,
        head_commit: { id: MAIN_SHA, tree_id: TREE_SHA },
        status: 'completed',
        conclusion: 'success',
        path: '.github/workflows/pandora-mobile-integration.yml@main',
        workflow_id: 7002,
        check_suite_id: 8002,
        run_attempt: 3,
        updated_at: '2026-08-23T13:34:00.000Z',
        repository: { id: 55, full_name: 'banataosystems/Pandoras-box' },
        head_repository: { id: 55, full_name: 'banataosystems/Pandoras-box' },
      };
    } else if (String(url).endsWith('/actions/runs/9002/attempts/3/jobs?per_page=100')) {
      body = {
        total_count: 1,
        jobs: [{
          id: 6002,
          run_id: 9002,
          name: 'Exact source / Flutter / Android',
          head_sha: MAIN_SHA,
          status: 'completed',
          conclusion: 'success',
          check_run_url: `https://api.github.com/repos/banataosystems/Pandoras-box/check-runs/${jobCheckRunId}`,
        }],
      };
    } else if (String(url).endsWith(`/check-runs/${jobCheckRunId}`)) {
      body = {
        id: jobCheckRunId,
        url: `https://api.github.com/repos/banataosystems/Pandoras-box/check-runs/${jobCheckRunId}`,
        name: 'Exact source / Flutter / Android',
        app: { id: GITHUB_ACTIONS_APP_ID },
        head_sha: MAIN_SHA,
        status: 'completed',
        conclusion: 'success',
        check_suite: { id: 8002 },
      };
    } else {
      throw new Error(`unexpected mobile artifact read: ${url}`);
    }
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const options = {
    origin: 'https://api.github.com',
    headers: { authorization: 'Bearer test' },
    fetchFn,
    releaseEvidence: {
      android: {
        ciArtifactDatabaseReceipt: {
          databaseCaptured: true,
          externalId: MOBILE_ARTIFACT_ID,
          sourceUrl: artifactUrl,
          artifactName: `pandora-mobile-android-validation-${MAIN_SHA}`,
          artifactSha256: MOBILE_ARTIFACT_SHA256,
          apkSha256: MOBILE_APK_SHA256,
          sourceSha: MAIN_SHA,
          sourceTreeSha: TREE_SHA,
          productionOrigin: 'https://mcpmaster.vercel.app',
          capturedAt: '2026-08-23T13:55:00.000Z',
        },
      },
    },
    mainSha: MAIN_SHA,
    mainTreeSha: TREE_SHA,
    mobileCheck: {
      id: 5002,
      name: 'Exact source / Flutter / Android',
      app: { id: GITHUB_ACTIONS_APP_ID },
      head_sha: MAIN_SHA,
      status: 'completed',
      conclusion: 'success',
      check_suite: { id: 8002 },
    },
  };

  const verified = await readMobileArtifactProviderReadback(options);
  assert.equal(verified.verified, true);
  assert.equal(verified.artifactId, MOBILE_ARTIFACT_ID);
  assert.equal(verified.artifactSha256, MOBILE_ARTIFACT_SHA256);
  assert.equal(verified.apkSha256, MOBILE_APK_SHA256);
  assert.equal(verified.runAttempt, 3);

  artifactDigest = `sha256:${'0'.repeat(64)}`;
  assert.equal((await readMobileArtifactProviderReadback(options)).reason, 'artifact_identity_mismatch');
  artifactDigest = `sha256:${MOBILE_ARTIFACT_SHA256}`;
  runEvent = 'pull_request';
  assert.equal((await readMobileArtifactProviderReadback(options)).reason, 'workflow_run_identity_mismatch');
  runEvent = 'push';
  jobCheckRunId = 9999;
  assert.equal((await readMobileArtifactProviderReadback(options)).reason, 'workflow_job_identity_mismatch');
});

test('GitHub pull inventory paginates beyond the newest 100 without omissions', async () => {
  const requested = [];
  const fetchFn = async (url) => {
    requested.push(String(url));
    const page = String(url).includes('&page=2') ? 2 : 1;
    const body = page === 1
      ? Array.from({ length: 100 }, (_, index) => ({ number: index + 1 }))
      : [{ number: 101 }];
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const pulls = await readAllGitHubPulls({
    origin: 'https://api.github.test',
    owner: 'banataosystems',
    repo: 'Pandoras-box',
    headers: { authorization: 'Bearer test' },
    fetchFn,
  });
  assert.equal(pulls.length, 101);
  assert.deepEqual(pulls.map(({ number }) => number), Array.from({ length: 101 }, (_, index) => index + 1));
  assert.equal(requested.length, 2);
  assert.match(requested[1], /per_page=100&page=2$/);
});

test('GitHub refresh preserves the 41-item registry after archive decisions close PRs', async () => {
  const requested = [];
  let includeUnknownProtected = false;
  let strictProtection = true;
  const fetchFn = async (url) => {
    requested.push(String(url));
    let body;
    if (String(url).includes('/branches/main/protection')) {
      body = {
        required_status_checks: {
          strict: strictProtection,
          checks: [
            ...REQUIRED_CHECK_IDENTITIES.map((context) => ({
              context,
              app_id: context === 'external-review'
                ? TRUSTED_EXTERNAL_REVIEW_APP_ID
                : GITHUB_ACTIONS_APP_ID,
            })),
            ...(includeUnknownProtected
              ? [{ context: 'future-protected-check', app_id: 424242 }]
              : []),
          ],
        },
        required_pull_request_reviews: {
          required_approving_review_count: 1,
          dismiss_stale_reviews: true,
          require_last_push_approval: true,
          bypass_pull_request_allowances: { users: [], teams: [], apps: [] },
        },
        required_conversation_resolution: { enabled: true },
        enforce_admins: { enabled: true },
        allow_force_pushes: { enabled: false },
        allow_deletions: { enabled: false },
      };
    } else if (String(url).includes('/branches/main')) {
      body = { commit: { sha: MAIN_SHA, commit: { tree: { sha: TREE_SHA } } } };
    } else if (String(url).includes('/check-runs')) {
      body = {
        check_runs: [
          ...REQUIRED_CHECK_IDENTITIES.map((name, index) => ({
            id: 7000 + index,
            name,
            head_sha: MAIN_SHA,
            app: name === 'external-review'
              ? { id: TRUSTED_EXTERNAL_REVIEW_APP_ID, slug: 'independent-review-provider' }
              : { id: GITHUB_ACTIONS_APP_ID, slug: 'github-actions' },
            check_suite: { id: 8000 + index },
            status: 'completed',
            conclusion: 'success',
            completed_at: '2026-08-23T14:00:00Z',
          })),
          ...(includeUnknownProtected
            ? [{
              id: 7999,
              name: 'future-protected-check',
              head_sha: MAIN_SHA,
              app: { id: 424242 },
              check_suite: { id: 8999 },
              conclusion: 'success',
              completed_at: '2026-08-23T14:00:01Z',
            }]
            : []),
        ],
      };
    } else if (String(url).includes('/actions/runs?')) {
      body = {
        workflow_runs: REPOSITORY_CHECK_IDENTITIES.map((name) => ({
          check_suite_id: 8000 + REQUIRED_CHECK_IDENTITIES.indexOf(name),
          path: REQUIRED_CHECK_WORKFLOW_PATHS[name],
          head_sha: MAIN_SHA,
          head_branch: 'main',
          event: 'push',
          status: 'completed',
          conclusion: 'success',
          repository: { full_name: 'banataosystems/Pandoras-box' },
          head_repository: { full_name: 'banataosystems/Pandoras-box' },
        })),
      };
    } else if (String(url).includes('/pulls?')) {
      body = registry.decisions.map((decision) => ({
        number: decision.number,
        state: decision.decision === 'archive' || decision.decision === 'close' ? 'closed' : 'open',
        head: { sha: decision.headSha },
      }));
    } else {
      throw new Error(`unexpected GitHub request: ${url}`);
    }
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const result = await readGitHubStatus({
    env: {
      VERCEL_OIDC_TOKEN: 'oidc-test-token',
      PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID: String(TRUSTED_EXTERNAL_REVIEW_APP_ID),
    },
    fetchFn,
    resolver: {
      async resolve() {
        return {
          token: 'github-test-token',
          baseUrl: 'https://api.github.test',
          allowedRepositories: ['banataosystems/Pandoras-box'],
        };
      },
    },
  });

  assert.equal(result.triageInventoryCount, 41);
  assert.equal(result.openPullRequestCount, 10);
  assert.equal(result.triageExactHeadMatches, true);
  assert.equal(result.protectionHasExactCheckIdentities, true);
  assert.equal(result.protectedMainPolicyExact, true);
  assert.equal(result.protectedWorkflowBindingsExact, true);
  assert.equal(result.exactIntegrationChecks, 'success');
  assert.equal(result.trustedExternalReviewConfigured, true);
  assert.equal(result.trustedExternalReviewVerified, true);
  assert.equal(result.requiredChecks.length, REQUIRED_CHECK_IDENTITIES.length);
  assert.ok(requested.some((url) => url.includes('pulls?state=all')));

  const actionsAsReviewer = await readGitHubStatus({
    env: {
      VERCEL_OIDC_TOKEN: 'oidc-test-token',
      PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID: String(GITHUB_ACTIONS_APP_ID),
    },
    fetchFn,
    resolver: {
      async resolve() {
        return {
          token: 'github-test-token',
          baseUrl: 'https://api.github.test',
          allowedRepositories: ['banataosystems/Pandoras-box'],
        };
      },
    },
  });
  assert.equal(actionsAsReviewer.trustedExternalReviewConfigured, false);
  assert.equal(actionsAsReviewer.trustedExternalReviewVerified, false);
  assert.equal(actionsAsReviewer.protectionHasExactCheckIdentities, false);

  strictProtection = false;
  const weakened = await readGitHubStatus({
    env: {
      VERCEL_OIDC_TOKEN: 'oidc-test-token',
      PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID: String(TRUSTED_EXTERNAL_REVIEW_APP_ID),
    },
    fetchFn,
    resolver: {
      async resolve() {
        return {
          token: 'github-test-token',
          baseUrl: 'https://api.github.test',
          allowedRepositories: ['banataosystems/Pandoras-box'],
        };
      },
    },
  });
  assert.equal(weakened.protectionHasExactCheckIdentities, true);
  assert.equal(weakened.protectedMainPolicyExact, false);
  strictProtection = true;

  includeUnknownProtected = true;
  const failed = await readGitHubStatus({
    env: {
      VERCEL_OIDC_TOKEN: 'oidc-test-token',
      PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID: String(TRUSTED_EXTERNAL_REVIEW_APP_ID),
    },
    fetchFn,
    resolver: {
      async resolve() {
        return {
          token: 'github-test-token',
          baseUrl: 'https://api.github.test',
          allowedRepositories: ['banataosystems/Pandoras-box'],
        };
      },
    },
  });
  assert.equal(failed.protectionHasExactCheckIdentities, false);
  assert.equal(failed.protectedWorkflowBindingsExact, true);
  assert.equal(failed.exactIntegrationChecks, 'success');
  assert.equal(failed.trustedExternalReviewVerified, false);
});
