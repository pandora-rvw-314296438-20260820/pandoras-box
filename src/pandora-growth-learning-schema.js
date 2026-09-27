"use strict";

const { createHash } = require("node:crypto");

const SCHEMA_VERSION = "growth-learning-v1";
const CLAIM_KINDS = Object.freeze([
  "verified_fact",
  "user_decision",
  "provider_evidence",
  "inference",
  "assumption",
  "superseded",
]);

const AUTHORITY_BY_KIND = Object.freeze({
  verified_fact: Object.freeze(["provider_readback", "independent_verification", "authoritative_record"]),
  user_decision: Object.freeze(["owner_decision", "authorized_user_decision"]),
  provider_evidence: Object.freeze(["provider_readback"]),
  inference: Object.freeze(["model_inference"]),
  assumption: Object.freeze(["assumption"]),
  superseded: Object.freeze(["supersession"]),
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OPAQUE = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$/;
const SHA256 = /^[0-9a-f]{64}$/i;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const FORBIDDEN_KEYS = /^(secret|token|access_token|refresh_token|api_key|password|authorization|cookie|private_key|service_role)$/i;

class GrowthLearningSchemaError extends Error {
  constructor(code) {
    super(code);
    this.name = "GrowthLearningSchemaError";
    this.code = code;
  }
}
function fail(code) { throw new GrowthLearningSchemaError(code); }
function isObject(value) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}
function exactKeys(value, allowed, required, code) {
  if (!isObject(value)) fail(code);
  if (Object.keys(value).some((key) => !allowed.includes(key))) fail(code);
  if (required.some((key) => !Object.hasOwn(value, key))) fail(code);
}
function uuid(value, code) {
  if (typeof value !== "string" || !UUID.test(value)) fail(code);
  return value.toLowerCase();
}
function opaque(value, code) {
  if (typeof value !== "string" || !OPAQUE.test(value)) fail(code);
  return value;
}
function text(value, min, max, code) {
  if (typeof value !== "string") fail(code);
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) fail(code);
  return trimmed;
}
function timestamp(value, code) {
  if (typeof value !== "string" || !TIMESTAMP.test(value)) fail(code);
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString() !== value) fail(code);
  return value;
}
function freeze(value) {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}
function assertNoSensitiveKeys(value) {
  if (Array.isArray(value)) {
    for (const child of value) assertNoSensitiveKeys(child);
    return;
  }
  if (!isObject(value)) return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.test(key)) fail("sensitive_key_rejected");
    assertNoSensitiveKeys(child);
  }
}
function normalizeScope(scope) {
  exactKeys(scope, ["organization_id", "project_id"], ["organization_id", "project_id"], "trusted_scope_required");
  return {
    organization_id: uuid(scope.organization_id, "trusted_scope_invalid"),
    project_id: uuid(scope.project_id, "trusted_scope_invalid"),
  };
}
function normalizeAuthority(value, claimKind) {
  exactKeys(value, ["kind", "ref"], ["kind", "ref"], "authority_invalid");
  if (!AUTHORITY_BY_KIND[claimKind].includes(value.kind)) fail("authority_kind_invalid");
  return { kind: value.kind, ref: opaque(value.ref, "authority_ref_invalid") };
}
function normalizeProvenance(value) {
  exactKeys(
    value,
    ["source_type", "source_locator", "source_sha", "observed_at"],
    ["source_type", "source_locator", "source_sha", "observed_at"],
    "provenance_invalid",
  );
  const sourceTypes = ["provider", "document", "repository", "owner", "verification", "model"];
  if (!sourceTypes.includes(value.source_type)) fail("provenance_source_type_invalid");
  const sourceSha = value.source_sha === null ? null : text(value.source_sha, 7, 64, "provenance_sha_invalid");
  if (sourceSha !== null && !/^[0-9a-f]{7,64}$/i.test(sourceSha)) fail("provenance_sha_invalid");
  return {
    source_type: value.source_type,
    source_locator: text(value.source_locator, 1, 1000, "provenance_locator_invalid"),
    source_sha: sourceSha,
    observed_at: timestamp(value.observed_at, "provenance_observed_at_invalid"),
  };
}
function normalizeEvidenceRefs(value) {
  if (!Array.isArray(value) || value.length > 32) fail("evidence_refs_invalid");
  return value.map((entry) => {
    exactKeys(
      entry,
      ["type", "ref", "sha256", "artifact_class", "observed_at"],
      ["type", "ref"],
      "evidence_ref_invalid",
    );
    const result = {
      type: opaque(entry.type, "evidence_type_invalid"),
      ref: text(entry.ref, 1, 1000, "evidence_ref_invalid"),
    };
    if (Object.hasOwn(entry, "sha256")) {
      if (typeof entry.sha256 !== "string" || !SHA256.test(entry.sha256)) fail("evidence_sha_invalid");
      result.sha256 = entry.sha256.toLowerCase();
    }
    if (Object.hasOwn(entry, "artifact_class")) {
      result.artifact_class = opaque(entry.artifact_class, "artifact_class_invalid");
    }
    if (Object.hasOwn(entry, "observed_at")) {
      result.observed_at = timestamp(entry.observed_at, "evidence_observed_at_invalid");
    }
    return result;
  });
}
function normalizeValidity(value) {
  exactKeys(
    value,
    ["effective_at", "review_due_at", "expires_at"],
    ["effective_at", "review_due_at", "expires_at"],
    "validity_invalid",
  );
  const effectiveAt = timestamp(value.effective_at, "effective_at_invalid");
  const reviewDueAt = timestamp(value.review_due_at, "review_due_at_invalid");
  const expiresAt = value.expires_at === null ? null : timestamp(value.expires_at, "expires_at_invalid");
  if (effectiveAt > reviewDueAt) fail("validity_order_invalid");
  if (expiresAt !== null && reviewDueAt > expiresAt) fail("validity_order_invalid");
  return { effective_at: effectiveAt, review_due_at: reviewDueAt, expires_at: expiresAt };
}
function normalizeSupersession(value, claimKind) {
  if (claimKind !== "superseded") {
    if (value !== null) fail("supersession_not_applicable");
    return null;
  }
  exactKeys(value, ["supersedes_ref", "reason"], ["supersedes_ref", "reason"], "supersession_required");
  return {
    supersedes_ref: opaque(value.supersedes_ref, "supersedes_ref_invalid"),
    reason: text(value.reason, 3, 1000, "supersession_reason_invalid"),
  };
}

