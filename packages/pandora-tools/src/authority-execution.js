"use strict";

const { randomUUID } = require("node:crypto");
const {
  RISK_LEVELS,
  SIDE_EFFECTS,
  TOOL_DECISIONS,
  canonicalizeJson,
  sha256Hex,
  secureEqualHex,
} = require("./contracts");
const { validateToolProposal } = require("./validation");
const { assertRequirementRefsAuthorized } = require("./trust");
const { effectiveRisk, POLICY_VERSION } = require("./policy");
const { approvalBindingFromAction, createApprovalGrant } = require("./approvals");
const { PandoraToolError } = require("./errors");
const { recordLineage } = require("./lineage");

const AUTHORITY_SCHEMA_VERSION = "pandora-standing-authority-decision-v1";

const AUTHORITY_DECISIONS = Object.freeze({
  AUTO_EXECUTE: "auto_execute",
  STANDING_AUTHORIZED: "standing_authorized",
  NEEDS_APPROVAL: "needs_approval",
  DENY: "deny",
});

const GRANTING_AUTHORITY_BASES = Object.freeze([
  "explicit_current_user_instruction",
  "active_explicit_standing_policy",
]);

const NON_GRANTING_AUTHORITY_BASES = Object.freeze([
  "none",
  "model_proposal",
  "memory_pattern",
  "prediction",
  "recommendation",
  "provider_capability",
  "prior_success",
  "expired_standing_policy",
  "revoked_standing_policy",
  "ambiguous_scope",
]);

const RESTRICTIVE_AUTHORITY_BASES = Object.freeze([
  "safety_policy",
  "security_boundary",
  "protected_app_boundary",
  "organization_policy",
  "provider_permission",
]);

const RISK_ORDER = Object.freeze({
  [RISK_LEVELS.LOW]: 1,
  [RISK_LEVELS.MEDIUM]: 2,
  [RISK_LEVELS.HIGH]: 3,
  [RISK_LEVELS.CRITICAL]: 4,
});

function asDate(value, field) {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new PandoraToolError("approval_required", "AUTHORITY_TIME_INVALID", `${field} is invalid`);
  }
  return date;
}

function authorityRequired(definition, args, context, risk) {
  const mutates = ![SIDE_EFFECTS.NONE, SIDE_EFFECTS.READ].includes(definition.sideEffect);
  if (RISK_ORDER[risk] >= RISK_ORDER[RISK_LEVELS.HIGH]) return true;
  if (definition.approval === "REQUIRED") return true;
  if (context.environment === "production" && mutates) return true;
  if (definition.expensive && context.budget?.requires_approval_for_extra_spend === true) return true;
  return false;
}

function authorityScopeFromAction(proposal, context = {}) {
  const snapshot = {
    destination_or_audience: context.destination_or_audience ?? null,
    data_sensitivity: context.data_sensitivity ?? null,
    cost: context.authority_cost ?? context.cost ?? context.budget ?? null,
    destructive: proposal?.arguments?.destructive === true,
    production: context.environment === "production" || proposal?.arguments?.target_environment === "production",
    protected_app: context.protected_app_scope ?? context.protected_app ?? null,
  };
  return Object.freeze(JSON.parse(canonicalizeJson(snapshot)));
}

function authorizationFingerprint(binding, definition, proposal = null, context = {}) {
  const authorityScope = authorityScopeFromAction(proposal, context);
  return sha256Hex(canonicalizeJson({
    schema_version: AUTHORITY_SCHEMA_VERSION,
    principal: binding.actor_id,
    capability: [...definition.capabilityRequirements].sort(),
    operation: binding.tool,
    tool_version: binding.tool_version,
    provider_or_execution_boundary: definition.executor,
    resource_or_account_scope: binding.target_resource,
    organization_id: binding.organization_id,
    project_id: binding.project_id,
    environment: binding.environment,
    destination_or_audience: authorityScope.destination_or_audience,
    data_sensitivity: authorityScope.data_sensitivity,
    cost: authorityScope.cost,
    destructive: authorityScope.destructive,
    production: authorityScope.production,
    protected_app: authorityScope.protected_app,
    risk: binding.risk,
    policy_version: binding.policy_version,
    project_version: binding.project_version,
    project_state_hash: binding.project_state_hash,
    action_hash: binding.action_hash,
  }));
}

