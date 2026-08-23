"use strict";

const { createHash } = require("node:crypto");

const CANONICAL_REPOSITORY = "banataosystems/Pandoras-box";
const PROOF_STAGES = Object.freeze([
  "documented",
  "implemented",
  "tested",
  "deployed",
  "productionVerified",
]);
const CANONICAL_GOAL_IDS = Object.freeze([
  "canonical-status",
  "pr-triage-41",
  "owner-worker-clean-main",
  "exact-release-binding",
  "physical-android",
  "commercial-pilot",
]);
const EXPECTED_TRIAGE_COUNTS = Object.freeze({
  land: 1,
  consolidate: 9,
  archive: 31,
  close: 0,
});
const PHYSICAL_ANDROID_JOURNEY_STEPS = Object.freeze([
  "owner_authenticate",
  "submit_owner_command",
  "observe_durable_dispatch",
  "observe_worker_01_claim",
  "observe_exact_provider_result",
  "observe_proof_in_owner_read",
]);

function exactStringArray(value, expected) {
  return Array.isArray(value)
    && value.length === expected.length
    && value.every((entry, index) => entry === expected[index]);
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, stableValue(nested)]));
  }
  return value;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalStatusHash(pack) {
  const { canonicalJsonSha256: _ignored, ...hashable } = pack;
  return sha256(JSON.stringify(stableValue(hashable)));
}

function validSha(value) {
  return typeof value === "string" && /^[0-9a-f]{40}$/i.test(value);
}

function validSha256(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
}

