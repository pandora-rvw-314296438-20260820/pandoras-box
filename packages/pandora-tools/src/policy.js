"use strict";

const { TOOL_DECISIONS, RISK_LEVELS } = require("./contracts");
const { PandoraToolError } = require("./errors");

const POLICY_VERSION = "pandora-tool-policy/1.0.0";
const RISK_ORDER = Object.freeze({ LOW: 1, MEDIUM: 2, HIGH: 3, CRITICAL: 4 });

function decision(disposition, reasonCode, risk, extra = {}) {
  return Object.freeze({ disposition, reason_code: reasonCode, risk, policy_version: POLICY_VERSION, ...extra });
}

function effectiveRisk(definition, args) {
  let risk = definition.defaultRisk || RISK_LEVELS.CRITICAL;
  if (definition.name === "request_migration" && args.destructive === true) risk = RISK_LEVELS.HIGH;
  if (definition.name === "request_domain_attach" && args.target_environment === "production") risk = RISK_LEVELS.HIGH;
  return risk;
}

function missingCapabilities(required, actorCapabilities) {
  const granted = new Set(Array.isArray(actorCapabilities) ? actorCapabilities : []);
  return required.filter((capability) => !granted.has(capability));
}

function assertResourceOwnership({ organization_id, project, actor, resource }) {
  if (!organization_id || !project?.id || !project?.organization_id || !actor?.id || !actor?.organization_id) {
    throw new PandoraToolError("authorization", "RESOURCE_CONTEXT_INCOMPLETE", "Organization, project, and actor bindings are required");
  }
  if (project.organization_id !== organization_id || actor.organization_id !== organization_id) {
    throw new PandoraToolError("authorization", "CROSS_ORG_ACCESS", "Cross-organization access is forbidden");
  }
  if (resource?.project_id && resource.project_id !== project.id) {
    throw new PandoraToolError("authorization", "CROSS_PROJECT_ACCESS", "Cross-project access is forbidden");
  }
  if (resource?.organization_id && resource.organization_id !== organization_id) {
    throw new PandoraToolError("authorization", "CROSS_ORG_RESOURCE", "Resource belongs to a different organization");
  }
  return true;
}

function verificationIsCurrent(args, state) {
  const verification = state.verification;
  if (!verification || verification.status !== "passed") return false;
  if (verification.run_id !== args.verification_run_id) return false;
  if (verification.project_id !== state.project.id) return false;
  if (verification.version_id !== args.version_id) return false;
  if (verification.artifact_digest !== args.artifact_digest) return false;
  if (state.project.version_id !== args.version_id) return false;
  if (verification.project_spec_version !== state.project_spec_version) return false;
  if (state.migration_state_version && verification.migration_state_version !== state.migration_state_version) return false;
  return true;
}

function evaluatePolicy({ definition, args, actor, organization_id, project, environment, resource = {}, approval = null, verification = null, budget = null, project_spec_version = null, migration_state_version = null, now = new Date() }) {
  if (!definition) return decision(TOOL_DECISIONS.DENY, "UNKNOWN_TOOL", RISK_LEVELS.CRITICAL);
  let risk = effectiveRisk(definition, args);
  try {
    assertResourceOwnership({ organization_id, project, actor, resource });
  } catch (error) {
    return decision(TOOL_DECISIONS.DENY, error.code || "RESOURCE_SCOPE_DENIED", risk);
  }
  if (args.project_id !== project.id) return decision(TOOL_DECISIONS.DENY, "PROJECT_BINDING_MISMATCH", risk);
  if (args.environment !== environment) return decision(TOOL_DECISIONS.DENY, "ENVIRONMENT_BINDING_MISMATCH", risk);
  if (!definition.allowedEnvironments.includes(environment)) return decision(TOOL_DECISIONS.DENY, "ENVIRONMENT_NOT_ALLOWED", risk);
  const missing = missingCapabilities(definition.capabilityRequirements, actor.capabilities);
  if (missing.length > 0) return decision(TOOL_DECISIONS.DENY, "CAPABILITY_MISSING", risk, { missing_capabilities: missing });
  if (environment === "production" && definition.sideEffect !== "NONE" && definition.sideEffect !== "READ" && !actor.capabilities.includes("production.access")) {
    return decision(TOOL_DECISIONS.DENY, "PRODUCTION_CAPABILITY_MISSING", risk);
  }
  if (definition.expensive && budget) {
    if (budget.exhausted === true || (Number.isFinite(budget.remaining_units) && budget.remaining_units <= 0)) {
      return decision(TOOL_DECISIONS.DENY, "DENY_BUDGET_EXHAUSTED", risk);
    }
    if (budget.requires_approval_for_extra_spend === true) {
      return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "REQUIRE_APPROVAL_FOR_EXTRA_SPEND", risk);
    }
  }
  if (definition.name === "request_publish") {
    if (args.target_environment !== "production" || environment !== "production") return decision(TOOL_DECISIONS.DENY, "PUBLISH_TARGET_INVALID", RISK_LEVELS.HIGH);
    if (!verificationIsCurrent(args, { verification, project, project_spec_version, migration_state_version })) {
      return decision(TOOL_DECISIONS.DENY, "VERIFICATION_REQUIRED_OR_STALE", RISK_LEVELS.HIGH);
    }
    risk = RISK_LEVELS.HIGH;
  }
  if (definition.name === "request_migration" && args.destructive === true && environment === "production") risk = RISK_LEVELS.CRITICAL;
  if (RISK_ORDER[risk] >= RISK_ORDER.HIGH || definition.approval === "REQUIRED") {
    if (!approval) return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_REQUIRED", risk);
    if (approval.status !== "approved") return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_NOT_APPROVED", risk);
    if (approval.expires_at && new Date(approval.expires_at) <= now) return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_EXPIRED", risk);
  }
  return decision(TOOL_DECISIONS.ALLOW, "POLICY_ALLOWED", risk);
}

module.exports = { POLICY_VERSION, effectiveRisk, assertResourceOwnership, verificationIsCurrent, evaluatePolicy };
