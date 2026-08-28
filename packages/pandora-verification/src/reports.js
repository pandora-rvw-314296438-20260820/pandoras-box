
"use strict";

const { detectProductionDrift } = require("./checks");
const { verifyProductionEvidence } = require("./execution");

function createReleaseReadinessReport(readiness) {
  if (!readiness || typeof readiness !== "object") throw new Error("release readiness is required");
  const decision = readiness.publish_eligible === true ? "ELIGIBLE" : "NOT_ELIGIBLE";
  const blockers = [
    ...(readiness.failed_checks ?? []).map((check) => ({ type: "failed_check", check })),
    ...(readiness.blocked_checks ?? []).map((check) => ({ type: "blocked_check", check })),
    ...(readiness.missing_checks ?? []).map((check) => ({ type: "missing_check", check })),
    ...(readiness.expired_checks ?? []).map((check) => ({ type: "expired_check", check })),
  ];
  return Object.freeze({
    schema_version: 1,
    verification_run_id: readiness.verification_run_id,
    project_spec_id: readiness.project_spec_id,
    project_spec_version: readiness.project_spec_version,
    project_version_id: readiness.project_version_id,
    source_commit: readiness.source_commit,
    source_digest: readiness.source_digest,
    artifact_digest: readiness.artifact_digest,
    verification_state: readiness.verification,
    freshness: readiness.freshness ?? "unknown",
    production_eligible: readiness.publish_eligible === true,
    decision,
    required_checks: Object.freeze([...(readiness.required_checks ?? [])]),
    blockers: Object.freeze(blockers),
    requirement_coverage: Object.freeze([...(readiness.requirement_coverage ?? [])]),
    evidence_refs: Object.freeze([...(readiness.evidence_refs ?? [])]),
    human_summary: readiness.publish_eligible === true
      ? "This exact version has current required verification evidence and is eligible for Worker C publish policy evaluation."
      : `This exact version is not publish eligible; ${blockers.length} verification blocker(s) remain.`,
  });
}

function verifyRollbackTarget({ request, targetVersionId, deployment, domain, probes = [] }) {
  if (request.project_version_id !== targetVersionId) return Object.freeze({ status: "FAIL", failure_class: "runtime", summary: "Rollback request does not identify the intended exact target version." });
  const result = verifyProductionEvidence({ request, deployment, domain, probes });
  if (result.status !== "PASS") return Object.freeze({ ...result, rollback_target_verified: false });
  return Object.freeze({ ...result, rollback_target_verified: true, summary: "Exact rollback target and post-rollback runtime verified." });
}

function classifyProductionVerification({ verifiedDeploymentId, currentDeploymentId, verifiedArtifactDigest, currentArtifactDigest, evidenceExpiresAt, domainMatches, runtimeHealthy, now = Date.now() }) {
  return detectProductionDrift({ verifiedDeploymentId, currentDeploymentId, verifiedArtifactDigest, currentArtifactDigest, evidenceExpiresAt, domainMatches, runtimeHealthy, now });
}

function historicalVerificationTimeline(runs) {
  if (!Array.isArray(runs)) throw new Error("runs must be an array");
  return Object.freeze(runs.map((run) => Object.freeze({ verification_run_id: run.verification_run_id, retry_of: run.retry_of ?? null, project_version_id: run.request?.project_version_id ?? null, status: run.status, completed_at: run.completed_at ?? null, invalidated_at: run.invalidated_at ?? null })));
}

module.exports = { createReleaseReadinessReport, verifyRollbackTarget, classifyProductionVerification, historicalVerificationTimeline };
