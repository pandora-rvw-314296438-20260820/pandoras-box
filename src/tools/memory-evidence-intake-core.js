"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.EvidenceCandidateArgsSchema = void 0;
exports.submitEvidenceCandidate = submitEvidenceCandidate;

const { randomUUID } = require("node:crypto");
const { z } = require("zod");

const MAX_RESPONSE_BYTES = 100_000;
const DEFAULT_TIMEOUT_MS = 8_000;
const MAX_TIMEOUT_MS = 30_000;
const CANONICAL_PROJECT_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CANONICAL_PROJECT_KEY_PATTERN = /^[a-z0-9][a-z0-9._-]{1,95}$/;
const CORRELATION_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;
const IDEMPOTENCY_CONFLICT_CODE = "idempotency_conflict";
const FAILURE_SCHEMA_VERSION = "1.0.0";
const FAILURE_PROVIDER = "pandora-memory";
const FAILURE_OPERATION = "memory.submitEvidenceCandidate";
const EVIDENCE_PRIVACY_SCAN_VERSION = "evidence_privacy_v2";
const MAX_RETRY_AFTER_MS = 86_400_000;

const SAFE_BACKEND_FAILURES = new Map([
  ["unsupported_action", { httpStatuses: [400], validationCategory: "capability_contract", retryable: false }],
  ["unexpected_field", { httpStatuses: [400], validationCategory: "request_validation", retryable: false }],
  ["project_identity_invalid", { httpStatuses: [400], validationCategory: "project_identity", retryable: false }],
  ["evidence_candidate_invalid", { httpStatuses: [400], validationCategory: "candidate_validation", retryable: false }],
  ["sensitive_candidate_rejected", { httpStatuses: [400], validationCategory: "privacy_policy", retryable: false }],
  ["namespace_not_allowed", { httpStatuses: [403], validationCategory: "namespace_authorization", retryable: false }],
  ["scope_not_allowed", { httpStatuses: [403], validationCategory: "scope_authorization", retryable: false }],
  ["project_not_allowed", { httpStatuses: [403], validationCategory: "project_authorization", retryable: false }],
  [IDEMPOTENCY_CONFLICT_CODE, { httpStatuses: [409], validationCategory: "idempotency", retryable: false }],
]);

function safeCorrelationId(value, fallback) {
  return typeof value === "string" && CORRELATION_ID_PATTERN.test(value)
    ? value
    : fallback;
}

function responseCorrelationId(response, fallback) {
  const candidates = [
    response?.headers?.get?.("x-request-id"),
    response?.headers?.get?.("x-vercel-id"),
    response?.headers?.get?.("cf-ray"),
    response?.headers?.get?.("sb-request-id"),
  ];
  return candidates.reduce(
    (resolved, value) => resolved || safeCorrelationId(value, ""),
    "",
  ) || fallback;
}

function retryableStatus(status) {
  return status === 408 || status === 429 || status >= 500;
}

function normalizeOuterFailureStatus(status) {
  return Number.isInteger(status) && status >= 400 && status < 500
    ? status
    : 502;
}

function responseRetryAfterMs(response) {
  const raw = response?.headers?.get?.("retry-after");
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  if (/^\d{1,9}$/.test(value)) {
    return Math.min(Number(value) * 1000, MAX_RETRY_AFTER_MS);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) return null;
  return Math.min(Math.max(parsed - Date.now(), 0), MAX_RETRY_AFTER_MS);
}

function failureEnvelope(input) {
  const retryAfterMs = Number.isInteger(input.retryAfterMs)
    && input.retryAfterMs >= 0
    && input.retryAfterMs <= MAX_RETRY_AFTER_MS
    ? input.retryAfterMs
    : null;
  return Object.freeze({
    schemaVersion: FAILURE_SCHEMA_VERSION,
    provider: FAILURE_PROVIDER,
    operation: FAILURE_OPERATION,
    summary: input.summary || (Number.isInteger(input.httpStatus)
      ? `Pandora Memory candidate submission failed (${input.httpStatus})`
      : "Pandora Memory candidate submission failed"),
    httpStatus: Number.isInteger(input.httpStatus) ? input.httpStatus : null,
    safeErrorCode: input.safeErrorCode,
    validationCategory: input.validationCategory,
    retryable: input.retryable === true,
    ...(retryAfterMs === null ? {} : { retryAfterMs }),
    privacyScanVersion: EVIDENCE_PRIVACY_SCAN_VERSION,
    correlationId: input.correlationId,
    timestamp: input.timestamp,
  });
}

