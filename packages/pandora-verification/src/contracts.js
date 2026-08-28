"use strict";

const { createHash, randomUUID } = require("node:crypto");

const RUN_STATUSES = Object.freeze(["PENDING", "RUNNING", "PASS", "FAIL", "BLOCKED", "INCONCLUSIVE", "STALE"]);
const CHECK_STATUSES = Object.freeze(["PASS", "FAIL", "BLOCKED", "INCONCLUSIVE", "SKIPPED"]);
const FAILURE_CLASSES = Object.freeze([
  "source", "build", "unit_test", "integration", "browser", "visual", "accessibility",
  "security", "dependency", "migration", "runtime", "domain", "acceptance",
  "business_acceptance", "provider", "environment", "verification_infrastructure", "unknown",
]);
const SECURITY_SEVERITIES = Object.freeze(["INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"]);

const REQUIRED_IDENTITY_FIELDS = Object.freeze([
  "organization_id", "project_id", "project_spec_id", "project_version_id", "source_commit",
  "source_digest", "artifact_digest", "target_environment", "required_check_profile", "requested_by",
]);

function stableStringify(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
}

function sha256(value) {
  return createHash("sha256").update(Buffer.isBuffer(value) ? value : String(value)).digest("hex");
}

function requireString(name, value) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`verification identity: ${name} is required`);
}

function requireDigest(name, value) {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/i.test(value)) {
    throw new Error(`verification identity: ${name} must be a 64-hex digest`);
  }
}

function assertExactVerificationRequest(request, profiles) {
  if (!request || typeof request !== "object" || Array.isArray(request)) throw new Error("verification request must be an object");
  for (const field of REQUIRED_IDENTITY_FIELDS) requireString(field, request[field]);
  if (!/^[0-9a-f]{40}$/i.test(request.source_commit)) {
    throw new Error("verification identity: source_commit must be an exact 40-hex commit SHA");
  }
  requireDigest("source_digest", request.source_digest);
  requireDigest("artifact_digest", request.artifact_digest);
  if (request.migration_set_digest != null) requireDigest("migration_set_digest", request.migration_set_digest);
  if (request.runtime_target_digest != null) requireDigest("runtime_target_digest", request.runtime_target_digest);
  if (request.preview_deployment_id != null) requireString("preview_deployment_id", request.preview_deployment_id);
  if (!profiles[request.required_check_profile]) throw new Error(`verification request: unknown check profile ${request.required_check_profile}`);
  return true;
}

function identityEnvelope(request, profiles) {
  assertExactVerificationRequest(request, profiles);
  return {
    project_spec_id: request.project_spec_id,
    project_spec_version: request.project_spec_version ?? null,
    project_version_id: request.project_version_id,
    source_commit: request.source_commit.toLowerCase(),
    source_digest: request.source_digest.toLowerCase(),
    artifact_digest: request.artifact_digest.toLowerCase(),
    migration_set_digest: request.migration_set_digest?.toLowerCase() ?? null,
    preview_deployment_id: request.preview_deployment_id ?? null,
    target_environment: request.target_environment,
    runtime_target_digest: request.runtime_target_digest?.toLowerCase() ?? null,
    required_check_profile: request.required_check_profile,
  };
}

function identityDigest(request, profiles) {
  return sha256(stableStringify(identityEnvelope(request, profiles)));
}

function createEvidence({ type, data, mediaType = "application/json", createdAt = new Date().toISOString() }) {
  requireString("evidence type", type);
  return Object.freeze({
    evidence_id: randomUUID(), type, media_type: mediaType, created_at: createdAt,
    sha256: sha256(Buffer.isBuffer(data) ? data : stableStringify(data)), data,
  });
}

function requirementCoverage(requirements, results) {
  return (requirements ?? []).map((requirement) => {
    const requirementId = typeof requirement === "string" ? requirement : requirement.id;
    const matching = results.filter((result) => result.requirement_id === requirementId);
    let status = "NOT TESTABLE";
    if (matching.some((result) => result.status === "FAIL")) status = "FAIL";
    else if (matching.some((result) => result.status === "BLOCKED")) status = "BLOCKED";
    else if (matching.some((result) => result.status === "INCONCLUSIVE")) status = "INCONCLUSIVE";
    else if (matching.length > 0 && matching.every((result) => result.status === "PASS")) status = "PASS";
    return { requirement_id: requirementId, status, check_ids: matching.map((result) => result.check_id) };
  });
}

function repairFeedback(result) {
  if (!result || result.status === "PASS") return null;
  return Object.freeze({
    check: result.check_id,
    requirement_id: result.requirement_id ?? null,
    failure_class: result.failure_class ?? "unknown",
    summary: result.summary ?? "Verification failed.",
    evidence_refs: [...(result.evidence_refs ?? [])],
  });
}

module.exports = {
  RUN_STATUSES, CHECK_STATUSES, FAILURE_CLASSES, SECURITY_SEVERITIES,
  stableStringify, sha256, requireDigest, assertExactVerificationRequest,
  identityEnvelope, identityDigest, createEvidence, requirementCoverage, repairFeedback,
};
