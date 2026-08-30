
import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const MAX_BODY_BYTES = 24 * 1024;

type JsonRecord = Record<string, unknown>;
type UntypedClient = SupabaseClient<any, "public", "public", any, any>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const REVIEWER = /^[a-z0-9][a-z0-9._:-]{2,127}$/;
const NONCE = /^[A-Za-z0-9._:-]{16,128}$/;
const SIGNATURE_B64 = /^[A-Za-z0-9+/]{86}==$/;
const TIMESTAMP = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function requiredText(value: unknown, field: string) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`INVALID_${field.toUpperCase()}`);
  return value.trim();
}

function authorityBearer(request: Request) {
  const authorization = request.headers.get("authorization") || "";
  if (!/^Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i.test(authorization)) {
    throw new Error("REVIEW_AUTH_INVALID");
  }
  return authorization.replace(/^Bearer\s+/i, "");
}

async function readBody(request: Request) {
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new Error("BODY_TOO_LARGE");
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
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - value.length % 4) % 4);
  return decodeBase64(base64);
}

async function sha256Hex(value: string | Uint8Array) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    typeof value === "string" ? new TextEncoder().encode(value) : value,
  );
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function validateAuthorityJwt(
  token: string,
  expected: { scopeKey: string; reviewerId: string; requestSha256: string },
  nowSeconds = Date.now() / 1000,
) {
  try {
    const segments = token.split(".");
    if (segments.length !== 3 || segments.some((segment) => !segment)) throw new Error("invalid");
    const claims = asRecord(JSON.parse(new TextDecoder().decode(decodeBase64Url(segments[1]))));
    if (
      claims.role !== "projectos_reviewer_ingest" ||
      claims.iss !== "pandora-independent-review-authority" ||
      claims.pandora_audience !== "pandora-intelligence-certification" ||
      claims.pandora_purpose !== "intelligence_asset_certification" ||
      claims.pandora_scope_key !== expected.scopeKey ||
      String(claims.pandora_reviewer_id || "").toLowerCase() !== expected.reviewerId ||
      claims.pandora_request_sha256 !== expected.requestSha256 ||
      typeof claims.jti !== "string" || !/^[A-Za-z0-9._:-]{16,128}$/.test(claims.jti) ||
      typeof claims.iat !== "number" || !Number.isSafeInteger(claims.iat) ||
      typeof claims.nbf !== "number" || !Number.isSafeInteger(claims.nbf) ||
      typeof claims.exp !== "number" || !Number.isSafeInteger(claims.exp) ||
      claims.iat < nowSeconds - 120 || claims.iat > nowSeconds + 30 ||
      claims.nbf < claims.iat - 5 || claims.nbf > nowSeconds + 30 ||
      claims.exp <= nowSeconds || claims.exp > nowSeconds + 120 ||
      claims.exp - claims.iat > 120
    ) throw new Error("invalid");
    return claims;
  } catch {
    throw new Error("REVIEW_AUTH_INVALID");
  }
}

async function verifyEd25519(publicKeyB64: string, signatureB64: string, basis: string) {
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

function serviceClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function reviewerClient(token: string) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { authorization: `Bearer ${token}` } },
  });
}

async function rpc(client: UntypedClient, name: string, args: JsonRecord, code: string) {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(code);
  return result.data;
}

