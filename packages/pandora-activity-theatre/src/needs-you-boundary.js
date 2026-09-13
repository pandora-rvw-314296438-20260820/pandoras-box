"use strict";

const { normalizeActivityEvent } = require("./activity-theatre-event.js");

const NEEDS_YOU_APPROVAL_REASON_CODES = Object.freeze([
  "authorization_required",
  "missing_consequential_user_choice",
]);

const NEEDS_YOU_USER_ACTION_REASON_CODES = Object.freeze([
  "account_connection_or_reauthentication_required",
  "protected_app_user_presence_required",
  "user_only_recovery_or_conflict_resolution",
  "external_blocker_only_user_can_resolve",
]);

const APPROVAL_REASON_SET = new Set(NEEDS_YOU_APPROVAL_REASON_CODES);
const USER_ACTION_REASON_SET = new Set(NEEDS_YOU_USER_ACTION_REASON_CODES);
const AUTHORITY_DECISIONS = new Set(["auto_execute", "standing_authorized", "needs_approval", "deny"]);

function normalizeAuthorityDecision(value) {
  if (value == null) return null;
  if (typeof value !== "string") throw new Error("authorityDecision must be a string");
  const normalized = value.trim().toLowerCase();
  if (!AUTHORITY_DECISIONS.has(normalized)) throw new Error(`unsupported authorityDecision: ${normalized}`);
  return normalized;
}

function hasEvidence(event, relation, type = null) {
  return event.evidence.some((item) => item.relation === relation && (type == null || item.type === type));
}

function hasAuthoritativeSource(event, allowedSourceTypes) {
  return allowedSourceTypes.includes(event.provenance.sourceType) && Boolean(event.provenance.sourceEventId);
}

function assertApprovalBoundary(event, authorityDecision) {
  if (event.blocker.approvalRequired !== true) {
    throw new Error(`${event.blocker.reasonCode} requires blocker.approvalRequired=true`);
  }
  if (!event.blocker.policyRef) {
    throw new Error(`${event.blocker.reasonCode} requires blocker.policyRef`);
  }
  if (authorityDecision !== "needs_approval") {
    throw new Error(`${event.blocker.reasonCode} requires authorityDecision=needs_approval`);
  }
  if (!hasEvidence(event, "policy", "policy_decision")) {
    throw new Error(`${event.blocker.reasonCode} requires policy_decision evidence`);
  }
}

function assertUserActionBoundary(event, authorityDecision) {
  if (event.blocker.approvalRequired !== false) {
    throw new Error(`${event.blocker.reasonCode} is a user-action blocker and requires blocker.approvalRequired=false`);
  }
  if (authorityDecision === "needs_approval") {
    throw new Error(`${event.blocker.reasonCode} must not masquerade as an approval boundary`);
  }
  if (authorityDecision === "deny") {
    throw new Error("authorityDecision=deny is non-overridable and must not emit Needs You");
  }

  const allowed = {
    account_connection_or_reauthentication_required: ["runtime", "provider", "tool"],
    protected_app_user_presence_required: ["runtime", "device", "tool"],
    user_only_recovery_or_conflict_resolution: ["runtime", "device", "provider", "tool"],
    external_blocker_only_user_can_resolve: ["runtime", "device", "provider", "tool"],
  }[event.blocker.reasonCode];

  if (!hasAuthoritativeSource(event, allowed)) {
    throw new Error(`${event.blocker.reasonCode} requires authoritative runtime/device/provider/tool provenance`);
  }
}

function assertNeedsYouBoundary(input, options = {}) {
  const event = normalizeActivityEvent(input);
  if (event.state !== "needs_you") throw new Error("Needs You boundary requires state=needs_you");

  const authorityDecision = normalizeAuthorityDecision(options.authorityDecision);
  const reasonCode = event.blocker.reasonCode;

  if (APPROVAL_REASON_SET.has(reasonCode)) {
    assertApprovalBoundary(event, authorityDecision);
  } else if (USER_ACTION_REASON_SET.has(reasonCode)) {
    assertUserActionBoundary(event, authorityDecision);
  } else {
    throw new Error(`unsupported Needs You reason: ${reasonCode}`);
  }

  return event;
}

function needsYouBoundaryStatus(input, options = {}) {
  const event = assertNeedsYouBoundary(input, options);
  return Object.freeze({
    state: "needs_you",
    paused: true,
    blocking: true,
    jobId: event.jobId,
    eventId: event.eventId,
    sequence: event.sequence,
    reasonCode: event.blocker.reasonCode,
    reason: event.blocker.reason,
    requiredAction: event.blocker.requiredAction,
    approvalRequired: event.blocker.approvalRequired,
    policyRef: event.blocker.policyRef,
    occurredAt: event.occurredAt,
    admittedAt: event.admittedAt,
  });
}

module.exports = {
  NEEDS_YOU_APPROVAL_REASON_CODES,
  NEEDS_YOU_USER_ACTION_REASON_CODES,
  assertNeedsYouBoundary,
  needsYouBoundaryStatus,
};
