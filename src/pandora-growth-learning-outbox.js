"use strict";

const { createHash } = require("node:crypto");
const { projectGrowthLearningCandidate } = require("./pandora-growth-learning-schema.js");

const ADAPTER_SCHEMA_VERSION = "growth-learning-outbox-adapter-v1";
const BINDING_SCHEMA_VERSION = "growth-learning-outbox-binding-v1";
const LEARNING_KIND = "growth_learning_v1";
const MEMORY_PROJECT_ID = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const MEMORY_PROJECT_KEY = "mcpmaster-pandoras-box";
const MEMORY_NAMESPACE = "real_life";
const MEMORY_PRINCIPAL_KEY = "projectos-mcpmaster-production";
const MEMORY_ENVIRONMENT = "production";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const RUNTIME_HOLD_REASON = "memory_growth_learning_intake_unsupported";

class GrowthLearningOutboxError extends Error {
  constructor(code) {
    super(code);
    this.name = "GrowthLearningOutboxError";
    this.code = code;
  }
}
function fail(code) { throw new GrowthLearningOutboxError(code); }
function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(value));
}
function exactKeys(value, expected, code) {
  if (!isObject(value)) fail(code);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length ||
      actual.some((key, index) => key !== wanted[index])) fail(code);
}
function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isObject(value)) {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}
function uuidFromHash(hash) {
  if (!SHA256.test(hash)) fail("request_hash_invalid");
  const bytes = Buffer.from(hash.slice(0, 32), "hex");
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16),
    hex.slice(16, 20), hex.slice(20, 32)].join("-");
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

function projectGrowthLearningOutbox(input, trustedScope) {
  const candidate = projectGrowthLearningCandidate(input, trustedScope);
  const binding = {
    schema_version: BINDING_SCHEMA_VERSION,
    source_scope: {
      organization_id: candidate.organization_id,
      project_id: candidate.project_id,
    },
    target_memory: {
      project_id: MEMORY_PROJECT_ID,
      project_key: MEMORY_PROJECT_KEY,
      namespace: MEMORY_NAMESPACE,
      principal_key: MEMORY_PRINCIPAL_KEY,
      environment: MEMORY_ENVIRONMENT,
    },
    candidate,
  };
  const contextHash = sha256Hex(canonicalJson(binding));
  const requestHash = sha256Hex(`growth-learning-request-v1\n${contextHash}`);
  const requestId = uuidFromHash(requestHash);
  const eventKey = `growth:${candidate.organization_id}:${candidate.project_id}:${candidate.source_event_id}:${candidate.content_hash}`;
  if (eventKey.length > 1000) fail("event_key_invalid");

  const payload = {
    schema_version: 1,
    product_key: "projectos",
    source_event_id: requestId,
    source_request_id: requestId,
    organization_id: candidate.organization_id,
    intake_id: null,
    project_id: MEMORY_PROJECT_ID,
    project_key: MEMORY_PROJECT_KEY,
    tool: "facebook.growth_learning",
    risk: "write",
    outcome_status: "completed",
    duration_ms: 0,
    completed_at: candidate.observed_at,
    context_status: "available",
    context_hash: contextHash,
    result_fingerprint: candidate.content_hash,
    error_fingerprint: null,
    privacy_policy: "metadata_only_v1",
    learning_kind: LEARNING_KIND,
    growth_learning: binding,
  };

  return deepFreeze({
    schema_version: ADAPTER_SCHEMA_VERSION,
    outbox: {
      event_key: eventKey,
      organization_id: candidate.organization_id,
      request_id: requestId,
      intake_id: null,
      project_id: candidate.project_id,
      project_key: MEMORY_PROJECT_KEY,
      payload,
      delivery_status: "pending",
    },
    lifecycle: {
      delivery: "pending",
      review: "not_received",
      promotion: "not_promoted",
      retrieval: "not_retrievable",
      canonical_memory_written: false,
    },
    runtime_gate: {
      state: "held",
      reason: RUNTIME_HOLD_REASON,
      required_endpoint: "pandora-projectos-learning",
      required_learning_kind: LEARNING_KIND,
    },
  });
}

