"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.ProviderExecutionOutcomeError = void 0;
exports.emitReconciliationEvent = emitReconciliationEvent;
exports.finalizationAmbiguity = finalizationAmbiguity;
exports.localPostSuccessError = localPostSuccessError;
exports.markProviderOutcome = markProviderOutcome;
exports.normalizedProviderError = normalizedProviderError;
exports.operationIdentity = operationIdentity;
exports.reconciliationSummary = reconciliationSummary;
exports.sanitizedResultSummary = sanitizedResultSummary;

const { createHash } = require("node:crypto");
const { executionPayloadHash } = require("./execution-payload.js");
const { prepareToolPresentation } = require("./provider-result-contract.js");

const PROVIDER_OUTCOMES = new Set([
  "not_executed",
  "failed_before_side_effects",
  "ambiguous",
  "succeeded",
]);
const PROVIDER_IDEMPOTENCY_TOOLS = new Set(["memory.submitEvidenceCandidate"]);
const SAFE_TOKEN = /^[a-z0-9][a-z0-9._:-]{0,79}$/;
const SAFE_CORRELATION_ID = /^[A-Za-z0-9._:-]{1,128}$/;
const SAFE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
// Provider responses and arbitrary thrown objects are not trusted to attest
// whether a mutation happened. Only this module's marker (used by reviewed
// provider adapters) or a normalized outcome error may establish that fact.
const TRUSTED_OUTCOME_MARKS = new WeakMap();

function safeToken(value, fallback) {
  return typeof value === "string" && SAFE_TOKEN.test(value) ? value : fallback;
}
function safeUuid(value) {
  return typeof value === "string" && SAFE_UUID.test(value) ? value : null;
}
function safeSummary(value, fallback) {
  return typeof value === "string"
    && Buffer.byteLength(value, "utf8") <= 200
    && !/[\u0000-\u001f\u007f]/.test(value)
    ? value
    : fallback;
}
function safeMetadata(failure) {
  if (!failure || typeof failure !== "object" || Array.isArray(failure)) return {};
  const provider = safeToken(failure.provider, null);
  const operation = safeToken(failure.operation, null);
  const correlationId = typeof failure.correlationId === "string"
    && SAFE_CORRELATION_ID.test(failure.correlationId) ? failure.correlationId : null;
  const privacyScanVersion = safeToken(failure.privacyScanVersion, null);
  const httpStatus = Number.isInteger(failure.httpStatus)
    && failure.httpStatus >= 100 && failure.httpStatus <= 599 ? failure.httpStatus : null;
  const retryAfterMs = Number.isInteger(failure.retryAfterMs)
    && failure.retryAfterMs >= 0 && failure.retryAfterMs <= 86_400_000
    ? failure.retryAfterMs : null;
  return {
    ...(provider ? { provider } : {}),
    ...(operation ? { operation } : {}),
    ...(httpStatus === null ? {} : { httpStatus }),
    ...(correlationId ? { correlationId } : {}),
    ...(privacyScanVersion ? { privacyScanVersion } : {}),
    ...(retryAfterMs === null ? {} : { retryAfterMs }),
  };
}
function mutationState(outcome, downstream) {
  if (outcome === "not_executed") return "DEFINITELY_NOT_DISPATCHED";
  if (outcome === "failed_before_side_effects") return "PROVIDER_REJECTED_WITH_NO_SIDE_EFFECT";
  if (outcome === "ambiguous") return "OUTCOME_AMBIGUOUS_AFTER_DISPATCH";
  return downstream && downstream !== "succeeded"
    ? "PROVIDER_SUCCEEDED_LOCAL_FINALIZATION_FAILED"
    : "PROVIDER_SUCCEEDED";
}
function retryContract(outcome, supported, retryable) {
  if (outcome === "ambiguous") {
    return supported ? "same_immutable_idempotency_identity_only" : "reconcile_before_retry";
  }
  if (outcome === "succeeded") return "do_not_repeat_provider_mutation";
  return retryable ? "normal_retry_policy" : "not_retryable";
}

function operationIdentity(tool, args) {
  const key = [args?.idempotencyKey, args?.idempotency_key]
    .find((value) => typeof value === "string" && value.trim());
  const supported = PROVIDER_IDEMPOTENCY_TOOLS.has(tool) && typeof key === "string";
  return Object.freeze({
    tool,
    payloadHash: executionPayloadHash(tool, args),
    providerIdempotencySupported: supported,
    idempotencyIdentityHash: supported
      ? createHash("sha256").update(key.trim(), "utf8").digest("hex")
      : null,
  });
}

