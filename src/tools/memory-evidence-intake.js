"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.EVIDENCE_CANDIDATE_SUBMIT_SCOPE = void 0;
exports.submitEvidenceCandidate = submitEvidenceCandidate;

const { z } = require("zod");
const core = require("./memory-evidence-intake-core.js");
const { markProviderOutcome } = require("../runtime/provider-execution-state-machine.js");

const EVIDENCE_CANDIDATE_SUBMIT_SCOPE = "memory:evidence-candidate:submit";
exports.EVIDENCE_CANDIDATE_SUBMIT_SCOPE = EVIDENCE_CANDIDATE_SUBMIT_SCOPE;

// Keep the canonical entrypoint visibly bound to the backend summary limit.
const OutcomeObservationArgsSchema = z.object({
  summary: z.string().trim().min(1).max(1800),
}).passthrough();

for (const [name, value] of Object.entries(core)) {
  if (name !== "submitEvidenceCandidate") exports[name] = value;
}

const MAX_OBSERVED_RESPONSE_BYTES = 100_000;
const PROVEN_NO_SIDE_EFFECT_CODES = new Map([
  [400, new Set([
    "unsupported_action",
    "unexpected_field",
    "project_identity_invalid",
    "evidence_candidate_invalid",
    "sensitive_candidate_rejected",
  ])],
  [403, new Set([
    "namespace_not_allowed",
    "scope_not_allowed",
    "project_not_allowed",
  ])],
]);

function safeBackendCode(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const candidate = typeof body.error === "string"
    ? body.error
    : typeof body.error?.code === "string"
      ? body.error.code
      : typeof body.code === "string"
        ? body.code
        : null;
  return candidate && /^[a-z0-9][a-z0-9._:-]{0,79}$/.test(candidate)
    ? candidate
    : null;
}

async function readObservedResponse(response) {
  const rawLength = response?.headers?.get?.("content-length")?.trim();
  if (rawLength && /^\d+$/.test(rawLength)) {
    const declared = Number(rawLength);
    if (!Number.isSafeInteger(declared) || declared > MAX_OBSERVED_RESPONSE_BYTES) {
      return null;
    }
  }
  if (!response || typeof response.clone !== "function") return null;

  const clone = response.clone();
  if (!clone.body?.getReader) {
    const text = await clone.text();
    return Buffer.byteLength(text, "utf8") <= MAX_OBSERVED_RESPONSE_BYTES
      ? text
      : null;
  }

  const reader = clone.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > MAX_OBSERVED_RESPONSE_BYTES) {
        await reader.cancel().catch(() => undefined);
        return null;
      }
      chunks.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock?.();
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function responseOutcome(response) {
  const status = Number.isInteger(response?.status) ? response.status : 0;
  if (status !== 400 && status !== 403 && (status < 200 || status >= 300)) {
    // Timeouts, rate limits, conflicts, and server failures do not by
    // themselves prove that the request was rejected before a write. The
    // immutable provider idempotency identity is the only safe replay path.
    return { outcome: "ambiguous", evidence: `memory_http_${status || "unknown"}_ambiguous` };
  }

  try {
    const text = await readObservedResponse(response);
    if (text === null) {
      return { outcome: "ambiguous", evidence: "memory_response_unbounded" };
    }
    const body = text ? JSON.parse(text) : {};
    const code = safeBackendCode(body);

    if (status >= 200 && status < 300) {
      if (body && typeof body === "object" && body.ok === true) {
        return { outcome: "succeeded", evidence: "memory_success_acknowledgement" };
      }
      // A malformed or negative 2xx body is a response-contract failure after
      // dispatch, never proof that the provider did not apply the mutation.
      return { outcome: "ambiguous", evidence: "memory_2xx_body_ambiguous" };
    }

    if (status === 400 || status === 403) {
      const codes = PROVEN_NO_SIDE_EFFECT_CODES.get(status);
      if (code && codes?.has(code)) {
        return {
          outcome: "failed_before_side_effects",
          evidence: `memory_contract_rejection_${status}_${code}`,
        };
      }
    }

    // A 409 is deliberately ambiguous. The canonical Memory contract can
    // reconcile or write a review row before returning a conflict, so status
    // alone never proves that no side effect occurred.
    return { outcome: "ambiguous", evidence: `memory_http_${status}_ambiguous` };
  } catch {
    return { outcome: "ambiguous", evidence: "memory_response_parse_ambiguous" };
  }
}

async function submitEvidenceCandidate(args, configuration, fetchFn = globalThis.fetch) {
  const grantedScopes = Array.isArray(configuration?.grantedScopes)
    ? configuration.grantedScopes
    : [];
  if (!grantedScopes.includes(EVIDENCE_CANDIDATE_SUBMIT_SCOPE)) {
    throw markProviderOutcome(
      new Error("Pandora Memory evidence-candidate submit scope is not granted"),
      "failed_before_side_effects",
      "candidate_submit_scope_not_granted",
    );
  }

  // The underlying core still contains the historical `memory:write` guard.
  // Translate the narrowly authorized external capability only inside this
  // candidate-only wrapper. Callers never need or receive generic write scope.
  const scopedConfiguration = {
    ...configuration,
    grantedScopes: [...new Set([...grantedScopes, "memory:write"])],
  };

  try {
    OutcomeObservationArgsSchema.parse(args);
  } catch (error) {
    throw markProviderOutcome(error, "failed_before_side_effects", "local_schema_validation");
  }

  if (typeof fetchFn !== "function") {
    try {
      return await core.submitEvidenceCandidate(args, scopedConfiguration, fetchFn);
    } catch (error) {
      throw markProviderOutcome(error, "failed_before_side_effects", "fetch_unavailable_before_dispatch");
    }
  }

  let dispatchStarted = false;
  let observed;
  const observingFetch = async (...fetchArgs) => {
    dispatchStarted = true;
    try {
      const response = await fetchFn(...fetchArgs);
      observed = await responseOutcome(response);
      return response;
    } catch (error) {
      observed = { outcome: "ambiguous", evidence: "transport_failed_after_dispatch" };
      throw error;
    }
  };

  try {
    return await core.submitEvidenceCandidate(args, scopedConfiguration, observingFetch);
  } catch (error) {
    const resolved = observed || (dispatchStarted
      ? { outcome: "ambiguous", evidence: "dispatch_outcome_unobserved" }
      : { outcome: "failed_before_side_effects", evidence: "local_failure_before_dispatch" });
    throw markProviderOutcome(error, resolved.outcome, resolved.evidence);
  }
}
