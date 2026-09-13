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
const credentialLikePatterns = Object.freeze([
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
  /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|private[_-]?key)\s*[:=]\s*["']?[^\s,;}"']{4,}/i,
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
  if (credentialLikePatterns.some((pattern) => pattern.test(normalized))) {
    throw new Error(`${field} contains credential-like material`);
  }
  return normalized;
}

function opaqueId(value, field) {
  const normalized = nonEmpty(value, field, 200);
  if (!opaqueIdPattern.test(normalized)) {
    throw new Error(`${field} must be an opaque identifier using letters, digits, dot, colon, underscore or hyphen`);
  }
  return normalized;
}

function isoTimestamp(value, field) {
  const normalized = nonEmpty(value, field, 80);
  if (!/(?:Z|[+-]\d{2}:\d{2})$/i.test(normalized) || Number.isNaN(Date.parse(normalized))) {
    throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
  }
  return new Date(normalized).toISOString();
}

function optionalText(value, field, maxLength) {
  if (value == null) return null;
  return nonEmpty(value, field, maxLength);
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
  return Object.freeze({
    sourceType,
    sourceId: opaqueId(provenance.sourceId, "provenance.sourceId"),
    sourceEventId: optionalOpaqueId(provenance.sourceEventId, "provenance.sourceEventId"),
    observedAt: isoTimestamp(provenance.observedAt, "provenance.observedAt"),
    evidenceRef: optionalText(provenance.evidenceRef, "provenance.evidenceRef", 500),
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
    reason: nonEmpty(blocker.reason, "blocker.reason", 500),
    requiredAction: nonEmpty(blocker.requiredAction, "blocker.requiredAction", 500),
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
    summary: nonEmpty(outcome.summary, "outcome.summary", 1000),
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
    message: nonEmpty(event.message, "message", 1000),
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
