const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const OBSERVER_ID = /^[a-z0-9][a-z0-9._:-]{2,127}$/;
const NONCE = /^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DEPLOYMENT_ID = /^dpl_[A-Za-z0-9]+$/;
const ARTIFACT_ID = /^[1-9][0-9]{0,19}$/;
const BASE64_SIGNATURE = /^[A-Za-z0-9+/]{86}==$/;
const RFC3339_MILLIS = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/;

const CANONICAL_REPOSITORY = "banataosystems/Pandoras-box";
const PRODUCTION_ORIGIN = "https://mcpmaster.vercel.app";
const PACKAGE_NAME = "com.banataosystems.pandora_mobile";
const REQUIRED_JOURNEY_STEPS = Object.freeze([
  "owner_authenticate",
  "submit_owner_command",
  "observe_durable_dispatch",
  "observe_worker_01_claim",
  "observe_exact_provider_result",
  "observe_proof_in_owner_read",
]);

const RECEIPT_KEYS = Object.freeze([
  "action",
  "apkSha256",
  "ciArtifactExternalId",
  "ciArtifactName",
  "ciArtifactSha256",
  "ciArtifactUrl",
  "completedSteps",
  "deviceIdHash",
  "network",
  "nonce",
  "observerId",
  "observerKeyFingerprint",
  "organizationId",
  "ownerDispatchId",
  "ownerPlanId",
  "packageName",
  "productionDeploymentId",
  "productionOrigin",
  "providerObservationIndex",
  "repository",
  "requestId",
  "reviewerRuntimeProofId",
  "schemaVersion",
  "signatureB64",
  "sourceSha",
  "sourceTreeSha",
  "timestamp",
  "verificationEvidenceId",
  "workerEvidenceSha256",
]);

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected) {
  if (!isRecord(value)) return false;
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
}

function validTimestamp(value, now = new Date()) {
  if (typeof value !== "string" || !RFC3339_MILLIS.test(value)) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed <= now.getTime() + 30_000 &&
    parsed >= now.getTime() - 5 * 60_000;
}

function validatePhysicalAndroidReceiptRequest(value, now = new Date()) {
  if (!exactKeys(value, RECEIPT_KEYS)) {
    throw new Error("INVALID_PHYSICAL_ANDROID_RECEIPT");
  }
  const expectedObservationIndex = value.network === "wifi" ? 1 : 2;
  const expectedArtifactUrl =
    `https://api.github.com/repos/${CANONICAL_REPOSITORY}/actions/artifacts/${value.ciArtifactExternalId}`;
  if (
    value.schemaVersion !== 1 || value.action !== "capture" ||
    !UUID.test(value.organizationId) || !UUID.test(value.requestId) ||
    !OBSERVER_ID.test(value.observerId) || !NONCE.test(value.nonce) ||
    !SHA256.test(value.observerKeyFingerprint) ||
    value.repository !== CANONICAL_REPOSITORY ||
    !SHA40.test(value.sourceSha) || !SHA40.test(value.sourceTreeSha) ||
    !DEPLOYMENT_ID.test(value.productionDeploymentId) ||
    value.productionOrigin !== PRODUCTION_ORIGIN ||
    !ARTIFACT_ID.test(value.ciArtifactExternalId) ||
    value.ciArtifactUrl !== expectedArtifactUrl ||
    value.ciArtifactName !== `pandora-mobile-android-validation-${value.sourceSha}` ||
    !SHA256.test(value.ciArtifactSha256) || !SHA256.test(value.apkSha256) ||
    !SHA256.test(value.deviceIdHash) || value.packageName !== PACKAGE_NAME ||
    !["wifi", "mobile_data"].includes(value.network) ||
    value.providerObservationIndex !== expectedObservationIndex ||
    !Array.isArray(value.completedSteps) ||
    value.completedSteps.length !== REQUIRED_JOURNEY_STEPS.length ||
    !value.completedSteps.every((step, index) => step === REQUIRED_JOURNEY_STEPS[index]) ||
    !UUID.test(value.ownerPlanId) || !UUID.test(value.ownerDispatchId) ||
    !SHA256.test(value.workerEvidenceSha256) ||
    !UUID.test(value.verificationEvidenceId) ||
    !UUID.test(value.reviewerRuntimeProofId) ||
    !validTimestamp(value.timestamp, now) ||
    !BASE64_SIGNATURE.test(value.signatureB64)
  ) {
    throw new Error("INVALID_PHYSICAL_ANDROID_RECEIPT");
  }
  return value;
}

function physicalAndroidReceiptSignatureBasis(value) {
  const signedAt = typeof value?.timestamp === "string"
    ? new Date(value.timestamp)
    : new Date(Number.NaN);
  validatePhysicalAndroidReceiptRequest(value, signedAt);
  return [
    "pandora-physical-android-request-v1",
    "capture",
    value.organizationId,
    value.observerId,
    value.observerKeyFingerprint,
    value.requestId,
    value.nonce,
    value.timestamp,
    value.repository,
    value.sourceSha,
    value.sourceTreeSha,
    value.productionDeploymentId,
    value.productionOrigin,
    value.ciArtifactExternalId,
    value.ciArtifactUrl,
    value.ciArtifactName,
    value.ciArtifactSha256,
    value.apkSha256,
    value.deviceIdHash,
    value.packageName,
    value.network,
    String(value.providerObservationIndex),
    value.completedSteps.join(","),
    value.ownerPlanId,
    value.ownerDispatchId,
    value.workerEvidenceSha256,
    value.verificationEvidenceId,
    value.reviewerRuntimeProofId,
  ].join("|");
}

export {
  BASE64_SIGNATURE,
  RECEIPT_KEYS,
  REQUIRED_JOURNEY_STEPS,
  physicalAndroidReceiptSignatureBasis,
  validatePhysicalAndroidReceiptRequest,
};
