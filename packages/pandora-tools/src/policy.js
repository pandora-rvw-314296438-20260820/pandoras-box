"use strict";

const { TOOL_DECISIONS, RISK_LEVELS, SIDE_EFFECTS } = require("./contracts");
const { PandoraToolError } = require("./errors");

const POLICY_VERSION = "pandora-tool-policy/1.1.0";
const RISK_ORDER = Object.freeze({ LOW: 1, MEDIUM: 2, HIGH: 3, CRITICAL: 4 });

function decision(disposition, reasonCode, risk, extra = {}) {
  return Object.freeze({ disposition, reason_code: reasonCode, risk, policy_version: POLICY_VERSION, ...extra });
}
function maxRisk(a, b) { return RISK_ORDER[a] >= RISK_ORDER[b] ? a : b; }

function effectiveRisk(definition, args, trusted = {}) {
  let risk = definition.defaultRisk || RISK_LEVELS.CRITICAL;
  if (args.environment === "production" && ![SIDE_EFFECTS.NONE, SIDE_EFFECTS.READ].includes(definition.sideEffect)) risk = maxRisk(risk, RISK_LEVELS.HIGH);
  if (definition.name === "request_migration") {
    if (args.destructive === true) risk = args.environment === "production" ? RISK_LEVELS.CRITICAL : maxRisk(risk, RISK_LEVELS.HIGH);
    if (trusted.migration_preflight?.destructive === true || trusted.migration_preflight?.risk === "CRITICAL") risk = RISK_LEVELS.CRITICAL;
    else if (["HIGH","CRITICAL"].includes(trusted.migration_preflight?.risk)) risk = maxRisk(risk, RISK_LEVELS.HIGH);
  }
  if (definition.name === "request_domain_attach") risk = maxRisk(risk, RISK_LEVELS.HIGH);
  if (definition.name === "request_publish") risk = maxRisk(risk, RISK_LEVELS.HIGH);
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
  if (project.organization_id !== organization_id || actor.organization_id !== organization_id) throw new PandoraToolError("authorization", "CROSS_ORG_ACCESS", "Cross-organization access is forbidden");
  if (resource?.project_id && resource.project_id !== project.id) throw new PandoraToolError("authorization", "CROSS_PROJECT_ACCESS", "Cross-project access is forbidden");
  if (resource?.organization_id && resource.organization_id !== organization_id) throw new PandoraToolError("authorization", "CROSS_ORG_RESOURCE", "Resource belongs to a different organization");
  return true;
}

function verificationIsCurrent(args, state) {
  const v = state.verification;
  if (!v) return false;
  const passed = v.status === "passed" || v.status === "PASS" || (v.verification === "PASS" && v.publish_eligible === true);
  if (!passed || v.invalidated_at) return false;
  if (v.publish_eligible === false) return false;
  const runId = v.run_id ?? v.verification_run_id;
  const projectId = v.project_id ?? v.request?.project_id;
  const versionId = v.version_id ?? v.project_version_id ?? v.request?.project_version_id;
  const artifactDigest = v.artifact_digest ?? v.request?.artifact_digest;
  const specVersion = v.project_spec_version ?? v.request?.project_spec_version;
  if (runId !== args.verification_run_id) return false;
  if (projectId !== state.project.id) return false;
  if (versionId !== args.version_id) return false;
  if (artifactDigest !== args.artifact_digest) return false;
  if (state.project.version_id !== args.version_id) return false;
  if (specVersion !== state.project_spec_version) return false;
  if (state.migration_state_version && (v.migration_state_version ?? v.request?.migration_state_version) !== state.migration_state_version) return false;
  return true;
}

function migrationPreflightIsSafe(args, { migration_preflight, project, organization_id, environment }) {
  if (!migration_preflight) return environment !== "production";
  if (migration_preflight.authoritative !== true) return false;
  if (migration_preflight.project_id !== project.id || migration_preflight.organization_id !== organization_id) return false;
  if (migration_preflight.environment !== environment) return false;
  if (migration_preflight.migration_ref !== args.migration_ref) return false;
  if (migration_preflight.blocked === true || migration_preflight.status === "FAIL") return false;
  return true;
}

function domainAuthorizationIsCurrent(args, { domain_authorization, project, organization_id, now = new Date() }) {
  if (!domain_authorization || domain_authorization.authoritative !== true || domain_authorization.ownership_verified !== true) return false;
  if (domain_authorization.project_id !== project.id || domain_authorization.organization_id !== organization_id) return false;
  if (domain_authorization.hostname !== args.hostname || domain_authorization.deployment_id !== args.deployment_id) return false;
  if (domain_authorization.environment !== args.target_environment) return false;
  if (domain_authorization.expires_at && new Date(domain_authorization.expires_at) <= now) return false;
  return true;
}

