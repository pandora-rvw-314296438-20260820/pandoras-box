"use strict";

const { randomUUID } = require("node:crypto");
const net = require("node:net");
const { validateToolProposal } = require("./validation");
const { evaluatePolicy, effectiveRisk, POLICY_VERSION } = require("./policy");
const { TOOL_DECISIONS, SIDE_EFFECTS, canonicalizeJson, sha256Hex, computeActionHash } = require("./contracts");
const { approvalBindingFromAction, validateApprovalGrant } = require("./approvals");
const { PandoraToolError } = require("./errors");
const { normalizeExecutionFailure, executeWithTimeout } = require("./adapters");
const { authorizeNetworkTarget, bindResolvedNetworkTarget } = require("./network-policy");
const { assertRequirementRefsAuthorized } = require("./trust");
const { assertProductionStatePorts } = require("./durability");
const { createToolReceipt } = require("./receipts");
const { recordLineage } = require("./lineage");

class PandoraToolGateway {
  constructor({ resourceResolver, adapterRegistry, approvalStore = null, idempotencyCoordinator = null, rateLimitGuard = null, leaseManager = null, secretsBroker = null, lineageSink = null, canaries = [], now = () => new Date() }) {
    this.resourceResolver = resourceResolver;
    this.adapterRegistry = adapterRegistry;
    this.approvalStore = approvalStore;
    this.idempotency = idempotencyCoordinator;
    this.rate = rateLimitGuard;
    this.leases = leaseManager;
    this.secrets = secretsBroker;
    this.lineage = lineageSink;
    this.canaries = canaries;
    this.now = now;
  }

