"use strict";

const { computeActionHash, secureEqualHex } = require("./contracts");
const { PandoraToolError } = require("./errors");
const { POLICY_VERSION } = require("./policy");

function asDate(value, field) {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) throw new PandoraToolError("approval_required", "APPROVAL_TIME_INVALID", `${field} is invalid`);
  return date;
}

function approvalBindingFromAction({ proposal, organization_id, project_id, actor_id, environment, target_resource = null, project_version = null, project_state_hash = null, risk, policy_version = POLICY_VERSION }) {
  if (!proposal?.tool || !proposal?.version || !proposal?.arguments) throw new PandoraToolError("invalid_request", "APPROVAL_ACTION_INVALID", "Approval binding requires a normalized proposal");
  const action_hash = computeActionHash({
    tool: proposal.tool,
    version: proposal.version,
    arguments: proposal.arguments,
    organization_id,
    project_id,
    environment,
    target_resource,
    project_version,
    policy_version,
  });
  return Object.freeze({
    organization_id,
    project_id,
    actor_id,
    tool: proposal.tool,
    tool_version: proposal.version,
    action_hash,
    target_resource,
    environment,
    risk,
    policy_version,
    project_version,
    project_state_hash,
  });
}

function createApprovalGrant(binding, { approval_id, approved_by, approved_at, expires_at, one_time = true, status = "approved" }) {
  if (!approval_id || !approved_by) throw new PandoraToolError("approval_required", "APPROVAL_IDENTITY_INVALID", "Approval identity is required");
  const approved = asDate(approved_at, "approved_at");
  const expires = asDate(expires_at, "expires_at");
  if (expires <= approved) throw new PandoraToolError("approval_required", "APPROVAL_EXPIRY_INVALID", "Approval expiry must follow approval time");
  return Object.freeze({ ...binding, approval_id, approved_by, approved_at: approved.toISOString(), expires_at: expires.toISOString(), one_time: one_time !== false, status, revoked_at: null, consumed_at: null });
}

function validateApprovalGrant(grant, expected, { now = new Date(), requireOneTimeAvailable = true } = {}) {
  if (!grant) throw new PandoraToolError("approval_required", "APPROVAL_REQUIRED", "Approval is required");
  if (grant.revoked_at) throw new PandoraToolError("approval_required", "APPROVAL_REVOKED", "Approval was revoked");
  if (grant.status !== "approved") throw new PandoraToolError("approval_required", "APPROVAL_NOT_APPROVED", "Approval is not active");
  if (grant.one_time !== false && requireOneTimeAvailable && grant.consumed_at) throw new PandoraToolError("approval_required", "APPROVAL_ALREADY_CONSUMED", "One-time approval was already consumed");
  if (asDate(grant.expires_at, "expires_at") <= now) throw new PandoraToolError("approval_required", "APPROVAL_EXPIRED", "Approval has expired");
  if (grant.organization_id !== expected.organization_id) throw new PandoraToolError("approval_required", "APPROVAL_ORG_MISMATCH", "Approval belongs to another organization");
  if (grant.project_id !== expected.project_id) throw new PandoraToolError("approval_required", "APPROVAL_PROJECT_MISMATCH", "Approval belongs to another project");
  if (grant.actor_id !== expected.actor_id) throw new PandoraToolError("approval_required", "APPROVAL_ACTOR_MISMATCH", "Approval is bound to another actor");
  if (grant.tool !== expected.tool || grant.tool_version !== expected.tool_version) throw new PandoraToolError("approval_required", "APPROVAL_TOOL_MISMATCH", "Approval is bound to another tool version");
  if (grant.environment !== expected.environment) throw new PandoraToolError("approval_required", "APPROVAL_ENVIRONMENT_MISMATCH", "Approval is bound to another environment");
  if ((grant.target_resource ?? null) !== (expected.target_resource ?? null)) throw new PandoraToolError("approval_required", "APPROVAL_RESOURCE_MISMATCH", "Approval is bound to another resource");
  if (grant.risk !== expected.risk) throw new PandoraToolError("approval_required", "APPROVAL_RISK_MISMATCH", "Approval risk does not match current action");
  if (grant.policy_version !== expected.policy_version) throw new PandoraToolError("approval_required", "APPROVAL_POLICY_STALE", "Approval was issued under another policy version");
  if ((grant.project_version ?? null) !== (expected.project_version ?? null)) throw new PandoraToolError("approval_required", "APPROVAL_PROJECT_VERSION_STALE", "Approval was issued for another project version");
  if ((grant.project_state_hash ?? null) !== (expected.project_state_hash ?? null)) throw new PandoraToolError("approval_required", "APPROVAL_PROJECT_STATE_STALE", "Project state changed after approval");
  if (!secureEqualHex(grant.action_hash, expected.action_hash)) throw new PandoraToolError("approval_required", "APPROVAL_ACTION_HASH_MISMATCH", "Approved action differs from requested action");
  return true;
}

class MemoryApprovalStore {
  constructor() { this.durability = "memory"; this.records = new Map(); }
  async put(grant) { this.records.set(grant.approval_id, { ...grant }); return grant.approval_id; }
  async get(approvalId) { const value = this.records.get(approvalId); return value ? { ...value } : null; }
  async revoke(approvalId, at = new Date()) { const value = this.records.get(approvalId); if (!value) return false; value.revoked_at = at.toISOString(); value.status = "revoked"; return true; }
  async consume(approvalId, expectedActionHash, at = new Date()) {
    const value = this.records.get(approvalId);
    if (!value) throw new PandoraToolError("approval_required", "APPROVAL_MISSING", "Approval does not exist");
    if (!secureEqualHex(value.action_hash, expectedActionHash)) throw new PandoraToolError("approval_required", "APPROVAL_ACTION_HASH_MISMATCH", "Approval action changed before consumption");
    if (value.one_time !== false && value.consumed_at) throw new PandoraToolError("approval_required", "APPROVAL_ALREADY_CONSUMED", "One-time approval was already consumed");
    value.consumed_at = at.toISOString();
    return { ...value };
  }
}

module.exports = { approvalBindingFromAction, createApprovalGrant, validateApprovalGrant, MemoryApprovalStore };
