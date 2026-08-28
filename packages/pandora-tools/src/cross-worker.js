"use strict";

const { PandoraToolError } = require("./errors");

const BUILD_OPERATION_MAP = Object.freeze({
  list_files: ["list_files", "build.files.read"],
  read_file: ["read_file", "build.files.read"],
  write_file: ["write_file", "build.files.write"],
  delete_file: ["delete_file", "build.files.write"],
  move_file: ["move_file", "build.files.write"],
  request_build: ["build_project", "build.project.execute"],
  request_tests: ["run_integration_tests", "build.tests.execute"],
});

function toWorkerDBuildExecutionRequest(executionRequest, trusted) {
  const mapped = BUILD_OPERATION_MAP[executionRequest.tool];
  if (!mapped) throw new PandoraToolError("policy_denied", "WORKER_D_OPERATION_UNSUPPORTED", "Tool cannot be delegated to the build runtime");
  if (!trusted?.execution_id || !trusted?.build_job_id || !trusted?.project_version_id || !trusted?.source) throw new PandoraToolError("invalid_request", "WORKER_D_TRUSTED_CONTEXT_INCOMPLETE", "Build runtime delegation requires exact trusted identity");
  const environment = executionRequest.environment === "development" ? "sandbox" : executionRequest.tool === "request_tests" ? "test" : "preview-build";
  return Object.freeze({
    schemaVersion: 1,
    executionId: trusted.execution_id,
    buildJobId: trusted.build_job_id,
    projectId: executionRequest.project_id,
    organizationId: executionRequest.organization_id,
    projectVersionId: trusted.project_version_id,
    source: structuredClone(trusted.source),
    authorizedCapability: mapped[1],
    operation: mapped[0],
    environment,
    timeoutMs: trusted.timeout_ms,
    resourceLimits: structuredClone(trusted.resource_limits || {}),
    networkPolicy: structuredClone(trusted.network_policy || { mode: "deny" }),
    credentialLeaseRefs: [...(trusted.credential_lease_refs || [])],
    idempotencyKey: executionRequest.arguments.idempotency_key,
    attempt: trusted.attempt || 1,
    cancellationRef: trusted.cancellation_ref || null,
    arguments: structuredClone(executionRequest.arguments),
  });
}

function workerEVerificationContext(summary, projectId) {
  if (!summary || summary.verification !== "PASS" || summary.publish_eligible !== true) throw new PandoraToolError("verification_required", "WORKER_E_NOT_PUBLISH_ELIGIBLE", "Independent verification is not publish eligible");
  return Object.freeze({
    verification: "PASS",
    publish_eligible: true,
    verification_run_id: summary.verification_run_id,
    project_id: projectId,
    project_version_id: summary.project_version_id,
    artifact_digest: summary.artifact_digest,
    project_spec_version: summary.project_spec_version,
    source_commit: summary.source_commit,
    source_digest: summary.source_digest,
  });
}

function toWorkerFDeploymentRequest(executionRequest, { source_commit, verification_ref, expected_production_version_id = null, allow_first_production = false, runtime_type = "web_app", provider = "vercel" }) {
  if (executionRequest.tool !== "request_publish") throw new PandoraToolError("policy_denied", "WORKER_F_PUBLISH_ONLY", "Deployment publish request expected");
  if (!source_commit || !verification_ref) throw new PandoraToolError("invalid_request", "WORKER_F_TRUSTED_CONTEXT_INCOMPLETE", "Deployment requires exact source and verification references");
  return Object.freeze({
    organizationId: executionRequest.organization_id,
    projectId: executionRequest.project_id,
    projectVersionId: executionRequest.arguments.version_id,
    artifactDigest: executionRequest.arguments.artifact_digest,
    sourceCommit: source_commit,
    environment: "production",
    authorizationRef: executionRequest.action_hash,
    verificationRef: verification_ref,
    provider,
    runtimeType: runtime_type,
    expectedProductionVersionId: expected_production_version_id,
    allowFirstProduction: allow_first_production === true,
  });
}

module.exports = { BUILD_OPERATION_MAP, toWorkerDBuildExecutionRequest, workerEVerificationContext, toWorkerFDeploymentRequest };
