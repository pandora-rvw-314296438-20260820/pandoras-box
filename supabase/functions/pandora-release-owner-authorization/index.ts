import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";
import { validateOwnerAuthorizationRequest } from "./contract.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_BODY_BYTES = 16 * 1024;

type JsonRecord = Record<string, unknown>;
type UntypedSupabaseClient = SupabaseClient<any, "public", "public", any, any>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
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

function decodeJwtPayload(authorization: string) {
  const token = authorization.replace(/^Bearer\s+/i, "");
  const encoded = token.split(".")[1] || "";
  const normalized = encoded.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(encoded.length / 4) * 4, "=");
  try {
    const parsed = JSON.parse(atob(normalized));
    return asRecord(parsed);
  } catch {
    return {};
  }
}

function requireRecentAal2Session(
  claims: JsonRecord,
  nowSeconds = Date.now() / 1000,
) {
  const sessionId = String(claims.session_id || "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(sessionId)) {
    throw new Error("RECENT_AAL2_SESSION_REQUIRED");
  }
  const recentMfa = Array.isArray(claims.amr)
    ? claims.amr
      .map(asRecord)
      .filter((entry) => [
        "totp",
        "mfa/totp",
        "mfa/phone",
        "mfa/webauthn",
      ].includes(String(entry.method || "")))
      .map((entry) => Number(entry.timestamp))
      .filter((timestamp) => Number.isSafeInteger(timestamp))
      .sort((left, right) => right - left)[0]
    : undefined;
  if (recentMfa === undefined || recentMfa < nowSeconds - 300 || recentMfa > nowSeconds + 30) {
    throw new Error("RECENT_AAL2_SESSION_REQUIRED");
  }
  return {
    sessionId,
    mfaVerifiedAt: new Date(recentMfa * 1000).toISOString(),
  };
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function authenticateOwner(request: Request, organizationId: string) {
  const authorization = request.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) throw new Error("SIGN_IN_REQUIRED");
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user || authData.user.is_anonymous === true) {
    throw new Error("SIGN_IN_REQUIRED");
  }
  const claims = decodeJwtPayload(authorization);
  if (claims.aal !== "aal2" || claims.is_anonymous === true) {
    throw new Error("AAL2_REQUIRED");
  }
  const session = requireRecentAal2Session(claims);
  const { data: memberships, error: membershipError } = await client
    .from("memberships")
    .select("organization_id, role, status")
    .eq("organization_id", organizationId)
    .eq("user_id", authData.user.id)
    .eq("role", "owner")
    .eq("status", "active")
    .limit(2);
  if (membershipError || memberships?.length !== 1) throw new Error("OWNER_ROLE_REQUIRED");
  return { client, userId: authData.user.id, ...session };
}

async function consumeAuthenticatedRateLimit(
  organizationId: string,
  userId: string,
) {
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("consume_runtime_rate_limit", {
    p_organization_id: organizationId,
    p_key_hash: await sha256Hex(`pandora-release-owner-authorization:v1:${userId}`),
    p_limit: 10,
    p_window_seconds: 60,
  });
  if (error) throw new Error("RATE_LIMIT_CONTROL_UNAVAILABLE");
  if (asRecord(data).allowed !== true) throw new Error("RATE_LIMITED");
}

async function authorize(request: Request, raw: JsonRecord) {
  const input = validateOwnerAuthorizationRequest(raw);
  const owner = await authenticateOwner(request, input.organizationId);
  await consumeAuthenticatedRateLimit(input.organizationId, owner.userId);
  const result = await (owner.client as UntypedSupabaseClient).rpc(
    "capture_canonical_release_owner_authorization",
    {
      p_organization_id: input.organizationId,
      p_repository: input.repository,
      p_owner_user_id: owner.userId,
      p_source_sha: input.sourceSha,
      p_production_deployment_id: input.productionDeploymentId,
      p_review_receipt_id: input.reviewReceiptId,
      p_review_receipt_sha256: input.reviewReceiptSha256,
      p_aal: "aal2",
      p_request_id: input.requestId,
      p_authorized_at: input.authorizedAt,
    },
  );
  if (result.error) throw new Error("OWNER_AUTHORIZATION_REJECTED");
  const ownerAuthorization = asRecord(result.data);
  const receiptMfaTime = Date.parse(String(ownerAuthorization.mfaVerifiedAt || ""));
  const expectedMfaTime = Date.parse(owner.mfaVerifiedAt);
  if (ownerAuthorization.verified !== true ||
    ownerAuthorization.authority !== "OWNER_AUTHORIZATION" ||
    ownerAuthorization.ownerUserId !== owner.userId ||
    ownerAuthorization.sourceSha !== input.sourceSha ||
    ownerAuthorization.productionDeploymentId !== input.productionDeploymentId ||
    ownerAuthorization.reviewReceiptId !== input.reviewReceiptId ||
    ownerAuthorization.reviewReceiptSha256 !== input.reviewReceiptSha256 ||
    ownerAuthorization.aal !== "aal2" ||
    ownerAuthorization.sessionId !== owner.sessionId ||
    !Number.isFinite(receiptMfaTime) || !Number.isFinite(expectedMfaTime) ||
    Math.abs(receiptMfaTime - expectedMfaTime) > 1000 ||
    !/^[0-9a-f]{64}$/.test(String(ownerAuthorization.receiptSha256 || ""))) {
    throw new Error("OWNER_AUTHORIZATION_READBACK_MISMATCH");
  }
  return { ok: true, ownerAuthorization };
}

Deno.serve(async (request: Request) => {
  if (request.headers.get("origin")) {
    return response({ ok: false, error: { code: "BROWSER_ORIGIN_REJECTED" } }, 403);
  }
  if (request.method !== "POST") {
    return response({ ok: false, error: { code: "METHOD_NOT_ALLOWED" } }, 405);
  }
  try {
    return response(await authorize(request, await readBody(request)));
  } catch (error) {
    const code = error instanceof Error ? error.message : "OWNER_AUTHORIZATION_GATEWAY_ERROR";
    const status = code === "SIGN_IN_REQUIRED" ? 401
      : code === "OWNER_ROLE_REQUIRED" || code === "AAL2_REQUIRED" ||
          code === "RECENT_AAL2_SESSION_REQUIRED" ? 403
      : code === "RATE_LIMITED" ? 429
      : code.includes("MISMATCH") || code.includes("REJECTED") ? 409
      : code.includes("INVALID") || code === "BODY_TOO_LARGE" ? 400
      : 503;
    return response(
      { ok: false, error: { code } },
      status,
      status === 429 ? { "retry-after": "60" } : {},
    );
  }
});
