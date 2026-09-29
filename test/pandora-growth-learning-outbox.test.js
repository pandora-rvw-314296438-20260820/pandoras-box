"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  LEARNING_KIND,
  MEMORY_PROJECT_ID,
  MEMORY_PROJECT_KEY,
  MEMORY_NAMESPACE,
  MEMORY_PRINCIPAL_KEY,
  RUNTIME_HOLD_REASON,
  GrowthLearningOutboxError,
  projectGrowthLearningOutbox,
  validateGrowthLearningIntakeAcceptance,
} = require("../src/pandora-growth-learning-outbox.js");

const scope = Object.freeze({
  organization_id: "2270b266-59da-4c39-bfd9-9f8d08352af0",
  project_id: "ee282126-3f61-4058-8c92-2fedbfcecf1f",
});

function learning(kind) {
  const value = {
    schema_version: "growth-learning-v1",
    learning_id: `fb026-${kind}-001`,
    ...scope,
    subject_key: "facebook-growth",
    claim_kind: kind,
    statement: `A bounded ${kind} growth learning.`,
    observed_at: "2026-09-29T00:00:00.000Z",
    validity: {
      effective_at: "2026-09-29T00:00:00.000Z",
      review_due_at: "2026-10-29T00:00:00.000Z",
      expires_at: "2026-11-29T00:00:00.000Z",
    },
    confidence: 0.9,
    confidence_basis: "Bounded source evidence.",
    authority: { kind: "provider_readback", ref: "meta:readback:001" },
    provenance: {
      source_type: "provider",
      source_locator: "meta:graph:v26",
      source_sha: null,
      observed_at: "2026-09-29T00:00:00.000Z",
    },
    evidence_refs: [{ type: "provider", ref: "meta:receipt:001" }],
    supersession: null,
  };

  if (kind === "verified_fact") {
    value.authority = { kind: "independent_verification", ref: "verification:001" };
    value.provenance.source_type = "verification";
  } else if (kind === "user_decision") {
    value.authority = { kind: "owner_decision", ref: "owner:decision:001" };
    value.provenance.source_type = "owner";
    value.evidence_refs = [];
  } else if (kind === "inference") {
    value.authority = { kind: "model_inference", ref: "model:run:001" };
    value.provenance.source_type = "model";
  } else if (kind === "assumption") {
    value.authority = { kind: "assumption", ref: "planning:001" };
    value.provenance.source_type = "model";
    value.confidence = 0.4;
    value.evidence_refs = [];
  } else if (kind === "superseded") {
    value.authority = { kind: "supersession", ref: "review:001" };
    value.provenance.source_type = "verification";
    value.supersession = {
      supersedes_ref: "memory:item:old",
      reason: "New provider evidence replaced the old claim.",
    };
  }
  return value;
}

function accepted(projected, overrides = {}) {
  const candidate = projected.outbox.payload.growth_learning.candidate;
  return {
    ok: true,
    status: "pending_review",
    source_event_id: projected.outbox.payload.source_event_id,
    learning_id: candidate.source_event_id,
    content_hash: candidate.content_hash,
    candidate_id: "11111111-1111-4111-8111-111111111111",
    review_item_id: "22222222-2222-4222-8222-222222222222",
    review_required: true,
    canonical_memory_written: false,
    promotion_status: "not_promoted",
    retrieval_status: "not_retrievable",
    deduplicated: false,
    ...overrides,
  };
}

test("all six epistemic classes remain distinct and lossless in the signed binding", () => {
  const kinds = [
    "verified_fact", "user_decision", "provider_evidence",
    "inference", "assumption", "superseded",
  ];
  for (const kind of kinds) {
    const input = learning(kind);
    const projected = projectGrowthLearningOutbox(input, scope);
    const candidate = projected.outbox.payload.growth_learning.candidate;
    assert.equal(candidate.claim_kind, kind);
    assert.equal(candidate.claim, input.statement);
    assert.equal(candidate.effective_at, input.validity.effective_at);
    assert.equal(candidate.review_due_at, input.validity.review_due_at);
    assert.equal(candidate.expires_at, input.validity.expires_at);
    assert.equal(candidate.authority_kind, input.authority.kind);
    assert.deepEqual(candidate.provenance, input.provenance);
    assert.deepEqual(candidate.evidence_refs, input.evidence_refs);
    assert.deepEqual(candidate.supersession, input.supersession);
    assert.equal(projected.outbox.payload.learning_kind, LEARNING_KIND);
  }
});

