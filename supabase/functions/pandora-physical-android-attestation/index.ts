import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";
import {
  physicalAndroidReceiptSignatureBasis,
  validatePhysicalAndroidReceiptRequest,
} from "./contract.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const MAX_BODY_BYTES = 32 * 1024;
const EXTERNAL_AUTHORITY_ISSUER = "pandora-physical-android-authority-v1";

type JsonRecord = Record<string, unknown>;
type UntypedSupabaseClient = SupabaseClient<any, "public", "public", any, any>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
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

async function readBody(request: Request) {
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    throw new Error("BODY_TOO_LARGE");
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_BODY_BYTES) {
    throw new Error(bytes.byteLength ? "BODY_TOO_LARGE" : "INVALID_JSON");
  }
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as JsonRecord;
  } catch {
    throw new Error("INVALID_JSON");
  }
}

function decodeBase64Url(value: string) {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  const decoded = atob(base64);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function externallyAuthorizedBearer(request: Request, body: JsonRecord) {
  const authorization = request.headers.get("authorization") || "";
  if (!/^Bearer [A-Za-z0-9._~-]+$/.test(authorization)) {
    throw new Error("OBSERVER_AUTH_FAILED");
  }
  try {
    const token = authorization.slice("Bearer ".length);
    const segments = token.split(".");
    if (segments.length !== 3 || segments.some((segment) => !segment)) {
      throw new Error("invalid");
    }
    // The Supabase gateway and PostgREST validate the JWT signature. This
    // decode is only an early exact-purpose check; the DB rechecks every claim
    // and atomically consumes issuer+jti.
    const claims = asRecord(JSON.parse(
      new TextDecoder().decode(decodeBase64Url(segments[1])),
    ));
    if (
      claims.role !== "projectos_physical_android_ingest" ||
      claims.iss !== EXTERNAL_AUTHORITY_ISSUER ||
      claims.aud !== "projectos_physical_android_ingest" ||
      claims.purpose !== "canonical_physical_android_capture" ||
      claims.organization_id !== body.organizationId ||
      claims.observer_id !== body.observerId ||
      claims.observer_key_fingerprint !== body.observerKeyFingerprint ||
      claims.request_id !== body.requestId ||
      claims.network !== body.network ||
      claims.provider_observation_index !== body.providerObservationIndex ||
      claims.device_id_hash !== body.deviceIdHash
    ) {
      throw new Error("OBSERVER_AUTH_FAILED");
    }
    return authorization;
  } catch {
    throw new Error("OBSERVER_AUTH_FAILED");
  }
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function authorityClient(authorization: string) {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("PHYSICAL_ANDROID_GATEWAY_UNAVAILABLE");
  }
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { authorization } },
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

async function capture(request: Request, raw: JsonRecord) {
  const body = validatePhysicalAndroidReceiptRequest(raw);
  const authorization = externallyAuthorizedBearer(request, body);
  const signatureBasis = physicalAndroidReceiptSignatureBasis(body);
  // This is a separate RPC/transaction so the organization+purpose counter
  // remains durable even when the later identity or receipt checks reject.
  const client = authorityClient(authorization);
  const rate = asRecord(await rpc(
    client,
    "consume_physical_android_authority_rate_limit",
    { p_organization_id: body.organizationId },
    "OBSERVER_AUTH_FAILED",
  ));
  if (rate.allowed !== true) throw new Error("RATE_LIMITED");
  const receipt = asRecord(await rpc(
    client,
    "capture_canonical_physical_android_receipt",
    {
      p_organization_id: body.organizationId,
      p_request_id: body.requestId,
      p_observer_id: body.observerId,
      p_observer_key_fingerprint: body.observerKeyFingerprint,
      p_repository: body.repository,
      p_source_sha: body.sourceSha,
      p_source_tree_sha: body.sourceTreeSha,
      p_production_deployment_id: body.productionDeploymentId,
      p_production_origin: body.productionOrigin,
      p_ci_artifact_external_id: body.ciArtifactExternalId,
      p_ci_artifact_url: body.ciArtifactUrl,
      p_ci_artifact_name: body.ciArtifactName,
      p_ci_artifact_sha256: body.ciArtifactSha256,
      p_apk_sha256: body.apkSha256,
      p_device_id_hash: body.deviceIdHash,
      p_package_name: body.packageName,
      p_network: body.network,
      p_completed_steps: body.completedSteps,
      p_owner_plan_id: body.ownerPlanId,
      p_owner_dispatch_id: body.ownerDispatchId,
      p_worker_evidence_sha256: body.workerEvidenceSha256,
      p_verification_evidence_id: body.verificationEvidenceId,
      p_reviewer_runtime_proof_id: body.reviewerRuntimeProofId,
      p_nonce: body.nonce,
      p_timestamp: body.timestamp,
      p_signature_b64: body.signatureB64,
      p_signature_basis_sha256: await sha256Hex(signatureBasis),
    },
    "OBSERVER_AUTH_FAILED",
  ));
  if (
    receipt.verified !== true ||
    receipt.authority !== "PHYSICAL_ANDROID_OBSERVER" ||
    receipt.storageAuthority !== "IMMUTABLE_PHYSICAL_ANDROID_RECEIPT" ||
    receipt.network !== body.network ||
    receipt.providerObservationIndex !== body.providerObservationIndex ||
    typeof receipt.receiptId !== "string" ||
    !/^[0-9a-f]{64}$/.test(String(receipt.receiptSha256 || ""))
  ) {
    throw new Error("PHYSICAL_ANDROID_RECEIPT_READBACK_MISMATCH");
  }
  return { ok: true, receipt };
}

Deno.serve(async (request: Request) => {
  if (request.headers.get("origin")) {
    return response({ ok: false, error: { code: "BROWSER_ORIGIN_REJECTED" } }, 403);
  }
  if (request.method !== "POST") {
    return response({ ok: false, error: { code: "METHOD_NOT_ALLOWED" } }, 405);
  }
  try {
    return response(await capture(request, await readBody(request)));
  } catch (error) {
    const code = error instanceof Error
      ? error.message
      : "PHYSICAL_ANDROID_GATEWAY_ERROR";
    const status = code === "RATE_LIMITED"
      ? 429
      : code === "OBSERVER_AUTH_FAILED" || code.includes("AUTHORITY")
      ? 401
      : code.includes("INVALID") || code === "BODY_TOO_LARGE"
      ? 400
      : code.includes("MISMATCH")
      ? 409
      : 503;
    return response({ ok: false, error: { code } }, status);
  }
});