function validateGrowthLearning(input, trustedScope) {
  assertNoSensitiveKeys(input);
  const scope = normalizeScope(trustedScope);
  const fields = [
    "schema_version",
    "learning_id",
    "organization_id",
    "project_id",
    "subject_key",
    "claim_kind",
    "statement",
    "observed_at",
    "validity",
    "confidence",
    "confidence_basis",
    "authority",
    "provenance",
    "evidence_refs",
    "supersession",
  ];
  exactKeys(input, fields, fields, "learning_shape_invalid");
  if (input.schema_version !== SCHEMA_VERSION) fail("schema_version_invalid");
  const claimKind = input.claim_kind;
  if (!CLAIM_KINDS.includes(claimKind)) fail("claim_kind_invalid");

  const suppliedScope = normalizeScope({
    organization_id: input.organization_id,
    project_id: input.project_id,
  });
  if (scope.organization_id !== suppliedScope.organization_id || scope.project_id !== suppliedScope.project_id) {
    fail("scope_mismatch");
  }

  const confidence = Number(input.confidence);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) fail("confidence_invalid");
  if (claimKind === "assumption" && confidence > 0.5) fail("assumption_confidence_too_high");

  const authority = normalizeAuthority(input.authority, claimKind);
  const provenance = normalizeProvenance(input.provenance);
  const evidenceRefs = normalizeEvidenceRefs(input.evidence_refs);
  const validity = normalizeValidity(input.validity);
  const supersession = normalizeSupersession(input.supersession, claimKind);

  if (["verified_fact", "provider_evidence", "superseded"].includes(claimKind) && evidenceRefs.length < 1) {
    fail("evidence_required");
  }
  if (claimKind === "provider_evidence" && provenance.source_type !== "provider") {
    fail("provider_provenance_required");
  }
  if (claimKind === "user_decision" && !["owner", "document"].includes(provenance.source_type)) {
    fail("decision_provenance_invalid");
  }
  if (claimKind === "inference" && provenance.source_type !== "model") {
    fail("inference_provenance_invalid");
  }
  if (claimKind === "assumption" && evidenceRefs.length > 0) {
    fail("assumption_evidence_not_authoritative");
  }

  const normalized = {
    schema_version: SCHEMA_VERSION,
    learning_id: opaque(input.learning_id, "learning_id_invalid"),
    ...scope,
    subject_key: opaque(input.subject_key, "subject_key_invalid"),
    claim_kind: claimKind,
    statement: text(input.statement, 1, 1800, "statement_invalid"),
    observed_at: timestamp(input.observed_at, "observed_at_invalid"),
    validity,
    confidence,
    confidence_basis: text(input.confidence_basis, 1, 1000, "confidence_basis_invalid"),
    authority,
    provenance,
    evidence_refs: evidenceRefs,
    supersession,
  };
  return freeze(normalized);
}

function projectGrowthLearningCandidate(input, trustedScope) {
  const learning = validateGrowthLearning(input, trustedScope);
  const contentHash = createHash("sha256").update(JSON.stringify(learning)).digest("hex");
  return freeze({
    schema_version: "growth-learning-candidate-v1",
    learning_kind: "growth_learning_v1",
    source_event_id: learning.learning_id,
    organization_id: learning.organization_id,
    project_id: learning.project_id,
    subject_key: learning.subject_key,
    claim_kind: learning.claim_kind,
    claim: learning.statement,
    observed_at: learning.observed_at,
    effective_at: learning.validity.effective_at,
    review_due_at: learning.validity.review_due_at,
    expires_at: learning.validity.expires_at,
    confidence: learning.confidence,
    confidence_basis: learning.confidence_basis,
    authority_kind: learning.authority.kind,
    authority_ref: learning.authority.ref,
    provenance: learning.provenance,
    evidence_refs: learning.evidence_refs,
    supersession: learning.supersession,
    content_hash: contentHash,
    review_required: true,
    canonical_memory_written: false,
  });
}

module.exports = {
  SCHEMA_VERSION,
  CLAIM_KINDS,
  AUTHORITY_BY_KIND,
  GrowthLearningSchemaError,
  validateGrowthLearning,
  projectGrowthLearningCandidate,
};
