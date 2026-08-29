"use strict";

const { PandoraToolError } = require("./errors");
const { durableExecutorConcurrency } = require("./control-plane");
const { toWorkerFDeploymentRequest } = require("./cross-worker");

function requiredObject(value, code, message) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new PandoraToolError("invalid_request", code, message);
  return value;
}
function exact(left, right, code, message) {
  if ((left ?? null) !== (right ?? null)) throw new PandoraToolError("conflict", code, message);
}
function lower(value) { return String(value || "").toLowerCase(); }

class WorkerFDeploymentExecutorAdapter {
  constructor({ runtimeManager, contextResolver }) {
    if (!runtimeManager || typeof runtimeManager.publishVersion !== "function") throw new TypeError("Worker F runtime manager is required");
    if (!contextResolver || typeof contextResolver.resolvePublish !== "function") throw new TypeError("trusted publish context resolver is required");
    this.runtimeManager = runtimeManager;
    this.contextResolver = contextResolver;
    this.productionConcurrency = durableExecutorConcurrency("compare_and_set", "worker-f:runtime-operation+production-cas");
  }

  async execute(request) {
    if (request?.tool !== "request_publish") throw new PandoraToolError("policy_denied", "WORKER_F_PUBLISH_ONLY", "Deployment publish request expected");
    const args = requiredObject(request.arguments, "WORKER_F_ARGUMENTS_REQUIRED", "Publish arguments are required");
    const trusted = requiredObject(await this.contextResolver.resolvePublish({
      organization_id: request.organization_id,
      project_id: request.project_id,
      project_version_id: args.version_id,
      preview_id: args.preview_id,
      verification_run_id: args.verification_run_id,
      artifact_digest: args.artifact_digest,
      action_hash: request.action_hash,
    }), "WORKER_F_TRUSTED_CONTEXT_INCOMPLETE", "Trusted publish context is incomplete");
    const preview = requiredObject(trusted.preview_fact, "WORKER_F_PREVIEW_REQUIRED", "Exact preview fact is required");
    exact(trusted.preview_id, args.preview_id, "WORKER_F_PREVIEW_ID_MISMATCH", "Trusted preview identity changed");
    exact(preview.projectVersionId, args.version_id, "WORKER_F_PREVIEW_VERSION_MISMATCH", "Preview belongs to another project version");
    exact(lower(preview.artifactDigest), lower(args.artifact_digest), "WORKER_F_PREVIEW_ARTIFACT_MISMATCH", "Preview artifact does not match approved publish action");
    exact(lower(preview.sourceCommit), lower(trusted.source_commit), "WORKER_F_PREVIEW_SOURCE_MISMATCH", "Preview source does not match trusted project version");
    if (trusted.verification_ref && trusted.verification_ref !== args.verification_run_id) throw new PandoraToolError("verification_required", "WORKER_F_VERIFICATION_REF_MISMATCH", "Publish verification identity changed");
    const input = toWorkerFDeploymentRequest(request, {
      source_commit: trusted.source_commit,
      verification_ref: args.verification_run_id,
      expected_production_version_id: trusted.expected_production_version_id ?? null,
      allow_first_production: trusted.allow_first_production === true,
      runtime_type: trusted.runtime_type || "web_app",
      provider: trusted.provider || "vercel",
    });
    return Object.freeze({ output: await this.runtimeManager.publishVersion(input, preview) });
  }
}

class WorkerFDomainExecutorAdapter {
  constructor({ runtimeManager, contextResolver }) {
    if (!runtimeManager || typeof runtimeManager.attachDomain !== "function") throw new TypeError("Worker F runtime manager is required");
    if (!contextResolver || typeof contextResolver.resolveDomain !== "function") throw new TypeError("trusted domain context resolver is required");
    this.runtimeManager = runtimeManager;
    this.contextResolver = contextResolver;
    this.productionConcurrency = durableExecutorConcurrency("claim", "worker-f:runtime-operation");
  }

