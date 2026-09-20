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
"paused",
"resuming",
"result",
"failed",
"cancelled",
]);
const ACTIVITY_EVENT_SOURCE_TYPES = Object.freeze([
"runtime",
"device",
"provider",
"pandora",
"model",
"tool",
]);
const ACTIVITY_EVIDENCE_TYPES = Object.freeze([
"runtime_event",
"provider_receipt",
"device_event",
"tool_receipt",
"test_receipt",
"artifact",
"verification_receipt",
"policy_decision",
"user_control",
]);
const ACTIVITY_CONTROL_TYPES = Object.freeze(["pause", "resume", "cancel", "redirect", "constraint"]);
const NEEDS_YOU_REASON_CODES = Object.freeze([
"authorization_required",
"missing_consequential_user_choice",
"account_connection_or_reauthentication_required",
"protected_app_user_presence_required",
"user_only_recovery_or_conflict_resolution",
"external_blocker_only_user_can_resolve",
]);
const EVIDENCE_RELATIONS = Object.freeze([
"source",
"verification",
"failure",
"accepted_control",
"authoritative_pause",
"authoritative_cancellation",
"prior_attempt",
"capability",
"policy",
"readback",
]);
const TERMINAL_ACTIVITY_STATES = Object.freeze(["result", "failed", "cancelled"]);
const STATE_SET = new Set(ACTIVITY_EVENT_STATES);
const SOURCE_SET = new Set(ACTIVITY_EVENT_SOURCE_TYPES);
const EVIDENCE_TYPE_SET = new Set(ACTIVITY_EVIDENCE_TYPES);
const CONTROL_TYPE_SET = new Set(ACTIVITY_CONTROL_TYPES);
const NEEDS_YOU_REASON_SET = new Set(NEEDS_YOU_REASON_CODES);
const EVIDENCE_RELATION_SET = new Set(EVIDENCE_RELATIONS);
const TERMINAL_SET = new Set(TERMINAL_ACTIVITY_STATES);
const opaqueIdPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;
const timestampPattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/i;
const highConfidenceCredentialPatterns = Object.freeze([
/Authorization\s*:\s*(?:Bearer|Basic)\s+[^\s]+/i,
/gh[pousr]_[A-Za-z0-9_]{20,}/,
/\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
/\b(?:xox[a-z]-|xapp-)[A-Za-z0-9-]{10,}\b/i,
/https:\/\/hooks\.slack\.com\/services\/[A-Za-z0-9/_-]{20,}/i,
/\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/,
/\bsk-[A-Za-z0-9_-]{20,}\b/,
/(?:sbp|vcp|sb_secret|vercel)_[A-Za-z0-9_-]{12,}/i,
/AIza[0-9A-Za-z_-]{20,}/,
/\bBearer\s+[A-Za-z0-9._~+\/-]{12,}/i,
/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
/(?:postgres(?:ql)?):\/\/[^\s:@]+:[^@\s]+@/i,
/https?:\/\/[^/\s:@]+:[^@\s/]+@/i,
/\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b/,
]);
const credentialAssignmentPattern = /(?:api[_-]?key|access[_-]?key[_-]?id|secret[_-]?access[_-]?key|secret[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|private[_-]?key)\s*[:=]\s*["']?([^\s,;}"']{4,})/gi;
const safeCredentialStatusValues = new Set([
"disabled", "expired", "hidden", "invalid", "missing", "not-configured", "not_configured",
"redacted", "required", "revoked", "unknown", "unavailable", "unset",
]);
const allowedTopLevelKeys = new Set([
"schemaVersion", "eventId", "jobId", "sequence", "writerEpoch", "admittedBy", "admissionMode",
"state", "message", "occurredAt", "admittedAt", "provenance", "evidence", "domain", "capability",
"executionId", "parentEventId", "control", "transition", "blocker", "outcome",
]);
const allowedProvenanceKeys = new Set(["sourceType", "sourceId", "sourceEventId", "observedAt"]);
const allowedEvidenceKeys = new Set(["type", "ref", "relation"]);
const allowedControlKeys = new Set(["type", "requestId", "acceptedAt", "acceptanceAmbiguous"]);
const allowedTransitionKeys = new Set([
"priorAttemptId", "priorAuthorityScopeRef", "authorityScopeRef", "consequential", "priorIdempotencyKey", "idempotencyKey", "effectAmbiguous",
]);
const allowedBlockerKeys = new Set(["reasonCode", "reason", "requiredAction", "approvalRequired", "policyRef"]);
const allowedOutcomeKeys = new Set(["summary", "physicalDevice"]);
function plainObject(value, field) {
if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${field} must be an object`);
const prototype = Object.getPrototypeOf(value);
if (prototype !== Object.prototype && prototype !== null) throw new Error(`${field} must be a plain object`);
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
if (highConfidenceCredentialPatterns.some((pattern) => pattern.test(value))) throw new Error(`${field} contains credential-like material`);
if (!inspectNamedAssignments) return value;
credentialAssignmentPattern.lastIndex = 0;
let match;
while ((match = credentialAssignmentPattern.exec(value)) !== null) {
const assigned = String(match[1] || "").replace(/^[\[({]+|[\])}.]+$/g, "").toLowerCase();
if (!safeCredentialStatusValues.has(assigned)) throw new Error(`${field} contains credential-like material`);
}
return value;
}
function publicText(value, field, maxLength) {
const normalized = nonEmpty(value, field, maxLength);
return assertNoCredentialLikeMaterial(normalized, field, { inspectNamedAssignments: true });
}
function optionalText(value, field, maxLength) {
if (value == null) return null;
return publicText(value, field, maxLength);
}
function opaqueId(value, field) {
const normalized = nonEmpty(value, field, 200);
assertNoCredentialLikeMaterial(normalized, field, { inspectNamedAssignments: true });
if (!opaqueIdPattern.test(normalized)) throw new Error(`${field} must be an opaque identifier using letters, digits, dot, colon, underscore or hyphen`);
return normalized;
}
function optionalOpaqueId(value, field) {
if (value == null) return null;
return opaqueId(value, field);
}
function positiveSafeInteger(value, field) {
if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${field} must be a positive safe integer`);
return value;
}
function isLeapYear(year) {
return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}
function isoTimestamp(value, field) {
const normalized = nonEmpty(value, field, 80);
const match = timestampPattern.exec(normalized);
if (!match) throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
const year = Number(match[1]);
const month = Number(match[2]);
const day = Number(match[3]);
const hour = Number(match[4]);
const minute = Number(match[5]);
const second = Number(match[6]);
const zone = match[7];
const daysInMonth = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
if (month < 1 || month > 12 || day < 1 || day > daysInMonth[month - 1] || hour > 23 || minute > 59 || second > 59) {
throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
}
if (zone.toUpperCase() !== "Z") {
const offsetHour = Number(zone.slice(1, 3));
const offsetMinute = Number(zone.slice(4, 6));
if (offsetHour > 23 || offsetMinute > 59) throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
}
const timestamp = Date.parse(normalized);
if (Number.isNaN(timestamp)) throw new Error(`${field} must be an offset-aware ISO-8601 timestamp`);
return new Date(timestamp).toISOString();
}
function normalizeEvidence(input, index) {
const evidence = plainObject(input, `evidence[${index}]`);
assertKnownKeys(evidence, allowedEvidenceKeys, `evidence[${index}]`);
const type = nonEmpty(evidence.type, `evidence[${index}].type`, 80).toLowerCase();
if (!EVIDENCE_TYPE_SET.has(type)) throw new Error(`unsupported evidence type: ${type}`);
const relation = nonEmpty(evidence.relation, `evidence[${index}].relation`, 80).toLowerCase();
if (!EVIDENCE_RELATION_SET.has(relation)) throw new Error(`unsupported evidence relation: ${relation}`);
return Object.freeze({
type,
ref: publicText(evidence.ref, `evidence[${index}].ref`, 500),
relation,
});
}
function normalizeEvidenceList(input) {
if (input == null) return Object.freeze([]);
if (!Array.isArray(input)) throw new Error("evidence must be an array");
if (input.length > 20) throw new Error("evidence contains too many references");
const list = input.map(normalizeEvidence);
const keys = new Set();
for (const item of list) {
const key = `${item.type}\u0000${item.relation}\u0000${item.ref}`;
if (keys.has(key)) throw new Error("evidence contains a duplicate reference");
keys.add(key);
}
return Object.freeze(list);
}
function normalizeProvenance(input, evidence) {
const provenance = plainObject(input, "provenance");
assertKnownKeys(provenance, allowedProvenanceKeys, "provenance");
const sourceType = nonEmpty(provenance.sourceType, "provenance.sourceType", 40).toLowerCase();
if (!SOURCE_SET.has(sourceType)) throw new Error(`unsupported provenance.sourceType: ${sourceType}`);
const normalized = Object.freeze({
sourceType,
sourceId: opaqueId(provenance.sourceId, "provenance.sourceId"),
sourceEventId: optionalOpaqueId(provenance.sourceEventId, "provenance.sourceEventId"),
observedAt: isoTimestamp(provenance.observedAt, "provenance.observedAt"),
});
if (!normalized.sourceEventId && evidence.length === 0) throw new Error("provenance requires sourceEventId or typed evidence");
return normalized;
}
function hasEvidence(evidence, relation, type = null) {
return evidence.some((item) => item.relation === relation && (type == null || item.type === type));
}
function normalizeControl(input, evidence) {
if (input == null) return null;
const control = plainObject(input, "control");
assertKnownKeys(control, allowedControlKeys, "control");
const type = nonEmpty(control.type, "control.type", 40).toLowerCase();
if (!CONTROL_TYPE_SET.has(type)) throw new Error(`unsupported control.type: ${type}`);
if (control.acceptanceAmbiguous != null && typeof control.acceptanceAmbiguous !== "boolean") {
throw new Error("control.acceptanceAmbiguous must be boolean");
}
const normalized = Object.freeze({
type,
requestId: opaqueId(control.requestId, "control.requestId"),
acceptedAt: isoTimestamp(control.acceptedAt, "control.acceptedAt"),
acceptanceAmbiguous: control.acceptanceAmbiguous === true,
});
if (!hasEvidence(evidence, "accepted_control", "user_control")) {
throw new Error("accepted control requires user_control evidence");
}
if (normalized.acceptanceAmbiguous && !hasEvidence(evidence, "readback")) {
throw new Error("ambiguous control acceptance requires readback evidence");
}
return normalized;
}
function normalizeTransition(input, state, evidence) {
if (state !== "retrying" && state !== "fallback") {
if (input != null) throw new Error("transition is only valid for retrying or fallback events");
return null;
}
const transition = plainObject(input, "transition");
assertKnownKeys(transition, allowedTransitionKeys, "transition");
if (typeof transition.consequential !== "boolean") throw new Error("transition.consequential must be boolean");
if (transition.effectAmbiguous != null && typeof transition.effectAmbiguous !== "boolean") {
throw new Error("transition.effectAmbiguous must be boolean");
}
const normalized = Object.freeze({
priorAttemptId: opaqueId(transition.priorAttemptId, "transition.priorAttemptId"),
priorAuthorityScopeRef: publicText(transition.priorAuthorityScopeRef, "transition.priorAuthorityScopeRef", 300),
authorityScopeRef: publicText(transition.authorityScopeRef, "transition.authorityScopeRef", 300),
consequential: transition.consequential,
priorIdempotencyKey: optionalOpaqueId(transition.priorIdempotencyKey, "transition.priorIdempotencyKey"),
idempotencyKey: optionalOpaqueId(transition.idempotencyKey, "transition.idempotencyKey"),
effectAmbiguous: transition.effectAmbiguous === true,
});
if (normalized.authorityScopeRef !== normalized.priorAuthorityScopeRef) {
throw new Error("retry or fallback authority scope may not expand");
}
if (state === "retrying" && !hasEvidence(evidence, "prior_attempt")) {
throw new Error("retrying requires prior attempt evidence");
}
if (state === "fallback" && !hasEvidence(evidence, "prior_attempt") && !hasEvidence(evidence, "capability")) {
throw new Error("fallback requires prior attempt or capability evidence");
}
if (normalized.consequential && (!normalized.idempotencyKey || !normalized.priorIdempotencyKey)) {
throw new Error("consequential retry or fallback requires current and prior idempotency identity");
}
if (normalized.consequential && normalized.idempotencyKey !== normalized.priorIdempotencyKey) {
throw new Error("consequential retry must reuse idempotency identity");
}
if (normalized.effectAmbiguous && !hasEvidence(evidence, "readback")) {
throw new Error("ambiguous retry or fallback requires readback evidence");
}
return normalized;
}
function normalizeBlocker(input, state) {
if (state !== "needs_you") {
if (input != null) throw new Error("blocker is only valid for needs_you events");
return null;
}
const blocker = plainObject(input, "blocker");
assertKnownKeys(blocker, allowedBlockerKeys, "blocker");
if (typeof blocker.approvalRequired !== "boolean") throw new Error("blocker.approvalRequired must be boolean");
const reasonCode = nonEmpty(blocker.reasonCode, "blocker.reasonCode", 100).toLowerCase();
if (!NEEDS_YOU_REASON_SET.has(reasonCode)) throw new Error(`unsupported blocker.reasonCode: ${reasonCode}`);
return Object.freeze({
reasonCode,
reason: publicText(blocker.reason, "blocker.reason", 500),
requiredAction: publicText(blocker.requiredAction, "blocker.requiredAction", 500),
approvalRequired: blocker.approvalRequired,
policyRef: optionalText(blocker.policyRef, "blocker.policyRef", 300),
});
}
function normalizeOutcome(input, state, evidence) {
if (state !== "result") {
if (input != null) throw new Error("outcome is only valid for result events");
return null;
}
const outcome = plainObject(input, "outcome");
assertKnownKeys(outcome, allowedOutcomeKeys, "outcome");
if (!hasEvidence(evidence, "verification", "verification_receipt")) {
throw new Error("result requires overall-job verification evidence");
}
if (outcome.physicalDevice != null && typeof outcome.physicalDevice !== "boolean") {
throw new Error("outcome.physicalDevice must be boolean");
}
if (outcome.physicalDevice === true && !hasEvidence(evidence, "verification", "device_event")) {
throw new Error("physical-device result requires physical device verification evidence");
}
return Object.freeze({
summary: publicText(outcome.summary, "outcome.summary", 1000),
physicalDevice: outcome.physicalDevice === true,
});
}
function assertStateEvidence(state, control, evidence) {
if (state === "failed" && !hasEvidence(evidence, "failure")) throw new Error("failed requires failure evidence");
if (state === "paused") {
const acceptedPause = control?.type === "pause" && hasEvidence(evidence, "accepted_control", "user_control");
const authoritativePause = evidence.some((item) => item.relation === "authoritative_pause" && (item.type === "runtime_event" || item.type === "device_event"));
if (!acceptedPause && !authoritativePause) {
throw new Error("paused requires accepted pause control or authoritative runtime evidence");
}
}
if (state === "resuming" && control?.type !== "resume") throw new Error("resuming requires an accepted resume control");
if (state === "cancelled") {
const acceptedCancel = control?.type === "cancel" && hasEvidence(evidence, "accepted_control", "user_control");
const authoritativeCancellation = evidence.some((item) => item.relation === "authoritative_cancellation" && ["runtime_event", "device_event", "provider_receipt"].includes(item.type));
if (!acceptedCancel && !authoritativeCancellation) {
throw new Error("cancelled requires accepted cancel control or authoritative cancellation evidence");
}
}
if (control?.type === "pause" && state !== "paused") throw new Error("accepted pause control must emit paused state");
if (control?.type === "resume" && state !== "resuming") throw new Error("accepted resume control must emit resuming state");
if (control?.type === "cancel" && state !== "cancelled") throw new Error("accepted cancel control must emit cancelled state");
}
function normalizeActivityEvent(input) {
const event = plainObject(input, "event");
assertKnownKeys(event, allowedTopLevelKeys, "event");
if (event.schemaVersion !== ACTIVITY_EVENT_SCHEMA_VERSION) throw new Error(`unsupported activity event schemaVersion: ${event.schemaVersion}`);
const sequence = positiveSafeInteger(event.sequence, "sequence");
const writerEpoch = positiveSafeInteger(event.writerEpoch, "writerEpoch");
const state = nonEmpty(event.state, "state", 40).toLowerCase();
if (!STATE_SET.has(state)) throw new Error(`unsupported activity state: ${state}`);
const occurredAt = isoTimestamp(event.occurredAt, "occurredAt");
const admittedAt = isoTimestamp(event.admittedAt, "admittedAt");
if (Date.parse(admittedAt) < Date.parse(occurredAt)) throw new Error("admittedAt cannot precede occurredAt");
const admissionMode = nonEmpty(event.admissionMode, "admissionMode", 20).toLowerCase();
if (admissionMode !== "online" && admissionMode !== "offline") throw new Error("admissionMode must be online or offline");
const evidence = normalizeEvidenceList(event.evidence);
if (admissionMode === "offline" && !hasEvidence(evidence, "policy", "policy_decision")) {
throw new Error("offline admission requires current-epoch policy evidence");
}
const provenance = normalizeProvenance(event.provenance, evidence);
const control = normalizeControl(event.control, evidence);
const transition = normalizeTransition(event.transition, state, evidence);
const blocker = normalizeBlocker(event.blocker, state);
const outcome = normalizeOutcome(event.outcome, state, evidence);
assertStateEvidence(state, control, evidence);
const normalized = {
schemaVersion: ACTIVITY_EVENT_SCHEMA_VERSION,
eventId: opaqueId(event.eventId, "eventId"),
jobId: opaqueId(event.jobId, "jobId"),
sequence,
writerEpoch,
admittedBy: opaqueId(event.admittedBy, "admittedBy"),
admissionMode,
state,
message: publicText(event.message, "message", 1000),
occurredAt,
admittedAt,
provenance,
evidence,
domain: optionalText(event.domain, "domain", 100),
capability: optionalText(event.capability, "capability", 160),
executionId: optionalOpaqueId(event.executionId, "executionId"),
parentEventId: optionalOpaqueId(event.parentEventId, "parentEventId"),
control,
transition,
blocker,
outcome,
};
return Object.freeze(normalized);
}
function isTerminalActivityState(state) {
return TERMINAL_SET.has(String(state || "").trim().toLowerCase());
}
function validateActivityTimeline(input) {
if (!Array.isArray(input) || input.length === 0) throw new Error("activity timeline must contain at least one event");
const events = input.map(normalizeActivityEvent);
const jobId = events[0].jobId;
const eventIds = new Set();
const writersByEpoch = new Map();
let lastSequence = null;
let lastWriterEpoch = null;
let lastAdmittedBy = null;
let terminalSeen = false;
let paused = false;
for (const event of events) {
if (event.jobId !== jobId) throw new Error("activity timeline cannot mix job identities");
if (eventIds.has(event.eventId)) throw new Error("activity timeline contains duplicate eventId");
if (lastSequence != null && event.sequence !== lastSequence + 1) throw new Error("activity timeline contains a sequence gap or duplicate");
if (lastWriterEpoch != null && event.writerEpoch < lastWriterEpoch) throw new Error("writerEpoch cannot move backwards");
const knownWriter = writersByEpoch.get(event.writerEpoch);
if (knownWriter && knownWriter !== event.admittedBy) throw new Error("single writer per job epoch violated");
writersByEpoch.set(event.writerEpoch, event.admittedBy);
if (lastAdmittedBy != null && event.admittedBy !== lastAdmittedBy && event.writerEpoch <= lastWriterEpoch) {
throw new Error("writer handoff requires epoch advance");
}
if (terminalSeen) throw new Error("activity timeline cannot emit events after a terminal state");
if (event.state === "resuming" && !paused) throw new Error("resuming requires prior paused state");
if (event.state === "paused") paused = true;
if (event.state === "resuming") paused = false;
eventIds.add(event.eventId);
lastSequence = event.sequence;
lastWriterEpoch = event.writerEpoch;
lastAdmittedBy = event.admittedBy;
terminalSeen = isTerminalActivityState(event.state);
}
return Object.freeze(events);
}
function validateActivityReplay(input, options = {}) {
const events = validateActivityTimeline(input);
const afterSequence = options.afterSequence == null ? 0 : options.afterSequence;
if (!Number.isSafeInteger(afterSequence) || afterSequence < 0) throw new Error("afterSequence must be a non-negative safe integer");
if (events[0].sequence !== afterSequence + 1) throw new Error("activity replay does not continue from the known cursor");
if (options.expectedJobId != null && events[0].jobId !== opaqueId(options.expectedJobId, "expectedJobId")) {
throw new Error("activity replay job identity mismatch");
}
return events;
}
function activityReplayCheckpoint(input) {
const events = validateActivityTimeline(input);
const last = events[events.length - 1];
return Object.freeze({ jobId: last.jobId, sequence: last.sequence, eventId: last.eventId, writerEpoch: last.writerEpoch });
}
module.exports = {
ACTIVITY_CONTROL_TYPES,
ACTIVITY_EVIDENCE_TYPES,
ACTIVITY_EVENT_SCHEMA_VERSION,
ACTIVITY_EVENT_SOURCE_TYPES,
ACTIVITY_EVENT_STATES,
EVIDENCE_RELATIONS,
NEEDS_YOU_REASON_CODES,
TERMINAL_ACTIVITY_STATES,
activityReplayCheckpoint,
isTerminalActivityState,
normalizeActivityEvent,
validateActivityReplay,
validateActivityTimeline,
};