class MemoryEvidenceSubmissionError extends Error {
  constructor(input) {
    const failure = failureEnvelope(input);
    // The JSON message is deliberate: ProjectOS currently stores a bounded
    // error string in its hash-linked audit ledger. Serializing this fixed,
    // allowlisted envelope keeps both the caller and audit structurally useful
    // without accepting arbitrary provider text or confidential response data.
    super(JSON.stringify(failure));
    this.name = "MemoryEvidenceSubmissionError";
    if (failure.safeErrorCode === IDEMPOTENCY_CONFLICT_CODE) {
      this.code = failure.safeErrorCode;
    }
    this.status = normalizeOuterFailureStatus(input.outerStatus);
    this.failure = failure;
  }
}
exports.MemoryEvidenceSubmissionError = MemoryEvidenceSubmissionError;

class MemoryEvidenceIdempotencyConflictError extends MemoryEvidenceSubmissionError {
  constructor(input) {
    super({
      httpStatus: 409,
      summary: "Pandora Memory candidate idempotency conflict",
      safeErrorCode: IDEMPOTENCY_CONFLICT_CODE,
      validationCategory: "idempotency",
      retryable: false,
      correlationId: input.correlationId,
      timestamp: input.timestamp,
      outerStatus: 409,
    });
    this.name = "MemoryEvidenceIdempotencyConflictError";
  }
}

exports.MemoryEvidenceIdempotencyConflictError = MemoryEvidenceIdempotencyConflictError;
exports.IDEMPOTENCY_CONFLICT_CODE = IDEMPOTENCY_CONFLICT_CODE;
exports.EVIDENCE_PRIVACY_SCAN_VERSION = EVIDENCE_PRIVACY_SCAN_VERSION;

const NamespaceSchema = z.enum(["real_life", "au"]);
const ProofStageSchema = z.enum([
  "documented",
  "implemented",
  "tested",
  "deployed",
  "production_verified",
]);

const EvidenceKindSchema = z.enum([
  "verified_build",
  "verified_preview",
  "verified_publish",
  "verified_repair",
  "repeated_failure",
]);
const EVIDENCE_KIND_PROOF_STAGES = Object.freeze({
  verified_build: new Set(["tested", "deployed", "production_verified"]),
  verified_preview: new Set(["deployed", "production_verified"]),
  verified_publish: new Set(["production_verified"]),
  verified_repair: new Set(["tested", "deployed", "production_verified"]),
  repeated_failure: new Set(["tested", "deployed", "production_verified"]),
});
const EVIDENCE_KIND_REQUIRED_TYPES = Object.freeze({
  verified_build: ["build_job", "project_version", "verification_run"],
  verified_preview: ["project_version", "preview_deployment", "verification_run"],
  verified_publish: ["project_version", "production_deployment", "verification_run"],
  verified_repair: ["repair_attempt", "project_version", "verification_run"],
  repeated_failure: ["failure_fingerprint", "failure_run"],
});

const EvidenceCandidateSuccessResponseSchema = z.object({
  ok: z.literal(true),
  candidate_id: z.string().regex(CANONICAL_PROJECT_ID_PATTERN),
  review_item_id: z.string().regex(CANONICAL_PROJECT_ID_PATTERN),
  status: z.literal("pending_review"),
  idempotency_key: z.string().trim().regex(/^[A-Za-z0-9._:-]{16,160}$/),
  namespace: NamespaceSchema,
  project_id: z.string().regex(CANONICAL_PROJECT_ID_PATTERN),
  project_key: z.string().regex(CANONICAL_PROJECT_KEY_PATTERN),
  proof_stage: ProofStageSchema,
  evidence_kind: EvidenceKindSchema,
  deduplicated: z.boolean(),
  created_at: z.string().datetime({ offset: true }).nullable(),
  canonical_memory_written: z.literal(false),
  privacy_policy: z.literal("metadata_only_v1"),
}).strict();

