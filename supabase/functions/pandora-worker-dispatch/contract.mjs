const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const WORKER_ID = /^[a-z0-9][a-z0-9._:-]{2,127}$/;
const NONCE = /^[A-Za-z0-9._:-]{16,128}$/;
const BASE64_SIGNATURE = /^[A-Za-z0-9+/]{86}==$/;
const ALLOWED_JOB_CLASSES = new Set(["node_regression", "supabase_migration_replay"]);

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
  if (typeof value !== "string") return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && Math.abs(parsed - now.getTime()) <= 5 * 60 * 1000;
}

function validateClaimRequest(value, now = new Date()) {
  const keys = [
    "action",
    "nonce",
    "organizationId",
    "requestId",
    "schemaVersion",
    "signatureB64",
    "timestamp",
    "workerId",
  ];
  if (!exactKeys(value, keys)) throw new Error("INVALID_CLAIM_REQUEST");
  if (
    value.schemaVersion !== 1 || value.action !== "claim" ||
    !UUID.test(value.organizationId) || !UUID.test(value.requestId) ||
    !WORKER_ID.test(value.workerId) || !NONCE.test(value.nonce) ||
    !BASE64_SIGNATURE.test(value.signatureB64) ||
    !validTimestamp(value.timestamp, now)
  ) {
    throw new Error("INVALID_CLAIM_REQUEST");
  }
  return value;
}

function claimSignatureBasis(value) {
  return [
    "pandora-worker-request-v1",
    "claim",
    value.organizationId,
    value.workerId,
    value.requestId,
    value.nonce,
    value.timestamp,
  ].join("|");
}

const RESULT_KEYS = [
  "acquisitionImageDigest",
  "completedAt",
  "dispatchId",
  "exactSha",
  "exitCode",
  "isolation",
  "jobClass",
  "jobDigest",
  "networkPolicy",
  "organizationId",
  "outcome",
  "planId",
  "productionMutationAllowed",
  "repository",
  "runnerImageDigest",
  "runnerPolicyHash",
  "schemaVersion",
  "sourceTreeSha",
  "startedAt",
  "stderrSha256",
  "stdoutSha256",
  "testsDiscovered",
  "workerId",
];

