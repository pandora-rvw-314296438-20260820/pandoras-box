import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";
import {
  jobDigest,
  resultEvidenceHash,
  validateClaimRequest,
  validateCompleteRequest,
  validateJobPayload,
  workerAuthorityRequestHash,
} from "./contract.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const WORKER_JOB_AUTHORITY_URL =
  Deno.env.get("PANDORA_WORKER_JOB_AUTHORITY_URL") || "";
const MAX_BODY_BYTES = 64 * 1024;
const MAX_AUTHORITY_RESPONSE_BYTES = 16 * 1024;

type JsonRecord = Record<string, unknown>;
type UntypedSupabaseClient = SupabaseClient<
  any,
  "public",
  "public",
  any,
  any
>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function exactKeys(value: JsonRecord, expected: string[]) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((entry, index) => entry === wanted[index]);
}

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

async function readBody(req: Request) {
  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    throw new Error("BODY_TOO_LARGE");
  }
  const reader = req.body?.getReader();
  if (!reader) throw new Error("INVALID_JSON");
  const chunks: Uint8Array[] = [];
  let received = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    received += value.byteLength;
    if (received > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new Error("BODY_TOO_LARGE");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const decoded = JSON.parse(new TextDecoder().decode(bytes));
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      throw new Error("INVALID_JSON");
    }
    return decoded as JsonRecord;
  } catch {
    throw new Error("INVALID_JSON");
  }
}

function bearer(req: Request) {
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i.test(
    authorization,
  )) {
    throw new Error("WORKER_AUTHORITY_REQUIRED");
  }
  return authorization.replace(/^Bearer\s+/i, "");
}

function jwtClaims(token: string) {
  try {
    const segment = token.split(".")[1];
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
    return asRecord(JSON.parse(atob(padded)));
  } catch {
    throw new Error("WORKER_AUTHORITY_REQUIRED");
  }
}

function exactAuthorityClaims(
  claims: JsonRecord,
  purpose: "worker_claim" | "worker_complete",
  request: JsonRecord,
  requestSha256: string,
) {
  const workerKeyFingerprint = String(claims.worker_key_fingerprint || "");
  const dispatchId = purpose === "worker_complete"
    ? String(request.dispatchId || "")
    : "";
  const planId = purpose === "worker_complete" ? String(request.planId || "") : "";
  if (
    claims.role !== "projectos_worker_ingest" ||
    claims.iss !== "pandora-independent-worker-authority" ||
    claims.aud !== "projectos_worker_ingest" ||
    claims.purpose !== purpose ||
    claims.sub !== request.requestId ||
    claims.organization_id !== request.organizationId ||
    claims.worker_id !== request.workerId ||
    !/^[0-9a-f]{64}$/.test(workerKeyFingerprint) ||
    claims.request_id !== request.requestId ||
    String(claims.dispatch_id || "") !== dispatchId ||
    String(claims.plan_id || "") !== planId ||
    claims.request_sha256 !== requestSha256 ||
    !/^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$/.test(String(claims.jti || ""))
  ) {
    throw new Error("WORKER_AUTHORITY_MISMATCH");
  }
  return workerKeyFingerprint;
}

function rpcClient(token: string) {
  if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/i.test(SUPABASE_URL) ||
      !/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(
        SUPABASE_ANON_KEY,
      )) {
    throw new Error("WORKER_DATABASE_CONFIGURATION_UNAVAILABLE");
  }
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

async function rpc(
  client: UntypedSupabaseClient,
  name: string,
  args: JsonRecord,
  code: string,
) {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(code);
  return result.data;
}

function runnerConfiguration() {
  const runnerPolicyHash = Deno.env.get("PANDORA_WORKER_RUNNER_POLICY_SHA256") || "";
  const runnerImageDigest = Deno.env.get("PANDORA_WORKER_RUNNER_IMAGE_DIGEST") || "";
  const acquisitionImageDigest =
    Deno.env.get("PANDORA_WORKER_ACQUISITION_IMAGE_DIGEST") || "";
  if (
    !/^[0-9a-f]{64}$/.test(runnerPolicyHash) ||
    !/^sha256:[0-9a-f]{64}$/.test(runnerImageDigest) ||
    !/^sha256:[0-9a-f]{64}$/.test(acquisitionImageDigest)
  ) {
    throw new Error("PINNED_RUNNER_CONFIGURATION_UNAVAILABLE");
  }
  return { runnerPolicyHash, runnerImageDigest, acquisitionImageDigest };
}