function validLowerSha256(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

function buildFreshness(generatedAt, expiresAt) {
  const generatedAtEpochMs = Date.parse(generatedAt || "");
  const expiresAtEpochMs = Date.parse(expiresAt || "");
  const generatedAtValid = Number.isFinite(generatedAtEpochMs);
  const expiresAtValid = Number.isFinite(expiresAtEpochMs);
  const generatedBeforeExpiry = generatedAtValid
    && expiresAtValid
    && generatedAtEpochMs < expiresAtEpochMs;
  return {
    generatedAtValid,
    expiresAtValid,
    generatedBeforeExpiry,
    currentAtGeneration: generatedBeforeExpiry,
    windowMs: generatedBeforeExpiry ? expiresAtEpochMs - generatedAtEpochMs : null,
  };
}

function exactTriageRegistry(triage) {
  if (!triage || !Array.isArray(triage.decisions) || triage.total !== 41) return false;
  if (!triage.counts || Object.keys(EXPECTED_TRIAGE_COUNTS).some(
    (decision) => triage.counts[decision] !== EXPECTED_TRIAGE_COUNTS[decision],
  )) return false;
  const numbers = new Set();
  const heads = new Set();
  const derived = { land: 0, consolidate: 0, archive: 0, close: 0 };
  for (const decision of triage.decisions) {
    if (!Number.isSafeInteger(decision?.number)
      || decision.number <= 0
      || numbers.has(decision.number)
      || !Object.hasOwn(derived, decision.decision)
      || !validSha(decision.headSha)
      || heads.has(decision.headSha)) return false;
    numbers.add(decision.number);
    heads.add(decision.headSha);
    derived[decision.decision] += 1;
  }
  return triage.decisions.length === triage.total
    && Object.keys(EXPECTED_TRIAGE_COUNTS).every(
      (decision) => derived[decision] === EXPECTED_TRIAGE_COUNTS[decision],
    );
}

function goalRecord({ id, title, complete, ready = false, evidence, blockers, owner, nextAction }) {
  return {
    id,
    title,
    state: complete ? "complete" : ready ? "ready" : "blocked",
    evidence: evidence.filter(Boolean),
    blockers: complete ? [] : blockers,
    owner,
    nextAction,
  };
}

function validUuid(value) {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function exactVercelDeploymentSourceUrl(deploymentId) {
  return `https://api.vercel.com/v13/deployments/${deploymentId}`
    + "?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7";
}

const VERCEL_ALIAS_SOURCE_URL = "https://api.vercel.com/v13/deployments/mcpmaster.vercel.app"
  + "?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7";

function providerUnavailable(name, observedAt) {
  return {
    ok: false,
    provider: name,
    observedAt,
    errorCode: `${name.toUpperCase()}_STATUS_UNAVAILABLE`,
  };
}

async function boundedRead(name, reader, observedAt, timeoutMs) {
  if (typeof reader !== "function") return providerUnavailable(name, observedAt);
  let timer;
  try {
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("timeout")), timeoutMs);
    });
    const value = await Promise.race([Promise.resolve().then(() => reader()), timeout]);
    if (!value || typeof value !== "object" || value.ok !== true) {
      return providerUnavailable(name, observedAt);
    }
    return { ...value, provider: name, ok: true };
  } catch {
    return providerUnavailable(name, observedAt);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function taskForStage(stage, complete, blockers, repository, proofLadder) {
  const labels = {
    documented: "Canonical authority and triage are recorded",
    implemented: "Canonical main resolves to exact source",
    tested: "Required checks pass on the exact source",
    deployed: "Production deployment and rollback bind that source",
    productionVerified: "The live customer journey is verified",
  };
  return {
    id: `STATUS-${PROOF_STAGES.indexOf(stage) + 1}`,
    title: labels[stage],
    phase: "canonical-convergence",
    repository,
    declaredStatus: complete ? "complete" : "blocked",
    status: complete ? "complete" : "blocked",
    dependencyReady: PROOF_STAGES.slice(0, PROOF_STAGES.indexOf(stage))
      .every((prior) => proofLadder[prior] === true),
    missingDependencies: [],
    blockerIds: complete ? [] : blockers,
    evidenceIds: [],
    blocksPhaseExit: true,
    builderAgent: "ProjectOS",
    reviewerAgent: "independent-review",
  };
}

function buildCanonicalStatusPack(input) {
  const generatedAt = input.generatedAt;
  const freshness = buildFreshness(generatedAt, input.expiresAt);
  const github = input.evidence.github;
  const memory = input.evidence.memory;
  const vercel = input.evidence.vercel;
  const supabase = input.evidence.supabase;
  const android = input.evidence.android;
  const independentReview = input.evidence.independentReview || {};
  const ownerAuthorization = input.evidence.ownerAuthorization || {};
  const triage = input.triage;

  const githubAvailable = github.ok === true
    && github.repository === CANONICAL_REPOSITORY
    && validSha(github.mainSha)
    && validSha(github.mainTreeSha);
  const triageRegistryExact = exactTriageRegistry(triage);
  const triageComplete = githubAvailable
    && triageRegistryExact
    && Number.isInteger(github.triageInventoryCount)
    && github.triageInventoryCount === triage.total
    && triage.decisions.length === triage.total
    && github.triageExactHeadMatches === true;
  const memoryCurrent = memory.ok === true
    && memory.healthStatus === "projectos-connected"
    && memory.contextState === "healthy"
    && memory.fresh === true
    && Array.isArray(memory.approvedRecordIds)
    && memory.approvedRecordIds.length > 0
    && Array.isArray(memory.conflicts)
    && memory.conflicts.length === 0;
  const supabaseCurrent = supabase.ok === true
    && supabase.projectStatus === "ACTIVE_HEALTHY"
    && supabase.managementApiVersionReadback === true
    && supabase.migrationVersionParity === "match"
    && supabase.providerDatabaseReceiptReadback === true
    && supabase.sourceArtifactDatabaseReceiptPresent === true
    && supabase.sourceArtifactBoundToLiveVersions === true
    && supabase.exactAppliedBytesProven === false
    && supabase.providerReadback === false
    && supabase.migrationByteParity === "not_provider_reconstructable"
    && supabase.migrationParity === "source_artifact_bound_to_live_versions"
    && supabase.sourceSha === github.mainSha
    && validSha256(supabase.expectedSourceChainSha256)
    && supabase.sourceArtifactChainSha256 === supabase.expectedSourceChainSha256
    && validSha256(supabase.expectedAppliedChainSha256)
    && supabase.appliedChainSha256 === supabase.expectedAppliedChainSha256
    && supabase.providerDatabaseCapturedVersionChainSha256
      === supabase.expectedAppliedChainSha256;
  const sourceArtifact = github.sourceArtifactProviderReadback;
  const sourceArtifactProviderCurrent = sourceArtifact?.verified === true
    && sourceArtifact.provider === "github"
    && Number.isFinite(Date.parse(sourceArtifact.observedAt || ""))
    && /^[1-9][0-9]{0,19}$/.test(String(sourceArtifact.artifactId || ""))
    && validSha256(sourceArtifact.artifactSha256)
    && sourceArtifact.artifactId === supabase.sourceArtifactExternalId
    && sourceArtifact.artifactSha256 === supabase.sourceArtifactSha256
    && sourceArtifact.sourceSha === github.mainSha
    && sourceArtifact.sourceTreeSha === github.mainTreeSha
    && supabase.sourceArtifactSourceTreeSha === github.mainTreeSha
    && sourceArtifact.artifactName === `canonical-release-source-${github.mainSha}`
    && sourceArtifact.artifactUrl
      === `https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/${sourceArtifact.artifactId}`
    && sourceArtifact.event === "push"
    && sourceArtifact.workflowPath === ".github/workflows/canonical-release-evidence.yml"
    && Number.isSafeInteger(sourceArtifact.runId)
    && sourceArtifact.runId > 0
    && Number.isSafeInteger(sourceArtifact.runAttempt)
    && sourceArtifact.runAttempt > 0
    && Number.isSafeInteger(sourceArtifact.workflowId)
    && sourceArtifact.workflowId > 0
    && Number.isSafeInteger(sourceArtifact.jobId)
    && sourceArtifact.jobId > 0
    && Number.isSafeInteger(sourceArtifact.checkRunId)
    && sourceArtifact.checkRunId > 0
    && Number.isSafeInteger(sourceArtifact.checkSuiteId)
    && sourceArtifact.checkSuiteId > 0;
  const mobileArtifactReceipt = android.ciArtifactDatabaseReceipt;
  const mobileArtifact = github.mobileArtifactProviderReadback;
  const mobileArtifactCreatedAt = Date.parse(mobileArtifact?.artifactCreatedAt || "");
  const mobileArtifactRunCompletedAt = Date.parse(mobileArtifact?.runCompletedAt || "");
  const mobileArtifactReceiptCapturedAt = Date.parse(mobileArtifact?.receiptCapturedAt || "");
  const mobileArtifactProviderCurrent = mobileArtifact?.verified === true
    && mobileArtifact.provider === "github"
    && Number.isFinite(Date.parse(mobileArtifact.observedAt || ""))
    && mobileArtifactReceipt?.databaseCaptured === true
    && /^[1-9][0-9]{0,19}$/.test(String(mobileArtifact.artifactId || ""))
    && mobileArtifact.artifactId === mobileArtifactReceipt.externalId
    && mobileArtifact.artifactUrl === mobileArtifactReceipt.sourceUrl
    && mobileArtifact.artifactName === mobileArtifactReceipt.artifactName
    && mobileArtifact.artifactName === `pandora-mobile-android-validation-${github.mainSha}`
    && validSha256(mobileArtifact.artifactSha256)
    && mobileArtifact.artifactSha256 === mobileArtifactReceipt.artifactSha256
    && validSha256(mobileArtifact.apkSha256)
    && mobileArtifact.apkSha256 === mobileArtifactReceipt.apkSha256
    && mobileArtifact.apkSha256 === android.artifactSha256
    && mobileArtifact.sourceSha === github.mainSha
    && mobileArtifact.sourceSha === mobileArtifactReceipt.sourceSha
    && mobileArtifact.sourceTreeSha === github.mainTreeSha
    && mobileArtifact.sourceTreeSha === mobileArtifactReceipt.sourceTreeSha
    && mobileArtifact.productionOrigin === "https://mcpmaster.vercel.app"
    && mobileArtifact.productionOrigin === mobileArtifactReceipt.productionOrigin
    && mobileArtifact.event === "push"
    && mobileArtifact.workflowPath === ".github/workflows/pandora-mobile-integration.yml"
    && Number.isFinite(mobileArtifactCreatedAt)
    && Number.isFinite(Date.parse(mobileArtifact.artifactExpiresAt || ""))
    && Number.isFinite(mobileArtifactRunCompletedAt)
    && Number.isFinite(mobileArtifactReceiptCapturedAt)
    && mobileArtifactCreatedAt <= mobileArtifactRunCompletedAt
    && mobileArtifactRunCompletedAt <= mobileArtifactReceiptCapturedAt
    && mobileArtifact.receiptCapturedAt === mobileArtifactReceipt.capturedAt
    && Number.isSafeInteger(mobileArtifact.runId)
    && mobileArtifact.runId > 0
    && Number.isSafeInteger(mobileArtifact.runAttempt)
    && mobileArtifact.runAttempt > 0
    && Number.isSafeInteger(mobileArtifact.workflowId)
    && mobileArtifact.workflowId > 0
    && Number.isSafeInteger(mobileArtifact.jobId)
    && mobileArtifact.jobId > 0
    && Number.isSafeInteger(mobileArtifact.checkRunId)
    && mobileArtifact.checkRunId > 0
    && Number.isSafeInteger(mobileArtifact.checkSuiteId)
    && mobileArtifact.checkSuiteId > 0;
  const productionObservedAt = Date.parse(vercel.productionObservedAt || "");
  const transitionObservedAt = Date.parse(vercel.rollbackTransitionObservedAt || "");
  const restorationObservedAt = Date.parse(vercel.rollbackRestorationObservedAt || "");
  const transitionAliasPreObservedAt = Date.parse(vercel.rollbackTransitionAliasPreObservedAt || "");
  const transitionRouteProbeObservedAt = Date.parse(vercel.rollbackTransitionRouteProbeObservedAt || "");
  const transitionAliasPostObservedAt = Date.parse(vercel.rollbackTransitionAliasPostObservedAt || "");
  const restorationAliasPreObservedAt = Date.parse(vercel.rollbackRestorationAliasPreObservedAt || "");
  const restorationRouteProbeObservedAt = Date.parse(vercel.rollbackRestorationRouteProbeObservedAt || "");
  const restorationAliasPostObservedAt = Date.parse(vercel.rollbackRestorationAliasPostObservedAt || "");
  const vercelRollbackReceiptsCurrent = validUuid(vercel.rollbackTransitionEvidenceId)
    && validUuid(vercel.rollbackRestorationEvidenceId)
    && vercel.rollbackTransitionEvidenceId !== vercel.rollbackRestorationEvidenceId
    && vercel.rollbackTransitionExternalId === vercel.rollbackDeploymentId
    && vercel.rollbackRestorationExternalId === vercel.deploymentId
    && vercel.rollbackTransitionSourceUrl
      === exactVercelDeploymentSourceUrl(vercel.rollbackDeploymentId)
    && vercel.rollbackRestorationSourceUrl
      === exactVercelDeploymentSourceUrl(vercel.deploymentId)
    && vercel.rollbackTransitionAliasSourceUrl === VERCEL_ALIAS_SOURCE_URL
    && vercel.rollbackRestorationAliasSourceUrl === VERCEL_ALIAS_SOURCE_URL
    && validSha256(vercel.rollbackTransitionAliasPreResponseSha256)
    && validSha256(vercel.rollbackTransitionAliasPostResponseSha256)
    && validSha256(vercel.rollbackRestorationAliasPreResponseSha256)
    && validSha256(vercel.rollbackRestorationAliasPostResponseSha256)
    && vercel.rollbackTransitionRouteProbeContract === "canonical_routes_v1"
    && validSha256(vercel.rollbackTransitionRouteProbeSha256)
    && vercel.rollbackRestorationRouteProbeContract === "canonical_routes_v1"
    && validSha256(vercel.rollbackRestorationRouteProbeSha256)
    && Number.isFinite(productionObservedAt)
    && Number.isFinite(transitionObservedAt)
    && Number.isFinite(restorationObservedAt)
    && Number.isFinite(transitionAliasPreObservedAt)
    && Number.isFinite(transitionRouteProbeObservedAt)
    && Number.isFinite(transitionAliasPostObservedAt)
    && Number.isFinite(restorationAliasPreObservedAt)
    && Number.isFinite(restorationRouteProbeObservedAt)
    && Number.isFinite(restorationAliasPostObservedAt)
    && transitionAliasPreObservedAt < transitionRouteProbeObservedAt
    && transitionRouteProbeObservedAt < transitionAliasPostObservedAt
    && transitionAliasPostObservedAt <= transitionObservedAt
    && restorationAliasPreObservedAt < restorationRouteProbeObservedAt
    && restorationRouteProbeObservedAt < restorationAliasPostObservedAt
    && restorationAliasPostObservedAt <= restorationObservedAt
    && productionObservedAt < transitionObservedAt
    && transitionObservedAt < restorationObservedAt;
  const authorityDocumentsCurrent = validLowerSha256(input.authorityPolicySha256)
    && validLowerSha256(input.historicalSurfaceRegistrySha256);
  const documented = Boolean(authorityDocumentsCurrent
    && triageComplete);
  const implemented = documented && githubAvailable;
  const trustedExternalReviewCurrent = github.trustedExternalReviewConfigured === true
    && Number.isSafeInteger(github.trustedExternalReviewAppId)
    && github.trustedExternalReviewAppId > 0
    && github.trustedExternalReviewAppId !== 15368
    && github.trustedExternalReviewVerified === true;
  const tested = implemented
    && github.exactIntegrationChecks === "success"
    && github.protectionHasExactCheckIdentities === true
    && github.protectedMainPolicyExact === true
    && trustedExternalReviewCurrent;
  const deployed = tested
    && supabaseCurrent
    && sourceArtifactProviderCurrent
    && vercel.ok === true
    && vercel.providerReadback === true
    && vercel.gitRepository === CANONICAL_REPOSITORY
    && validSha(vercel.sourceSha)
    && vercel.sourceSha === github.mainSha
    && typeof vercel.deploymentId === "string"
    && vercel.deploymentId.length > 0
    && typeof vercel.rollbackDeploymentId === "string"
    && vercel.rollbackDeploymentId.length > 0
    && vercel.rollbackDeploymentId !== vercel.deploymentId
    && validSha(vercel.rollbackSourceSha)
    && vercel.rollbackSourceSha !== vercel.sourceSha
    && vercel.productionAlias === "mcpmaster.vercel.app"
    && vercel.productionAliasSourceUrl === VERCEL_ALIAS_SOURCE_URL
    && vercel.productionAliasLiveRead === true
    && vercel.productionTarget === "production"
    && vercelRollbackReceiptsCurrent
    && vercel.rollbackVerified === true
    && vercel.rollbackVerifiedCandidateDeploymentId === vercel.deploymentId
    && vercel.rollbackRestoredDeploymentId === vercel.deploymentId;
  const wifiObservedAt = Date.parse(android.wifi?.observedAt || "");
  const mobileDataObservedAt = Date.parse(android.mobileData?.observedAt || "");
  const wifiCapturedAt = Date.parse(android.wifi?.capturedAt || "");
  const mobileDataCapturedAt = Date.parse(android.mobileData?.capturedAt || "");
  const physicalAndroidVerified = android.ok === true
    && android.authority === "PHYSICAL_ANDROID_OBSERVER"
    && android.storageAuthority === "IMMUTABLE_PHYSICAL_ANDROID_RECEIPT"
    && android.providerReadback === true
    && mobileArtifactProviderCurrent
    && validSha(android.sourceSha)
    && android.sourceSha === github.mainSha
    && android.sourceTreeSha === github.mainTreeSha
    && android.deploymentId === vercel.deploymentId
    && android.productionOrigin === "https://mcpmaster.vercel.app"
    && validSha256(android.artifactSha256)
    && validSha256(android.deviceIdHash)
    && android.packageName === "com.banataosystems.pandora_mobile"
    && mobileArtifactReceipt?.storageAuthority
      === "IMMUTABLE_PHYSICAL_ANDROID_RECEIPT"
    && validUuid(android.ownerPlanId)
    && validUuid(android.ownerDispatchId)
    && validLowerSha256(android.workerEvidenceSha256)
    && validUuid(android.verificationEvidenceId)
    && validUuid(android.reviewerRuntimeProofId)
    && android.wifi?.verified === true
    && android.wifi?.network === "wifi"
    && validUuid(android.wifi?.receiptId)
    && android.wifi?.receiptId === mobileArtifactReceipt?.wifiEvidenceId
    && validLowerSha256(android.wifi?.receiptSha256)
    && validLowerSha256(android.wifi?.observerKeyFingerprint)
    && validLowerSha256(android.wifi?.signatureBasisSha256)
    && android.wifi?.providerObservationIndex === 1
    && exactStringArray(
      android.wifi?.completedSteps,
      PHYSICAL_ANDROID_JOURNEY_STEPS,
    )
    && Number.isFinite(wifiObservedAt)
    && Number.isFinite(wifiCapturedAt)
    && wifiObservedAt <= wifiCapturedAt
    && wifiObservedAt > restorationAliasPostObservedAt
    && android.wifi?.artifactSha256 === android.artifactSha256
    && android.mobileData?.verified === true
    && android.mobileData?.network === "mobile_data"
    && validUuid(android.mobileData?.receiptId)
    && android.mobileData?.receiptId
      === mobileArtifactReceipt?.mobileDataEvidenceId
    && validLowerSha256(android.mobileData?.receiptSha256)
    && android.mobileData?.observerId === android.wifi?.observerId
    && android.mobileData?.observerKeyFingerprint
      === android.wifi?.observerKeyFingerprint
    && validLowerSha256(android.mobileData?.signatureBasisSha256)
    && android.mobileData?.providerObservationIndex === 2
    && exactStringArray(
      android.mobileData?.completedSteps,
      PHYSICAL_ANDROID_JOURNEY_STEPS,
    )
    && Number.isFinite(mobileDataObservedAt)
    && Number.isFinite(mobileDataCapturedAt)
    && mobileDataObservedAt > wifiObservedAt
    && mobileDataObservedAt <= mobileDataCapturedAt
    && mobileDataCapturedAt > wifiCapturedAt
    && mobileDataObservedAt > restorationAliasPostObservedAt
    && android.mobileData?.receiptId !== android.wifi?.receiptId
    && android.mobileData?.artifactSha256 === android.artifactSha256
    && mobileArtifactReceiptCapturedAt === mobileDataCapturedAt;
  const independentReviewedAt = Date.parse(independentReview.reviewedAt || "");
  const independentReviewCapturedAt = Date.parse(independentReview.capturedAt || independentReview.reviewedAt || "");
  const independentReviewCurrent = independentReview.ok === true
    && independentReview.verified === true
    && independentReview.authority === "INDEPENDENT_REVIEWER"
    && validUuid(independentReview.receiptId)
    && validLowerSha256(independentReview.receiptSha256)
    && independentReview.sourceSha === github.mainSha
    && independentReview.sourceTreeSha === github.mainTreeSha
    && independentReview.productionDeploymentId === vercel.deploymentId
    && independentReview.rollbackDeploymentId === vercel.rollbackDeploymentId
    && independentReview.supabaseMigrationChainSha256 === supabase.sourceArtifactChainSha256
    && validLowerSha256(independentReview.reviewerKeyFingerprint)
    && Number.isFinite(independentReviewedAt)
    && Number.isFinite(independentReviewCapturedAt)
    && independentReviewedAt <= independentReviewCapturedAt
    && independentReviewedAt > restorationObservedAt
    && independentReviewedAt > wifiObservedAt
    && independentReviewedAt > mobileDataObservedAt;
  const ownerAuthorizedAt = Date.parse(ownerAuthorization.authorizedAt || "");
  const ownerAuthorizationCapturedAt = Date.parse(ownerAuthorization.capturedAt || ownerAuthorization.authorizedAt || "");
  const ownerMfaVerifiedAt = Date.parse(ownerAuthorization.mfaVerifiedAt || "");
  const ownerAuthorizationCurrent = ownerAuthorization.ok === true
    && ownerAuthorization.verified === true
    && ownerAuthorization.authority === "OWNER_AUTHORIZATION"
    && validUuid(ownerAuthorization.receiptId)
    && validUuid(ownerAuthorization.ownerUserId)
    && ownerAuthorization.sourceSha === github.mainSha
    && ownerAuthorization.productionDeploymentId === vercel.deploymentId
    && ownerAuthorization.reviewReceiptId === independentReview.receiptId
    && validLowerSha256(ownerAuthorization.reviewReceiptSha256)
    && ownerAuthorization.reviewReceiptSha256 === independentReview.receiptSha256
    && ownerAuthorization.aal === "aal2"
    && validUuid(ownerAuthorization.sessionId)
    && Number.isFinite(ownerAuthorizedAt)
    && Number.isFinite(ownerAuthorizationCapturedAt)
    && Number.isFinite(ownerMfaVerifiedAt)
    && ownerMfaVerifiedAt >= ownerAuthorizedAt - 5 * 60 * 1000
    && ownerMfaVerifiedAt <= ownerAuthorizedAt + 30 * 1000
    && ownerAuthorizedAt <= ownerAuthorizationCapturedAt
    && ownerAuthorizedAt > independentReviewCapturedAt;
  const productionVerified = deployed
    && vercel.productionVerified === true
    && vercel.productionVerifiedDeploymentId === vercel.deploymentId
    && physicalAndroidVerified
    && independentReviewCurrent
    && ownerAuthorizationCurrent;

  const conflicts = [];
  const blockers = [];
  const unknowns = [];
  if (!authorityDocumentsCurrent) blockers.push("canonical-authority-documents-unbound");
  if (!githubAvailable) blockers.push("github-canonical-main-unavailable");
  if (githubAvailable && !triageComplete) blockers.push("github-pr-triage-stale-or-incomplete");
  if (!freshness.currentAtGeneration) blockers.push("status-pack-expiry-window-invalid");
  if (githubAvailable && github.exactIntegrationChecks !== "success") {
    blockers.push("github-exact-integration-checks-not-green");
  }
  if (githubAvailable && github.protectionHasExactCheckIdentities !== true) {
    blockers.push("github-protected-check-identities-not-exact");
  }
  if (githubAvailable && github.protectedMainPolicyExact !== true) {
    blockers.push("github-protected-main-policy-not-exact");
  }
  if (githubAvailable && github.trustedExternalReviewConfigured !== true) {
    blockers.push("github-trusted-external-review-authority-unconfigured");
  } else if (githubAvailable && !trustedExternalReviewCurrent) {
    blockers.push("github-trusted-external-review-not-green");
  }
  if (!memoryCurrent) blockers.push("memory-approved-context-stale-conflicted-or-empty");
  if (!supabaseCurrent) blockers.push("supabase-migration-parity-unverified");
  if (!sourceArtifactProviderCurrent) blockers.push("github-source-artifact-provider-readback-unverified");
  if (!deployed) blockers.push("vercel-source-deployment-rollback-binding-unproven");
  if (!mobileArtifactProviderCurrent) blockers.push("github-mobile-artifact-provider-readback-unverified");
  if (!physicalAndroidVerified) blockers.push("physical-android-wifi-mobile-data-proof-unverified");
  if (!independentReviewCurrent) blockers.push("independent-review-receipt-unverified");
  if (!ownerAuthorizationCurrent) blockers.push("owner-authorization-receipt-unverified");
  if (!productionVerified) blockers.push("production-journey-unverified");

  if (githubAvailable && vercel.ok === true && validSha(vercel.sourceSha) && vercel.sourceSha !== github.mainSha) {
    conflicts.push({
      id: "source-deployment-sha-mismatch",
      githubMainSha: github.mainSha,
      vercelSourceSha: vercel.sourceSha,
    });
  }
  if (vercel.ok === true && vercel.gitRepository && vercel.gitRepository !== CANONICAL_REPOSITORY) {
    conflicts.push({
      id: "noncanonical-vercel-git-link",
      expectedRepository: CANONICAL_REPOSITORY,
      observedRepository: vercel.gitRepository,
    });
  }
  if (memory.ok !== true) unknowns.push("memory");
  if (github.ok !== true) unknowns.push("github");
  if (vercel.ok !== true) unknowns.push("vercel");
  if (supabase.ok !== true) unknowns.push("supabase");
  if (android.ok !== true) unknowns.push("android");
  if (independentReview.ok !== true) unknowns.push("independentReview");
  if (ownerAuthorization.ok !== true) unknowns.push("ownerAuthorization");

  const proofLadder = { documented, implemented, tested, deployed, productionVerified };
  const completed = PROOF_STAGES.filter((stage) => proofLadder[stage]).length;
  const authoritative = documented
    && tested
    && memoryCurrent
    && supabaseCurrent
    && deployed
    && productionVerified
    && independentReviewCurrent
    && ownerAuthorizationCurrent
    && freshness.currentAtGeneration
    && conflicts.length === 0
    && unknowns.length === 0
    && blockers.length === 0;
  const status = authoritative
    ? "current"
    : conflicts.length > 0
      ? "conflicted"
      : unknowns.length > 0
        ? "unavailable"
        : "stale";
  const stageTasks = PROOF_STAGES.map((stage) => taskForStage(
    stage,
    proofLadder[stage],
    blockers,
    CANONICAL_REPOSITORY,
    proofLadder,
  ));
  const nextTask = stageTasks.find((task) => task.status !== "complete") ?? null;
  const currentPhase = {
    id: "canonical-convergence",
    name: "Canonical source-to-customer proof",
    status: completed === PROOF_STAGES.length ? "complete" : blockers.length ? "blocked" : "active",
    completedTasks: completed,
    gatingTasks: PROOF_STAGES.length,
  };
  const goals = [
    goalRecord({
      id: CANONICAL_GOAL_IDS[0],
      title: "One automatically refreshed canonical status pack; stale surfaces historical",
      complete: authorityDocumentsCurrent && freshness.currentAtGeneration,
      evidence: [
        "endpoint:/api/operator/status",
        validLowerSha256(input.authorityPolicySha256)
          ? `authority-policy-sha256:${input.authorityPolicySha256}`
          : null,
        validLowerSha256(input.historicalSurfaceRegistrySha256)
          ? `historical-surface-registry-sha256:${input.historicalSurfaceRegistrySha256}`
          : null,
        freshness.currentAtGeneration ? `freshness-window-ms:${freshness.windowMs}` : null,
      ],
      blockers: [
        ...(!authorityDocumentsCurrent ? ["canonical-authority-or-historical-registry-unbound"] : []),
        ...(!freshness.currentAtGeneration ? ["status-pack-expiry-window-invalid"] : []),
      ],
      owner: "ProjectOS",
      nextAction: authorityDocumentsCurrent && freshness.currentAtGeneration
        ? "keep-authenticated-status-refresh-current"
        : "restore-canonical-status-authority-and-refresh-window",
    }),
    goalRecord({
      id: CANONICAL_GOAL_IDS[1],
      title: "Triage all 41 pull requests into land, consolidate, archive, or close",
      complete: triageComplete,
      evidence: [
        triageRegistryExact ? "triage-denominator:41" : null,
        triageRegistryExact ? "triage-counts:land=1,consolidate=9,archive=31,close=0" : null,
        triageComplete ? "triage-heads:exact-provider-match" : null,
      ],
      blockers: ["github-pr-triage-stale-or-incomplete"],
      owner: "ProjectOS",
      nextAction: triageComplete
        ? "execute-approved-triage-decisions-without-changing-the-registry"
        : "reconcile-all-41-provider-heads-and-decisions",
    }),
    goalRecord({
      id: CANONICAL_GOAL_IDS[2],
      title: "Rebuild the owner-command and worker path from protected main",
      complete: tested,
      evidence: [
        githubAvailable ? `protected-main:${github.mainSha}` : null,
        github.protectedMainPolicyExact === true ? "protected-main-policy:exact" : null,
        tested ? "workflow:Windows worker contract" : null,
      ],
      blockers: ["owner-worker-clean-main-proof-not-green"],
      owner: "ProjectOS",
      nextAction: tested
        ? "keep-owner-worker-contract-green-on-protected-main"
        : "complete-owner-worker-contract-on-one-clean-protected-main-source",
    }),
    goalRecord({
      id: CANONICAL_GOAL_IDS[3],
      title: "Bind all passing tests, one exact source SHA, deployment, and rollback",
      complete: deployed,
      evidence: [
        tested && githubAvailable ? `source-sha:${github.mainSha}` : null,
        deployed ? `deployment-id:${vercel.deploymentId}` : null,
        deployed ? `rollback-deployment-id:${vercel.rollbackDeploymentId}` : null,
        tested ? "required-checks:all-green-on-exact-source" : null,
      ],
      blockers: ["exact-test-source-deployment-rollback-binding-unproven"],
      owner: "ProjectOS",
      nextAction: deployed
        ? "preserve-exact-release-and-rollback-receipts"
        : "complete-all-tests-and-provider-bound-deployment-rollback-proof",
    }),
    goalRecord({
      id: CANONICAL_GOAL_IDS[4],
      title: "Complete the physical Android journey on Wi-Fi and mobile data",
      complete: physicalAndroidVerified,
      evidence: [
        physicalAndroidVerified ? `apk-sha256:${android.artifactSha256}` : null,
        physicalAndroidVerified ? `wifi-receipt:${android.wifi.receiptId}` : null,
        physicalAndroidVerified ? `mobile-data-receipt:${android.mobileData.receiptId}` : null,
      ],
      blockers: ["physical-android-wifi-mobile-data-proof-unverified"],
      owner: "owner",
      nextAction: physicalAndroidVerified
        ? "preserve-the-two-immutable-physical-observer-receipts"
        : "run-the-same-bound-apk-journey-on-wifi-then-mobile-data",
    }),
    goalRecord({
      id: CANONICAL_GOAL_IDS[5],
      title: "Return to real customer interviews and complete the first paid pilot",
      complete: false,
      ready: productionVerified,
      evidence: [productionVerified ? "technical-release-gate:complete" : "technical-release-gate:incomplete"],
      blockers: [
        ...(!productionVerified ? ["production-proof-must-complete-before-commercial-outreach"] : []),
        "customer-interviews-and-first-paid-pilot-evidence-not-yet-recorded",
      ],
      owner: "owner",
      nextAction: productionVerified
        ? "conduct-customer-interviews-and-secure-the-first-paid-pilot"
        : "finish-the-physical-production-proof-then-return-immediately-to-interviews",
    }),
  ];

  const pack = {
    schemaVersion: "1.0.0",
    statusPackSchemaVersion: "1.0.0",
    planVersion: "canonical-status-pack-v1",
    generatedAt,
    expiresAt: input.expiresAt,
    observedThrough: generatedAt,
    freshness,
    authoritative,
    status,
    project: {
      key: "mcpmaster-pandoras-box",
      repository: CANONICAL_REPOSITORY,
      branch: "main",
    },
    authority: {
      policySha256: input.authorityPolicySha256,
      historicalSurfaceRegistrySha256: input.historicalSurfaceRegistrySha256,
    },
    evidence: {
      memory,
      github,
      vercel,
      supabase,
      android,
      independentReview,
      ownerAuthorization,
    },
    pullRequests: {
      observedOpen: github.openPullRequestCount ?? null,
      observedRegistryItems: github.triageInventoryCount ?? null,
      triaged: triage.decisions.length,
      denominator: triage.total,
      counts: triage.counts,
      exactHeadMatches: github.triageExactHeadMatches === true,
      observedAt: triage.observedAt,
    },
    proofLadder,
    conflicts,
    unknowns,
    blockers,
    nextAction: blockers[0] ?? "continue-production-observation",
    currentPhase,
    phases: [currentPhase],
    progress: {
      completed,
      total: PROOF_STAGES.length,
      percent: Math.round((completed / PROOF_STAGES.length) * 100),
    },
    tasks: stageTasks,
    nextTask,
    blocked: stageTasks.filter((task) => task.status === "blocked"),
    readyParallel: [],
    drift: blockers,
    goals,
  };
  return { ...pack, canonicalJsonSha256: canonicalStatusHash(pack) };
}

function canonicalStatusSemanticsValid(pack) {
  if (!pack || typeof pack !== "object" || Array.isArray(pack)) return false;
  const expectedFreshness = buildFreshness(pack.generatedAt, pack.expiresAt);
  if (JSON.stringify(pack.freshness) !== JSON.stringify(expectedFreshness)) return false;
  if (pack.observedThrough !== pack.generatedAt) return false;
  if (pack.canonicalJsonSha256 !== canonicalStatusHash(pack)) return false;
  const conflicts = Array.isArray(pack.conflicts) ? pack.conflicts : [];
  const unknowns = Array.isArray(pack.unknowns) ? pack.unknowns : [];
  const expectedStatus = pack.authoritative === true
    ? "current"
    : conflicts.length > 0
      ? "conflicted"
      : unknowns.length > 0
        ? "unavailable"
        : "stale";
  if (pack.status !== expectedStatus) return false;
  if (pack.status === "current") {
    if (!expectedFreshness.currentAtGeneration
      || !Array.isArray(pack.blockers)
      || pack.blockers.length !== 0
      || conflicts.length !== 0
      || unknowns.length !== 0
      || !PROOF_STAGES.every((stage) => pack.proofLadder?.[stage] === true)) return false;
    if (!Array.isArray(pack.goals)
      || pack.goals.length !== CANONICAL_GOAL_IDS.length
      || !CANONICAL_GOAL_IDS.every((id, index) => pack.goals[index]?.id === id)
      || !pack.goals.slice(0, 5).every((goal) => goal.state === "complete")
      || pack.goals[5]?.state !== "ready") return false;
  }
  return true;
}

async function refreshCanonicalStatusPack(options) {
  const now = options.now ? options.now() : new Date();
  const generatedAt = now.toISOString();
  const ttlMs = options.ttlMs ?? 5 * 60 * 1000;
  const timeoutMs = options.timeoutMs ?? 12_000;
  const [memory, github, vercel, supabase, android, independentReview, ownerAuthorization] = await Promise.all([
    boundedRead("memory", options.readers?.memory, generatedAt, timeoutMs),
    boundedRead("github", options.readers?.github, generatedAt, timeoutMs),
    boundedRead("vercel", options.readers?.vercel, generatedAt, timeoutMs),
    boundedRead("supabase", options.readers?.supabase, generatedAt, timeoutMs),
    boundedRead("android", options.readers?.android, generatedAt, timeoutMs),
    boundedRead("independentReview", options.readers?.independentReview, generatedAt, timeoutMs),
    boundedRead("ownerAuthorization", options.readers?.ownerAuthorization, generatedAt, timeoutMs),
  ]);
  return buildCanonicalStatusPack({
    generatedAt,
    expiresAt: new Date(now.getTime() + ttlMs).toISOString(),
    authorityPolicySha256: options.authorityPolicySha256,
    historicalSurfaceRegistrySha256: options.historicalSurfaceRegistrySha256,
    triage: options.triage,
    evidence: {
      memory,
      github,
      vercel,
      supabase,
      android,
      independentReview,
      ownerAuthorization,
    },
  });
}

module.exports = {
  CANONICAL_GOAL_IDS,
  CANONICAL_REPOSITORY,
  PROOF_STAGES,
  buildCanonicalStatusPack,
  canonicalStatusHash,
  canonicalStatusSemanticsValid,
  refreshCanonicalStatusPack,
  stableValue,
};
