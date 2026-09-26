"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  CONTRACT_STATUS, DEFINITIONS, OutcomeContractError,
  validateOutcomeEvent, deduplicateOutcomeBatch,
} = require("../src/pandora-growth-outcomes.js");

const SCOPE = Object.freeze({
  organization_id: "11111111-1111-4111-8111-111111111111",
  tracking_tenant_id: "22222222-2222-4222-8222-222222222222",
  project_id: "33333333-3333-4333-8333-333333333333",
});
const OTHER = "44444444-4444-4444-8444-444444444444";
function sample(name = "landing_view") {
  const definition = DEFINITIONS[name];
  const event = {
    schema_version: 1, event_name: name, event_id: "event:1", outcome_id: "outcome:1",
    acquisition_path: definition.paths[0], ...SCOPE, journey_id: "journey:1",
    occurred_at: "2026-09-25T08:00:00.000Z", delivery_source: "server",
    evidence: Object.fromEntries(definition.required_evidence.map((key) => [key, key + ":1"])),
    attribution: { kind: "unattributed" },
  };
  if (definition.subject_required) event.subject_id = "subject:1";
  if (definition.money) event.money = { amount_minor: 12000, currency: "PHP" };
  if (name === "retention_observed") event.retention = {
    policy_ref: "retention-policy:1", cohort_ref: "cohort:1",
    window_start: "2026-09-01T00:00:00.000Z", window_end: "2026-09-24T00:00:00.000Z",
  };
  return event;
}
function rejects(event, code, scope = SCOPE) {
  assert.throws(() => validateOutcomeEvent(event, scope), (error) => error instanceof OutcomeContractError && error.code === code);
}