  async handle(rawProposal, context) {
    const now = this.now();
    const toolCallId = context.tool_call_id || randomUUID();
    const validated = validateToolProposal(rawProposal, { authorizedSubpaths: context.authorized_subpaths || [""] });
    const { definition, proposal } = validated;
    assertRequirementRefsAuthorized(proposal, context.authorized_requirement_refs ?? null);
    const args = proposal.arguments;
    const resolved = await this.resourceResolver.resolve({ organization_id: context.organization_id, project_id: args.project_id, environment: args.environment, actor: context.actor, tool: definition.name });
    const project = resolved.project;
    const targetResource = resolved.target_resource || resolved.resource?.id || definition.executor;
    const projectVersion = resolved.project_version ?? project.version_id ?? null;
    const stateHash = resolved.project_state_hash ?? null;
    const risk = effectiveRisk(definition, args, { migration_preflight: context.migration_preflight || null });
    const actionHash = computeActionHash({ tool: definition.name, version: definition.version, arguments: args, organization_id: context.organization_id, project_id: project.id, environment: context.environment, target_resource: targetResource, project_version: projectVersion, policy_version: POLICY_VERSION });
    await recordLineage(this.lineage, "tool_proposal", { tool_call_id: toolCallId, model_run_id: context.model_run_id || null, build_job_id: context.build_job_id || null, project_spec_id: context.project_spec_id || resolved.project_spec_id || null, project_spec_version: context.project_spec_version || null, project_version_id: projectVersion, project_id: project.id, organization_id: context.organization_id, environment: context.environment, target_resource: targetResource, tool: definition.name, tool_version: definition.version, policy_version: POLICY_VERSION, arguments_sha256: sha256Hex(canonicalizeJson(args)), risk, side_effect: definition.sideEffect, retry_mode: definition.retry, idempotency_mode: definition.idempotency, idempotency_key: args.idempotency_key || null, request_id: args.request_id || null, approval_required: definition.approval === "REQUIRED" || ["HIGH","CRITICAL"].includes(risk), action_hash: actionHash, requirement_refs: proposal.requirement_refs || [] });

    let approval = null;
    let grant = null;
    const expectedApproval = approvalBindingFromAction({ proposal, organization_id: context.organization_id, project_id: project.id, actor_id: context.actor.id, environment: context.environment, target_resource: targetResource, project_version: projectVersion, project_state_hash: stateHash, risk, policy_version: POLICY_VERSION });
    if (context.approval_id) {
      if (!this.approvalStore) throw new PandoraToolError("approval_required", "APPROVAL_STORE_UNAVAILABLE", "Approval store is unavailable");
      grant = await this.approvalStore.get(context.approval_id);
      validateApprovalGrant(grant, expectedApproval, { now });
      approval = { status: "approved", expires_at: grant.expires_at };
    }

    const policy = evaluatePolicy({ definition, args, actor: context.actor, organization_id: context.organization_id, project, environment: context.environment, resource: resolved.resource || {}, approval, verification: context.verification || null, budget: context.budget || null, project_spec_version: context.project_spec_version || null, migration_state_version: context.migration_state_version || null, migration_preflight: context.migration_preflight || null, domain_authorization: context.domain_authorization || null, now });
    await recordLineage(this.lineage, "policy_decision", { tool_call_id: toolCallId, organization_id: context.organization_id, project_id: project.id, project_spec_id: context.project_spec_id || resolved.project_spec_id || null, build_job_id: context.build_job_id || null, project_version_id: projectVersion, tool: definition.name, tool_version: definition.version, environment: context.environment, target_resource: targetResource, arguments_sha256: sha256Hex(canonicalizeJson(args)), side_effect: definition.sideEffect, approval_required: definition.approval === "REQUIRED" || ["HIGH","CRITICAL"].includes(policy.risk), action_hash: actionHash, ...policy, approval_id: grant?.approval_id || null, approval_expires_at: grant?.expires_at || null });
    if (policy.disposition !== TOOL_DECISIONS.ALLOW) return Object.freeze({ tool_call_id: toolCallId, executed: false, decision: policy, action_hash: actionHash });
    assertProductionStatePorts(definition, context.environment, { approvalStore: this.approvalStore, idempotencyCoordinator: this.idempotency, leaseManager: this.leases, concurrencyPort: this.adapterRegistry.get(definition.executor).productionConcurrency || null, rateLimitGuard: this.rate, lineageSink: this.lineage });

    // Resolve the trusted executor before creating durable mutation state.
    const adapter = this.adapterRegistry.get(definition.executor);
    const idemScope = { organization_id: context.organization_id, project_id: project.id, environment: context.environment, tool: definition.name, idempotency_key: args.idempotency_key };
    if (this.rate && context.rate_limit) await this.rate.consume({ ...idemScope, model_run_id: context.model_run_id, build_job_id: context.build_job_id }, context.rate_limit, now);
    if (this.idempotency && definition.idempotency !== "NONE") {
      const replay = await this.idempotency.begin({ definition, scope: idemScope, action_hash: actionHash, request_id: args.request_id, now, metadata: { tool_call_id: toolCallId, project_spec_id: context.project_spec_id || resolved.project_spec_id || null, build_job_id: context.build_job_id || null, model_run_id: context.model_run_id || null, project_version_id: projectVersion, tool_name: definition.name, tool_version: String(definition.version), action_name: definition.name, environment: context.environment, target_resource_ref: targetResource, policy_version: policy.policy_version, arguments_sha256: sha256Hex(canonicalizeJson(args)), risk_level: policy.risk, decision: policy.disposition, side_effect: definition.sideEffect, retry_mode: definition.retry, idempotency_mode: definition.idempotency, approval_required: definition.approval === "REQUIRED" || ["HIGH","CRITICAL"].includes(policy.risk), approval_id: grant?.approval_id || null } });
      if (replay.mode === "replay") return Object.freeze({ tool_call_id: toolCallId, executed: false, replayed: true, decision: policy, action_hash: actionHash, receipt: replay.receipt });
    }

    const executionRequest = Object.freeze({ tool_call_id: toolCallId, tool: definition.name, tool_version: definition.version, arguments: args, organization_id: context.organization_id, project_id: project.id, environment: context.environment, action_hash: actionHash, policy_version: policy.policy_version, risk: policy.risk, capabilities: definition.capabilityRequirements, resource_scope: { target_resource: targetResource, project_version: projectVersion }, model_run_id: context.model_run_id || null, build_job_id: context.build_job_id || null });
    const mutation = ![SIDE_EFFECTS.NONE, SIDE_EFFECTS.READ].includes(definition.sideEffect);
    const started = this.now();
    let mutationLease = null;
    let credentialLease = null;
    let credentialLeaseHandedOff = false;
    let providerStarted = false;

    try {
      if (mutation && this.leases) {
        mutationLease = await this.leases.acquire({ resource_key: `${context.organization_id}:${project.id}:${context.environment}:${targetResource}`, owner_id: context.build_job_id || toolCallId, expected_version: context.expected_resource_version ?? null, current_version: resolved.resource_version ?? null, ttl_ms: Math.min(definition.timeoutMs + 10_000, 10 * 60_000), now });
      }

      if (grant && grant.one_time !== false) {
        if (!this.approvalStore) throw new PandoraToolError("approval_required", "APPROVAL_STORE_UNAVAILABLE", "Approval store is unavailable");
        await this.approvalStore.consume(grant.approval_id, actionHash, now);
      }

      await recordLineage(this.lineage, "tool_execution_started", { tool_call_id: toolCallId, action_hash: actionHash, executor: definition.executor, organization_id: context.organization_id, project_id: project.id, idempotency_key: args.idempotency_key || null });
      let rawResult;
      const networkRequirement = typeof adapter.networkRequirement === "function" ? await adapter.networkRequirement(executionRequest) : null;
      let authorizedNetwork = null;
      if (networkRequirement) {
        const target = authorizeNetworkTarget(networkRequirement, context.network_policy || {});
        let addresses;
        if (net.isIP(target.host)) addresses = [target.host];
        else {
          if (!context.network_resolver || typeof context.network_resolver.resolve !== "function") {
            throw new PandoraToolError("network", "NETWORK_RESOLVER_REQUIRED", "Authorized external network access requires a trusted DNS resolver");
          }
          addresses = await context.network_resolver.resolve(target.host);
        }
        authorizedNetwork = bindResolvedNetworkTarget(target, addresses);
      }
      const credentialRequest = typeof adapter.credentialRequirement === "function" ? await adapter.credentialRequirement(executionRequest) : null;
      if (credentialRequest) {
        if (!this.secrets) throw new PandoraToolError("authorization", "SECRETS_BROKER_UNAVAILABLE", "Scoped credential broker is unavailable");
        const scope = { organization_id: context.organization_id, project_id: project.id, environment: context.environment, operation: definition.name, resource_id: targetResource };
        credentialLease = await this.secrets.issueLease({ ...credentialRequest, scope, requested_by: context.build_job_id || toolCallId }, { actor_capabilities: context.actor.capabilities, now });
        if (credentialRequest.delivery === "lease_ref") {
          credentialLeaseHandedOff = true;
          providerStarted = true;
          rawResult = await executeWithTimeout(adapter, executionRequest, { credential_lease_refs: [credentialLease.lease_id], authorized_network: authorizedNetwork }, { timeoutMs: definition.timeoutMs, mutation });
        } else {
          rawResult = await this.secrets.withCredential(credentialLease, scope, async (credential) => {
            providerStarted = true;
            return executeWithTimeout(adapter, executionRequest, { credential, authorized_network: authorizedNetwork }, { timeoutMs: definition.timeoutMs, mutation });
          }, now);
        }
      } else {
        providerStarted = true;
        rawResult = await executeWithTimeout(adapter, executionRequest, { authorized_network: authorizedNetwork }, { timeoutMs: definition.timeoutMs, mutation });
      }

      const finished = this.now();
      const receipt = createToolReceipt({ tool_call_id: toolCallId, definition, organization_id: context.organization_id, project_id: project.id, environment: context.environment, action_hash: actionHash, policy_version: policy.policy_version, risk: policy.risk, resource_scope: executionRequest.resource_scope, model_run_id: context.model_run_id || null, build_job_id: context.build_job_id || null, maxOutputBytes: definition.maxPayloadBytes, status: "succeeded", started_at: started.toISOString(), finished_at: finished.toISOString(), retryable: false, artifacts: rawResult?.artifacts || [], output: rawResult?.output ?? rawResult ?? null, provenance: { executor: definition.executor, untrusted_output: true }, canaries: this.canaries });
      if (this.idempotency && definition.idempotency !== "NONE") await this.idempotency.succeeded(idemScope, receipt, finished);
      await recordLineage(this.lineage, "tool_execution_finished", { tool_call_id: toolCallId, action_hash: actionHash, execution_id: receipt.execution_id, status: receipt.status, organization_id: context.organization_id, project_id: project.id, idempotency_key: args.idempotency_key || null, retryable: false, receipt });
      return Object.freeze({ tool_call_id: toolCallId, executed: true, decision: policy, action_hash: actionHash, receipt });
    } catch (error) {
      const failure = normalizeExecutionFailure(error);
      const finished = this.now();
      if (this.idempotency && definition.idempotency !== "NONE") {
        if (failure.ambiguous) await this.idempotency.ambiguous(idemScope, failure, finished);
        else await this.idempotency.failedSafe(idemScope, failure, finished);
      }
      const receipt = createToolReceipt({ tool_call_id: toolCallId, definition, organization_id: context.organization_id, project_id: project.id, environment: context.environment, action_hash: actionHash, policy_version: policy.policy_version, risk: policy.risk, resource_scope: executionRequest.resource_scope, model_run_id: context.model_run_id || null, build_job_id: context.build_job_id || null, maxOutputBytes: definition.maxPayloadBytes, status: "failed", started_at: started.toISOString(), finished_at: finished.toISOString(), retryable: failure.retryable, error: failure.owner, provenance: { executor: definition.executor, provider_started: providerStarted }, canaries: this.canaries });
      await recordLineage(this.lineage, "tool_execution_finished", { tool_call_id: toolCallId, action_hash: actionHash, execution_id: receipt.execution_id, status: receipt.status, error_class: failure.error_class, organization_id: context.organization_id, project_id: project.id, idempotency_key: args.idempotency_key || null, retryable: failure.retryable, receipt });
      return Object.freeze({ tool_call_id: toolCallId, executed: providerStarted, decision: policy, action_hash: actionHash, receipt });
    } finally {
      if (credentialLease && this.secrets && !credentialLeaseHandedOff) await this.secrets.revoke(credentialLease.lease_id, this.now());
      if (mutationLease) await this.leases.release(mutationLease);
    }
  }
}

module.exports = { PandoraToolGateway };