  async execute(request) {
    if (request?.tool !== "request_domain_attach") throw new PandoraToolError("policy_denied", "WORKER_F_DOMAIN_ONLY", "Domain attachment request expected");
    const args = requiredObject(request.arguments, "WORKER_F_ARGUMENTS_REQUIRED", "Domain arguments are required");
    const trusted = requiredObject(await this.contextResolver.resolveDomain({
      organization_id: request.organization_id,
      project_id: request.project_id,
      hostname: args.hostname,
      deployment_id: args.deployment_id,
      target_environment: args.target_environment,
      action_hash: request.action_hash,
    }), "WORKER_F_TRUSTED_CONTEXT_INCOMPLETE", "Trusted domain context is incomplete");
    exact(trusted.deployment_id, args.deployment_id, "WORKER_F_DOMAIN_DEPLOYMENT_MISMATCH", "Domain target deployment changed");
    exact(trusted.hostname, args.hostname, "WORKER_F_DOMAIN_HOSTNAME_MISMATCH", "Domain hostname changed");
    if (!trusted.project_version_id || !trusted.artifact_digest || !trusted.source_commit || !trusted.verification_ref) throw new PandoraToolError("invalid_request", "WORKER_F_TRUSTED_CONTEXT_INCOMPLETE", "Domain attachment requires exact runtime lineage");
    const input = Object.freeze({
      organizationId: request.organization_id,
      projectId: request.project_id,
      projectVersionId: trusted.project_version_id,
      artifactDigest: trusted.artifact_digest,
      sourceCommit: trusted.source_commit,
      environment: args.target_environment,
      authorizationRef: request.action_hash,
      verificationRef: trusted.verification_ref,
      provider: trusted.provider || "vercel",
      runtimeType: trusted.runtime_type || "web_app",
      expectedProductionVersionId: trusted.expected_production_version_id ?? null,
      allowFirstProduction: trusted.allow_first_production === true,
    });
    return Object.freeze({ output: await this.runtimeManager.attachDomain({ input, domain: args.hostname }) });
  }
}

class SupabaseDatabaseChangePlanStore {
  constructor(client, artifactResolver) {
    if (!client || typeof client.from !== "function") throw new TypeError("Supabase service client is required");
    if (!artifactResolver || typeof artifactResolver.resolveVersionRef !== "function") throw new TypeError("trusted artifact resolver is required");
    this.client = client;
    this.artifactResolver = artifactResolver;
    this.durability = "durable";
  }
  _data(result, code) {
    if (result?.error) throw new PandoraToolError("internal", code, "Database change control-plane operation failed", { provider_code: result.error.code || null });
    return result?.data ?? null;
  }
  _one(rows) { return Array.isArray(rows) ? rows[0] ?? null : rows ?? null; }

  async resolveExactPlan({ organization_id, project_id, environment, action_hash, idempotency_key, migration_ref }) {
    const artifactVersionId = await this.artifactResolver.resolveVersionRef({ organization_id, project_id, reference: migration_ref, expected_kind: "migration" });
    if (!artifactVersionId) return null;
    const result = await this.client.from("pandora_database_change_plans").select("*")
      .eq("organization_id", organization_id).eq("project_id", project_id).eq("environment", environment)
      .eq("action_hash", action_hash).eq("idempotency_key", idempotency_key)
      .eq("migration_artifact_version_id", artifactVersionId).limit(1);
    return this._one(this._data(result, "DATABASE_CHANGE_PLAN_READ_FAILED"));
  }