function evaluatePolicy({ definition, args, actor, organization_id, project, environment, resource = {}, approval = null, verification = null, budget = null, project_spec_version = null, migration_state_version = null, migration_preflight = null, domain_authorization = null, now = new Date() }) {
  if (!definition) return decision(TOOL_DECISIONS.DENY, "UNKNOWN_TOOL", RISK_LEVELS.CRITICAL);
  let risk = effectiveRisk(definition, args, { migration_preflight });
  try { assertResourceOwnership({ organization_id, project, actor, resource }); }
  catch (error) { return decision(TOOL_DECISIONS.DENY, error.code || "RESOURCE_SCOPE_DENIED", risk); }
  if (args.project_id !== project.id) return decision(TOOL_DECISIONS.DENY, "PROJECT_BINDING_MISMATCH", risk);
  if (args.environment !== environment) return decision(TOOL_DECISIONS.DENY, "ENVIRONMENT_BINDING_MISMATCH", risk);
  if (!definition.allowedEnvironments.includes(environment)) return decision(TOOL_DECISIONS.DENY, "ENVIRONMENT_NOT_ALLOWED", risk);
  const missing = missingCapabilities(definition.capabilityRequirements, actor.capabilities);
  if (missing.length > 0) return decision(TOOL_DECISIONS.DENY, "CAPABILITY_MISSING", risk, { missing_capabilities: missing });

  const mutates = ![SIDE_EFFECTS.NONE, SIDE_EFFECTS.READ].includes(definition.sideEffect);
  if (environment === "production" && mutates && !actor.capabilities.includes("production.access")) return decision(TOOL_DECISIONS.DENY, "PRODUCTION_CAPABILITY_MISSING", risk);

  if (definition.expensive && budget) {
    if (budget.exhausted === true || (Number.isFinite(budget.remaining_units) && budget.remaining_units <= 0)) return decision(TOOL_DECISIONS.DENY, "DENY_BUDGET_EXHAUSTED", risk);
    if (budget.requires_approval_for_extra_spend === true && !approval) return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "REQUIRE_APPROVAL_FOR_EXTRA_SPEND", risk);
  }

  if (definition.name === "request_migration") {
    if (!migrationPreflightIsSafe(args, { migration_preflight, project, organization_id, environment })) return decision(TOOL_DECISIONS.DENY, "MIGRATION_PREFLIGHT_REQUIRED_OR_STALE", maxRisk(risk, RISK_LEVELS.HIGH));
    if (migration_preflight?.destructive === true && environment === "production") risk = RISK_LEVELS.CRITICAL;
  }

  if (definition.name === "request_publish") {
    if (args.target_environment !== "production" || environment !== "production") return decision(TOOL_DECISIONS.DENY, "PUBLISH_TARGET_INVALID", RISK_LEVELS.HIGH);
    if (!verificationIsCurrent(args, { verification, project, project_spec_version, migration_state_version })) return decision(TOOL_DECISIONS.DENY, "VERIFICATION_REQUIRED_OR_STALE", RISK_LEVELS.HIGH);
    risk = maxRisk(risk, RISK_LEVELS.HIGH);
  }

  if (definition.name === "request_domain_attach") {
    if (!domainAuthorizationIsCurrent(args, { domain_authorization, project, organization_id, now })) return decision(TOOL_DECISIONS.DENY, "DOMAIN_OWNERSHIP_REQUIRED_OR_STALE", maxRisk(risk, RISK_LEVELS.HIGH));
  }

  const approvalRequired = RISK_ORDER[risk] >= RISK_ORDER.HIGH || definition.approval === "REQUIRED" || (environment === "production" && mutates);
  if (approvalRequired) {
    if (!approval) return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_REQUIRED", risk);
    if (approval.status !== "approved") return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_NOT_APPROVED", risk);
    if (approval.expires_at && new Date(approval.expires_at) <= now) return decision(TOOL_DECISIONS.REQUIRE_APPROVAL, "APPROVAL_EXPIRED", risk);
  }
  return decision(TOOL_DECISIONS.ALLOW, "POLICY_ALLOWED", risk);
}

module.exports = { POLICY_VERSION, effectiveRisk, assertResourceOwnership, verificationIsCurrent, migrationPreflightIsSafe, domainAuthorizationIsCurrent, evaluatePolicy };