function validatedBody(body: JsonRecord) {
  const allowed = new Set([
    "assetId", "reviewerId", "evidenceId", "sourceDigestSha256", "contentDigestSha256",
    "requestSha256", "nonce", "timestamp", "signatureB64", "assetExpiresAt",
  ]);
  if (Object.keys(body).some((key) => !allowed.has(key))) throw new Error("UNKNOWN_FIELD");
  const assetId = requiredText(body.assetId, "asset_id").toLowerCase();
  const reviewerId = requiredText(body.reviewerId, "reviewer_id").toLowerCase();
  const evidenceId = requiredText(body.evidenceId, "evidence_id");
  const sourceDigestSha256 = requiredText(body.sourceDigestSha256, "source_digest").toLowerCase();
  const contentDigestSha256 = body.contentDigestSha256 == null
    ? null
    : requiredText(body.contentDigestSha256, "content_digest").toLowerCase();
  const requestSha256 = requiredText(body.requestSha256, "request_sha256").toLowerCase();
  const nonce = requiredText(body.nonce, "nonce");
  const timestamp = requiredText(body.timestamp, "timestamp");
  const signatureB64 = requiredText(body.signatureB64, "signature");
  const assetExpiresAt = body.assetExpiresAt == null ? null : requiredText(body.assetExpiresAt, "asset_expires_at");
  if (!UUID.test(assetId) || !REVIEWER.test(reviewerId) || evidenceId.length > 240 ||
      !SHA256.test(sourceDigestSha256) || (contentDigestSha256 !== null && !SHA256.test(contentDigestSha256)) ||
      !SHA256.test(requestSha256) || !NONCE.test(nonce) || !TIMESTAMP.test(timestamp) || !SIGNATURE_B64.test(signatureB64)) {
    throw new Error("INVALID_REVIEW_REQUEST");
  }
  const signedAt = Date.parse(timestamp);
  if (!Number.isFinite(signedAt) || Math.abs(Date.now() - signedAt) > 300_000) throw new Error("STALE_REVIEW_SIGNATURE");
  if (assetExpiresAt !== null) {
    const expires = Date.parse(assetExpiresAt);
    if (!Number.isFinite(expires) || expires <= Date.now() || expires > Date.now() + 90 * 24 * 60 * 60 * 1000) {
      throw new Error("INVALID_ASSET_EXPIRY");
    }
  }
  return { assetId, reviewerId, evidenceId, sourceDigestSha256, contentDigestSha256, requestSha256, nonce, timestamp, signatureB64, assetExpiresAt };
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const token = authorityBearer(request);
    const input = validatedBody(await readBody(request));
    const service = serviceClient();
    const target = asRecord(await rpc(service, "pandora_resolve_intelligence_review_target", {
      p_asset_id: input.assetId,
      p_reviewer_id: input.reviewerId,
    }, "REVIEW_TARGET_UNAVAILABLE"));

    const scopeKey = requiredText(target.scopeKey, "scope_key");
    const targetSource = requiredText(target.sourceDigestSha256, "target_source").toLowerCase();
    const targetContent = target.contentDigestSha256 == null ? null : String(target.contentDigestSha256).toLowerCase();
    const publicKeyB64 = requiredText(target.reviewerPublicKeyB64, "reviewer_public_key");
    const keyFingerprint = requiredText(target.reviewerKeyFingerprint, "reviewer_key_fingerprint").toLowerCase();
    if (targetSource !== input.sourceDigestSha256 || targetContent !== input.contentDigestSha256) {
      throw new Error("REVIEW_TARGET_DIGEST_MISMATCH");
    }

    const requestBasis = [
      "pandora:intelligence-certify:v1", input.assetId, input.sourceDigestSha256,
      input.contentDigestSha256 ?? "-", input.evidenceId, input.reviewerId, scopeKey,
    ].join("\n");
    const expectedRequestSha = await sha256Hex(requestBasis);
    if (expectedRequestSha !== input.requestSha256) throw new Error("REVIEW_REQUEST_DIGEST_MISMATCH");
    validateAuthorityJwt(token, { scopeKey, reviewerId: input.reviewerId, requestSha256: expectedRequestSha });

    const signatureBasis = [
      "pandora-intelligence-review-v1", input.assetId, input.sourceDigestSha256,
      input.contentDigestSha256 ?? "-", input.evidenceId, input.reviewerId, scopeKey,
      input.nonce, input.timestamp,
    ].join("\n");
    const signatureBasisSha256 = await sha256Hex(signatureBasis);
    if (!await verifyEd25519(publicKeyB64, input.signatureB64, signatureBasis)) {
      throw new Error("REVIEW_SIGNATURE_INVALID");
    }
    if (await sha256Hex(decodeBase64(publicKeyB64)) !== keyFingerprint) {
      throw new Error("REVIEWER_KEY_FINGERPRINT_MISMATCH");
    }

    const attestation = asRecord(await rpc(service, "pandora_record_intelligence_review_attestation", {
      p_asset_id: input.assetId,
      p_reviewer_id: input.reviewerId,
      p_evidence_id: input.evidenceId,
      p_source_digest_sha256: input.sourceDigestSha256,
      p_content_digest_sha256: input.contentDigestSha256,
      p_request_sha256: expectedRequestSha,
      p_nonce: input.nonce,
      p_timestamp: input.timestamp,
      p_signature_b64: input.signatureB64,
      p_signature_basis_sha256: signatureBasisSha256,
    }, "REVIEW_ATTESTATION_WRITE_FAILED"));
    const attestationId = requiredText(attestation.attestationId, "attestation_id");

    const finalized = asRecord(await rpc(reviewerClient(token), "pandora_finalize_intelligence_review_attestation", {
      p_attestation_id: attestationId,
      p_request_sha256: expectedRequestSha,
      p_asset_expires_at: input.assetExpiresAt,
    }, "REVIEW_FINALIZATION_FAILED"));

    return jsonResponse({
      ok: true,
      assetId: finalized.assetId ?? input.assetId,
      attestationId,
      trustState: finalized.trustState ?? "TRUSTED",
      verificationWorker: "E",
      verificationVerdict: "PASS",
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "REVIEW_GATEWAY_FAILED";
    const status = code.includes("AUTH") || code.includes("GRANT") || code.includes("SIGNATURE") ? 403 :
      code.includes("INVALID") || code.includes("DIGEST") || code.includes("STALE") || code === "UNKNOWN_FIELD" ? 400 : 409;
    return jsonResponse({ error: code }, status);
  }
});