test("contract is a proposal, with immutable definitions and no activation claim", () => {
  assert.equal(CONTRACT_STATUS, "proposed_owner_review");
  assert.equal(Object.keys(DEFINITIONS).length, 14);
  assert.ok(Object.isFrozen(DEFINITIONS));
  assert.throws(() => DEFINITIONS.paid_activation.required_evidence.push("unverified_ref"), TypeError);
});
for (const name of Object.keys(DEFINITIONS)) {
  test("accepts well-formed " + name + " without claiming evidence authenticity", () => {
    const event = validateOutcomeEvent(sample(name), SCOPE);
    assert.equal(event.event_name, name);
    assert.ok(Object.isFrozen(event));
    assert.ok(Object.isFrozen(event.evidence));
  });
}
for (const field of Object.keys(SCOPE)) {
  test("rejects cross-scope " + field, () => rejects({ ...sample(), [field]: OTHER }, "scope_mismatch"));
}
test("scope must be explicit, not inferred from the event", () => assert.throws(() => validateOutcomeEvent(sample(), undefined), (error) => error.code === "trusted_scope_required"));
test("null project is explicit and must match trusted scope", () => {
  const event = { ...sample(), project_id: null };
  assert.equal(validateOutcomeEvent(event, { ...SCOPE, project_id: null }).project_id, null);
  rejects(event, "scope_mismatch");
});
test("invalid UUIDs and missing scope fields fail closed", () => {
  rejects(sample(), "trusted_scope_invalid", { ...SCOPE, organization_id: "organization:any" });
  rejects(sample(), "trusted_scope_required", { organization_id: SCOPE.organization_id });
});
test("UUID case is canonicalized before scope matching", () => {
  const scope = { ...SCOPE, organization_id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA" };
  const event = { ...sample(), organization_id: scope.organization_id.toLowerCase() };
  assert.equal(validateOutcomeEvent(event, scope).organization_id, event.organization_id);
});
test("does not mutate caller data", () => {
  const event = sample();
  const before = structuredClone(event);
  validateOutcomeEvent(event, SCOPE);
  assert.deepEqual(event, before);
  assert.equal(Object.isFrozen(event), false);
});
for (const [name, path] of [["signup_completed", "enterprise"], ["lead_qualified", "self_serve"], ["landing_view", "unknown"]]) {
  test("rejects path mismatch for " + name, () => rejects({ ...sample(name), acquisition_path: path }, "acquisition_path_invalid"));
}
for (const name of Object.keys(DEFINITIONS).filter((name) => DEFINITIONS[name].authority === "server")) {
  test("browser cannot assert verified business outcome " + name, () => rejects({ ...sample(name), delivery_source: "browser" }, "server_evidence_required"));
}
test("client landing capture remains nonfinancial", () => {
  const event = { ...sample(), delivery_source: "browser" };
  assert.equal(validateOutcomeEvent(event, SCOPE).event_name, "landing_view");
  rejects({ ...event, money: { amount_minor: 500, currency: "PHP" } }, "non_monetary_event_has_money");
});
test("qualified lead requires qualification and policy references", () => {
  const event = sample("lead_qualified");
  delete event.evidence.qualification_policy_ref;
  rejects(event, "evidence_shape_invalid");
});
test("paid activation requires payment and entitlement, not just a signup", () => {
  const event = sample("paid_activation");
  delete event.evidence.entitlement_ref;
  rejects(event, "evidence_shape_invalid");
});
test("paid activation is not a second monetary event", () => rejects({ ...sample("paid_activation"), money: { amount_minor: 12000, currency: "PHP" } }, "non_monetary_event_has_money"));
test("refund requires a link to the original payment", () => {
  const event = sample("refund_settled");
  delete event.evidence.payment_ref;
  rejects(event, "evidence_shape_invalid");
});
test("unknown revenue stays missing instead of becoming zero", () => {
  const event = sample("payment_settled");
  delete event.money;
  rejects(event, "money_required");
});
for (const amount of [0, -1, 1.5, "12000", null, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
  test("rejects invalid minor-unit amount " + String(amount), () => {
    const event = sample("payment_settled");
    event.money.amount_minor = amount;
    rejects(event, "amount_minor_invalid");
  });
}
for (const currency of ["php", "", "US", "PHP ", null, 123]) {
  test("rejects invalid currency representation " + String(currency), () => {
    const event = sample("payment_settled");
    event.money.currency = currency;
    rejects(event, "currency_invalid");
  });
}
test("valid currencies remain separate, no cross-currency aggregation occurs", () => {
  const php = sample("payment_settled"), usd = sample("payment_settled");
  usd.event_id = "event:2"; usd.outcome_id = "outcome:2"; usd.money.currency = "USD";
  const batch = deduplicateOutcomeBatch([php, usd], SCOPE);
  assert.deepEqual(batch.unique.map((event) => event.money.currency), ["PHP", "USD"]);
  assert.equal(Object.hasOwn(batch, "revenue"), false);
});
test("unattributed stays unattributed", () => assert.deepEqual(validateOutcomeEvent(sample(), SCOPE).attribution, { kind: "unattributed" }));
test("unattributed cannot smuggle a campaign ID", () => rejects({ ...sample(), attribution: { kind: "unattributed", campaign_id: "123" } }, "unattributed_has_claims"));
test("observed attribution needs first-party click evidence", () => {
  rejects({ ...sample(), attribution: { kind: "observed", evidence_ref: "evidence:1", campaign_id: "123" } }, "observed_click_required");
  const attribution = { kind: "observed", evidence_ref: "evidence:1", click_id: "pdc_" + "a".repeat(32), campaign_id: "90071992547409930000" };
  assert.deepEqual(validateOutcomeEvent({ ...sample(), attribution }, SCOPE).attribution, attribution);
});
test("platform reporting is not relabelled as observed", () => {
  const attribution = { kind: "platform_reported", evidence_ref: "report:1", campaign_id: "123" };
  assert.equal(validateOutcomeEvent({ ...sample(), attribution }, SCOPE).attribution.kind, "platform_reported");
});
test("inference remains inference and requires a method", () => {
  const attribution = { kind: "inferred", evidence_ref: "evidence:1", campaign_id: "123" };
  rejects({ ...sample(), attribution }, "inference_method_required");
  assert.equal(validateOutcomeEvent({ ...sample(), attribution: { ...attribution, method: "assisted-model:v1" } }, SCOPE).attribution.kind, "inferred");
});
test("provider IDs cannot be rounded JavaScript numbers", () => rejects({ ...sample(), attribution: { kind: "platform_reported", evidence_ref: "report:1", campaign_id: 123 } }, "provider_id_invalid"));
test("ad IDs require ad-set context", () => rejects({ ...sample(), attribution: { kind: "platform_reported", evidence_ref: "report:1", campaign_id: "123", ad_id: "456" } }, "attribution_hierarchy_incomplete"));
test("creative IDs require ad and campaign context", () => rejects({ ...sample(), attribution: { kind: "platform_reported", evidence_ref: "report:1", campaign_id: "123", creative_id: "456" } }, "attribution_hierarchy_incomplete"));
test("retention has no invented default observation window", () => {
  const event = sample("retention_observed"); delete event.retention;
  rejects(event, "retention_policy_required");
});
test("incomplete retention windows cannot be reported as completed", () => {
  const event = sample("retention_observed"); event.retention.window_end = "2026-10-01T00:00:00.000Z";
  rejects(event, "retention_window_invalid");
});
test("inverted retention window is invalid", () => {
  const event = sample("retention_observed"); event.retention.window_end = event.retention.window_start;
  rejects(event, "retention_window_invalid");
});
for (const occurred_at of ["2026-02-30T00:00:00.000Z", "2026-09-25", "2026-09-25T16:00:00+08:00", "not-a-date", null]) {
  test("rejects ambiguous or invalid occurrence time " + String(occurred_at), () => rejects({ ...sample(), occurred_at }, "occurred_at_invalid"));
}
for (const extra of ["access_token", "email", "phone", "metadata", "user_data", "raw_payload"]) {
  test("rejects undeclared potentially sensitive field " + extra, () => rejects({ ...sample(), [extra]: "SENSITIVE_TEST_SENTINEL" }, "event_shape_invalid"));
}
test("rejected values do not enter error messages", () => {
  const event = sample(); event.evidence.capture_ref = "SENSITIVE_TEST_SENTINEL@example.invalid";
  assert.throws(() => validateOutcomeEvent(event, SCOPE), (error) => error.code === "evidence_ref_invalid" && !error.message.includes("SENSITIVE_TEST_SENTINEL"));
});
test("rejects prototype pollution shaped JSON", () => rejects(JSON.parse(JSON.stringify(sample()).replace('{', '{"__proto__":{},')), "event_shape_invalid"));
test("rejects inherited or unknown event definitions", () => rejects({ ...sample(), event_name: "__proto__" }, "event_name_invalid"));
test("rejects schema drift", () => rejects({ ...sample(), schema_version: 2 }, "schema_version_invalid"));
test("duplicate server deliveries count once", () => {
  const event = sample("payment_settled");
  const result = deduplicateOutcomeBatch([event, structuredClone(event)], SCOPE);
  assert.equal(result.unique.length, 1); assert.equal(result.duplicates, 1);
});
test("browser/server copies of the same landing event count once", () => {
  const event = sample();
  const result = deduplicateOutcomeBatch([{ ...event, delivery_source: "browser" }, event], SCOPE);
  assert.equal(result.unique.length, 1); assert.equal(result.duplicates, 1);
});
test("nested JSON key ordering cannot defeat deduplication", () => {
  const event = sample("payment_settled"), reordered = structuredClone(event);
  reordered.evidence = { settlement_ref: event.evidence.settlement_ref, payment_ref: event.evidence.payment_ref };
  reordered.money = { currency: "PHP", amount_minor: 12000 };
  assert.equal(deduplicateOutcomeBatch([event, reordered], SCOPE).duplicates, 1);
});
for (const field of ["amount", "currency", "subject", "event_id", "journey", "attribution"]) {
  test("conflicting duplicate " + field + " fails instead of overwriting", () => {
    const event = sample("payment_settled"), changed = structuredClone(event);
    if (field === "amount") changed.money.amount_minor = 1;
    if (field === "currency") changed.money.currency = "USD";
    if (field === "subject") changed.subject_id = "subject:2";
    if (field === "event_id") changed.event_id = "event:2";
    if (field === "journey") changed.journey_id = "journey:2";
    if (field === "attribution") changed.attribution = { kind: "platform_reported", evidence_ref: "report:1", campaign_id: "123" };
    assert.throws(() => deduplicateOutcomeBatch([event, changed], SCOPE), (error) => error.code === "duplicate_outcome_conflict");
  });
}
test("reused delivery ID cannot identify a different outcome", () => {
  const event = sample();
  assert.throws(() => deduplicateOutcomeBatch([event, { ...event, outcome_id: "outcome:2" }], SCOPE), (error) => error.code === "event_id_reused");
});
test("different outcomes are not collapsed", () => {
  const a = sample(), b = { ...sample(), event_id: "event:2", outcome_id: "outcome:2" };
  assert.equal(deduplicateOutcomeBatch([a, b], SCOPE).unique.length, 2);
});
test("cross-tenant batch rejects rather than returns a partial success", () => {
  assert.throws(() => deduplicateOutcomeBatch([sample(), { ...sample(), tracking_tenant_id: OTHER }], SCOPE), (error) => error.code === "scope_mismatch");
});
test("empty batch still needs trusted scope", () => assert.throws(() => deduplicateOutcomeBatch([], null), (error) => error.code === "trusted_scope_required"));
test("batch is bounded", () => assert.throws(() => deduplicateOutcomeBatch(Array(1001).fill(sample()), SCOPE), (error) => error.code === "batch_invalid"));
