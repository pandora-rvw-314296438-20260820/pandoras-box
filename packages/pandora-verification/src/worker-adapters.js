
"use strict";

const { requireDigest } = require("./contracts");

const WORKER_D_OPERATION_BY_CHECK = Object.freeze({
  source_lint: "run_lint",
  source_typecheck: "run_typecheck",
  unit_tests: "run_unit_tests",
  integration_tests: "run_integration_tests",
  reproducible_build: "build_project",
});

function requireUuid(value, name) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) throw new Error(`${name} must be a UUID`);
  return value.toLowerCase();
}
function requireCommit(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{40}$/.test(value)) throw new Error("source_commit must be exact 40-hex");
  return value;
}

function buildWorkerDVerificationRequest({ verificationRequest, checkId, executionId, buildJobId, idempotencyKey, attempt = 1, repository }) {
  const operation = WORKER_D_OPERATION_BY_CHECK[checkId];
  if (!operation) throw new Error(`Worker D adapter does not support ${checkId}`);
  const capability = ["run_unit_tests", "run_integration_tests"].includes(operation) ? "build.tests.execute" : "build.project.execute";
  return Object.freeze({
    schemaVersion: 1,
    executionId: requireUuid(executionId, "executionId"),
    buildJobId: requireUuid(buildJobId, "buildJobId"),
    projectId: requireUuid(verificationRequest.project_id, "projectId"),
    organizationId: requireUuid(verificationRequest.organization_id, "organizationId"),
    projectVersionId: requireUuid(verificationRequest.project_version_id, "projectVersionId"),
    source: Object.freeze({ kind: "git_commit", repository, commitSha: requireCommit(verificationRequest.source_commit) }),
    authorizedCapability: capability,
    operation,
    environment: "test",
    timeoutMs: 15 * 60 * 1000,
    networkPolicy: Object.freeze({ mode: "deny", allow: Object.freeze([]) }),
    credentialLeaseRefs: Object.freeze([]),
    idempotencyKey,
    attempt,
    arguments: Object.freeze({ verificationRunId: verificationRequest.verification_run_id, checkId, exactSourceDigest: verificationRequest.source_digest }),
  });
}

function workerDResultToIndependentOutcome(result, { requestedByVerifier = false } = {}) {
  if (!requestedByVerifier) return Object.freeze({ status: "INCONCLUSIVE", authoritative: false, failure_class: "verification_infrastructure", summary: "Builder-originated test receipt is evidence only." });
  if (!result || !["completed", "failed", "cancelled"].includes(result.status)) return Object.freeze({ status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Worker D result is unavailable or malformed." });
  if (result.status === "cancelled") return Object.freeze({ status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Verification sandbox execution was cancelled." });
  const pass = result.status === "completed" && result.exitCode === 0;
  return Object.freeze({
    status: pass ? "PASS" : "FAIL",
    authoritative: true,
    failure_class: pass ? null : (result.failureClass === "test" ? "integration" : result.failureClass ?? "build"),
    summary: pass ? "Worker E independently observed a successful sandbox execution." : "Worker E independently observed a failed sandbox execution.",
    evidence_refs: Object.freeze([result.stdoutArtifactRef, result.stderrArtifactRef, ...(result.artifactRefs ?? [])].filter(Boolean)),
  });
}

function workerFDeploymentToEvidence(fact) {
  if (!fact || typeof fact !== "object") throw new Error("Worker F deployment fact is required");
  if (fact.artifactDigest) requireDigest("artifactDigest", fact.artifactDigest);
  return Object.freeze({
    deployment_id: fact.providerDeploymentId ?? fact.deploymentId ?? null,
    url: fact.url ?? fact.providerUrl ?? null,
    provider_status: String(fact.providerState ?? fact.status ?? "").toUpperCase() || null,
    project_version_id: fact.projectVersionId ?? null,
    artifact_digest: fact.artifactDigest ?? null,
    source_commit: fact.sourceCommit ?? null,
    reproducible_lineage: Object.freeze([...(fact.reproducibleLineage ?? [])]),
  });
}

function workerFDomainToEvidence(fact, intendedDomain) {
  if (!fact || typeof fact !== "object") throw new Error("Worker F domain fact is required");
  return Object.freeze({
    intended_domain: intendedDomain,
    observed_domain: fact.domain ?? fact.observedDomain ?? null,
    ownership_verified: fact.ownershipVerified === true,
    dns_resolves: fact.dnsConfigured === true || fact.dnsResolves === true,
    tls_valid: fact.tlsReady === true || fact.tlsValid === true,
    routing_correct: fact.routingReady === true,
    unexpected_redirect: fact.unexpectedRedirect === true,
    project_binding_correct: fact.projectBindingCorrect !== false && Boolean(fact.projectId ?? fact.providerProjectId),
  });
}

module.exports = { WORKER_D_OPERATION_BY_CHECK, buildWorkerDVerificationRequest, workerDResultToIndependentOutcome, workerFDeploymentToEvidence, workerFDomainToEvidence };
