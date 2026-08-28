"use strict";

const { PandoraToolError } = require("./errors");

// Worker C capability (external authorization) and Worker D capability
// (bounded builder operation) are deliberately distinct contracts.
const BUILD_OPERATION_MAP = Object.freeze({
  list_files: Object.freeze({ operation: "list_files", gatewayCapability: "workspace.files.read", workerCapability: "build.files.read" }),
  read_file: Object.freeze({ operation: "read_file", gatewayCapability: "workspace.files.read", workerCapability: "build.files.read" }),
  write_file: Object.freeze({ operation: "write_file", gatewayCapability: "workspace.files.write", workerCapability: "build.files.write" }),
  delete_file: Object.freeze({ operation: "delete_file", gatewayCapability: "workspace.files.delete", workerCapability: "build.files.write" }),
  move_file: Object.freeze({ operation: "move_file", gatewayCapability: "workspace.files.write", workerCapability: "build.files.write" }),
  request_build: Object.freeze({ operation: "build_project", gatewayCapability: "build.execute", workerCapability: "build.project.execute" }),
  request_tests: Object.freeze({ operation: "run_integration_tests", gatewayCapability: "test.execute", workerCapability: "build.tests.execute" }),
  create_artifact: Object.freeze({ operation: "collect_artifacts", gatewayCapability: "artifact.write", workerCapability: "build.artifacts.collect" }),
});

function toWorkerDBuildExecutionRequest(executionRequest, trusted) {
  const mapped = BUILD_OPERATION_MAP[executionRequest.tool];
  if (!mapped) throw new PandoraToolError("policy_denied", "WORKER_D_OPERATION_UNSUPPORTED", "Tool cannot be delegated to the build runtime");
  if (!trusted?.execution_id || !trusted?.build_job_id || !trusted?.project_version_id || !trusted?.source) throw new PandoraToolError("invalid_request", "WORKER_D_TRUSTED_CONTEXT_INCOMPLETE", "Build runtime delegation requires exact trusted identity");
  if (!executionRequest.action_hash) throw new PandoraToolError("invalid_request", "WORKER_C_AUTHORIZATION_IDENTITY_MISSING", "Build runtime delegation requires an exact Worker C authorization identity");
  const environment = executionRequest.environment === "development" ? "sandbox" : executionRequest.tool === "request_tests" ? "test" : "preview-build";
  const idempotencyKey = executionRequest.arguments.idempotency_key;
  const request = Object.freeze({
    schemaVersion: 1,
    executionId: trusted.execution_id,
    buildJobId: trusted.build_job_id,
    projectId: executionRequest.project_id,
    organizationId: executionRequest.organization_id,
    projectVersionId: trusted.project_version_id,
    source: structuredClone(trusted.source),
    authorizedCapability: mapped.workerCapability,
    operation: mapped.operation,
    environment,
    timeoutMs: trusted.timeout_ms,
    resourceLimits: structuredClone(trusted.resource_limits || {}),
    networkPolicy: structuredClone(trusted.network_policy || { mode: "deny" }),
    credentialLeaseRefs: [...(trusted.credential_lease_refs || [])],
    idempotencyKey,
    attempt: trusted.attempt || 1,
    cancellationRef: trusted.cancellation_ref || null,
    arguments: structuredClone(executionRequest.arguments),
  });
  const gatewayAuthorization = Object.freeze({
    version: 1,
    tool: executionRequest.tool,
    capability: mapped.gatewayCapability,
    projectId: executionRequest.project_id,
    projectVersionId: trusted.project_version_id,
    environment: executionRequest.environment,
    authorizationId: executionRequest.action_hash,
    idempotencyKey,
  });
  return Object.freeze({ request, gatewayAuthorization });
}

function workerEVerificationContext(summary, projectId) {
  if (!summary || summary.verification !== "PASS" || summary.publish_eligible !== true) throw new PandoraToolError("verification_required", "WORKER_E_NOT_PUBLISH_ELIGIBLE", "Independent verification is not publish eligible");
  if (summary.failed_checks?.length || summary.blocked_checks?.length || summary.missing_checks?.length) throw new PandoraToolError("verification_required", "WORKER_E_RELEASE_READINESS_INCOMPLETE", "Independent verification is not publish eligible");
  return Object.freeze({
    verification: "PASS",
    publish_eligible: true,
    verification_run_id: summary.verification_run_id,
    project_id: projectId,
    project_spec_id: summary.project_spec_id ?? null,
    project_spec_version: summary.project_spec_version ?? null,
    project_version_id: summary.project_version_id,
    artifact_digest: summary.artifact_digest,
    source_commit: summary.source_commit,
    source_digest: summary.source_digest,
    evidence_refs: [...(summary.evidence_refs || [])],
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
