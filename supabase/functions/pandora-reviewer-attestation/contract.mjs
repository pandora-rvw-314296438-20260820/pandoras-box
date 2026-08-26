const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const REVIEWER_ID = /^[a-z0-9][a-z0-9._:-]{2,127}$/;
const NONCE = /^[A-Za-z0-9._:-]{16,128}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const BASE64_SIGNATURE = /^[A-Za-z0-9+/]{86}==$/;
const RFC3339_MILLIS = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/;
const CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";

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
  return Number.isFinite(parsed) && Math.abs(parsed - now.getTime()) <= 5 * 60 * 1000;
}

const ATTESTATION_KEYS = Object.freeze([
  "action",
  "decision",
  "dispatchId",
  "exactSha",
  "nonce",
  "organizationId",
  "planId",
  "repository",
  "requestId",
  "reviewArtifactSha256",
  "reviewerId",
  "schemaVersion",
  "signatureB64",
  "sourceTreeSha",
  "timestamp",
  "verifierRuntimeProofId",
  "workerEvidenceSha256",
]);

function validateReviewerAttestationRequest(value, now = new Date()) {
  if (!exactKeys(value, ATTESTATION_KEYS)) {
    throw new Error("INVALID_REVIEWER_ATTESTATION");
  }
  if (
    value.schemaVersion !== 1 || value.action !== "attest" ||
    !UUID.test(value.organizationId) || !UUID.test(value.requestId) ||
    !UUID.test(value.dispatchId) || !UUID.test(value.planId) ||
    !UUID.test(value.verifierRuntimeProofId) ||
    !REVIEWER_ID.test(value.reviewerId) || !NONCE.test(value.nonce) ||
    !BASE64_SIGNATURE.test(value.signatureB64) ||
    value.repository !== CANONICAL_REPOSITORY ||
    !SHA40.test(value.exactSha) || !SHA40.test(value.sourceTreeSha) ||
    !SHA256.test(value.workerEvidenceSha256) ||
    !SHA256.test(value.reviewArtifactSha256) ||
    !["pass", "fail"].includes(value.decision) ||
    !validTimestamp(value.timestamp, now)
  ) {
    throw new Error("INVALID_REVIEWER_ATTESTATION");
  }
  return value;
}

function reviewerAttestationSignatureBasis(value) {
  const signedAt = typeof value?.timestamp === "string"
    ? new Date(value.timestamp)
    : new Date(Number.NaN);
  validateReviewerAttestationRequest(value, signedAt);
  return [
    "pandora-reviewer-request-v1",
    "attest",
    value.organizationId,
    value.reviewerId,
    value.requestId,
    value.nonce,
    value.timestamp,
    value.dispatchId,
    value.planId,
    value.verifierRuntimeProofId,
    value.workerEvidenceSha256,
    value.repository,
    value.exactSha,
    value.sourceTreeSha,
    value.decision,
    value.reviewArtifactSha256,
  ].join("|");
}

export {
  ATTESTATION_KEYS,
  BASE64_SIGNATURE,
  reviewerAttestationSignatureBasis,
  validateReviewerAttestationRequest,
};