test("trusted source scope and fixed Memory target cannot be caller-selected", () => {
  const projected = projectGrowthLearningOutbox(learning("provider_evidence"), scope);
  const binding = projected.outbox.payload.growth_learning;
  assert.deepEqual(binding.source_scope, scope);
  assert.equal(binding.target_memory.project_id, MEMORY_PROJECT_ID);
  assert.equal(binding.target_memory.project_key, MEMORY_PROJECT_KEY);
  assert.equal(binding.target_memory.namespace, MEMORY_NAMESPACE);
  assert.equal(binding.target_memory.principal_key, MEMORY_PRINCIPAL_KEY);
  assert.equal(projected.outbox.organization_id, scope.organization_id);
  assert.equal(projected.outbox.project_id, scope.project_id);
  assert.throws(
    () => projectGrowthLearningOutbox(learning("provider_evidence"), {
      ...scope,
      project_id: "33333333-3333-4333-8333-333333333333",
    }),
    /scope_mismatch/,
  );
});

test("projection is deterministic, immutable, and binds semantic changes", () => {
  const first = projectGrowthLearningOutbox(learning("provider_evidence"), scope);
  const replay = projectGrowthLearningOutbox(learning("provider_evidence"), scope);
  assert.deepEqual(first, replay);
  assert.match(first.outbox.request_id, /^[0-9a-f-]{36}$/);
  assert.match(first.outbox.payload.context_hash, /^[0-9a-f]{64}$/);
  assert.match(first.outbox.payload.result_fingerprint, /^[0-9a-f]{64}$/);
  assert.equal(
    first.outbox.event_key,
    `growth:${scope.organization_id}:${scope.project_id}:fb026-provider_evidence-001:${first.outbox.payload.result_fingerprint}`,
  );
  assert.doesNotMatch(first.outbox.event_key, /undefined/);
  assert.equal(Object.isFrozen(first), true);
  assert.equal(Object.isFrozen(first.outbox.payload.growth_learning.candidate), true);

  const changed = learning("provider_evidence");
  changed.validity.review_due_at = "2026-10-30T00:00:00.000Z";
  const second = projectGrowthLearningOutbox(changed, scope);
  assert.notEqual(first.outbox.payload.context_hash, second.outbox.payload.context_hash);
  assert.notEqual(first.outbox.event_key, second.outbox.event_key);
});

test("source preparation exposes the Pandora-native Memory route without promotion authority", () => {
  const projected = projectGrowthLearningOutbox(learning("verified_fact"), scope);
  assert.deepEqual(projected.lifecycle, {
    delivery: "pending",
    review: "not_received",
    promotion: "not_promoted",
    retrieval: "not_retrievable",
    canonical_memory_written: false,
  });
  assert.equal(projected.runtime_gate.state, "ready");
  assert.equal(projected.runtime_gate.reason, RUNTIME_HOLD_REASON);
  assert.equal(projected.outbox.delivery_status, "pending");
});

test("delivery acceptance requires exact candidate and review bindings", () => {
  const projected = projectGrowthLearningOutbox(learning("verified_fact"), scope);
  const result = validateGrowthLearningIntakeAcceptance(
    projected.outbox.payload, accepted(projected),
  );
  assert.equal(result.delivered, true);
  assert.equal(result.review_status, "pending_review");
  assert.equal(result.promotion_status, "not_promoted");
  assert.equal(result.retrieval_status, "not_retrievable");
  assert.equal(result.canonical_memory_written, false);

  for (const patch of [
    { status: "accepted" },
    { source_event_id: "33333333-3333-4333-8333-333333333333" },
    { content_hash: "0".repeat(64) },
    { review_required: false },
    { canonical_memory_written: true },
    { promotion_status: "promoted" },
    { retrieval_status: "retrievable" },
    { candidate_id: null },
    { review_item_id: null },
  ]) {
    assert.throws(
      () => validateGrowthLearningIntakeAcceptance(
        projected.outbox.payload, accepted(projected, patch),
      ),
      (error) => error instanceof GrowthLearningOutboxError,
    );
  }
});