  async claimPlan(plan, toolCallId) {
    const result = await this.client.from("pandora_database_change_plans")
      .update({ status: "executing", execution_tool_call_id: toolCallId })
      .eq("id", plan.id).eq("organization_id", plan.organization_id).eq("project_id", plan.project_id)
      .eq("action_hash", plan.action_hash).eq("status", "approved").select("*");
    return this._one(this._data(result, "DATABASE_CHANGE_PLAN_CLAIM_FAILED"));
  }
  async markApplied(plan, toolCallId) {
    const result = await this.client.from("pandora_database_change_plans").update({ status: "applied" })
      .eq("id", plan.id).eq("execution_tool_call_id", toolCallId).eq("status", "executing").select("*");
    return this._one(this._data(result, "DATABASE_CHANGE_PLAN_APPLY_FAILED"));
  }
  async markFailed(plan, toolCallId) {
    const result = await this.client.from("pandora_database_change_plans").update({ status: "failed" })
      .eq("id", plan.id).eq("execution_tool_call_id", toolCallId).eq("status", "executing").select("*");
    return this._one(this._data(result, "DATABASE_CHANGE_PLAN_FAIL_FAILED"));
  }
}

class WorkerADatabaseChangeExecutorAdapter {
  constructor({ planStore, migrationExecutor }) {
    if (!planStore || planStore.durability !== "durable" || typeof planStore.resolveExactPlan !== "function" || typeof planStore.claimPlan !== "function") throw new TypeError("durable Worker A database-change plan store is required");
    if (!migrationExecutor || typeof migrationExecutor.executeMigration !== "function") throw new TypeError("database migration executor is required");
    this.planStore = planStore;
    this.migrationExecutor = migrationExecutor;
    this.productionConcurrency = durableExecutorConcurrency("claim", "worker-a:pandora_database_change_plans");
  }
  async credentialRequirement(request) { return typeof this.migrationExecutor.credentialRequirement === "function" ? this.migrationExecutor.credentialRequirement(request) : null; }
  async networkRequirement(request) { return typeof this.migrationExecutor.networkRequirement === "function" ? this.migrationExecutor.networkRequirement(request) : null; }

  async execute(request, runtime = {}) {
    if (request?.tool !== "request_migration") throw new PandoraToolError("policy_denied", "DATABASE_MIGRATION_ONLY", "Database migration request expected");
    const args = requiredObject(request.arguments, "DATABASE_MIGRATION_ARGUMENTS_REQUIRED", "Migration arguments are required");
    const plan = await this.planStore.resolveExactPlan({
      organization_id: request.organization_id,
      project_id: request.project_id,
      environment: request.environment,
      action_hash: request.action_hash,
      idempotency_key: args.idempotency_key,
      migration_ref: args.migration_ref,
    });
    if (!plan) throw new PandoraToolError("resource_missing", "DATABASE_CHANGE_PLAN_NOT_FOUND", "Approved database change plan was not found");
    if (plan.status !== "approved") throw new PandoraToolError("conflict", "DATABASE_CHANGE_PLAN_NOT_APPROVED", "Database change plan is not executable");
    exact(plan.action_hash, request.action_hash, "DATABASE_CHANGE_ACTION_MISMATCH", "Database change plan action changed");
    const claimed = await this.planStore.claimPlan(plan, request.tool_call_id);
    if (!claimed) throw new PandoraToolError("conflict", "DATABASE_CHANGE_PLAN_CLAIM_CONFLICT", "Database change plan was claimed by another execution");
    try {
      const result = await this.migrationExecutor.executeMigration(claimed, runtime);
      const applied = await this.planStore.markApplied(claimed, request.tool_call_id);
      if (!applied) throw new PandoraToolError("ambiguous_mutation", "DATABASE_CHANGE_APPLY_STATE_AMBIGUOUS", "Database migration completed but durable state could not be confirmed");
      return Object.freeze({ output: { plan_id: applied.id, status: "applied", result: result ?? null } });
    } catch (error) {
      if (error?.mutationMayHaveCommitted === true || error?.mutation_may_have_committed === true || error?.errorClass === "ambiguous_mutation") throw error;
      await this.planStore.markFailed(claimed, request.tool_call_id);
      throw error;
    }
  }
}

module.exports = { WorkerFDeploymentExecutorAdapter, WorkerFDomainExecutorAdapter, SupabaseDatabaseChangePlanStore, WorkerADatabaseChangeExecutorAdapter };