class ProviderExecutionOutcomeError extends Error {
  constructor(input) {
    const providerOutcome = PROVIDER_OUTCOMES.has(input.providerOutcome)
      ? input.providerOutcome : "ambiguous";
    const downstream = safeToken(input.downstreamProcessingOutcome, "not_started");
    const supported = input.identity?.providerIdempotencySupported === true;
    let retryable = input.retryable === true;
    if (providerOutcome === "ambiguous") retryable = retryable && supported;
    if (providerOutcome === "succeeded") retryable = false;
    const mutableFailure = {
      schemaVersion: "1.0.0",
      safeErrorCode: safeToken(input.safeErrorCode, "provider_execution_outcome_ambiguous"),
      summary: safeSummary(
        input.summary,
        "Provider execution requires reconciliation before any repeat",
      ),
      providerOutcome,
      mutationState: mutationState(providerOutcome, downstream),
      downstreamProcessingOutcome: downstream,
      validationCategory: safeToken(input.validationCategory, "provider_execution"),
      retryable,
      automaticRetryAllowed: false,
      retryContract: retryContract(providerOutcome, supported, retryable),
      reconciliationRequired: input.reconciliationRequired === true,
      terminalClassification: input.reconciliationRequired === true
        ? "reconciliation_required"
        : providerOutcome === "succeeded" ? "succeeded" : "failed_without_side_effect",
      providerIdempotencySupported: supported,
      payloadHash: input.identity?.payloadHash || null,
      idempotencyIdentityHash: input.identity?.idempotencyIdentityHash || null,
      planId: safeUuid(input.planId),
      ...safeMetadata(input.providerFailure),
      evidencePolicy: "privacy_safe_summary_only_v1",
      timestamp: new Date().toISOString(),
    };
    // Keep the durable/HTTP error envelope within the same 1,000-byte audit
    // ceiling even when a downstream service supplies maximally long, but
    // syntactically safe, metadata. Core mutation truth fields are never
    // removed; optional correlation metadata is shed first.
    for (const key of [
      "correlationId",
      "retryAfterMs",
      "privacyScanVersion",
      "operation",
      "provider",
      "httpStatus",
    ]) {
      if (Buffer.byteLength(JSON.stringify(mutableFailure), "utf8") <= 1000) break;
      delete mutableFailure[key];
    }
    if (Buffer.byteLength(JSON.stringify(mutableFailure), "utf8") > 1000) {
      mutableFailure.safeErrorCode = "provider_execution_failed";
      mutableFailure.validationCategory = "provider_execution";
      mutableFailure.downstreamProcessingOutcome = providerOutcome === "succeeded"
        ? "local_processing_failed"
        : "not_started";
    }
    if (Buffer.byteLength(JSON.stringify(mutableFailure), "utf8") > 1000) {
      mutableFailure.summary = "Provider execution requires reconciliation before any repeat";
    }
    const failure = Object.freeze(mutableFailure);
    super(JSON.stringify(failure));
    this.name = "ProviderExecutionOutcomeError";
    this.status = Number.isInteger(input.status) && input.status >= 400 && input.status <= 599
      ? input.status : providerOutcome === "succeeded" ? 502 : 503;
    this.code = failure.safeErrorCode;
    this.providerOutcome = providerOutcome;
    this.retryable = retryable;
    this.reconciliationRequired = failure.reconciliationRequired;
    this.failure = failure;
  }
}
exports.ProviderExecutionOutcomeError = ProviderExecutionOutcomeError;

function markProviderOutcome(error, outcome, evidence = "provider_contract") {
  if (!error || typeof error !== "object" || !PROVIDER_OUTCOMES.has(outcome)) return error;
  const existing = TRUSTED_OUTCOME_MARKS.get(error);
  if (!existing) {
    TRUSTED_OUTCOME_MARKS.set(error, Object.freeze({
      outcome,
      evidence: safeToken(evidence, "provider_contract"),
    }));
  }
  if (!PROVIDER_OUTCOMES.has(error.providerOutcome)) {
    try {
      Object.defineProperty(error, "providerOutcome", {
        value: existing?.outcome || outcome,
        enumerable: false,
        configurable: false,
        writable: false,
      });
    } catch { return error; }
  }
  if (typeof error.providerOutcomeEvidence !== "string") {
    try {
      Object.defineProperty(error, "providerOutcomeEvidence", {
        value: existing?.evidence || safeToken(evidence, "provider_contract"),
        enumerable: false,
        configurable: false,
        writable: false,
      });
    } catch { /* outcome remains usable */ }
  }
  return error;
}

function explicitOutcome(error) {
  if (error instanceof ProviderExecutionOutcomeError) return error.providerOutcome;
  return TRUSTED_OUTCOME_MARKS.get(error)?.outcome;
}

function normalizedProviderError(error, identity) {
  if (error instanceof ProviderExecutionOutcomeError) return error;
  const failure = error?.failure && typeof error.failure === "object" ? error.failure : {};
  const status = Number.isInteger(error?.status)
    ? error.status : Number.isInteger(failure.httpStatus) ? failure.httpStatus : 503;
  const outcome = explicitOutcome(error) || "ambiguous";
  const reconciliationRequired = outcome === "ambiguous" || outcome === "succeeded";
  return new ProviderExecutionOutcomeError({
    providerOutcome: outcome,
    downstreamProcessingOutcome: outcome === "succeeded" ? "failed" : "not_started",
    safeErrorCode: safeToken(error?.code ?? failure.safeErrorCode, "provider_execution_failed"),
    validationCategory: safeToken(failure.validationCategory, "provider_execution"),
    retryable: outcome === "ambiguous"
      ? identity.providerIdempotencySupported
      : error?.retryable === true || failure.retryable === true,
    reconciliationRequired,
    status,
    identity,
    providerFailure: failure,
    summary: reconciliationRequired
      ? "Provider execution outcome requires reconciliation before any repeat"
      : "Provider contract proves the mutation did not create an external side effect",
  });
}