function validateAuthorityDecision(raw, expected, definition, proposal, context = {}, { now = new Date() } = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new PandoraToolError("approval_required", "AUTHORITY_DECISION_INVALID", "Authority decision is missing or invalid");
  }
  if (raw.schema_version !== AUTHORITY_SCHEMA_VERSION) {
    throw new PandoraToolError("approval_required", "AUTHORITY_SCHEMA_MISMATCH", "Authority decision schema is not supported");
  }
  if (!Object.values(AUTHORITY_DECISIONS).includes(raw.decision)) {
    throw new PandoraToolError("approval_required", "AUTHORITY_DECISION_INVALID", "Authority decision is invalid");
  }

  const expectedFingerprint = authorizationFingerprint(expected, definition, proposal, context);
  if (!secureEqualHex(raw.authorization_fingerprint, expectedFingerprint)) {
    throw new PandoraToolError("approval_required", "AUTHORITY_FINGERPRINT_MISMATCH", "Authority decision does not match this action");
  }
  if (!secureEqualHex(raw.action_hash, expected.action_hash)) {
    throw new PandoraToolError("approval_required", "AUTHORITY_ACTION_HASH_MISMATCH", "Authority decision action hash does not match");
  }
  if (raw.policy_version !== expected.policy_version) {
    throw new PandoraToolError("approval_required", "AUTHORITY_POLICY_STALE", "Authority decision was issued under another policy version");
  }
  if (raw.risk !== expected.risk) {
    throw new PandoraToolError("approval_required", "AUTHORITY_RISK_MISMATCH", "Authority decision risk does not match current action");
  }

  const issuedAt = asDate(raw.issued_at, "issued_at");
  const expiresAt = asDate(raw.expires_at, "expires_at");
  if (issuedAt > now) {
    throw new PandoraToolError("approval_required", "AUTHORITY_NOT_YET_VALID", "Authority decision is not valid yet");
  }
  if (expiresAt <= now || expiresAt <= issuedAt) {
    throw new PandoraToolError("approval_required", "AUTHORITY_EXPIRED", "Authority decision has expired");
  }
  if (raw.revoked_at) {
    throw new PandoraToolError("approval_required", "AUTHORITY_REVOKED", "Authority decision was revoked");
  }

  const basis = String(raw.authority_basis || "");
  const granting = GRANTING_AUTHORITY_BASES.includes(basis);
  const nonGranting = NON_GRANTING_AUTHORITY_BASES.includes(basis);
  const restrictive = RESTRICTIVE_AUTHORITY_BASES.includes(basis);

  if (raw.decision === AUTHORITY_DECISIONS.AUTO_EXECUTE) {
    if (basis !== "explicit_current_user_instruction") {
      throw new PandoraToolError("approval_required", "AUTHORITY_BASIS_INVALID", "Auto-execute requires explicit current user authority");
    }
    const requestId = proposal.arguments?.request_id;
    if (!requestId || raw.request_id !== requestId) {
      throw new PandoraToolError("approval_required", "AUTHORITY_REQUEST_MISMATCH", "Current-user authority must bind to the exact request");
    }
  } else if (raw.decision === AUTHORITY_DECISIONS.STANDING_AUTHORIZED) {
    if (basis !== "active_explicit_standing_policy" || raw.standing_policy_match !== true) {
      throw new PandoraToolError("approval_required", "AUTHORITY_BASIS_INVALID", "Standing authorization must come from an exact matching active policy");
    }
    if (typeof raw.standing_policy_id !== "string" || !raw.standing_policy_id.trim()) {
      throw new PandoraToolError("approval_required", "STANDING_POLICY_ID_REQUIRED", "Standing authorization requires a policy identity");
    }
  } else if (raw.decision === AUTHORITY_DECISIONS.NEEDS_APPROVAL) {
    if (granting || restrictive || !nonGranting) {
      throw new PandoraToolError("approval_required", "AUTHORITY_BASIS_INVALID", "Needs-approval decision must use a non-granting authority basis");
    }
  } else if (raw.decision === AUTHORITY_DECISIONS.DENY) {
    if (!restrictive) {
      throw new PandoraToolError("policy_denied", "AUTHORITY_BASIS_INVALID", "Deny decision must come from a restrictive policy boundary");
    }
  }

  return Object.freeze({
    schema_version: AUTHORITY_SCHEMA_VERSION,
    decision: raw.decision,
    authority_basis: basis,
    authorization_fingerprint: expectedFingerprint,
    action_hash: expected.action_hash,
    policy_version: expected.policy_version,
    risk: expected.risk,
    request_id: raw.request_id || null,
    standing_policy_id: raw.standing_policy_id || null,
    standing_policy_match: raw.standing_policy_match === true,
    issued_at: issuedAt.toISOString(),
    expires_at: expiresAt.toISOString(),
    reason_code: String(raw.reason_code || "AUTHORITY_DECISION"),
  });
}