function jobAuthorityUrl() {
  let parsed: URL;
  try {
    parsed = new URL(WORKER_JOB_AUTHORITY_URL);
  } catch {
    throw new Error("EXTERNAL_JOB_AUTHORITY_UNAVAILABLE");
  }
  if (
    parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.hash ||
    /(?:^|\.)supabase\.co$/i.test(parsed.hostname) ||
    /(?:^|\.)vercel\.(?:app|com)$/i.test(parsed.hostname)
  ) {
    throw new Error("EXTERNAL_JOB_AUTHORITY_UNAVAILABLE");
  }
  return parsed.toString();
}

async function externalJobSignature(
  authorityToken: string,
  request: JsonRecord,
  workerKeyFingerprint: string,
  payload: JsonRecord,
  digest: string,
) {
  const authorityResponse = await fetch(jobAuthorityUrl(), {
    method: "POST",
    headers: {
      authorization: `Bearer ${authorityToken}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      schemaVersion: 1,
      purpose: "worker_job",
      organizationId: request.organizationId,
      workerId: request.workerId,
      workerKeyFingerprint,
      claimRequestId: request.requestId,
      dispatchId: payload.dispatchId,
      planId: payload.planId,
      jobDigest: digest,
      jobPayload: payload,
    }),
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  const declared = Number(authorityResponse.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_AUTHORITY_RESPONSE_BYTES) {
    throw new Error("EXTERNAL_JOB_AUTHORITY_REJECTED");
  }
  const text = await authorityResponse.text();
  if (new TextEncoder().encode(text).byteLength > MAX_AUTHORITY_RESPONSE_BYTES) {
    throw new Error("EXTERNAL_JOB_AUTHORITY_REJECTED");
  }
  let decoded: JsonRecord;
  try {
    decoded = asRecord(JSON.parse(text));
  } catch {
    throw new Error("EXTERNAL_JOB_AUTHORITY_REJECTED");
  }
  if (
    !authorityResponse.ok ||
    !exactKeys(decoded, ["jobSignatureB64", "schemaVersion"]) ||
    decoded.schemaVersion !== 1 ||
    !/^[A-Za-z0-9+/]{86}==$/.test(String(decoded.jobSignatureB64 || ""))
  ) {
    throw new Error("EXTERNAL_JOB_AUTHORITY_REJECTED");
  }
  return String(decoded.jobSignatureB64);
}

async function claim(body: JsonRecord, token: string, claims: JsonRecord) {
  const request = validateClaimRequest(body);
  const keyFingerprint = String(claims.worker_key_fingerprint || "");
  const requestSha256 = await workerAuthorityRequestHash(
    "worker_claim",
    request,
    keyFingerprint,
  );
  exactAuthorityClaims(claims, "worker_claim", request, requestSha256);
  const client = rpcClient(token);
  const claimed = asRecord(await rpc(
    client,
    "claim_governed_worker_dispatch_authorized",
    {
      p_organization_id: request.organizationId,
      p_worker_identity: request.workerId,
      p_expected_key_fingerprint: keyFingerprint,
      p_request_id: request.requestId,
      p_nonce: request.nonce,
      p_timestamp: request.timestamp,
      p_signature_b64: request.signatureB64,
    },
    "WORKER_DISPATCH_CLAIM_REJECTED",
  ));
  if (!Object.keys(claimed).length) return { ok: true, job: null };

  if (claimed.status === "envelope_ready") {
    const payload = validateJobPayload(asRecord(claimed.jobPayload));
    const digest = await jobDigest(payload);
    if (
      digest !== claimed.jobDigest ||
      !/^[A-Za-z0-9+/]{86}==$/.test(String(claimed.jobSignature || ""))
    ) {
      throw new Error("STORED_JOB_ENVELOPE_MISMATCH");
    }
    return {
      ok: true,
      job: {
        digest,
        payload,
        signatureB64: claimed.jobSignature,
        redelivery: true,
      },
    };
  }

  const now = new Date();
  const payload = validateJobPayload({
    schemaVersion: 1,
    audience: `pandora-worker:${request.workerId}`,
    organizationId: claimed.organizationId,
    dispatchId: claimed.dispatchId,
    planId: claimed.planId,
    repository: claimed.repository,
    exactSha: claimed.exactSha,
    jobClass: claimed.jobClass,
    maxRuntimeSeconds: claimed.maxRuntimeSeconds,
    issuedAt: now.toISOString(),
    expiresAt: claimed.leaseExpiresAt,
    ...runnerConfiguration(),
    networkPolicy: "none",
    isolation: "hyperv_container",
    productionMutationAllowed: false,
  });
  const digest = await jobDigest(payload);
  const signatureB64 = await externalJobSignature(
    token,
    request,
    keyFingerprint,
    payload,
    digest,
  );
  const recorded = asRecord(await rpc(
    client,
    "record_governed_worker_job_envelope_authorized",
    {
      p_organization_id: request.organizationId,
      p_dispatch_id: claimed.dispatchId,
      p_plan_id: claimed.planId,
      p_worker_identity: request.workerId,
      p_expected_key_fingerprint: keyFingerprint,
      p_job_digest: digest,
      p_job_payload: payload,
      p_job_signature: signatureB64,
    },
    "WORKER_JOB_ENVELOPE_REJECTED",
  ));
  if (recorded.jobDigest !== digest || recorded.status !== "envelope_ready") {
    throw new Error("WORKER_JOB_ENVELOPE_READBACK_MISMATCH");
  }
  return { ok: true, job: { digest, payload, signatureB64, redelivery: false } };
}

async function complete(body: JsonRecord, token: string, claims: JsonRecord) {
  // A fresh exact-request authority token may replay a previously persisted
  // signed completion after a lost response. SQL permits stale timestamps only
  // when every stored completion field already matches.
  const request = validateCompleteRequest(body, new Date(), true);
  const computedEvidence = await resultEvidenceHash(request.resultSummary);
  if (computedEvidence !== request.evidenceSha256) {
    throw new Error("WORKER_EVIDENCE_HASH_MISMATCH");
  }
  const keyFingerprint = String(claims.worker_key_fingerprint || "");
  const requestSha256 = await workerAuthorityRequestHash(
    "worker_complete",
    request,
    keyFingerprint,
  );
  exactAuthorityClaims(claims, "worker_complete", request, requestSha256);
  const client = rpcClient(token);
  const completion = asRecord(await rpc(
    client,
    "finish_governed_worker_dispatch_authorized",
    {
      p_organization_id: request.organizationId,
      p_dispatch_id: request.dispatchId,
      p_plan_id: request.planId,
      p_worker_identity: request.workerId,
      p_expected_key_fingerprint: keyFingerprint,
      p_outcome: request.outcome,
      p_duration_ms: request.durationMs,
      p_job_digest: request.jobDigest,
      p_evidence_sha256: request.evidenceSha256,
      p_result_summary: request.resultSummary,
      p_request_id: request.requestId,
      p_nonce: request.nonce,
      p_timestamp: request.timestamp,
      p_signature_b64: request.signatureB64,
    },
    "WORKER_COMPLETION_REJECTED",
  ));
  return { ok: true, completion };
}

Deno.serve(async (req: Request) => {
  if (req.headers.get("origin")) {
    return response({ ok: false, error: { code: "BROWSER_ORIGIN_REJECTED" } }, 403);
  }
  if (req.method !== "POST") {
    return response({ ok: false, error: { code: "METHOD_NOT_ALLOWED" } }, 405);
  }
  try {
    const token = bearer(req);
    const claims = jwtClaims(token);
    const body = await readBody(req);
    if (body.action === "claim") return response(await claim(body, token, claims));
    if (body.action === "complete") {
      return response(await complete(body, token, claims));
    }
    return response({ ok: false, error: { code: "ACTION_NOT_ALLOWED" } }, 400);
  } catch (error) {
    const code = error instanceof Error ? error.message : "WORKER_GATEWAY_ERROR";
    const status = code === "BODY_TOO_LARGE" || code.startsWith("INVALID_")
      ? 400
      : code.includes("AUTHORITY")
      ? 401
      : code.includes("MISMATCH") || code.includes("REJECTED")
      ? 409
      : 503;
    return response({
      ok: false,
      error: {
        code,
        message: status === 503
          ? "The governed worker gateway is unavailable."
          : "The governed worker request was rejected.",
      },
    }, status);
  }
});
