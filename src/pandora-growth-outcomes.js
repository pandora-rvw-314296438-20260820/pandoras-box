"use strict";

// FB-003: proposed, side-effect-free acquisition contract. NOT a runtime ingest API.
// The caller must authenticate, resolve scope, and verify evidence in trusted code.
// Passing schema validation does not prove a payment, an attribution, or consent.
const { createHash } = require("node:crypto");
const SCHEMA_VERSION = 1;
const CONTRACT_STATUS = "proposed_owner_review";
const PATHS = Object.freeze(["self_serve", "enterprise"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OPAQUE_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const PROVIDER_ID = /^[1-9][0-9]{0,63}$/;
const CLICK_ID = /^pdc_[0-9a-f]{32}$/;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

function freeze(value) {
  if (value && typeof value === "object") {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
}

// These are semantic outcomes, not delivery attempts. required_evidence contains
// opaque references only. Evidence lookup and authority are integration gates.
const DEFINITIONS = freeze({
  landing_view: { paths: PATHS, authority: "capture", subject_required: false, required_evidence: ["capture_ref"], money: false },
  signup_completed: { paths: ["self_serve"], authority: "server", subject_required: true, required_evidence: ["account_ref"], money: false },
  project_created: { paths: ["self_serve"], authority: "server", subject_required: true, required_evidence: ["project_ref"], money: false },
  preview_ready: { paths: ["self_serve"], authority: "server", subject_required: true, required_evidence: ["preview_ref", "verification_ref"], money: false },
  publish_verified: { paths: ["self_serve"], authority: "server", subject_required: true, required_evidence: ["deployment_ref", "verification_ref"], money: false },
  lead_submitted: { paths: ["enterprise"], authority: "server", subject_required: true, required_evidence: ["lead_ref"], money: false },
  lead_qualified: { paths: ["enterprise"], authority: "server", subject_required: true, required_evidence: ["lead_ref", "qualification_ref", "qualification_policy_ref"], money: false },
  demo_completed: { paths: ["enterprise"], authority: "server", subject_required: true, required_evidence: ["meeting_ref", "completion_ref"], money: false },
  proposal_sent: { paths: ["enterprise"], authority: "server", subject_required: true, required_evidence: ["proposal_ref", "delivery_ref"], money: false },
  contract_signed: { paths: ["enterprise"], authority: "server", subject_required: true, required_evidence: ["contract_ref", "signature_ref"], money: false },
  paid_activation: { paths: PATHS, authority: "server", subject_required: true, required_evidence: ["activation_ref", "payment_ref", "entitlement_ref"], money: false },
  payment_settled: { paths: PATHS, authority: "server", subject_required: true, required_evidence: ["payment_ref", "settlement_ref"], money: true },
  refund_settled: { paths: PATHS, authority: "server", subject_required: true, required_evidence: ["refund_ref", "payment_ref", "settlement_ref"], money: true },
  retention_observed: { paths: PATHS, authority: "server", subject_required: true, required_evidence: ["observation_ref", "usage_ref"], money: false },
});

class OutcomeContractError extends Error {
  constructor(code) {
    super(code); // Fixed code only: never echo the input or evidence payload.
    this.name = "OutcomeContractError";
    this.code = code;
  }
}
function fail(code) { throw new OutcomeContractError(code); }
function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}
function keys(value, allowed, required, code) {
  if (!object(value) || Object.keys(value).some((key) => !allowed.includes(key))
      || required.some((key) => !Object.hasOwn(value, key))) fail(code);
}
function id(value, code = "opaque_id_invalid") {
  if (typeof value !== "string" || !OPAQUE_ID.test(value)) fail(code);
  return value;
}
function uuid(value, code) {
  if (typeof value !== "string" || !UUID.test(value)) fail(code);
  return value.toLowerCase();
}
function timestamp(value, code) {
  if (typeof value !== "string" || !TIMESTAMP.test(value)) fail(code);
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString() !== value) fail(code);
  return value;
}
function normalizeScope(scope) {
  const fields = ["organization_id", "tracking_tenant_id", "project_id"];
  keys(scope, fields, fields, "trusted_scope_required");
  return {
    organization_id: uuid(scope.organization_id, "trusted_scope_invalid"),
    tracking_tenant_id: uuid(scope.tracking_tenant_id, "trusted_scope_invalid"),
    project_id: scope.project_id === null ? null : uuid(scope.project_id, "trusted_scope_invalid"),
  };
}

function normalizeAttribution(value) {
  const kinds = ["observed", "platform_reported", "inferred", "unattributed"];
  const fields = ["kind", "evidence_ref", "click_id", "campaign_id", "adset_id", "ad_id", "creative_id", "method"];
  keys(value, fields, ["kind"], "attribution_invalid");
  if (!kinds.includes(value.kind)) fail("attribution_kind_invalid");
  if (value.kind === "unattributed") {
    if (Object.keys(value).length !== 1) fail("unattributed_has_claims");
    return { kind: "unattributed" };
  }
  const result = { kind: value.kind, evidence_ref: id(value.evidence_ref, "attribution_evidence_required") };
  if (Object.hasOwn(value, "click_id")) {
    if (typeof value.click_id !== "string" || !CLICK_ID.test(value.click_id)) fail("click_id_invalid");
    result.click_id = value.click_id;
  }
  for (const key of ["campaign_id", "adset_id", "ad_id", "creative_id"]) {
    if (Object.hasOwn(value, key)) {
      if (typeof value[key] !== "string" || !PROVIDER_ID.test(value[key])) fail("provider_id_invalid");
      result[key] = value[key]; // Keep IDs as strings; never lose integer precision.
    }
  }
  if (value.kind === "observed" && !result.click_id) fail("observed_click_required");
  if (value.kind !== "observed" && !result.campaign_id) fail("attribution_campaign_required");
  if ((result.adset_id || result.ad_id || result.creative_id) && !result.campaign_id) fail("attribution_hierarchy_incomplete");
  if (result.ad_id && !result.adset_id) fail("attribution_hierarchy_incomplete");
  if (result.creative_id && !result.ad_id) fail("attribution_hierarchy_incomplete");
  if (value.kind === "inferred") result.method = id(value.method, "inference_method_required");
  else if (Object.hasOwn(value, "method")) fail("inference_method_not_applicable");
  return result;
}

/** Schema validation only. trustedScope must come from an authenticated adapter,
 * never a request body's tenant choice. No network, storage, billing or ad action.
 */
function validateOutcomeEvent(input, trustedScope) {
  const scope = normalizeScope(trustedScope);
  const required = ["schema_version", "event_name", "event_id", "outcome_id", "acquisition_path", "organization_id", "tracking_tenant_id", "project_id", "journey_id", "occurred_at", "delivery_source", "evidence", "attribution"];
  keys(input, [...required, "subject_id", "money", "retention"], required, "event_shape_invalid");
  if (input.schema_version !== SCHEMA_VERSION) fail("schema_version_invalid");
  if (typeof input.event_name !== "string" || !Object.hasOwn(DEFINITIONS, input.event_name)) fail("event_name_invalid");
  const definition = DEFINITIONS[input.event_name];
  if (!definition.paths.includes(input.acquisition_path)) fail("acquisition_path_invalid");
  if (!["browser", "server"].includes(input.delivery_source)) fail("delivery_source_invalid");
  if (definition.authority === "server" && input.delivery_source !== "server") fail("server_evidence_required");
  const suppliedScope = normalizeScope({ organization_id: input.organization_id, tracking_tenant_id: input.tracking_tenant_id, project_id: input.project_id });
  if (Object.keys(scope).some((key) => scope[key] !== suppliedScope[key])) fail("scope_mismatch");
  const result = {
    schema_version: SCHEMA_VERSION, event_name: input.event_name,
    event_id: id(input.event_id), outcome_id: id(input.outcome_id),
    acquisition_path: input.acquisition_path, ...scope,
    journey_id: id(input.journey_id),
    occurred_at: timestamp(input.occurred_at, "occurred_at_invalid"),
    delivery_source: input.delivery_source,
  };
  if (definition.subject_required || Object.hasOwn(input, "subject_id")) result.subject_id = id(input.subject_id, "subject_id_required");
  keys(input.evidence, definition.required_evidence, definition.required_evidence, "evidence_shape_invalid");
  result.evidence = Object.fromEntries(definition.required_evidence.map((key) => [key, id(input.evidence[key], "evidence_ref_invalid")]));
  result.attribution = normalizeAttribution(input.attribution);
  if (definition.money) {
    keys(input.money, ["amount_minor", "currency"], ["amount_minor", "currency"], "money_required");
    if (!Number.isSafeInteger(input.money.amount_minor) || input.money.amount_minor <= 0) fail("amount_minor_invalid");
    if (typeof input.money.currency !== "string" || !/^[A-Z]{3}$/.test(input.money.currency)) fail("currency_invalid");
    result.money = { amount_minor: input.money.amount_minor, currency: input.money.currency };
  } else if (Object.hasOwn(input, "money")) fail("non_monetary_event_has_money");
  if (input.event_name === "retention_observed") {
    const fields = ["policy_ref", "cohort_ref", "window_start", "window_end"];
    keys(input.retention, fields, fields, "retention_policy_required");
    const start = timestamp(input.retention.window_start, "retention_window_invalid");
    const end = timestamp(input.retention.window_end, "retention_window_invalid");
    if (start >= end || end > result.occurred_at) fail("retention_window_invalid");
    result.retention = { policy_ref: id(input.retention.policy_ref), cohort_ref: id(input.retention.cohort_ref), window_start: start, window_end: end };
  } else if (Object.hasOwn(input, "retention")) fail("retention_not_applicable");
  return freeze(result);
}

function hash(parts) { return createHash("sha256").update(JSON.stringify(parts)).digest("hex"); }
function semanticKey(event) { return hash([event.organization_id, event.tracking_tenant_id, event.event_name, event.outcome_id]); }
function deliveryKey(event) { return hash([event.organization_id, event.tracking_tenant_id, event.event_name, event.event_id]); }
function fingerprint(event) {
  // Receipt time is not in the contract; occurrence time and all claims must match.
  // Normalize nested key order first. Only delivery_source can differ on a retry.
  const { delivery_source: ignored, ...claims } = event;
  return hash(claims);
}

/** All-or-nothing, in-memory regression helper, not a durable idempotency store.
 * Stable outcome IDs catch semantic replays; conflicting retries fail, not overwrite.
 */
function deduplicateOutcomeBatch(inputs, trustedScope) {
  if (!Array.isArray(inputs) || inputs.length > 1000) fail("batch_invalid");
  normalizeScope(trustedScope); // Empty batches must not bypass required scope.
  const unique = [], outcomes = new Map(), deliveries = new Map();
  let duplicates = 0;
  for (const input of inputs) {
    const event = validateOutcomeEvent(input, trustedScope);
    const semantic = semanticKey(event), delivery = deliveryKey(event), digest = fingerprint(event);
    if (deliveries.has(delivery) && deliveries.get(delivery) !== semantic) fail("event_id_reused");
    if (outcomes.has(semantic)) {
      if (outcomes.get(semantic) !== digest) fail("duplicate_outcome_conflict");
      duplicates += 1;
    } else {
      outcomes.set(semantic, digest);
      deliveries.set(delivery, semantic);
      unique.push(event);
    }
  }
  return freeze({ unique, duplicates });
}

module.exports = { SCHEMA_VERSION, CONTRACT_STATUS, DEFINITIONS, OutcomeContractError, validateOutcomeEvent, deduplicateOutcomeBatch };