function validateBoundGrowthPayload(payload) {
  const payloadKeys = [
    "schema_version", "product_key", "source_event_id", "source_request_id",
    "organization_id", "intake_id", "project_id", "project_key", "tool",
    "risk", "outcome_status", "duration_ms", "completed_at", "context_status",
    "context_hash", "result_fingerprint", "error_fingerprint",
    "privacy_policy", "learning_kind", "growth_learning",
  ];
  exactKeys(payload, payloadKeys, "growth_payload_shape_invalid");
  const binding = payload.growth_learning;
  exactKeys(
    binding,
    ["schema_version", "source_scope", "target_memory", "candidate"],
    "growth_binding_shape_invalid",
  );
  exactKeys(binding.source_scope, ["organization_id", "project_id"], "growth_source_scope_invalid");
  exactKeys(
    binding.target_memory,
    ["project_id", "project_key", "namespace", "principal_key", "environment"],
    "growth_target_memory_invalid",
  );
  const candidate = binding.candidate;
  const candidateKeys = [
    "schema_version", "learning_kind", "source_event_id", "organization_id",
    "project_id", "subject_key", "claim_kind", "claim", "observed_at",
    "effective_at", "review_due_at", "expires_at", "confidence",
    "confidence_basis", "authority_kind", "authority_ref", "provenance",
    "evidence_refs", "supersession", "content_hash", "review_required",
    "canonical_memory_written",
  ];
  exactKeys(candidate, candidateKeys, "growth_candidate_shape_invalid");

  let normalizedCandidate;
  try {
    normalizedCandidate = projectGrowthLearningCandidate({
      schema_version: "growth-learning-v1",
      learning_id: candidate.source_event_id,
      organization_id: candidate.organization_id,
      project_id: candidate.project_id,
      subject_key: candidate.subject_key,
      claim_kind: candidate.claim_kind,
      statement: candidate.claim,
      observed_at: candidate.observed_at,
      validity: {
        effective_at: candidate.effective_at,
        review_due_at: candidate.review_due_at,
        expires_at: candidate.expires_at,
      },
      confidence: candidate.confidence,
      confidence_basis: candidate.confidence_basis,
      authority: { kind: candidate.authority_kind, ref: candidate.authority_ref },
      provenance: candidate.provenance,
      evidence_refs: candidate.evidence_refs,
      supersession: candidate.supersession,
    }, binding.source_scope);
  } catch {
    fail("growth_candidate_invalid");
  }

  const expectedContextHash = sha256Hex(canonicalJson(binding));
  const expectedRequestId = uuidFromHash(
    sha256Hex(`growth-learning-request-v1\n${expectedContextHash}`),
  );
  if (binding.schema_version !== BINDING_SCHEMA_VERSION ||
      canonicalJson(normalizedCandidate) !== canonicalJson(candidate) ||
      binding.source_scope.organization_id !== candidate.organization_id ||
      binding.source_scope.project_id !== candidate.project_id ||
      binding.target_memory.project_id !== MEMORY_PROJECT_ID ||
      binding.target_memory.project_key !== MEMORY_PROJECT_KEY ||
      binding.target_memory.namespace !== MEMORY_NAMESPACE ||
      binding.target_memory.principal_key !== MEMORY_PRINCIPAL_KEY ||
      binding.target_memory.environment !== MEMORY_ENVIRONMENT ||
      payload.schema_version !== 1 || payload.product_key !== "projectos" ||
      payload.source_event_id !== expectedRequestId ||
      payload.source_request_id !== expectedRequestId ||
      payload.organization_id !== candidate.organization_id ||
      payload.intake_id !== null || payload.project_id !== MEMORY_PROJECT_ID ||
      payload.project_key !== MEMORY_PROJECT_KEY ||
      payload.tool !== "facebook.growth_learning" || payload.risk !== "write" ||
      payload.outcome_status !== "completed" || payload.duration_ms !== 0 ||
      payload.completed_at !== candidate.observed_at ||
      payload.context_status !== "available" ||
      payload.context_hash !== expectedContextHash ||
      payload.result_fingerprint !== candidate.content_hash ||
      payload.error_fingerprint !== null ||
      payload.privacy_policy !== "metadata_only_v1" ||
      payload.learning_kind !== LEARNING_KIND) {
    fail("growth_payload_binding_invalid");
  }
  return candidate;
}

