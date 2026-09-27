"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SCHEMA_VERSION,
  CLAIM_KINDS,
  GrowthLearningSchemaError,
  validateGrowthLearning,
  projectGrowthLearningCandidate,
} = require("../src/pandora-growth-learning-schema.js");

const scope = Object.freeze({
  organization_id: "2270b266-59da-4c39-bfd9-9f8d08352af0",
  project_id: "ee282126-3f61-4058-8c92-2fedbfcecf1f",
});

function base(kind) {
  return {
    schema_version: SCHEMA_VERSION,
    learning_id: "fb025-learning-001",
    ...scope,
    subject_key: "facebook-growth",
    claim_kind: kind,
    statement: "A bounded growth learning claim.",
    observed_at: "2026-09-27T04:00:00.000Z",
    validity: {
      effective_at: "2026-09-27T04:00:00.000Z",
      review_due_at: "2026-10-27T04:00:00.000Z",
      expires_at: null,
    },
    confidence: 0.9,
    confidence_basis: "Provider and verification evidence agree.",
    authority: { kind: "provider_readback", ref: "meta:readback:001" },
    provenance: {
      source_type: "provider",
      source_locator: "meta:graph:v26",
      source_sha: null,
      observed_at: "2026-09-27T04:00:00.000Z",
    },
    evidence_refs: [{ type: "provider", ref: "meta:receipt:001" }],
    supersession: null,
  };
}

test("FB-025 enumerates all required epistemic claim kinds", () => {
  assert.deepEqual(CLAIM_KINDS, [
    "verified_fact",
    "user_decision",
    "provider_evidence",
    "inference",
    "assumption",
    "superseded",
  ]);
});

test("verified facts require evidence and trusted tenant scope", () => {
  const value = base("verified_fact");
  value.authority = { kind: "independent_verification", ref: "verification:001" };
  value.provenance.source_type = "verification";
  const normalized = validateGrowthLearning(value, scope);
  assert.equal(normalized.claim_kind, "verified_fact");
  assert.equal(normalized.organization_id, scope.organization_id);
  assert.throws(
    () => validateGrowthLearning({ ...value, evidence_refs: [] }, scope),
    (error) => error instanceof GrowthLearningSchemaError && error.code === "evidence_required",
  );
  assert.throws(
    () => validateGrowthLearning({ ...value, organization_id: "11111111-1111-4111-8111-111111111111" }, scope),
    (error) => error.code === "scope_mismatch",
  );
});

test("user decisions require owner/user authority and owner/document provenance", () => {
  const value = base("user_decision");
  value.authority = { kind: "owner_decision", ref: "owner-chat:2026-09-27:decision-1" };
  value.provenance.source_type = "owner";
  value.provenance.source_locator = "owner-chat:2026-09-27";
  value.evidence_refs = [];
  assert.equal(validateGrowthLearning(value, scope).authority.kind, "owner_decision");
  value.provenance.source_type = "provider";
  assert.throws(() => validateGrowthLearning(value, scope), /decision_provenance_invalid/);
});

test("provider evidence requires provider provenance", () => {
  const value = base("provider_evidence");
  assert.equal(validateGrowthLearning(value, scope).provenance.source_type, "provider");
  value.provenance.source_type = "repository";
  assert.throws(() => validateGrowthLearning(value, scope), /provider_provenance_required/);
});

test("inference remains explicitly model-derived and reviewable", () => {
  const value = base("inference");
  value.authority = { kind: "model_inference", ref: "router:run:001" };
  value.provenance.source_type = "model";
  value.provenance.source_locator = "router:run:001";
  value.evidence_refs = [{ type: "verification", ref: "ops:verification:001" }];
  const normalized = validateGrowthLearning(value, scope);
  assert.equal(normalized.claim_kind, "inference");
  assert.equal(normalized.authority.kind, "model_inference");
});

test("assumptions cannot masquerade as high-confidence evidence", () => {
  const value = base("assumption");
  value.authority = { kind: "assumption", ref: "planning:assumption:001" };
  value.provenance.source_type = "model";
  value.provenance.source_locator = "planning:assumption:001";
  value.confidence = 0.4;
  value.confidence_basis = "Unverified planning assumption.";
  value.evidence_refs = [];
  assert.equal(validateGrowthLearning(value, scope).confidence, 0.4);
  value.confidence = 0.9;
  assert.throws(() => validateGrowthLearning(value, scope), /assumption_confidence_too_high/);
});

test("superseded claims require an explicit replacement lineage", () => {
  const value = base("superseded");
  value.authority = { kind: "supersession", ref: "review:retcon:001" };
  value.provenance.source_type = "verification";
  value.provenance.source_locator = "review:retcon:001";
  value.supersession = { supersedes_ref: "memory:item:old", reason: "New provider evidence replaced the old claim." };
  const normalized = validateGrowthLearning(value, scope);
  assert.equal(normalized.supersession.supersedes_ref, "memory:item:old");
  value.supersession = null;
  assert.throws(() => validateGrowthLearning(value, scope), /supersession_required/);
});

test("candidate projection is always review-gated and never canonical", () => {
  const value = base("verified_fact");
  value.authority = { kind: "authoritative_record", ref: "billing:receipt:001" };
  value.provenance.source_type = "document";
  const candidate = projectGrowthLearningCandidate(value, scope);
  assert.equal(candidate.review_required, true);
  assert.equal(candidate.canonical_memory_written, false);
  assert.match(candidate.content_hash, /^[0-9a-f]{64}$/);
  assert.equal(candidate.project_id, scope.project_id);
  assert.equal(Object.isFrozen(candidate), true);
});

test("secret-shaped keys are rejected before projection", () => {
  const value = base("verified_fact");
  value.authority = { kind: "authoritative_record", ref: "record:001" };
  value.provenance.source_type = "document";
  value.evidence_refs = [{ type: "document", ref: "evidence:001", token: "should-never-be-accepted" }];
  assert.throws(() => validateGrowthLearning(value, scope), /sensitive_key_rejected/);
});

test("confidence accepts finite numbers only without coercing nonnumeric claims", () => {
  for (const confidence of [0, 0.5, 1]) {
    const value = base("provider_evidence");
    value.confidence = confidence;
    assert.equal(validateGrowthLearning(value, scope).confidence, confidence);
  }
  for (const confidence of [null, false, true, "", "0.9", [], [0.9], {}, NaN, Infinity, -Infinity, -0.1, 1.1]) {
    const value = base("provider_evidence");
    value.confidence = confidence;
    assert.throws(
      () => validateGrowthLearning(value, scope),
      (error) => error instanceof GrowthLearningSchemaError && error.code === "confidence_invalid",
    );
  }
  const missing = base("provider_evidence");
  delete missing.confidence;
  assert.throws(() => validateGrowthLearning(missing, scope), /learning_shape_invalid/);
});