function localPostSuccessError(error, identity, phase, code = "provider_response_contract_error") {
  return new ProviderExecutionOutcomeError({
    providerOutcome: "succeeded",
    downstreamProcessingOutcome: safeToken(phase, "local_processing_failed"),
    safeErrorCode: code,
    validationCategory: safeToken(error?.category, "response_contract"),
    retryable: false,
    reconciliationRequired: true,
    status: 502,
    identity,
    summary: "Provider response contract failed after the provider mutation succeeded; reconciliation is required",
  });
}
function finalizationAmbiguity(execution, planId) {
  return new ProviderExecutionOutcomeError({
    providerOutcome: execution?.providerOutcome || "ambiguous",
    downstreamProcessingOutcome: "durable_completion_unknown",
    safeErrorCode: "execution_finalization_ambiguous",
    validationCategory: "durable_ledger",
    retryable: false,
    reconciliationRequired: true,
    status: 503,
    identity: execution?.identity,
    planId,
    providerFailure: execution?.error?.failure,
    summary: "Provider outcome is known or ambiguous but durable local completion requires reconciliation",
  });
}

function sanitizedResultSummary(input, execution) {
  const source = input?.resultSummary && typeof input.resultSummary === "object"
    ? input.resultSummary : {};
  const summary = source.type === "memory_evidence_candidate"
    ? {
      type: "memory_evidence_candidate",
      candidateId: safeUuid(source.candidateId),
      reviewItemId: safeUuid(source.reviewItemId),
      status: safeToken(source.status, "pending_review"),
      deduplicated: source.deduplicated === true,
      namespace: safeToken(source.namespace, null),
      projectId: safeUuid(source.projectId),
      projectKey: safeToken(source.projectKey, null),
      proofStage: safeToken(source.proofStage, null),
      canonicalPromoted: source.canonicalPromoted === true,
      privacyScanVersion: safeToken(source.privacyScanVersion, null),
    }
    : { type: safeToken(source.type, "object") };
  return prepareToolPresentation({
    ...summary,
    providerOutcome: "succeeded",
    mutationState: "PROVIDER_SUCCEEDED",
    downstreamProcessingOutcome: "succeeded",
    retryable: false,
    automaticRetryAllowed: false,
    retryContract: "do_not_repeat_provider_mutation",
    reconciliationRequired: false,
    providerIdempotencySupported: execution.identity.providerIdempotencySupported,
    payloadHash: execution.identity.payloadHash,
    idempotencyIdentityHash: execution.identity.idempotencyIdentityHash,
    responseDelivery: "not_required_for_provider_outcome_truth",
    evidencePolicy: "privacy_safe_summary_only_v1",
  });
}

function reconciliationSummary(execution, failure) {
  const retryable = failure?.retryable === true
    && execution.identity.providerIdempotencySupported;
  const downstream = safeToken(
    failure?.downstreamProcessingOutcome,
    execution.providerOutcome === "succeeded" ? "local_processing_failed" : "not_started",
  );
  return prepareToolPresentation({
    type: "provider_execution_reconciliation",
    schemaVersion: "1.0.0",
    providerOutcome: execution.providerOutcome,
    mutationState: mutationState(execution.providerOutcome, downstream),
    downstreamProcessingOutcome: downstream,
    safeErrorCode: safeToken(failure?.safeErrorCode, "provider_execution_outcome_ambiguous"),
    retryable,
    automaticRetryAllowed: false,
    retryContract: retryContract(
      execution.providerOutcome,
      execution.identity.providerIdempotencySupported,
      retryable,
    ),
    reconciliationRequired: true,
    providerIdempotencySupported: execution.identity.providerIdempotencySupported,
    payloadHash: execution.identity.payloadHash,
    idempotencyIdentityHash: execution.identity.idempotencyIdentityHash,
    ...safeMetadata(failure),
    evidencePolicy: "privacy_safe_summary_only_v1",
  });
}

function emitReconciliationEvent(execution, phase, planId) {
  try {
    console.error(JSON.stringify({
      event: "provider_execution_reconciliation_required",
      phase: safeToken(phase, "local_processing_failed"),
      planId: safeUuid(planId),
      providerOutcome: execution.providerOutcome,
      mutationState: mutationState(execution.providerOutcome, phase),
      payloadHash: execution.identity.payloadHash,
      idempotencyIdentityHash: execution.identity.idempotencyIdentityHash,
      providerIdempotencySupported: execution.identity.providerIdempotencySupported,
      evidencePolicy: "privacy_safe_summary_only_v1",
    }));
  } catch { /* logging cannot alter provider truth */ }
}