const EvidenceRefSchema = z.object({
  type: z.string().trim().min(1).max(64),
  ref: z.string().trim().min(1).max(512),
  sha256: z.string().regex(/^[a-f0-9]{64}$/).optional(),
  artifact_class: z.string().trim().min(1).max(64).optional(),
  observed_at: z.string().datetime({ offset: true }).optional(),
}).strict();

const ProvenanceSchema = z.object({
  source_type: z.string().trim().min(1).max(64),
  source_locator: z.string().trim().min(1).max(512),
  source_sha: z.string().regex(/^[a-f0-9]{40}$/).optional(),
  parent_sha: z.string().regex(/^[a-f0-9]{40}$/).optional(),
  observed_at: z.string().datetime({ offset: true }),
}).strict();

exports.EvidenceCandidateArgsSchema = z.object({
  namespace: NamespaceSchema,
  projectId: z.string().uuid().optional(),
  projectKey: z.string().trim().regex(/^[a-z0-9][a-z0-9._-]{1,95}$/).optional(),
  title: z.string().trim().min(1).max(200),
  summary: z.string().trim().min(1).max(1800),
  proofStage: ProofStageSchema,
  evidenceKind: EvidenceKindSchema,
  claim: z.string().trim().min(1).max(1000),
  evidenceRefs: z.array(EvidenceRefSchema).min(1).max(20),
  provenance: ProvenanceSchema,
  idempotencyKey: z.string().trim().regex(/^[A-Za-z0-9._:-]{16,160}$/),
}).strict().superRefine((value, ctx) => {
  if (!value.projectId && !value.projectKey) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "projectId or projectKey is required" });
  }
  const stages = EVIDENCE_KIND_PROOF_STAGES[value.evidenceKind];
  if (!stages?.has(value.proofStage)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "proofStage is not valid for evidenceKind" });
  }
  const types = new Set(value.evidenceRefs.map((ref) => ref.type));
  const required = EVIDENCE_KIND_REQUIRED_TYPES[value.evidenceKind] || [];
  if (!required.every((type) => types.has(type))) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "evidenceRefs are incomplete for evidenceKind" });
  }
  if (value.evidenceKind === "repeated_failure") {
    if (value.evidenceRefs.length < 2) ctx.addIssue({ code: z.ZodIssueCode.custom, message: "repeated_failure requires repeated evidence" });
  } else if (!value.evidenceRefs.some((ref) => typeof ref.sha256 === "string")) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "verified evidence requires a SHA-256-backed ref" });
  }
});

function normalizeOrigin(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Pandora Memory origin is invalid");
  }
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    (url.pathname !== "/" && url.pathname !== "")
  ) {
    throw new Error("Pandora Memory origin must be a clean HTTPS origin");
  }
  return url.origin;
}

function boundedPositiveInteger(value, fallback, maximum) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0
    ? Math.min(parsed, maximum)
    : fallback;
}

const EVIDENCE_PRIVACY_TEXT_LIMIT = 20_000;
const EVIDENCE_SECRET_FIELD_PATTERN = /^(?:password|passwd|passphrase|pwd|pin|secret|client_secret|secret_key|secret_access_key|aws_secret_access_key|aws_access_key_id|access_key_id|api_key|access_token|refresh_token|service_role|private_key|accountkey|sharedaccesssignature)$/i;
const EVIDENCE_DIRECT_IDENTIFIER_FIELD_PATTERN = /^(?:phone|phone_number|mobile|mobile_number|telephone|address|street_address|home_address|mailing_address|full_name|first_name|last_name|given_name|family_name|ssn|social_security_number|passport|passport_number|tax_id|bank_account|iban|card_number)$/i;

