
"use strict";

const { detectProductionDrift } = require("./checks");
const { verifyProductionEvidence } = require("./execution");

const STORED_RUN_STATES = new Set([
  "PENDING",
  "RUNNING",
  "PASS",
  "FAIL",
  "BLOCKED",
  "INCONCLUSIVE",
  "STALE",
]);
const STORED_CHECK_STATES = new Set([
  "PASS",
  "FAIL",
  "BLOCKED",
  "INCONCLUSIVE",
  "SKIPPED",
]);
const COMMIT_SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;

function requiredText(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function assertDigest(value, label, pattern) {
  const normalized = requiredText(value, label);
  if (!pattern.test(normalized)) throw new Error(`${label} is invalid`);
  return normalized;
}

function checkFallbackStatement(checkKey, status) {
  const label = checkKey.replace(/[_-]+/g, " ").trim();
  const readable = label ? `${label[0].toUpperCase()}${label.slice(1)}` : "Verification check";
  const outcome = {
    PASS: "passed",
    FAIL: "failed",
    BLOCKED: "was blocked",
    INCONCLUSIVE: "was inconclusive",
    SKIPPED: "was skipped",
  }[status];
  return `${readable} ${outcome}.`;
}

function runHeadline(status) {
  return {
    PENDING: "Verification pending",
    RUNNING: "Verification in progress",
    PASS: "Verified",
    FAIL: "Verification failed",
    BLOCKED: "Verification blocked",
    INCONCLUSIVE: "Verification incomplete",
    STALE: "Verification no longer current",
  }[status];
}

function evidenceRef(evidence) {
  return Object.freeze({
    kind: "verification_evidence",
    id: requiredText(evidence.id, "verification evidence id"),
    evidence_type: requiredText(evidence.evidence_type, "verification evidence type"),
    content_sha256: assertDigest(
      evidence.content_sha256,
      "verification evidence content sha256",
      SHA256,
    ),
  });
}

function createCustomerVerificationReceipt({ run, checks = [], evidence = [] } = {}) {
  if (!run || typeof run !== "object" || Array.isArray(run)) {
    throw new Error("stored verification run is required");
  }
  if (!Array.isArray(checks)) throw new Error("stored verification checks must be an array");
  if (!Array.isArray(evidence)) throw new Error("stored verification evidence must be an array");

  const runId = requiredText(run.id, "verification run id");
  const runState = requiredText(run.status, "verification run status");
  if (!STORED_RUN_STATES.has(runState)) {
    throw new Error(`unsupported stored verification run status: ${runState}`);
  }

  const projectSpecId = requiredText(run.project_spec_id, "project spec id");
  const projectVersionId = requiredText(run.project_version_id, "project version id");
  const sourceCommit = assertDigest(run.source_commit, "source commit", COMMIT_SHA);
  const sourceDigest = assertDigest(run.source_digest, "source digest", SHA256);
  const artifactDigest = assertDigest(run.artifact_digest, "artifact digest", SHA256);
  const targetEnvironment = requiredText(run.target_environment, "target environment");

  const checkById = new Map();
  for (const check of checks) {
    if (!check || typeof check !== "object" || Array.isArray(check)) {
      throw new Error("stored verification check must be an object");
    }
    const checkId = requiredText(check.id, "verification check id");
    if (checkById.has(checkId)) throw new Error(`duplicate verification check id: ${checkId}`);
    if (requiredText(check.verification_run_id, "verification check run id") !== runId) {
      throw new Error(`verification check ${checkId} does not belong to run ${runId}`);
    }
    const status = requiredText(check.status, "verification check status");
    if (!STORED_CHECK_STATES.has(status)) {
      throw new Error(`unsupported stored verification check status: ${status}`);
    }
    requiredText(check.check_key, "verification check key");
    checkById.set(checkId, check);
  }

  const evidenceByCheck = new Map();
  const supportingEvidence = [];
  const evidenceIds = new Set();
  for (const item of evidence) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("stored verification evidence must be an object");
    }
    const id = requiredText(item.id, "verification evidence id");
    if (evidenceIds.has(id)) throw new Error(`duplicate verification evidence id: ${id}`);
    evidenceIds.add(id);
    if (requiredText(item.verification_run_id, "verification evidence run id") !== runId) {
      throw new Error(`verification evidence ${id} does not belong to run ${runId}`);
    }
    const ref = evidenceRef(item);
    if (item.verification_check_id == null) {
      supportingEvidence.push(ref);
      continue;
    }
    const checkId = requiredText(item.verification_check_id, "verification evidence check id");
    if (!checkById.has(checkId)) {
      throw new Error(`verification evidence ${id} references unknown check ${checkId}`);
    }
    const refs = evidenceByCheck.get(checkId) ?? [];
    refs.push(ref);
    evidenceByCheck.set(checkId, refs);
  }

  const orderedChecks = [...checkById.values()].sort((a, b) => {
    const byKey = String(a.check_key).localeCompare(String(b.check_key));
    return byKey || String(a.id).localeCompare(String(b.id));
  });

  const statements = orderedChecks.map((check) => {
    const checkId = requiredText(check.id, "verification check id");
    const checkKey = requiredText(check.check_key, "verification check key");
    const status = requiredText(check.status, "verification check status");
    const storedSummary = typeof check.summary === "string" ? check.summary.trim() : "";
    const refs = [...(evidenceByCheck.get(checkId) ?? [])].sort((a, b) =>
      a.id.localeCompare(b.id),
    );
    return Object.freeze({
      statement_id: `verification-check:${checkId}`,
      text: storedSummary || checkFallbackStatement(checkKey, status),
      status,
      check_key: checkKey,
      requirement_id:
        typeof check.requirement_id === "string" && check.requirement_id.trim()
          ? check.requirement_id.trim()
          : null,
      source_refs: Object.freeze([
        Object.freeze({ kind: "verification_run", id: runId }),
        Object.freeze({ kind: "verification_check", id: checkId }),
        ...refs,
      ]),
    });
  });

  return Object.freeze({
    schema: "pandora.customer-verification-receipt/1",
    schema_version: 1,
    verification_run_id: runId,
    project_spec_id: projectSpecId,
    project_version_id: projectVersionId,
    source_commit: sourceCommit,
    source_digest: sourceDigest,
    artifact_digest: artifactDigest,
    target_environment: targetEnvironment,
    verification_state: runState,
    headline: runHeadline(runState),
    headline_source_refs: Object.freeze([
      Object.freeze({ kind: "verification_run", id: runId }),
    ]),
    statements: Object.freeze(statements),
    supporting_evidence_refs: Object.freeze(
      supportingEvidence.sort((a, b) => a.id.localeCompare(b.id)),
    ),
  });
}

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

module.exports = {
  createCustomerVerificationReceipt,
  createReleaseReadinessReport,
  verifyRollbackTarget,
  classifyProductionVerification,
  historicalVerificationTimeline,
};