function createAuthorityGrant(binding, authority) {
  const approvalId = `authority-${authority.authorization_fingerprint.slice(0, 16)}-${randomUUID()}`;
  const grant = createApprovalGrant(binding, {
    approval_id: approvalId,
    approved_by: `authority:${authority.authority_basis}`,
    approved_at: authority.issued_at,
    expires_at: authority.expires_at,
    one_time: true,
  });
  return Object.freeze({
    ...grant,
    authority_schema_version: authority.schema_version,
    authority_basis: authority.authority_basis,
    authority_fingerprint: authority.authorization_fingerprint,
    standing_policy_id: authority.standing_policy_id,
    authority_reason_code: authority.reason_code,
  });
}

function denyResult(toolCallId, risk, authority) {
  return Object.freeze({
    tool_call_id: toolCallId,
    executed: false,
    decision: Object.freeze({
      disposition: TOOL_DECISIONS.DENY,
      reason_code: authority.reason_code || "AUTHORITY_DENIED",
      risk,
      policy_version: POLICY_VERSION,
      authority_basis: authority.authority_basis,
      authorization_fingerprint: authority.authorization_fingerprint,
    }),
    action_hash: authority.action_hash,
  });
}

class PandoraAuthorityToolExecutor {
  constructor({ gateway, authorityEvaluator = null, now = () => new Date() }) {
    if (!gateway || typeof gateway.handle !== "function" || !gateway.resourceResolver) {
      throw new PandoraToolError("internal", "AUTHORITY_GATEWAY_INVALID", "Authority executor requires a Pandora Tool Gateway");
    }
    if (authorityEvaluator != null && typeof authorityEvaluator.evaluate !== "function") {
      throw new PandoraToolError("internal", "AUTHORITY_EVALUATOR_INVALID", "Authority evaluator must expose evaluate()");
    }
    this.gateway = gateway;
    this.authorityEvaluator = authorityEvaluator;
    this.now = now;
  }