function validateResultSummary(value) {
  if (!exactKeys(value, RESULT_KEYS)) throw new Error("INVALID_RESULT_SUMMARY");
  const started = Date.parse(value.startedAt);
  const completed = Date.parse(value.completedAt);
  if (
    value.schemaVersion !== 1 || !UUID.test(value.organizationId) ||
    !UUID.test(value.dispatchId) || !UUID.test(value.planId) ||
    !WORKER_ID.test(value.workerId) || !SHA256.test(value.jobDigest) ||
    value.repository !== "pandora-rvw-314296438-20260820/pandoras-box" ||
    !SHA40.test(value.exactSha) || !ALLOWED_JOB_CLASSES.has(value.jobClass) ||
    !["completed", "failed"].includes(value.outcome) ||
    !Number.isInteger(value.exitCode) || value.exitCode < 0 || value.exitCode > 255 ||
    value.isolation !== "hyperv_container" || value.networkPolicy !== "none" ||
    value.productionMutationAllowed !== false || !SHA256.test(value.runnerPolicyHash) ||
    !/^sha256:[0-9a-f]{64}$/.test(value.runnerImageDigest) ||
    !/^sha256:[0-9a-f]{64}$/.test(value.acquisitionImageDigest) ||
    !SHA40.test(value.sourceTreeSha) ||
    !Number.isInteger(value.testsDiscovered) || value.testsDiscovered < 0 ||
    !Number.isFinite(started) || !Number.isFinite(completed) || completed < started ||
    !SHA256.test(value.stdoutSha256) || !SHA256.test(value.stderrSha256) ||
    (value.outcome === "completed" && (value.exitCode !== 0 || value.testsDiscovered < 1))
  ) {
    throw new Error("INVALID_RESULT_SUMMARY");
  }
  return value;
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256BytesHex(value) {
  const digest = await crypto.subtle.digest("SHA-256", value);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function signatureBytes(value) {
  if (!BASE64_SIGNATURE.test(value)) throw new Error("INVALID_WORKER_SIGNATURE");
  try {
    const binary = atob(value);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    if (bytes.byteLength !== 64) throw new Error("INVALID_WORKER_SIGNATURE");
    return bytes;
  } catch {
    throw new Error("INVALID_WORKER_SIGNATURE");
  }
}

async function workerAuthorityRequestHash(purpose, request, workerKeyFingerprint) {
  if (
    !["worker_claim", "worker_complete"].includes(purpose) ||
    !SHA256.test(workerKeyFingerprint) ||
    request?.action !== (purpose === "worker_claim" ? "claim" : "complete")
  ) {
    throw new Error("INVALID_WORKER_AUTHORITY_REQUEST");
  }
  const basis = purpose === "worker_claim"
    ? claimSignatureBasis(request)
    : completeSignatureBasis(request);
  const basisSha256 = await sha256Hex(basis);
  const signatureSha256 = await sha256BytesHex(signatureBytes(request.signatureB64));
  return sha256Hex([
    "pandora-worker-authority-v1",
    purpose,
    basisSha256,
    workerKeyFingerprint,
    signatureSha256,
  ].join("|"));
}

function resultEvidenceBasis(value) {
  validateResultSummary(value);
  return [
    "projectos-worker-evidence-v1",
    String(value.schemaVersion),
    value.organizationId,
    value.dispatchId,
    value.planId,
    value.workerId,
    value.jobDigest,
    value.repository,
    value.exactSha,
    value.jobClass,
    value.outcome,
    String(value.exitCode),
    value.isolation,
    value.networkPolicy,
    String(value.productionMutationAllowed),
    value.runnerPolicyHash,
    value.runnerImageDigest,
    value.acquisitionImageDigest,
    value.sourceTreeSha,
    String(value.testsDiscovered),
    value.startedAt,
    value.completedAt,
    value.stdoutSha256,
    value.stderrSha256,
  ].join("|");
}

async function resultEvidenceHash(value) {
  return sha256Hex(resultEvidenceBasis(value));
}

function validateCompleteRequest(value, now = new Date(), allowAuthorityReplay = false) {
  const keys = [
    "action",
    "dispatchId",
    "durationMs",
    "evidenceSha256",
    "jobDigest",
    "nonce",
    "organizationId",
    "outcome",
    "planId",
    "requestId",
    "resultSummary",
    "schemaVersion",
    "signatureB64",
    "timestamp",
    "workerId",
  ];
  if (!exactKeys(value, keys)) throw new Error("INVALID_COMPLETE_REQUEST");
  validateResultSummary(value.resultSummary);
  if (
    value.schemaVersion !== 1 || value.action !== "complete" ||
    !UUID.test(value.organizationId) || !UUID.test(value.dispatchId) ||
    !UUID.test(value.planId) || !UUID.test(value.requestId) ||
    !WORKER_ID.test(value.workerId) || !NONCE.test(value.nonce) ||
    !BASE64_SIGNATURE.test(value.signatureB64) ||
    !["completed", "failed"].includes(value.outcome) ||
    !Number.isInteger(value.durationMs) || value.durationMs < 0 || value.durationMs > 2100000 ||
    !SHA256.test(value.jobDigest) || !SHA256.test(value.evidenceSha256) ||
    (!allowAuthorityReplay && !validTimestamp(value.timestamp, now)) ||
    value.resultSummary.organizationId !== value.organizationId ||
    value.resultSummary.dispatchId !== value.dispatchId ||
    value.resultSummary.planId !== value.planId ||
    value.resultSummary.workerId !== value.workerId ||
    value.resultSummary.jobDigest !== value.jobDigest ||
    value.resultSummary.outcome !== value.outcome
  ) {
    throw new Error("INVALID_COMPLETE_REQUEST");
  }
  return value;
}

function completeSignatureBasis(value) {
  return [
    "pandora-worker-request-v1",
    "complete",
    value.organizationId,
    value.workerId,
    value.requestId,
    value.nonce,
    value.timestamp,
    value.dispatchId,
    value.planId,
    value.jobDigest,
    value.outcome,
    String(value.durationMs),
    value.evidenceSha256,
  ].join("|");
}

function validateJobPayload(value) {
  const keys = [
    "acquisitionImageDigest",
    "audience",
    "dispatchId",
    "exactSha",
    "expiresAt",
    "isolation",
    "issuedAt",
    "jobClass",
    "maxRuntimeSeconds",
    "networkPolicy",
    "organizationId",
    "planId",
    "productionMutationAllowed",
    "repository",
    "runnerImageDigest",
    "runnerPolicyHash",
    "schemaVersion",
  ];
  if (!exactKeys(value, keys)) throw new Error("INVALID_JOB_PAYLOAD");
  if (
    value.schemaVersion !== 1 || !/^pandora-worker:[a-z0-9][a-z0-9._:-]{2,127}$/.test(value.audience) ||
    !UUID.test(value.organizationId) || !UUID.test(value.dispatchId) ||
    !UUID.test(value.planId) || value.repository !== "pandora-rvw-314296438-20260820/pandoras-box" ||
    !SHA40.test(value.exactSha) || !ALLOWED_JOB_CLASSES.has(value.jobClass) ||
    !Number.isInteger(value.maxRuntimeSeconds) || value.maxRuntimeSeconds < 30 ||
    value.maxRuntimeSeconds > 1800 || !Number.isFinite(Date.parse(value.issuedAt)) ||
    !Number.isFinite(Date.parse(value.expiresAt)) || Date.parse(value.expiresAt) <= Date.parse(value.issuedAt) ||
    !SHA256.test(value.runnerPolicyHash) || !/^sha256:[0-9a-f]{64}$/.test(value.runnerImageDigest) ||
    !/^sha256:[0-9a-f]{64}$/.test(value.acquisitionImageDigest) ||
    value.networkPolicy !== "none" || value.isolation !== "hyperv_container" ||
    value.productionMutationAllowed !== false
  ) {
    throw new Error("INVALID_JOB_PAYLOAD");
  }
  return value;
}

function jobDigestBasis(value) {
  validateJobPayload(value);
  return [
    "projectos-worker-job-v1",
    String(value.schemaVersion),
    value.audience,
    value.organizationId,
    value.dispatchId,
    value.planId,
    value.repository,
    value.exactSha,
    value.jobClass,
    String(value.maxRuntimeSeconds),
    value.issuedAt,
    value.expiresAt,
    value.runnerPolicyHash,
    value.runnerImageDigest,
    value.acquisitionImageDigest,
    value.networkPolicy,
    value.isolation,
    String(value.productionMutationAllowed),
  ].join("|");
}

async function jobDigest(value) {
  return sha256Hex(jobDigestBasis(value));
}

export {
  BASE64_SIGNATURE,
  claimSignatureBasis,
  completeSignatureBasis,
  jobDigest,
  jobDigestBasis,
  resultEvidenceHash,
  resultEvidenceBasis,
  workerAuthorityRequestHash,
  validateClaimRequest,
  validateCompleteRequest,
  validateJobPayload,
  validateResultSummary,
};