function normalizePrivacyKey(value) {
  return String(value)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function decodePrivacyText(value) {
  let text = String(value)
    .normalize("NFKC")
    .replace(/[\u200B-\u200F\u2060\uFEFF]/g, "");
  const decodeHex = (match, raw) => {
    const code = Number.parseInt(raw, 16);
    return Number.isFinite(code) && code <= 0x10ffff
      ? String.fromCodePoint(code)
      : match;
  };
  text = text
    .replace(/\\u\{?([0-9a-f]{4,6})\}?/gi, decodeHex)
    .replace(/\\x([0-9a-f]{2})/gi, decodeHex)
    .replace(/&#x([0-9a-f]{2,6});?/gi, decodeHex)
    .replace(/&#(\d{2,7});?/g, (match, raw) => {
      const code = Number.parseInt(raw, 10);
      return Number.isFinite(code) && code <= 0x10ffff
        ? String.fromCodePoint(code)
        : match;
    })
    .replace(/&commat;/gi, "@")
    .replace(/&colon;/gi, ":");
  for (let depth = 0; depth < 2; depth += 1) {
    try {
      const decoded = decodeURIComponent(text);
      if (decoded === text) break;
      text = decoded;
    } catch {
      break;
    }
  }
  return text.slice(0, EVIDENCE_PRIVACY_TEXT_LIMIT);
}

function privacyTextReason(value) {
  const text = decodePrivacyText(value);
  const checks = [
    [/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, "direct_identifier_email"],
    [/(?:\+\d{1,3}[\s().-]*)?(?:\(?\d{2,4}\)?[\s.-]+)\d{3,4}[\s.-]+\d{3,4}\b/, "direct_identifier_phone"],
    [/\b(?:\+?63|0)9\d{9}\b/, "direct_identifier_phone"],
    [/\b(?:full[ _-]?name|first[ _-]?name|last[ _-]?name|given[ _-]?name|family[ _-]?name|name)\s*[:=]\s*["']?[A-Z][A-Z .'-]{2,80}/i, "direct_identifier_name"],
    [/\b(?:address|street[ _-]?address|home[ _-]?address|mailing[ _-]?address)\s*[:=]\s*[^,;\n]{5,160}/i, "direct_identifier_address"],
    [/\b\d{1,5}\s+[A-Z0-9.'-]+(?:\s+[A-Z0-9.'-]+){0,5}\s+(?:street|st|road|rd|avenue|ave|boulevard|blvd|drive|dr|lane|ln|court|ct|highway|hwy|barangay|brgy)\b/i, "direct_identifier_address"],
    [/\b\d{3}-\d{2}-\d{4}\b/, "direct_identifier_government"],
    [/\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b/, "direct_identifier_financial"],
    [/-----BEGIN (?:[A-Z0-9 -]+ )?PRIVATE KEY-----/i, "private_key_material"],
    [/\b(?:AKIA|ASIA|AIDA|AROA|AIPA|ANPA|ANVA)[A-Z0-9]{16}\b/, "cloud_credential_signature"],
    [/\bAIza[0-9A-Za-z_-]{35}\b/, "cloud_credential_signature"],
    [/\b(?:ghp|github_pat|glpat|sk|sbp|xox[baprs])_[A-Za-z0-9_-]{12,}\b/i, "credential_signature"],
    [/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/, "jwt_signature"],
    [/\b(?:password|passwd|passphrase|pwd|client[_ -]?secret|secret[_ -]?(?:key|access[_ -]?key)|aws[_ -]?(?:secret[_ -]?access[_ -]?key|access[_ -]?key[_ -]?id)|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|service[_ -]?role|private[_ -]?key|accountkey|sharedaccesssignature)\s*[:=]\s*["']?(?!(?:true|false|null|none|redacted|masked)\b)[^\s"',;}{]{4,}/i, "secret_assignment"],
    [/https?:\/\/[^/\s:@]+:[^/\s@]{4,}@/i, "credential_in_url"],
  ];
  for (const [pattern, reason] of checks) {
    if (pattern.test(text)) return reason;
  }
  return null;
}

function sensitiveReason(value) {
  const visit = (entry, key = null) => {
    if (key !== null) {
      const normalizedKey = normalizePrivacyKey(key);
      if (EVIDENCE_SECRET_FIELD_PATTERN.test(normalizedKey)) {
        return "secret_field";
      }
      if (EVIDENCE_DIRECT_IDENTIFIER_FIELD_PATTERN.test(normalizedKey)) {
        return "direct_identifier_field";
      }
    }
    if (typeof entry === "string") {
      return privacyTextReason(entry);
    }
    if (Array.isArray(entry)) {
      for (const item of entry) {
        const reason = visit(item);
        if (reason) return reason;
      }
      return null;
    }
    if (entry && typeof entry === "object") {
      for (const [childKey, childValue] of Object.entries(entry)) {
        const reason = visit(childValue, childKey);
        if (reason) return reason;
      }
    }
    return null;
  };
  return visit(value);
}

async function readBounded(response, maxBytes) {
  const declared = Number(response.headers?.get?.("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new Error("Pandora Memory response exceeded size limit");
  }

  if (response.body && typeof response.body.getReader === "function") {
    const reader = response.body.getReader();
    const chunks = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!value) continue;
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel().catch(() => undefined);
          throw new Error("Pandora Memory response exceeded size limit");
        }
        chunks.push(Buffer.from(value));
      }
    } finally {
      reader.releaseLock?.();
    }
    return Buffer.concat(chunks).toString("utf8");
  }

  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > maxBytes) {
    throw new Error("Pandora Memory response exceeded size limit");
  }
  return text;
}

