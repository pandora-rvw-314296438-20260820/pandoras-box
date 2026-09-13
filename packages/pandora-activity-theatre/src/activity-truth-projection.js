"use strict";

const { normalizeActivityEvent } = require("./activity-theatre-event.js");

const ACTIVITY_PUBLIC_PROJECTION_VERSION = 1;
const MEASUREMENT_SOURCE_TYPES = new Set(["runtime", "device", "provider", "projectos", "tool"]);
const MEASUREMENT_EVIDENCE_TYPES = new Set([
  "runtime_event",
  "provider_receipt",
  "device_event",
  "tool_receipt",
  "test_receipt",
  "artifact",
  "verification_receipt",
]);

const percentageClaimPattern = /(?:^|[^\d])(?:100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*(?:%|percent\b)/i;
const stageClaimPattern = /(?:\b(?:stage|phase|step)\s+\d+(?:\s*(?:of|\/)\s*\d+)?\b|\b(?:stage|phase)\s*[:=-]\s*[A-Za-z0-9][A-Za-z0-9 _.-]{0,60})/i;
const ratioClaimPattern = /\b\d+\s*(?:of|\/)\s*\d+\s+(?:items?|files?|tasks?|steps?|checks?|tests?|stages?|phases?)\b/i;
const leadingResultClaimPattern = /^(?:the\s+)?(?:job|task|request|work|operation|build|deployment|publication|release)\s+(?:is\s+|was\s+|has\s+been\s+)?(?:done|complete|completed|finished|successful|verified|live)\b/i;
const leadingSucceededPattern = /^(?:the\s+)?(?:job|task|request|work|operation|build|deployment|publication|release)\s+(?:succeeded|completed|finished)\b/i;
const standaloneResultClaimPattern = /^(?:done|complete|completed|finished|success|successful|succeeded|fixed|published|deployed|verified|live)\b(?:[.!:]|$)/i;
const successfulMutationPattern = /^(?:(?:the\s+)?(?:fix|publish|publication|deployment|build|release)\s+(?:was\s+)?(?:successful|completed|finished|verified)|(?:fixed|published|deployed|released|built)\s+successfully)\b/i;
const completePercentPattern = /^100(?:\.0+)?\s*%\s*(?:complete|completed|done|finished)\b/i;

function plainObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${field} must be a plain object`);
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) throw new Error(`${field} must be a plain object`);
  return value;
}

function messageClaimsMeasurement(message) {
  return percentageClaimPattern.test(message) || stageClaimPattern.test(message) || ratioClaimPattern.test(message);
}

function messageClaimsOverallResult(message) {
  const normalized = String(message || "").trim();
  return leadingResultClaimPattern.test(normalized)
    || leadingSucceededPattern.test(normalized)
    || standaloneResultClaimPattern.test(normalized)
    || successfulMutationPattern.test(normalized)
    || completePercentPattern.test(normalized);
}

function hasMeasurementSource(event) {
  if (MEASUREMENT_SOURCE_TYPES.has(event.provenance.sourceType) && event.provenance.sourceEventId) return true;
  return event.evidence.some((item) => item.relation === "source" && MEASUREMENT_EVIDENCE_TYPES.has(item.type));
}

function assertPublicClaimTruth(text, event, field) {
  if (messageClaimsMeasurement(text) && !hasMeasurementSource(event)) {
    throw new Error(`${field} measurable progress or stage claim requires runtime/device/provider/ProjectOS/tool source evidence`);
  }
  if (messageClaimsOverallResult(text) && event.state !== "result") {
    throw new Error(`${field} overall completion claim requires verified result state`);
  }
}

function assertActivityMessageTruth(event) {
  assertPublicClaimTruth(event.message, event, "message");
  if (event.outcome?.summary) assertPublicClaimTruth(event.outcome.summary, event, "outcome.summary");
  return event;
}

function assertActivityTruth(input) {
  return assertActivityMessageTruth(normalizeActivityEvent(input));
}

function evidenceProjection(evidence) {
  return Object.freeze(evidence.map((item) => Object.freeze({
    type: item.type,
    relation: item.relation,
    ref: item.ref,
  })));
}

function sourceProjection(provenance) {
  return Object.freeze({
    sourceType: provenance.sourceType,
    sourceId: provenance.sourceId,
    sourceEventId: provenance.sourceEventId,
    observedAt: provenance.observedAt,
  });
}

function blockerProjection(blocker) {
  if (!blocker) return null;
  return Object.freeze({
    reasonCode: blocker.reasonCode,
    reason: blocker.reason,
    requiredAction: blocker.requiredAction,
    approvalRequired: blocker.approvalRequired,
    policyRef: blocker.policyRef,
  });
}

function outcomeProjection(outcome) {
  if (!outcome) return null;
  return Object.freeze({ summary: outcome.summary, physicalDevice: outcome.physicalDevice });
}

function deriveActivityProjection(input) {
  const event = assertActivityTruth(input);
  return Object.freeze({
    projectionVersion: ACTIVITY_PUBLIC_PROJECTION_VERSION,
    eventId: event.eventId,
    jobId: event.jobId,
    sequence: event.sequence,
    state: event.state,
    message: event.message,
    occurredAt: event.occurredAt,
    admittedAt: event.admittedAt,
    domain: event.domain,
    capability: event.capability,
    executionId: event.executionId,
    source: sourceProjection(event.provenance),
    evidenceRefs: evidenceProjection(event.evidence),
    blocker: blockerProjection(event.blocker),
    outcome: outcomeProjection(event.outcome),
  });
}

function canonicalJson(value, field = "projection") {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`${field} contains a non-finite number`);
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map((item, index) => canonicalJson(item, `${field}[${index}]`)).join(",")}]`;
  plainObject(value, field);
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key], `${field}.${key}`)}`).join(",")}}`;
}

function validateActivityProjection(projection, sourceEvent) {
  plainObject(projection, "projection");
  const expected = deriveActivityProjection(sourceEvent);
  if (canonicalJson(projection) !== canonicalJson(expected)) {
    throw new Error("activity projection must be an exact derivation of its canonical source event");
  }
  return expected;
}

module.exports = {
  ACTIVITY_PUBLIC_PROJECTION_VERSION,
  assertActivityMessageTruth,
  assertActivityTruth,
  deriveActivityProjection,
  messageClaimsMeasurement,
  messageClaimsOverallResult,
  validateActivityProjection,
};