function validateGrowthLearningIntakeAcceptance(payload, response, httpStatus = null) {
  const candidate = validateBoundGrowthPayload(payload);
  if (response && response.status === "already_reviewed") {
    const terminalKeys = [
      "ok", "status", "source_event_id", "learning_id", "content_hash",
      "candidate_id", "review_item_id", "review_status", "deduplicated",
    ];
    const terminalStatuses = new Set([
      "needs_clarification",
      "blocked_namespace_mismatch",
      "blocked_sensitive",
      "blocked_policy",
      "approved_for_append",
      "rejected",
      "archived",
    ]);
    exactKeys(response, terminalKeys, "intake_response_shape_invalid");
    if (httpStatus !== 200 ||
        response.ok !== true ||
        response.source_event_id !== payload.source_event_id ||
        response.learning_id !== candidate.source_event_id ||
        response.content_hash !== candidate.content_hash ||
        !UUID.test(String(response.candidate_id || "")) ||
        !UUID.test(String(response.review_item_id || "")) ||
        !terminalStatuses.has(response.review_status) ||
        response.deduplicated !== true) {
      fail("intake_response_binding_invalid");
    }
    return deepFreeze({
      delivered: true,
      candidate_id: response.candidate_id.toLowerCase(),
      review_item_id: response.review_item_id.toLowerCase(),
      review_status: response.review_status,
      promotion_status: "not_promoted",
      retrieval_status: "not_retrievable",
      canonical_memory_written: false,
      deduplicated: true,
    });
  }

  const keys = [
    "ok", "status", "source_event_id", "learning_id", "content_hash",
    "candidate_id", "review_item_id", "review_required",
    "canonical_memory_written", "promotion_status", "retrieval_status",
    "deduplicated",
  ];
  exactKeys(response, keys, "intake_response_shape_invalid");
  if (response.ok !== true || response.status !== "pending_review" ||
      response.source_event_id !== payload.source_event_id ||
      response.learning_id !== candidate.source_event_id ||
      response.content_hash !== candidate.content_hash ||
      !UUID.test(String(response.candidate_id || "")) ||
      !UUID.test(String(response.review_item_id || "")) ||
      response.review_required !== true ||
      response.canonical_memory_written !== false ||
      response.promotion_status !== "not_promoted" ||
      response.retrieval_status !== "not_retrievable" ||
      typeof response.deduplicated !== "boolean") {
    fail("intake_response_binding_invalid");
  }
  return deepFreeze({
    delivered: true,
    candidate_id: response.candidate_id.toLowerCase(),
    review_item_id: response.review_item_id.toLowerCase(),
    review_status: "pending_review",
    promotion_status: "not_promoted",
    retrieval_status: "not_retrievable",
    canonical_memory_written: false,
    deduplicated: response.deduplicated,
  });
}

module.exports = {
  ADAPTER_SCHEMA_VERSION,
  BINDING_SCHEMA_VERSION,
  LEARNING_KIND,
  MEMORY_PROJECT_ID,
  MEMORY_PROJECT_KEY,
  MEMORY_NAMESPACE,
  MEMORY_PRINCIPAL_KEY,
  MEMORY_ENVIRONMENT,
  RUNTIME_HOLD_REASON,
  GrowthLearningOutboxError,
  canonicalJson,
  projectGrowthLearningOutbox,
  validateGrowthLearningIntakeAcceptance,
};