function parseBoundSuccessResponse(status, body, input) {
  if (status !== 200 && status !== 202) return null;
  const parsed = EvidenceCandidateSuccessResponseSchema.safeParse(body);
  if (!parsed.success) return null;
  const value = parsed.data;
  if (
    value.idempotency_key !== input.idempotencyKey ||
    value.namespace !== input.namespace ||
    value.proof_stage !== input.proofStage ||
    value.evidence_kind !== input.evidenceKind ||
    (input.projectId && value.project_id !== input.projectId) ||
    (input.projectKey && value.project_key !== input.projectKey)
  ) {
    return null;
  }
  if (status === 202 && (value.deduplicated || value.created_at === null)) {
    return null;
  }
  if (status === 200 && (!value.deduplicated || value.created_at !== null)) {
    return null;
  }
  return value;
}

function safeBackendFailure(status, body) {
  const candidateCode = body?.error;
  if (status === 429) {
    return {
      safeErrorCode: "provider_rate_limited",
      validationCategory: "rate_limit",
      retryable: true,
    };
  }
  if (status === 408) {
    return {
      safeErrorCode: "provider_timeout",
      validationCategory: "timeout",
      retryable: true,
    };
  }
  if (status >= 500) {
    return {
      safeErrorCode: "provider_server_error",
      validationCategory: "provider_server",
      retryable: true,
    };
  }
  if (status >= 200 && status < 300) {
    return {
      safeErrorCode: "response_contract_error",
      validationCategory: "response_contract",
      retryable: false,
    };
  }
  const known = typeof candidateCode === "string"
    ? SAFE_BACKEND_FAILURES.get(candidateCode)
    : undefined;
  if (known) {
    if (!known.httpStatuses.includes(status)) {
      return {
        safeErrorCode: "response_contract_error",
        validationCategory: "response_contract",
        retryable: false,
      };
    }
    return {
      safeErrorCode: candidateCode,
      validationCategory: known.validationCategory,
      retryable: known.retryable,
    };
  }
  if (status === 409) {
    return {
      safeErrorCode: "provider_conflict",
      validationCategory: "downstream_conflict",
      retryable: false,
    };
  }
  return {
    safeErrorCode: "memory_submission_failed",
    validationCategory: "unknown_downstream",
    retryable: false,
  };
}

function submissionFailure(input) {
  return new MemoryEvidenceSubmissionError({
    httpStatus: input.httpStatus,
    summary: input.summary,
    safeErrorCode: input.safeErrorCode,
    validationCategory: input.validationCategory,
    retryable: input.retryable,
    retryAfterMs: input.retryAfterMs,
    correlationId: input.correlationId,
    timestamp: new Date().toISOString(),
    outerStatus: input.outerStatus,
  });
}