test("already-reviewed terminal receipts require HTTP 200 and exact review status", () => {
  const projected = projectGrowthLearningOutbox(learning("verified_fact"), scope);
  const candidate = projected.outbox.payload.growth_learning.candidate;
  const statuses = [
    "needs_clarification", "blocked_namespace_mismatch", "blocked_sensitive",
    "blocked_policy", "approved_for_append", "rejected", "archived",
  ];
  for (const reviewStatus of statuses) {
    const response = {
      ok: true,
      status: "already_reviewed",
      source_event_id: projected.outbox.payload.source_event_id,
      learning_id: candidate.source_event_id,
      content_hash: candidate.content_hash,
      candidate_id: "11111111-1111-4111-8111-111111111111",
      review_item_id: "22222222-2222-4222-8222-222222222222",
      review_status: reviewStatus,
      deduplicated: true,
    };
    const result = validateGrowthLearningIntakeAcceptance(
      projected.outbox.payload, response, 200,
    );
    assert.equal(result.delivered, true);
    assert.equal(result.review_status, reviewStatus);
    assert.equal(result.canonical_memory_written, false);
    assert.throws(
      () => validateGrowthLearningIntakeAcceptance(
        projected.outbox.payload, response, 202,
      ),
      (error) => error instanceof GrowthLearningOutboxError,
    );
  }
  const bad = {
    ok: true,
    status: "already_reviewed",
    source_event_id: projected.outbox.payload.source_event_id,
    learning_id: candidate.source_event_id,
    content_hash: candidate.content_hash,
    candidate_id: "11111111-1111-4111-8111-111111111111",
    review_item_id: "22222222-2222-4222-8222-222222222222",
    review_status: "pending_review",
    deduplicated: true,
  };
  assert.throws(
    () => validateGrowthLearningIntakeAcceptance(
      projected.outbox.payload, bad, 200,
    ),
    (error) => error instanceof GrowthLearningOutboxError,
  );
});

test("delivery acceptance recomputes every signed binding and fixed scope", () => {
  const projected = projectGrowthLearningOutbox(learning("verified_fact"), scope);
  assert.equal(
    accepted(projected).learning_id,
    projected.outbox.payload.growth_learning.candidate.source_event_id,
  );

  const tampered = [
    (payload) => { payload.growth_learning.candidate.claim = "Tampered claim."; },
    (payload) => { payload.context_hash = "0".repeat(64); },
    (payload) => { payload.result_fingerprint = "0".repeat(64); },
    (payload) => {
      payload.growth_learning.target_memory.project_id =
        "33333333-3333-4333-8333-333333333333";
    },
    (payload) => {
      payload.growth_learning.source_scope.project_id =
        "33333333-3333-4333-8333-333333333333";
    },
    (payload) => {
      payload.source_request_id = "33333333-3333-4333-8333-333333333333";
    },
  ];
  for (const mutate of tampered) {
    const payload = structuredClone(projected.outbox.payload);
    mutate(payload);
    assert.throws(
      () => validateGrowthLearningIntakeAcceptance(payload, accepted(projected)),
      (error) => error instanceof GrowthLearningOutboxError,
    );
  }
});

test("a generic HTTP success is never accepted as growth-learning delivery", () => {
  const projected = projectGrowthLearningOutbox(learning("verified_fact"), scope);
  assert.throws(
    () => validateGrowthLearningIntakeAcceptance(
      projected.outbox.payload,
      { ok: true, status: "accepted_for_review" },
    ),
    /intake_response_shape_invalid/,
  );
});
