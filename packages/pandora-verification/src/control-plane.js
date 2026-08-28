
"use strict";

function assertIndependentIdentity(builderIdentity, verifierIdentity) {
  if (typeof verifierIdentity !== "string" || !verifierIdentity.trim()) throw new Error("verifier identity is required");
  if (builderIdentity && builderIdentity === verifierIdentity) throw new Error("builder and verifier identities must be independent");
  return true;
}

function toVerificationRunRow(run, { verifierIdentity, builderIdentity = null, buildJobId = null } = {}) {
  assertIndependentIdentity(builderIdentity, verifierIdentity);
  const request = run.request;
  return Object.freeze({ id: run.verification_run_id, organization_id: request.organization_id, project_id: request.project_id, project_spec_id: request.project_spec_id, project_version_id: request.project_version_id, build_job_id: buildJobId, source_commit: request.source_commit, source_digest: request.source_digest, artifact_digest: request.artifact_digest, migration_set_digest: request.migration_set_digest ?? null, runtime_target_digest: request.runtime_target_digest ?? null, preview_deployment_id: request.preview_deployment_id ?? null, target_environment: request.target_environment, required_check_profile: request.required_check_profile, requested_by: request.requested_by ?? null, builder_identity: builderIdentity, verifier_identity: verifierIdentity, identity_sha256: run.identity_digest, status: run.status, started_at: run.started_at, completed_at: run.completed_at, created_at: run.created_at });
}

function toVerificationCheckRow(run, result, checkId = null) {
  return Object.freeze({ organization_id: run.request.organization_id, project_id: run.request.project_id, verification_run_id: run.verification_run_id, requirement_id: result.requirement_id ?? null, check_key: checkId ?? result.check_id, status: result.status, failure_class: result.failure_class ?? null, security_severity: result.severity ?? null, summary: result.summary ?? null, details_redacted: { acceptance_criterion_id: result.acceptance_criterion_id ?? null, tool: result.tool ?? null, tool_version: result.tool_version ?? null, duration_ms: result.duration_ms ?? null, cache_key: result.cache_key ?? null, expires_at: result.expires_at ?? null, authoritative_issuer: result.authoritative_issuer ?? null } });
}

function toVerificationEvidenceRow(run, checkRowId, descriptor, { artifactVersionId = null, storageProvider = null, storagePath = null } = {}) {
  return Object.freeze({ organization_id: run.request.organization_id, project_id: run.request.project_id, verification_run_id: run.verification_run_id, verification_check_id: checkRowId, artifact_version_id: artifactVersionId, evidence_type: descriptor.evidence_type, media_type: descriptor.media_type, content_sha256: descriptor.content_sha256, storage_provider: storageProvider, storage_path: storagePath ?? descriptor.storage_ref ?? null });
}

class ControlPlaneVerificationStore {
  constructor({ insertRun, updateRun, insertCheck, insertEvidence } = {}) {
    for (const [name, fn] of Object.entries({ insertRun, updateRun, insertCheck, insertEvidence })) if (typeof fn !== "function") throw new Error(`control-plane verification store requires ${name}`);
    this.ports = Object.freeze({ insertRun, updateRun, insertCheck, insertEvidence });
  }
  createRun(run, identity) { return this.ports.insertRun(toVerificationRunRow(run, identity)); }
  finalizeRun(run, identity) { return this.ports.updateRun(toVerificationRunRow(run, identity)); }
  recordCheck(run, result) { return this.ports.insertCheck(toVerificationCheckRow(run, result)); }
  recordEvidence(run, checkRowId, descriptor, options) { return this.ports.insertEvidence(toVerificationEvidenceRow(run, checkRowId, descriptor, options)); }
}

module.exports = { assertIndependentIdentity, toVerificationRunRow, toVerificationCheckRow, toVerificationEvidenceRow, ControlPlaneVerificationStore };