  async handle(rawProposal, context) {
    if (context?.approval_id || !this.authorityEvaluator) {
      return this.gateway.handle(rawProposal, context);
    }

    const now = this.now();
    const toolCallId = context.tool_call_id || randomUUID();
    const { definition, proposal } = validateToolProposal(rawProposal, {
      authorizedSubpaths: context.authorized_subpaths || [""],
    });
    assertRequirementRefsAuthorized(proposal, context.authorized_requirement_refs ?? null);

    const args = proposal.arguments;
    const resolved = await this.gateway.resourceResolver.resolve({
      organization_id: context.organization_id,
      project_id: args.project_id,
      environment: args.environment,
      actor: context.actor,
      tool: definition.name,
    });
    const project = resolved.project;
    const targetResource = resolved.target_resource || resolved.resource?.id || definition.executor;
    const projectVersion = resolved.project_version ?? project.version_id ?? null;
    const stateHash = resolved.project_state_hash ?? null;
    const risk = effectiveRisk(definition, args, {
      migration_preflight: context.migration_preflight || null,
    });

    if (!authorityRequired(definition, args, context, risk)) {
      return this.gateway.handle(rawProposal, { ...context, tool_call_id: toolCallId });
    }

    const binding = approvalBindingFromAction({
      proposal,
      organization_id: context.organization_id,
      project_id: project.id,
      actor_id: context.actor.id,
      environment: context.environment,
      target_resource: targetResource,
      project_version: projectVersion,
      project_state_hash: stateHash,
      risk,
      policy_version: POLICY_VERSION,
    });
    const fingerprint = authorizationFingerprint(binding, definition, proposal, context);
    const rawAuthority = await this.authorityEvaluator.evaluate(Object.freeze({
      schema_version: AUTHORITY_SCHEMA_VERSION,
      authorization_fingerprint: fingerprint,
      action_hash: binding.action_hash,
      actor_id: binding.actor_id,
      organization_id: binding.organization_id,
      project_id: binding.project_id,
      tool: binding.tool,
      tool_version: binding.tool_version,
      environment: binding.environment,
      target_resource: binding.target_resource,
      project_version: binding.project_version,
      project_state_hash: binding.project_state_hash,
      risk: binding.risk,
      policy_version: binding.policy_version,
      execution_adapter: definition.executor,
      required_capabilities: Object.freeze([...definition.capabilityRequirements]),
      request_id: proposal.arguments?.request_id || null,
      authority_scope: authorityScopeFromAction(proposal, context),
    }));

    const postEvaluationFingerprint = authorizationFingerprint(binding, definition, proposal, context);
    if (!secureEqualHex(postEvaluationFingerprint, fingerprint)) {
      throw new PandoraToolError("approval_required", "AUTHORITY_SCOPE_DRIFT", "Authority scope changed while authorization was being evaluated");
    }

    const authority = validateAuthorityDecision(rawAuthority, binding, definition, proposal, context, { now });
    await recordLineage(this.gateway.lineage, "authority_decision", {
      tool_call_id: toolCallId,
      organization_id: binding.organization_id,
      project_id: binding.project_id,
      environment: binding.environment,
      tool: binding.tool,
      tool_version: binding.tool_version,
      action_hash: binding.action_hash,
      risk: binding.risk,
      policy_version: binding.policy_version,
      authority_decision: authority.decision,
      authority_basis: authority.authority_basis,
      authorization_fingerprint: authority.authorization_fingerprint,
      standing_policy_id: authority.standing_policy_id,
      authority_reason_code: authority.reason_code,
    });

    if (authority.decision === AUTHORITY_DECISIONS.DENY) {
      return denyResult(toolCallId, risk, authority);
    }
    if (authority.decision === AUTHORITY_DECISIONS.NEEDS_APPROVAL) {
      return this.gateway.handle(rawProposal, { ...context, tool_call_id: toolCallId });
    }

    if (!this.gateway.approvalStore || typeof this.gateway.approvalStore.put !== "function") {
      throw new PandoraToolError("approval_required", "AUTHORITY_EVIDENCE_STORE_UNAVAILABLE", "Durable authority evidence storage is unavailable");
    }

    const grant = createAuthorityGrant(binding, authority);
    await this.gateway.approvalStore.put(grant);
    return this.gateway.handle(rawProposal, {
      ...context,
      tool_call_id: toolCallId,
      approval_id: grant.approval_id,
    });
  }
}

module.exports = {
  AUTHORITY_SCHEMA_VERSION,
  AUTHORITY_DECISIONS,
  GRANTING_AUTHORITY_BASES,
  NON_GRANTING_AUTHORITY_BASES,
  RESTRICTIVE_AUTHORITY_BASES,
  authorityRequired,
  authorizationFingerprint,
  validateAuthorityDecision,
  createAuthorityGrant,
  PandoraAuthorityToolExecutor,
};
