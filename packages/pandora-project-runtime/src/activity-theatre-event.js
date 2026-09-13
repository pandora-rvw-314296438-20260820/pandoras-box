"use strict";

const ACTIVITY_EVENT_SCHEMA_VERSION = 1;

const ACTIVITY_EVENT_STATES = Object.freeze([
  "understanding",
  "planning",
  "acting",
  "checking",
  "needs_you",
  "retrying",
  "fallback",
  "verifying",
  "result",
  "failed",
  "cancelled",
]);

const ACTIVITY_EVENT_SOURCE_TYPES = Object.freeze([
  "runtime",
  "device",
  "provider",
  "projectos",
  "model",
  "tool",
]);

const TERMINAL_ACTIVITY_STATES = Object.freeze(["result", "failed", "cancelled"]);
const TERMINAL_ACTIVITY_STATE_SET = new Set(TERMINAL_ACTIVITY_STATES);
const ACTIVITY_EVENT_STATE_SET = new Set(ACTIVITY_EVENT_STATES);
const ACTIVITY_EVENT_SOURCE_TYPE_SET = new Set(ACTIVITY_EVENT_SOURCE_TYPES);

const opaqueIdPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;
const timestampPattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/i;
const highConfidenceCredentialPatterns = Object.freeze([
  /Authorization\s*:\s*(?:Bearer|Basic)\s+[^\s]+/i,
  /gh[pousr]_[A-Za-z0-9_]{20,}/,
  /\bsk-[A-Za-z0-9_-]{20,}\b/,
  /(?:sbp|vcp|sb_secret|vercel)_[A-Za-z0-9_-]{12,}/i,
  /AIza[0-9A-Za-z_-]{20,}/,
  /\bBearer\s+[A-Za-z0-9._~+\/-]{12,}/i,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /(?:postgres(?:ql)?):\/\/[^\s:@]+:[^@\s]+@/i,
  /https?:\/\/[^/\s:@]+:[^@\s/]+@/i,
  /\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b/,

]);
const credentialAssignmentPattern = /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|private[_-]?key)\s*[:=]\s*["']?([^\s,;}"']{4,})/gi;
const safeCredentialStatusValues = new Set([
  "disabled",
  "expired",
  "hidden",
  "invalid",
  "missing",
  "not-configured",
  "not_configured",
  "redacted",
  "required",
  "revoked",
  "unknown",
  "unavailable",
  "unset",
]);
const allowedTopLevelKeys = new Set([
  "schemaVersion",
  "eventId",
  "jobId",
  "sequence",
  "state",
  "message",
  "occurredAt",
  "provenance",
  "domain",
  "capability",
  "executionId",
  "parentEventId",
  "blocker",
  "outcome",
]);
const allowedProvenanceKeys = new Set([
  "sourceType",
  "sourceId",
  "sourceEventId",
  "observedAt",
  "evidenceRef",
]);
const allowedBlockerKeys = new Set([
  "reason",
  "requiredAction",
  "approvalRequired",
  "policyRef",
]);
const allowedOutcomeKeys = new Set([
  "summary",
  "verificationRef",
]);

function plainObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field} must be an object`);
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    throw new Error(`${field} must be a plain object`);
  }
  return value;
}

function assertKnownKeys(value, allowed, field) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new Error(`${field}.${key} is not part of the canonical activity schema`);
  }
}

function nonEmpty(value, field, maxLength = 500) {
  if (typeof value !== "string") throw new Error(`${field} must be a string`);
  const normalized = value.trim();
  if (!normalized) throw new Error(`${field} is required`);
  if (normalized.length > maxLength) throw new Error(`${field} is too long`);
  return normalized;
}

function assertNoCredentialLikeMaterial(value, field, { inspectNamedAssignments = false } = {}) {
  if (highConfidenceCredentialPatterns.some((pattern) => pattern.test(value))) {
    throw new Error(`${field} contains credential-like material`);
  }
  if (!inspectNamedAssignments) return value;

  credentialAssignmentPattern.lastIndex = 0;
  let match;
  while ((match = credentialAssignmentPattern.exec(value)) !== null) {
    const assigned = String(match[1] || "").replace(/^[\[({]+|[\])}.]+$/g, "").toLowerCase();
    if (!safeCredentialStatusValues.has(assigned)) {
      throw new Error(`${field} contains credential-like material`);
    }
  }
  return value;
}

function publicText(value, field, maxLength) {
  const normalized = nonEmpty(value, field, maxLength);
  return assertNoCredentialLikeMaterial(normalized, field, { inspectNamedAssignments: true });
}

function opaqueId(value, field) {
  const normalized = nonEmpty(value, field, 200);
  assertNoCredentialLikeMaterial(normalized, field);
  if (!opaqueIdPattern.test(normalized)) {
    throw new Error(`${field} must be an opaque identifier using letters, digits, dot, colon, underscore or hyphen`);
  }
  return normalized;
}

function isLeapYear(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function isoTimestamp(value, field) {
  const normalized = nonEmpty(value, field, 80);
  const match = timestampPattern.exec(normalized);
  if (!match) {
    throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const zone = match[7];
  const daysInMonth = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth[month - 1] ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  ) {
    throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
  }

  if (zone.toUpperCase() !== "Z") {
    const offsetHour = Number(zone.slice(1, 3));
    const offsetMinute = Number(zone.slice(4, 6));
    if (offsetHour > 23 || offsetMinute > 59) {
      throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
    }
  }

  const timestamp = Date.parse(normalized);
  if (Number.isNaN(timestamp)) {
    throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
  }
  return new Date(timestamp).toISOString();
}

function optionalText(value, field, maxLength) {
  if (value == null) return null;
  return publicText(value, field, maxLength);
}

function optionalOpaqueId(value, field) {
  if (value == null) return null;
  return opaqueId(value, field);
}

function normalizeProvenance(input) {
  const provenance = plainObject(input, "provenance");
  assertKnownKeys(provenance, allowedProvenanceKeys, "provenance");
  const sourceType = nonEmpty(provenance.sourceType, "provenance.sourceType", 40).toLowerCase();
  if (!ACTIVITY_EVENT_SOURCE_TYPE_SET.has(sourceType)) {
    throw new Error(`unsupported provenance.sourceType: ${sourceType}`);
  }
  const sourceId = opaqueId(provenance.sourceId, "provenance.sourceId");
  const sourceEventId = optionalOpaqueId(provenance.sourceEventId, "provenance.sourceEventId");
  const observedAt = isoTimestamp(provenance.observedAt, "provenance.observedAt");
  const evidenceRef = optionalText(provenance.evidenceRef, "provenance.evidenceRef", 500);
  if (!sourceEventId && !evidenceRef) {
    throw new Error("provenance requires sourceEventId or evidenceRef linking to a real source event");
  }
  return Object.freeze({
    sourceType,
    sourceId,
    sourceEventId,
    observedAt,
    evidenceRef,
  });
}

function normalizeBlocker(input, state) {
  if (state !== "needs_you") {
    if (input != null) throw new Error("blocker is only valid for needs_you events");
    return null;
  }
  const blocker = plainObject(input, "blocker");
  assertKnownKeys(blocker, allowedBlockerKeys, "blocker");
  if (typeof blocker.approvalRequired !== "boolean") {
    throw new Error("blocker.approvalRequired must be boolean");
  }
  return Object.freeze({
    reason: publicText(blocker.reason, "blocker.reason", 500),
    requiredAction: publicText(blocker.requiredAction, "blocker.requiredAction", 500),
    approvalRequired: blocker.approvalRequired,
    policyRef: optionalText(blocker.policyRef, "blocker.policyRef", 300),
  });
}

function normalizeOutcome(input, state) {
  if (state !== "result") {
    if (input != null) throw new Error("outcome is only valid for result events");
    return null;
  }
  const outcome = plainObject(input, "outcome");
  assertKnownKeys(outcome, allowedOutcomeKeys, "outcome");
  return Object.freeze({
    summary: publicText(outcome.summary, "outcome.summary", 1000),
    verificationRef: optionalText(outcome.verificationRef, "outcome.verificationRef", 500),
  });
}

function normalizeActivityEvent(input) {
  const event = plainObject(input, "event");
  assertKnownKeys(event, allowedTopLevelKeys, "event");

  if (event.schemaVersion !== ACTIVITY_EVENT_SCHEMA_VERSION) {
    throw new Error(`unsupported activity event schemaVersion: ${event.schemaVersion}`);
  }
  if (!Number.isSafeInteger(event.sequence) || event.sequence < 1) {
    throw new Error("sequence must be a positive safe integer");
  }

  const state = nonEmpty(event.state, "state", 40).toLowerCase();
  if (!ACTIVITY_EVENT_STATE_SET.has(state)) {
    throw new Error(`unsupported activity state: ${state}`);
  }

  const normalized = {
    schemaVersion: ACTIVITY_EVENT_SCHEMA_VERSION,
    eventId: opaqueId(event.eventId, "eventId"),
    jobId: opaqueId(event.jobId, "jobId"),
    sequence: event.sequence,
    state,
    message: publicText(event.message, "message", 1000),
    occurredAt: isoTimestamp(event.occurredAt, "occurredAt"),
    provenance: normalizeProvenance(event.provenance),
    domain: optionalText(event.domain, "domain", 100),
    capability: optionalText(event.capability, "capability", 160),
    executionId: optionalOpaqueId(event.executionId, "executionId"),
    parentEventId: optionalOpaqueId(event.parentEventId, "parentEventId"),
    blocker: normalizeBlocker(event.blocker, state),
    outcome: normalizeOutcome(event.outcome, state),
  };

  return Object.freeze(normalized);
}

function isTerminalActivityState(state) {
  return TERMINAL_ACTIVITY_STATE_SET.has(String(state || "").trim().toLowerCase());
}

function validateActivityTimeline(input) {
  if (!Array.isArray(input) || input.length === 0) {
    throw new Error("activity timeline must contain at least one event");
  }
  const events = input.map(normalizeActivityEvent);
  const jobId = events[0].jobId;
  const eventIds = new Set();
  let lastSequence = 0;
  let lastObservedAt = 0;
  let terminalSeen = false;

  for (const event of events) {
    if (event.jobId !== jobId) throw new Error("activity timeline cannot mix job identities");
    if (eventIds.has(event.eventId)) throw new Error("activity timeline contains duplicate eventId");
    if (event.sequence <= lastSequence) throw new Error("activity timeline sequence must be strictly increasing");
    const occurredAt = Date.parse(event.occurredAt);
    if (occurredAt < lastObservedAt) throw new Error("activity timeline timestamps must be nondecreasing");
    if (terminalSeen) throw new Error("activity timeline cannot emit events after a terminal state");
    eventIds.add(event.eventId);
    lastSequence = event.sequence;
    lastObservedAt = occurredAt;
    terminalSeen = isTerminalActivityState(event.state);
  }

  return Object.freeze(events);
}

module.exports = {
  ACTIVITY_EVENT_SCHEMA_VERSION,
  ACTIVITY_EVENT_SOURCE_TYPES,
  ACTIVITY_EVENT_STATES,
  TERMINAL_ACTIVITY_STATES,
  isTerminalActivityState,
  normalizeActivityEvent,
  validateActivityTimeline,
};
