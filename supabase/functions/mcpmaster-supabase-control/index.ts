import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, decodeJwt, jwtVerify } from "npm:jose@5.10.0";
import { routeForCanonicalReleaseCapture } from "./canonical-release-capture-routes.mjs";
import { assertProductionVercelClaims } from "./identity-policy.mjs";

const CONTROL_ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const MAX_REQUEST_BYTES = 256_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ControlRpc =
  | "get_supabase_control_accounts"
  | "get_github_control_accounts"
  | "get_runtime_security_config"
  | "create_execution_plan"
  | "approve_execution_plan"
  | "claim_execution_plan"
  | "finish_execution_plan"
  | "list_execution_plans"
  | "list_execution_audit"
  | "verify_execution_audit_chain"
  | "consume_runtime_rate_limit"
  | "get_canonical_release_status"
  | "capture_canonical_supabase_release_receipt"
  | "capture_canonical_vercel_rehearsal_receipt";

type ControlAction =
  | "catalog"
  | "github_catalog"
  | "runtime_security"
  | "execution_plan_create"
  | "execution_plan_approve"
  | "execution_plan_claim"
  | "execution_plan_finish"
  | "execution_plan_list"
  | "execution_audit_list"
  | "execution_audit_verify"
  | "runtime_rate_limit_consume"
  | "canonical_release_status"
  | "canonical_supabase_receipt_capture"
  | "canonical_vercel_rehearsal_capture";

