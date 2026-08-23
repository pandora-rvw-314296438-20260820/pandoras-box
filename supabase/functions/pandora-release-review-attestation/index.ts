import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";
import {
  releaseReviewAuthorityBasis,
  releaseReviewSignatureBasis,
  validateReleaseReviewRequest,
} from "./contract.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_BODY_BYTES = 32 * 1024;

type JsonRecord = Record<string, unknown>;
type UntypedSupabaseClient = SupabaseClient<any, "public", "public", any, any>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function authorityBearer(request: Request) {
  const authorization = request.headers.get("authorization") || "";
  if (!/^Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i.test(
    authorization,
  )) {
    throw new Error("REVIEWER_INGEST_AUTH_INVALID");
  }
  return authorization.replace(/^Bearer\s+/i, "");
}

function response(
  body: unknown,
  status = 200,
  additionalHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
      ...additionalHeaders,
    },
  });
}

async function readBody(request: Request) {
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    throw new Error("BODY_TOO_LARGE");
  }
  const reader = request.body?.getReader();
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
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid");
    return parsed as JsonRecord;
  } catch {
    throw new Error("INVALID_JSON");
  }
}

function decodeBase64(value: string) {
  const decoded = atob(value);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function decodeBase64Url(value: string) {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return decodeBase64(base64);
}

function validateReviewerIngestJwt(
  value: string,
  expected: {
    organizationId: unknown;
    purpose: string;
    requestSha256?: string;
    reviewerId: unknown;
  },
  nowSeconds = Date.now() / 1000,
) {
  try {
    const segments = value.split(".");
    if (segments.length !== 3 || segments.some((segment) => !segment)) {
      throw new Error("invalid");
    }
    const claims = asRecord(JSON.parse(
      new TextDecoder().decode(decodeBase64Url(segments[1])),
    ));
    if (
      claims.role !== "projectos_reviewer_ingest" ||
      claims.iss !== "pandora-independent-review-authority" ||
      claims.pandora_audience !== "projectos-reviewer-ingest" ||
      claims.pandora_purpose !== expected.purpose ||
      claims.pandora_organization_id !== expected.organizationId ||
      claims.pandora_reviewer_id !== expected.reviewerId ||
      (expected.requestSha256 !== undefined &&
        claims.pandora_request_sha256 !== expected.requestSha256) ||
      typeof claims.jti !== "string" ||
      !/^[A-Za-z0-9._:-]{16,128}$/.test(claims.jti) ||
      typeof claims.iat !== "number" || !Number.isSafeInteger(claims.iat) ||
      typeof claims.nbf !== "number" || !Number.isSafeInteger(claims.nbf) ||
      typeof claims.exp !== "number" || !Number.isSafeInteger(claims.exp) ||
      claims.iat < nowSeconds - 120 || claims.iat > nowSeconds + 30 ||
      claims.nbf < claims.iat - 5 || claims.nbf > nowSeconds + 30 ||
      claims.exp <= nowSeconds || claims.exp > nowSeconds + 120 ||
      claims.exp - claims.iat > 120
    ) {
      throw new Error("invalid");
    }
    return value;
  } catch {
    throw new Error("REVIEWER_INGEST_AUTH_INVALID");
  }
}

async function sha256Hex(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyReviewerSignature(
  publicKeyB64: string,
  signatureB64: string,
  basis: string,
) {
  try {
    const publicKey = await crypto.subtle.importKey(
      "raw",
      decodeBase64(publicKeyB64),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      { name: "Ed25519" },
      publicKey,
      decodeBase64(signatureB64),
      new TextEncoder().encode(basis),
    );
  } catch {
    return false;
  }
}

function rpcClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function reviewerIngestClient(
  token: string,
  expected: {
    organizationId: unknown;
    purpose: string;
    requestSha256: string;
    reviewerId: unknown;
  },
  nowSeconds = Date.now() / 1000,
) {
  const validatedToken = validateReviewerIngestJwt(token, expected, nowSeconds);
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${validatedToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
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

async function authenticateReviewer(
  client: UntypedSupabaseClient,
  request: JsonRecord,
  signatureBasis: string,
) {
  const identity = asRecord(await rpc(
    client,
    "resolve_compute_reviewer_identity",
    {
      p_organization_id: request.organizationId,
      p_reviewer_id: request.reviewerId,
    },
    "REVIEWER_IDENTITY_READ_FAILED",
  ));
  if (!identity.reviewerId || identity.reviewerId !== request.reviewerId) {
    throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  }
  const keyFingerprint = String(identity.keyFingerprint || "");
  if (!/^[0-9a-f]{64}$/.test(keyFingerprint)) throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  if (identity.runtimeProofId !== request.verifierRuntimeProofId ||
    !Array.isArray(identity.allowedRepositories) ||
    !identity.allowedRepositories.includes(request.repository)) {
    throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  }
  const publicKeyB64 = String(identity.publicKeyB64 || "");
  if (!await verifyReviewerSignature(
    publicKeyB64,
    String(request.signatureB64 || ""),
    signatureBasis,
  )) {
    throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  }
  const computedFingerprint = await sha256Hex(decodeBase64(publicKeyB64));
  if (computedFingerprint !== keyFingerprint) throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  return keyFingerprint;
}

async function consumeAuthenticatedRateLimit(
  client: UntypedSupabaseClient,
  organizationId: unknown,
  reviewerId: unknown,
) {
  const keyHash = await sha256Hex(
    `pandora-release-review-attestation:v1:${String(reviewerId || "")}`,
  );
  const result = asRecord(await rpc(client, "consume_runtime_rate_limit", {
    p_organization_id: organizationId,
    p_key_hash: keyHash,
    p_limit: 20,
    p_window_seconds: 60,
  }, "RATE_LIMIT_CONTROL_UNAVAILABLE"));
  if (result.allowed !== true) throw new Error("RATE_LIMITED");
}

async function attest(raw: JsonRecord, reviewerAuthorityToken: string) {
  const request = validateReleaseReviewRequest(raw);
  const client = rpcClient();
  validateReviewerIngestJwt(reviewerAuthorityToken, {
    organizationId: request.organizationId,
    purpose: "release_review",
    reviewerId: request.reviewerId,
  });
  await consumeAuthenticatedRateLimit(
    client,
    request.organizationId,
    "organization",
  );
  let keyFingerprint: string;
  try {
    keyFingerprint = await authenticateReviewer(
      client,
      request,
      releaseReviewSignatureBasis(request),
    );
  } catch (error) {
    if (error instanceof Error && error.message === "REVIEWER_IDENTITY_READ_FAILED") {
      throw error;
    }
    throw new Error("REVIEWER_AUTHENTICATION_FAILED");
  }
  await consumeAuthenticatedRateLimit(
    client,
    request.organizationId,
    request.reviewerId,
  );
  const signatureSha256 = await sha256Hex(
    decodeBase64(String(request.signatureB64)),
  );
  const authorityRequestSha256 = await sha256Hex(releaseReviewAuthorityBasis(
    request,
    keyFingerprint,
    signatureSha256,
  ));
  const reviewReceipt = asRecord(await rpc(
    reviewerIngestClient(reviewerAuthorityToken, {
      organizationId: request.organizationId,
      purpose: "release_review",
      requestSha256: authorityRequestSha256,
      reviewerId: request.reviewerId,
    }),
    "capture_canonical_release_review_receipt",
    {
      p_organization_id: request.organizationId,
      p_request_id: request.requestId,
      p_repository: request.repository,
      p_source_sha: request.sourceSha,
      p_source_tree_sha: request.sourceTreeSha,
      p_production_deployment_id: request.productionDeploymentId,
      p_rollback_deployment_id: request.rollbackDeploymentId,
      p_supabase_migration_chain_sha256: request.supabaseMigrationChainSha256,
      p_reviewer_id: request.reviewerId,
      p_verifier_runtime_proof_id: request.verifierRuntimeProofId,
      p_reviewer_key_fingerprint: keyFingerprint,
      p_review_external_id: request.reviewExternalId,
      p_review_source_url: request.reviewSourceUrl,
      p_review_digest: request.reviewDigest,
      p_signature_b64: request.signatureB64,
      p_signature_sha256: signatureSha256,
      p_request_nonce: request.nonce,
      p_reviewed_at: request.timestamp,
    },
    "RELEASE_REVIEW_RECEIPT_REJECTED",
  ));
  if (reviewReceipt.verified !== true ||
    reviewReceipt.authority !== "INDEPENDENT_REVIEWER" ||
    reviewReceipt.sourceSha !== request.sourceSha ||
    reviewReceipt.sourceTreeSha !== request.sourceTreeSha ||
    reviewReceipt.productionDeploymentId !== request.productionDeploymentId ||
    reviewReceipt.rollbackDeploymentId !== request.rollbackDeploymentId ||
    reviewReceipt.supabaseMigrationChainSha256 !== request.supabaseMigrationChainSha256 ||
    reviewReceipt.reviewerKeyFingerprint !== keyFingerprint ||
    reviewReceipt.reviewDigest !== request.reviewDigest ||
    !/^[0-9a-f]{64}$/.test(String(reviewReceipt.receiptSha256 || ""))) {
    throw new Error("RELEASE_REVIEW_READBACK_MISMATCH");
  }
  return { ok: true, reviewReceipt };
}

Deno.serve(async (request: Request) => {
  if (request.headers.get("origin")) {
    return response({ ok: false, error: { code: "BROWSER_ORIGIN_REJECTED" } }, 403);
  }
  if (request.method !== "POST") {
    return response({ ok: false, error: { code: "METHOD_NOT_ALLOWED" } }, 405);
  }
  try {
    // The Supabase gateway has already verified this exact external JWT.
    // The same bearer is forwarded unchanged to PostgREST for atomic JTI use.
    const reviewerAuthorityToken = authorityBearer(request);
    return response(await attest(await readBody(request), reviewerAuthorityToken));
  } catch (error) {
    const code = error instanceof Error ? error.message : "RELEASE_REVIEW_GATEWAY_ERROR";
    const status = code === "REVIEWER_AUTHENTICATION_FAILED" ||
        code === "REVIEWER_INGEST_AUTH_INVALID"
      ? 401
      : code === "RATE_LIMITED"
      ? 429
      : code.includes("NONCE") || code.includes("MISMATCH") || code.includes("REJECTED")
      ? 409
      : code.includes("INVALID") || code === "BODY_TOO_LARGE"
      ? 400
      : 503;
    return response(
      { ok: false, error: { code } },
      status,
      status === 429 ? { "retry-after": "60" } : {},
    );
  }
});