async function submitEvidenceCandidate(args, configuration, fetchFn = globalThis.fetch) {
  const input = exports.EvidenceCandidateArgsSchema.parse(args);
  if (!configuration?.allowedNamespaces?.includes(input.namespace)) {
    throw new Error(`Pandora Memory namespace is not allowed: ${input.namespace}`);
  }
  if (!configuration?.grantedScopes?.includes("memory:write")) {
    throw new Error("Pandora Memory write scope is not granted");
  }
  const reason = sensitiveReason(input);
  if (reason) {
    throw new Error(`Pandora Memory candidate rejected: ${reason}`);
  }
  if (typeof fetchFn !== "function") {
    throw new Error("Pandora Memory fetch transport is unavailable");
  }

  const origin = normalizeOrigin(configuration.baseUrl);
  const correlationId = randomUUID();
  const timeoutMs = boundedPositiveInteger(
    configuration.timeoutMs,
    DEFAULT_TIMEOUT_MS,
    MAX_TIMEOUT_MS,
  );
  const maxResponseBytes = boundedPositiveInteger(
    configuration.maxResponseBytes,
    MAX_RESPONSE_BYTES,
    MAX_RESPONSE_BYTES,
  );
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  const payload = {
    namespace: input.namespace,
    project_id: input.projectId ?? null,
    project_key: input.projectKey ?? null,
    title: input.title,
    summary: input.summary,
    proof_stage: input.proofStage,
    evidence_kind: input.evidenceKind,
    claim: input.claim,
    evidence_refs: input.evidenceRefs,
    provenance: input.provenance,
    idempotency_key: input.idempotencyKey,
  };

  try {
    let response;
    try {
      response = await fetchFn(`${origin}/api/projectos/memory/evidence-candidates`, {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: {
          "content-type": "application/json",
          "accept": "application/json",
          "x-pandora-vercel-oidc": configuration.oidcToken,
          "x-request-id": correlationId,
          // The strict JSON body remains unchanged. This bounded header and the
          // structured result/error envelope attest which privacy preflight ran.
          "x-pandora-privacy-scan-version": EVIDENCE_PRIVACY_SCAN_VERSION,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof MemoryEvidenceSubmissionError) throw error;
      throw submissionFailure({
        httpStatus: null,
        safeErrorCode: error instanceof Error && error.name === "AbortError"
          ? "provider_timeout"
          : "provider_transport_error",
        validationCategory: "transport",
        retryable: true,
        correlationId,
        outerStatus: 502,
      });
    }

    const resolvedCorrelationId = responseCorrelationId(response, correlationId);
    let text;
    try {
      text = await readBounded(response, maxResponseBytes);
    } catch {
      throw submissionFailure({
        httpStatus: Number.isInteger(response.status) ? response.status : null,
        safeErrorCode: "response_contract_error",
        validationCategory: "response_contract",
        retryable: retryableStatus(response.status),
        correlationId: resolvedCorrelationId,
        outerStatus: 502,
      });
    }

    let body = {};
    try {
      body = text ? JSON.parse(text) : {};
    } catch {
      throw submissionFailure({
        httpStatus: Number.isInteger(response.status) ? response.status : null,
        safeErrorCode: "response_contract_error",
        validationCategory: "response_contract",
        retryable: retryableStatus(response.status),
        correlationId: resolvedCorrelationId,
        outerStatus: 502,
      });
    }

    if (
      response.status === 409
      && body?.error === IDEMPOTENCY_CONFLICT_CODE
    ) {
      throw new MemoryEvidenceIdempotencyConflictError({
        correlationId: resolvedCorrelationId,
        timestamp: new Date().toISOString(),
      });
    }
    if (!response.ok || body?.ok === false) {
      const classified = safeBackendFailure(response.status, body);
      throw submissionFailure({
        httpStatus: response.status,
        ...classified,
        retryAfterMs: responseRetryAfterMs(response),
        correlationId: resolvedCorrelationId,
        outerStatus: classified.safeErrorCode === "response_contract_error"
          ? 502
          : normalizeOuterFailureStatus(response.status),
      });
    }
    const success = parseBoundSuccessResponse(response.status, body, input);
    if (!success) {
      throw submissionFailure({
        httpStatus: Number.isInteger(response.status) ? response.status : null,
        safeErrorCode: "response_contract_error",
        validationCategory: "response_contract",
        retryable: false,
        correlationId: resolvedCorrelationId,
        outerStatus: 502,
      });
    }

    return {
      ok: true,
      candidateId: success.candidate_id,
      reviewItemId: success.review_item_id,
      status: success.status,
      deduplicated: success.deduplicated,
      idempotencyKey: success.idempotency_key,
      namespace: success.namespace,
      projectId: success.project_id,
      projectKey: success.project_key,
      proofStage: success.proof_stage,
      evidenceKind: success.evidence_kind,
      createdAt: success.created_at,
      privacyPolicy: success.privacy_policy,
      privacyScanVersion: EVIDENCE_PRIVACY_SCAN_VERSION,
      canonicalPromoted: success.canonical_memory_written,
    };
  } finally {
    clearTimeout(timeout);
  }
}