interface ControlRoute {
  action: ControlAction;
  rpc: ControlRpc;
  params: Record<string, unknown>;
  responseKey:
    | "accounts"
    | "security"
    | "plan"
    | "plans"
    | "checkpoint"
    | "events"
    | "verification"
    | "rateLimit"
    | "releaseEvidence"
    | "supabaseReceipt"
    | "vercelRehearsalReceipt";
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function bearerToken(request: Request): string | undefined {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim();
}

function trustedIssuer(token: string): string {
  const decoded = decodeJwt(token);
  if (typeof decoded.iss !== "string") throw new Error("missing issuer");

  const issuer = new URL(decoded.iss);
  const segments = issuer.pathname.split("/").filter(Boolean);
  if (
    issuer.protocol !== "https:"
    || issuer.hostname !== "oidc.vercel.com"
    || issuer.username
    || issuer.password
    || issuer.search
    || issuer.hash
    || segments.length > 1
  ) {
    throw new Error("untrusted issuer");
  }

  issuer.pathname = segments.length === 1 ? `/${segments[0]}` : "";
  return issuer.toString().replace(/\/$/, "");
}

function audienceValues(audience: unknown): string[] {
  if (typeof audience === "string") return [audience];
  if (Array.isArray(audience) && audience.every((value) => typeof value === "string")) {
    return audience as string[];
  }
  return [];
}

async function verifyVercelToken(token: string): Promise<void> {
  const unverified = decodeJwt(token);
  const issuer = trustedIssuer(token);
  const audiences = audienceValues(unverified.aud);
  if (audiences.length === 0 || !audiences.every((value) => value.startsWith("https://vercel.com/"))) {
    throw new Error("untrusted audience");
  }

  const jwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks`));
  const { payload } = await jwtVerify(token, jwks, {
    issuer,
    audience: audiences,
  });

  assertProductionVercelClaims(payload, audiences);
}

function serviceRoleKey(): string | undefined {
  const modernKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modernKeys) {
    try {
      const parsed = JSON.parse(modernKeys) as Record<string, unknown>;
      if (typeof parsed.default === "string" && parsed.default.length > 0) return parsed.default;
    } catch {
      // Fall through to the legacy built-in key.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? undefined;
}

async function fetchRpc(
  supabaseUrl: string,
  key: string,
  rpcName: ControlRpc,
  params: Record<string, unknown>,
): Promise<unknown | undefined> {
  const rpcResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      p_organization_id: CONTROL_ORGANIZATION_ID,
      ...params,
    }),
    redirect: "error",
  });

  if (!rpcResponse.ok) return undefined;
  return rpcResponse.json();
}


function base64UrlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function base64UrlText(value: string): string {
  return base64UrlBytes(new TextEncoder().encode(value));
}
function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const output = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) { output.set(part, offset); offset += part.length; }
  return output;
}
function derLength(length: number): Uint8Array {
  if (length < 0x80) return new Uint8Array([length]);
  const bytes: number[] = [];
  let remaining = length;
  while (remaining > 0) { bytes.unshift(remaining & 0xff); remaining >>>= 8; }
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}
function derWrap(tag: number, body: Uint8Array): Uint8Array {
  return concatBytes(new Uint8Array([tag]), derLength(body.length), body);
}
function pemDer(privateKeyPem: string): Uint8Array {
  const base64 = privateKeyPem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}
function pkcs1ToPkcs8(pkcs1: Uint8Array): Uint8Array {
  const version = new Uint8Array([0x02, 0x01, 0x00]);
  const rsaAlgorithmIdentifier = new Uint8Array([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00]);
  return derWrap(0x30, concatBytes(version, rsaAlgorithmIdentifier, derWrap(0x04, pkcs1)));
}
async function githubAppJwt(appId: number, privateKeyPem: string): Promise<string> {
  const decoded = pemDer(privateKeyPem);
  const keyData = privateKeyPem.includes("BEGIN RSA PRIVATE KEY") ? pkcs1ToPkcs8(decoded) : decoded;
  const privateKey = await crypto.subtle.importKey("pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlText(JSON.stringify({ iat: now - 30, exp: now + 540, iss: appId }));
  const signingInput = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${base64UrlBytes(signature)}`;
}
async function githubAppInstallationToken(supabaseUrl: string, key: string): Promise<string> {
  const materialResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/pandora_get_github_app_runtime_material`, {
    method: "POST",
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: "{}", redirect: "error",
  });
  if (!materialResponse.ok) throw new Error("github_app_runtime_material_unavailable");
  const raw = await materialResponse.json();
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("github_app_runtime_material_invalid");
  const material = raw as Record<string, unknown>;
  const appId = Number(material.appId);
  const installationId = Number(material.installationId);
  const privateKeyPem = typeof material.privateKeyPem === "string" ? material.privateKeyPem : "";
  if (!Number.isInteger(appId) || appId !== 4785021 || !Number.isInteger(installationId) || installationId !== 158056492 || !privateKeyPem.includes("PRIVATE KEY")) {
    throw new Error("github_app_runtime_material_invalid");
  }
  const appJwt = await githubAppJwt(appId, privateKeyPem);
  const tokenResponse = await fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
    method: "POST",
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${appJwt}`,
      "content-type": "application/json",
      "user-agent": "Pandora-GitHub-App/1.0",
      "x-github-api-version": "2022-11-28",
    },
    body: "{}", redirect: "error",
  });
  const tokenPayload = await tokenResponse.json().catch(() => ({}));
  const token = tokenPayload && typeof tokenPayload === "object" && !Array.isArray(tokenPayload)
    && typeof (tokenPayload as Record<string, unknown>).token === "string"
    ? (tokenPayload as Record<string, unknown>).token as string : "";
  if (tokenResponse.status !== 201 || !token) throw new Error("github_app_installation_token_failed");
  return token;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function requiredString(input: Record<string, unknown>, key: string): string | undefined {
  const value = input[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function requiredUuid(input: Record<string, unknown>, key: string): string | undefined {
  const value = requiredString(input, key);
  return value && UUID_PATTERN.test(value) ? value : undefined;
}

function requiredInteger(
  input: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number,
): number | undefined {
  const value = input[key];
  return typeof value === "number"
      && Number.isInteger(value)
      && value >= minimum
      && value <= maximum
    ? value
    : undefined;
}


async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function serviceHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return {
    apikey: key,
    authorization: "Bearer " + key,
    "content-type": "application/json",
    ...extra,
  };
}

function localWorkerId(input: Record<string, unknown>): string | undefined {
  const value = requiredString(input, "workerId");
  return value && /^[A-Za-z0-9_.:-]{1,80}$/.test(value) ? value : undefined;
}

function localWorkerModel(input: Record<string, unknown>): string | undefined {
  const value = requiredString(input, "model");
  return value && value.length <= 160 ? value : undefined;
}

async function verifyLocalWorkerKey(
  supabaseUrl: string,
  key: string,
  presented: string,
): Promise<boolean> {
  if (!presented || presented.length > 512) return false;
  const path = "/rest/v1/pandora_runtime_provider_configs?provider=eq.local&config_key=eq.worker_key_sha256&active=eq.true&select=config_value&limit=1";
  const configResponse = await fetch(supabaseUrl + path, {
    headers: serviceHeaders(key),
    redirect: "error",
  });
  if (!configResponse.ok) return false;
  const rows = await configResponse.json().catch(() => []);
  if (!Array.isArray(rows) || rows.length !== 1 || !isRecord(rows[0])) return false;
  const expected = typeof rows[0].config_value === "string" ? rows[0].config_value.toLowerCase() : "";
  return expected.length === 64 && await sha256Hex(presented) === expected;
}

async function upsertLocalWorker(
  supabaseUrl: string,
  key: string,
  workerId: string,
  model: string,
  status: "ready" | "busy" | "degraded",
): Promise<boolean> {
  const workerResponse = await fetch(supabaseUrl + "/rest/v1/pandora_local_ai_workers", {
    method: "POST",
    headers: serviceHeaders(key, { prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify({
      worker_id: workerId,
      model,
      status,
      last_seen_at: new Date().toISOString(),
      metadata: {
        runtime: "llama.cpp",
        transport: "outbound_poll",
        nodeClass: "authorized_windows_edge",
      },
    }),
    redirect: "error",
  });
  return workerResponse.ok;
}

async function handleLocalWorker(
  request: Request,
  input: Record<string, unknown>,
  supabaseUrl: string,
  key: string,
): Promise<Response> {
  const workerKey = request.headers.get("x-pandora-worker-key")?.trim() || "";
  if (!await verifyLocalWorkerKey(supabaseUrl, key, workerKey)) {
    return response(401, { ok: false, error: "worker_unauthorized" });
  }

  const action = requiredString(input, "action");
  const workerId = localWorkerId(input);
  const model = localWorkerModel(input);
  if (!workerId || !model) {
    return response(400, { ok: false, error: "invalid_worker_request" });
  }

  if (action === "local_ai_heartbeat") {
    const state = requiredString(input, "status");
    const status = state === "busy" || state === "degraded" ? state : "ready";
    if (!await upsertLocalWorker(supabaseUrl, key, workerId, model, status)) {
      return response(502, { ok: false, error: "worker_heartbeat_failed" });
    }
    return response(200, { ok: true });
  }

  if (action === "local_ai_claim") {
    const now = new Date().toISOString();
    await fetch(
      supabaseUrl + "/rest/v1/pandora_local_ai_jobs?status=eq.queued&expires_at=lt." + encodeURIComponent(now),
      {
        method: "PATCH",
        headers: serviceHeaders(key, { prefer: "return=minimal" }),
        body: JSON.stringify({
          status: "cancelled",
          error_code: "expired",
          completed_at: now,
          updated_at: now,
        }),
        redirect: "error",
      },
    );

    const candidatePath =
      "/rest/v1/pandora_local_ai_jobs?status=eq.queued&model=eq." + encodeURIComponent(model) +
      "&expires_at=gt." + encodeURIComponent(now) +
      "&select=id,model,request_body&order=created_at.asc&limit=1";
    const candidateResponse = await fetch(supabaseUrl + candidatePath, {
      headers: serviceHeaders(key),
      redirect: "error",
    });
    if (!candidateResponse.ok) return response(502, { ok: false, error: "queue_read_failed" });
    const candidates = await candidateResponse.json().catch(() => []);
    if (!Array.isArray(candidates) || candidates.length === 0 || !isRecord(candidates[0])) {
      await upsertLocalWorker(supabaseUrl, key, workerId, model, "ready");
      return response(200, { ok: true, job: null });
    }

    const jobId = typeof candidates[0].id === "string" ? candidates[0].id : "";
    if (!UUID_PATTERN.test(jobId)) return response(502, { ok: false, error: "queue_read_invalid" });
    const claimToken = crypto.randomUUID();
    const claimPath =
      "/rest/v1/pandora_local_ai_jobs?id=eq." + jobId +
      "&status=eq.queued&select=id,model,request_body";
    const claimResponse = await fetch(supabaseUrl + claimPath, {
      method: "PATCH",
      headers: serviceHeaders(key, { prefer: "return=representation" }),
      body: JSON.stringify({
        status: "processing",
        claim_token: claimToken,
        worker_id: workerId,
        claimed_at: now,
        updated_at: now,
      }),
      redirect: "error",
    });
    if (!claimResponse.ok) return response(502, { ok: false, error: "queue_claim_failed" });
    const claimed = await claimResponse.json().catch(() => []);
    if (!Array.isArray(claimed) || claimed.length !== 1 || !isRecord(claimed[0])) {
      return response(200, { ok: true, job: null });
    }
    await upsertLocalWorker(supabaseUrl, key, workerId, model, "busy");
    return response(200, {
      ok: true,
      job: {
        id: jobId,
        model,
        claimToken,
        requestBody: isRecord(claimed[0].request_body) ? claimed[0].request_body : {},
      },
    });
  }

  if (action === "local_ai_complete") {
    const jobId = requiredUuid(input, "jobId");
    const claimToken = requiredUuid(input, "claimToken");
    if (!jobId || !claimToken) return response(400, { ok: false, error: "invalid_claim" });
    const success = input.success === true;
    const completeBody = success
      ? {
        status: "completed",
        result_body: isRecord(input.resultBody) ? input.resultBody : {},
        error_code: null,
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }
      : {
        status: "failed",
        result_body: null,
        error_code: typeof input.errorCode === "string" ? input.errorCode.slice(0, 120) : "local_ai_failed",
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
    const completePath =
      "/rest/v1/pandora_local_ai_jobs?id=eq." + jobId +
      "&claim_token=eq." + claimToken +
      "&worker_id=eq." + encodeURIComponent(workerId) +
      "&status=eq.processing&select=id";
    const completeResponse = await fetch(supabaseUrl + completePath, {
      method: "PATCH",
      headers: serviceHeaders(key, { prefer: "return=representation" }),
      body: JSON.stringify(completeBody),
      redirect: "error",
    });
    if (!completeResponse.ok) return response(502, { ok: false, error: "queue_complete_failed" });
    const completed = await completeResponse.json().catch(() => []);
    if (!Array.isArray(completed) || completed.length !== 1) {
      return response(409, { ok: false, error: "claim_not_current" });
    }
    await upsertLocalWorker(supabaseUrl, key, workerId, model, success ? "ready" : "degraded");
    return response(200, { ok: true });
  }

  return response(400, { ok: false, error: "unsupported_worker_action" });
}

function isLocalWorkerAction(input: Record<string, unknown>): boolean {
  const action = typeof input.action === "string" ? input.action : "";
  return ["local_ai_heartbeat", "local_ai_claim", "local_ai_complete"].includes(action);
}

function routeForInput(input: Record<string, unknown>): ControlRoute | undefined {
  const canonicalCapture = routeForCanonicalReleaseCapture(input);
  if (canonicalCapture) return canonicalCapture as ControlRoute;

  if (input.action === "catalog") {
    return {
      action: "catalog",
      rpc: "get_supabase_control_accounts",
      params: {},
      responseKey: "accounts",
    };
  }
  if (input.action === "github_catalog") {
    return {
      action: "github_catalog",
      rpc: "get_github_control_accounts",
      params: {},
      responseKey: "accounts",
    };
  }
  if (input.action === "runtime_security") {
    return {
      action: "runtime_security",
      rpc: "get_runtime_security_config",
      params: {},
      responseKey: "security",
    };
  }

  if (input.action === "execution_plan_create") {
    const requestId = requiredUuid(input, "requestId");
    const intakeId = requiredUuid(input, "intakeId");
    const tool = requiredString(input, "tool");
    const risk = requiredString(input, "risk");
    const payloadHash = requiredString(input, "payloadHash");
    const expiresAt = requiredString(input, "expiresAt");
    if (!requestId || !intakeId || !tool || !risk || !payloadHash || !expiresAt || !isRecord(input.args)) {
      return undefined;
    }
    return {
      action: "execution_plan_create",
      rpc: "create_execution_plan",
      responseKey: "plan",
      params: {
        p_request_id: requestId,
        p_intake_id: intakeId,
        p_tool: tool,
        p_risk: risk,
        p_args: input.args,
        p_payload_hash: payloadHash,
        p_expires_at: expiresAt,
      },
    };
  }

  if (input.action === "execution_plan_approve") {
    const planId = requiredUuid(input, "planId");
    const approvedBy = requiredString(input, "approvedBy");
    if (!planId || !approvedBy) return undefined;
    return {
      action: "execution_plan_approve",
      rpc: "approve_execution_plan",
      responseKey: "plan",
      params: { p_plan_id: planId, p_approved_by: approvedBy },
    };
  }

  if (input.action === "execution_plan_claim") {
    const planId = requiredUuid(input, "planId");
    if (!planId) return undefined;
    return {
      action: "execution_plan_claim",
      rpc: "claim_execution_plan",
      responseKey: "plan",
      params: { p_plan_id: planId },
    };
  }

  if (input.action === "execution_plan_finish") {
    const planId = requiredUuid(input, "planId");
    const status = requiredString(input, "status");
    if (!planId || !status) return undefined;
    return {
      action: "execution_plan_finish",
      rpc: "finish_execution_plan",
      responseKey: "plan",
      params: {
        p_plan_id: planId,
        p_status: status,
        p_duration_ms: typeof input.durationMs === "number" ? Math.max(0, Math.floor(input.durationMs)) : 0,
        p_error: typeof input.error === "string" ? input.error : null,
        p_result_summary: isRecord(input.resultSummary) ? input.resultSummary : {},
      },
    };
  }

  if (input.action === "execution_plan_list") {
    return {
      action: "execution_plan_list",
      rpc: "list_execution_plans",
      responseKey: "plans",
      params: {
        p_limit: typeof input.limit === "number" ? Math.min(Math.max(Math.floor(input.limit), 1), 500) : 100,
      },
    };
  }

  if (input.action === "execution_audit_list") {
    return {
      action: "execution_audit_list",
      rpc: "list_execution_audit",
      responseKey: "events",
      params: {
        p_limit: typeof input.limit === "number" ? Math.min(Math.max(Math.floor(input.limit), 1), 500) : 100,
      },
    };
  }

  if (input.action === "execution_audit_verify") {
    return {
      action: "execution_audit_verify",
      rpc: "verify_execution_audit_chain",
      responseKey: "verification",
      params: {},
    };
  }

  if (input.action === "runtime_rate_limit_consume") {
    const keyHash = requiredString(input, "keyHash");
    const limit = requiredInteger(input, "limit", 1, 10_000);
    const windowSeconds = requiredInteger(input, "windowSeconds", 1, 3_600);
    if (!keyHash || !/^[0-9a-f]{64}$/.test(keyHash) || !limit || !windowSeconds) return undefined;
    return {
      action: "runtime_rate_limit_consume",
      rpc: "consume_runtime_rate_limit",
      responseKey: "rateLimit",
      params: {
        p_key_hash: keyHash,
        p_limit: limit,
        p_window_seconds: windowSeconds,
      },
    };
  }

  if (input.action === "canonical_release_status") {
    const repository = requiredString(input, "repository");
    const sourceSha = requiredString(input, "sourceSha");
    if (
      repository !== "pandora-rvw-314296438-20260820/pandoras-box"
      || !sourceSha
      || !/^[0-9a-f]{40}$/.test(sourceSha)
    ) return undefined;
    return {
      action: "canonical_release_status",
      rpc: "get_canonical_release_status",
      responseKey: "releaseEvidence",
      params: {
        p_repository: repository,
        p_source_sha: sourceSha,
      },
    };
  }

  return undefined;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { ok: false, error: "method_not_allowed" });

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) {
    return response(413, { ok: false, error: "request_too_large" });
  }

  let input: Record<string, unknown>;
  try {
    const parsed = JSON.parse(rawBody);
    if (!isRecord(parsed)) throw new Error("not an object");
    input = parsed;
  } catch {
    return response(400, { ok: false, error: "invalid_json" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const key = serviceRoleKey();
  if (!supabaseUrl || !key) return response(503, { ok: false, error: "control_database_not_configured" });

  if (isLocalWorkerAction(input)) {
    return await handleLocalWorker(request, input, supabaseUrl, key);
  }

  const token = bearerToken(request);
  if (!token) return response(401, { ok: false, error: "unauthorized" });

  try {
    await verifyVercelToken(token);
  } catch {
    return response(401, { ok: false, error: "unauthorized" });
  }

  const route = routeForInput(input);
  if (!route) return response(400, { ok: false, error: "unsupported_or_invalid_action" });

  try {
    let payload = await fetchRpc(supabaseUrl, key, route.rpc, route.params);
    if (payload === undefined) return response(502, { ok: false, error: "control_operation_unavailable" });

    if (route.action === "github_catalog" && Array.isArray(payload)) {
      const hasGithubApp = payload.some((entry) => isRecord(entry) && entry.authMode === "github_app");
      if (hasGithubApp) {
        const installationToken = await githubAppInstallationToken(supabaseUrl, key);
        payload = payload.map((entry) => {
          if (!isRecord(entry) || entry.authMode !== "github_app") return entry;
          return { ...entry, authMode: "oauth", token: installationToken };
        });
      }
    }

    if (route.responseKey === "accounts") {
      if (!Array.isArray(payload)) return response(502, { ok: false, error: "control_operation_unavailable" });
      return response(200, { ok: true, accounts: payload });
    }

    if (
      route.responseKey === "checkpoint"
      || route.responseKey === "releaseEvidence"
    ) {
      if (payload !== null && (!payload || typeof payload !== "object" || Array.isArray(payload))) {
        return response(502, { ok: false, error: "control_operation_unavailable" });
      }
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (route.responseKey === "supabaseReceipt" || route.responseKey === "vercelRehearsalReceipt") {
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
        return response(502, { ok: false, error: "control_operation_unavailable" });
      }
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (route.responseKey === "events" || route.responseKey === "plans") {
      if (!Array.isArray(payload)) return response(502, { ok: false, error: "control_operation_unavailable" });
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return response(502, { ok: false, error: "control_operation_unavailable" });
    }

    return response(200, { ok: true, [route.responseKey]: payload });
  } catch {
    return response(502, { ok: false, error: "control_operation_unavailable" });
  }
});
