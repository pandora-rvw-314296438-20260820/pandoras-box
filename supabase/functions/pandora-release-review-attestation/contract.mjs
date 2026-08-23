const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REVIEWER_ID = /^[a-z0-9][a-z0-9._:-]{2,127}$/;
const NONCE = /^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DEPLOYMENT_ID = /^dpl_[A-Za-z0-9]+$/;
const EXTERNAL_ID = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,191}$/;
const BASE64_SIGNATURE = /^[A-Za-z0-9+/]{86}==$/;
const CANONICAL_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CANONICAL_REPOSITORY = "banataosystems/Pandoras-box";

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
  if (typeof value !== "string" || !CANONICAL_TIMESTAMP.test(value)) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && Math.abs(parsed - now.getTime()) <= 5 * 60 * 1000;
}

function validReviewUrl(value) {
  if (typeof value !== "string" || value.length < 12 || value.length > 2048) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
}

const RELEASE_REVIEW_KEYS = Object.freeze([
  "action",
  "nonce",
  "organizationId",
  "productionDeploymentId",
  "repository",
  "requestId",
  "reviewDigest",
  "reviewExternalId",
  "reviewSourceUrl",
  "reviewerId",
  "rollbackDeploymentId",
  "schemaVersion",
  "signatureB64",
  "sourceSha",
  "sourceTreeSha",
  "supabaseMigrationChainSha256",
  "timestamp",
  "verifierRuntimeProofId",
]);

function validateReleaseReviewRequest(value, now = new Date()) {
  if (!exactKeys(value, RELEASE_REVIEW_KEYS)) {
    throw new Error("INVALID_RELEASE_REVIEW_ATTESTATION");
  }
  if (
    value.schemaVersion !== 1 || value.action !== "attest_canonical_release" ||
    !UUID.test(value.organizationId) || !UUID.test(value.requestId) ||
    !UUID.test(value.verifierRuntimeProofId) ||
    !REVIEWER_ID.test(value.reviewerId) || !NONCE.test(value.nonce) ||
    !BASE64_SIGNATURE.test(value.signatureB64) ||
    value.repository !== CANONICAL_REPOSITORY ||
    !SHA40.test(value.sourceSha) || !SHA40.test(value.sourceTreeSha) ||
    !DEPLOYMENT_ID.test(value.productionDeploymentId) ||
    !DEPLOYMENT_ID.test(value.rollbackDeploymentId) ||
    value.productionDeploymentId === value.rollbackDeploymentId ||
    !SHA256.test(value.supabaseMigrationChainSha256) ||
    !EXTERNAL_ID.test(value.reviewExternalId) ||
    !validReviewUrl(value.reviewSourceUrl) ||
    !SHA256.test(value.reviewDigest) ||
    !validTimestamp(value.timestamp, now)
  ) {
    throw new Error("INVALID_RELEASE_REVIEW_ATTESTATION");
  }
  return value;
}

function releaseReviewSignatureBasis(value) {
  validateReleaseReviewRequest(value);
  return `pandora-canonical-release-review-v1|${JSON.stringify([
    value.organizationId,
    value.requestId,
    value.reviewerId,
    value.verifierRuntimeProofId,
    value.nonce,
    value.timestamp,
    value.repository,
    value.sourceSha,
    value.sourceTreeSha,
    value.productionDeploymentId,
    value.rollbackDeploymentId,
    value.supabaseMigrationChainSha256,
    value.reviewExternalId,
    value.reviewSourceUrl,
    value.reviewDigest,
    "approved",
  ])}`;
}

function releaseReviewAuthorityBasis(
  value,
  reviewerKeyFingerprint,
  signatureSha256,
) {
  validateReleaseReviewRequest(value);
  if (!SHA256.test(reviewerKeyFingerprint) || !SHA256.test(signatureSha256)) {
    throw new Error("INVALID_RELEASE_REVIEW_AUTHORITY_BINDING");
  }
  return [
    "pandora-release-review-authority-v1",
    value.organizationId,
    value.requestId,
    value.reviewerId,
    value.verifierRuntimeProofId,
    reviewerKeyFingerprint,
    value.nonce,
    value.timestamp,
    value.repository,
    value.sourceSha,
    value.sourceTreeSha,
    value.productionDeploymentId,
    value.rollbackDeploymentId,
    value.supabaseMigrationChainSha256,
    value.reviewExternalId,
    value.reviewSourceUrl,
    value.reviewDigest,
    signatureSha256,
    "approved",
  ].join("|");
}

export {
  BASE64_SIGNATURE,
  RELEASE_REVIEW_KEYS,
  releaseReviewAuthorityBasis,
  releaseReviewSignatureBasis,
  validateReleaseReviewRequest,
};
