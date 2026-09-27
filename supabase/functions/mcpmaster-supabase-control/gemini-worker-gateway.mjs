import { createRemoteJWKSet, decodeJwt, jwtVerify } from "npm:jose@5.10.0";

const ISSUER = "https://oidc.vercel.com/mbanatao";
const AUDIENCE = "https://vercel.com/mbanatao";
const OWNER = "mbanatao";
const OWNER_ID = "team_3yw1CN59ce4pj5SwyQGCAqN3";
const PROJECT = "mcpmaster";
const PROJECT_ID = "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk";
const ENVIRONMENT = "development";
const SUBJECT = "owner:mbanatao:project:mcpmaster:environment:development";
const PRINCIPAL = "vercel:mbanatao:mcpmaster:development:gemini-worker";
const ROUTE_MARKER = "/mcpmaster-supabase-control/gemini-worker";
const GEMINI_ORIGIN = "https://generativelanguage.googleapis.com";
const MAX_BODY_BYTES = 8 * 1024 * 1024;
const MAX_QUERY_BYTES = 2048;
const MODEL_PATH = /^\/v1(?:alpha|beta)?\/models(?:\/[A-Za-z0-9._-]{1,160}(?::[A-Za-z][A-Za-z0-9]{0,63})?)?$/;
const SAFE_QUERY_KEY = /^[A-Za-z0-9_.\-$]{1,64}$/;

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function gatewayPath(url) {
  const path = url.pathname;
  const index = path.indexOf(ROUTE_MARKER);
  if (index < 0) return null;
  const prefix = path.slice(0, index);
  if (prefix && prefix !== "/functions/v1") return null;
  const suffix = path.slice(index + ROUTE_MARKER.length);
  return suffix || "/";
}

function bearer(request) {
  const value = request.headers.get("authorization") || "";
  const match = value.match(/^Bearer\s+([A-Za-z0-9._~-]{80,4096})$/);
  return match?.[1] || "";
}

function audienceValues(value) {
  if (typeof value === "string") return [value];
  return Array.isArray(value) && value.every((entry) => typeof entry === "string")
    ? value
    : [];
}

async function verifyWorker(token) {
  if (!token) throw new Error("WORKER_UNAUTHORIZED");
  const unverified = decodeJwt(token);
  if (unverified.iss !== ISSUER) throw new Error("WORKER_UNAUTHORIZED");
  const audiences = audienceValues(unverified.aud);
  if (audiences.length !== 1 || audiences[0] !== AUDIENCE) {
    throw new Error("WORKER_UNAUTHORIZED");
  }

  const jwks = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
  const { payload } = await jwtVerify(token, jwks, {
    issuer: ISSUER,
    audience: AUDIENCE,
  });
  if (
    payload.environment !== ENVIRONMENT
    || payload.project !== PROJECT
    || payload.project_id !== PROJECT_ID
    || payload.owner !== OWNER
    || payload.owner_id !== OWNER_ID
    || payload.sub !== SUBJECT
    || payload.scope !== SUBJECT
  ) throw new Error("WORKER_UNAUTHORIZED");
  return payload;
}

function serviceRoleKey() {
  const modern = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern);
      if (typeof parsed.default === "string" && parsed.default.trim()) {
        return parsed.default.trim();
      }
    } catch {
      // Fall through to the legacy built-in key.
    }
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (legacy) return legacy;
  throw new Error("CONTROL_CREDENTIAL_UNAVAILABLE");
}

function serviceHeaders(key) {
  const headers = {
    apikey: key,
    "content-type": "application/json",
  };
  if (!key.startsWith("sb_secret_")) headers.authorization = `Bearer ${key}`;
  return headers;
}

async function geminiApiKey() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  if (!supabaseUrl) throw new Error("CONTROL_DATABASE_UNAVAILABLE");
  const key = serviceRoleKey();
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/pandora_gemini_stream_credential_service_20260901`,
    {
      method: "POST",
      headers: serviceHeaders(key),
      body: "{}",
      redirect: "error",
      signal: AbortSignal.timeout(8_000),
    },
  );
  if (!response.ok) throw new Error("GEMINI_CREDENTIAL_UNAVAILABLE");
  const value = await response.json().catch(() => null);
  if (typeof value !== "string" || value.trim().length < 20 || value.length > 4096) {
    throw new Error("GEMINI_CREDENTIAL_UNAVAILABLE");
  }
  return value.trim();
}

function upstreamQuery(input) {
  const query = new URLSearchParams();
  for (const [key, value] of input.searchParams) {
    if (key.toLowerCase() === "key") continue;
    if (!SAFE_QUERY_KEY.test(key) || value.length > 1024) throw new Error("QUERY_NOT_ALLOWED");
    query.append(key, value);
  }
  const encoded = query.toString();
  if (encoded.length > MAX_QUERY_BYTES) throw new Error("QUERY_NOT_ALLOWED");
  return encoded ? `?${encoded}` : "";
}

async function bodyBytes(request) {
  if (request.method === "GET") return undefined;
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new Error("REQUEST_TOO_LARGE");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_BODY_BYTES) throw new Error("REQUEST_TOO_LARGE");
  return bytes;
}

function upstreamHeaders(request, apiKey) {
  const headers = new Headers();
  const contentType = request.headers.get("content-type");
  const accept = request.headers.get("accept");
  const apiClient = request.headers.get("x-goog-api-client");
  if (contentType) headers.set("content-type", contentType);
  if (accept) headers.set("accept", accept);
  if (apiClient && apiClient.length <= 512) headers.set("x-goog-api-client", apiClient);
  headers.set("x-goog-api-key", apiKey);
  return headers;
}

function responseHeaders(upstream) {
  const headers = new Headers({
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  for (const name of ["content-type", "retry-after", "x-request-id"]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

export async function handleGeminiWorkerRequest(request) {
  const url = new URL(request.url);
  const path = gatewayPath(url);
  if (path === null) return null;
  if (request.headers.get("origin")) return json(403, { ok: false, error: "WORKER_REQUEST_DENIED" });

  let claims;
  try {
    claims = await verifyWorker(bearer(request));
  } catch {
    return json(401, { ok: false, error: "WORKER_UNAUTHORIZED" });
  }

  if (path === "/identity") {
    if (!["GET", "POST"].includes(request.method)) {
      return json(405, { ok: false, error: "METHOD_NOT_ALLOWED" });
    }
    const expiresAt = typeof claims.exp === "number"
      ? new Date(claims.exp * 1000).toISOString()
      : null;
    return json(200, {
      ok: true,
      principalId: PRINCIPAL,
      project: PROJECT,
      projectId: PROJECT_ID,
      owner: OWNER,
      ownerId: OWNER_ID,
      environment: ENVIRONMENT,
      expiresAt,
    });
  }

  if (!["GET", "POST"].includes(request.method) || !MODEL_PATH.test(path)) {
    return json(404, { ok: false, error: "GEMINI_ROUTE_NOT_ALLOWED" });
  }

  try {
    const [apiKey, body] = await Promise.all([geminiApiKey(), bodyBytes(request)]);
    const target = `${GEMINI_ORIGIN}${path}${upstreamQuery(url)}`;
    const upstream = await fetch(target, {
      method: request.method,
      headers: upstreamHeaders(request, apiKey),
      body,
      redirect: "error",
      signal: AbortSignal.timeout(110_000),
    });
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders(upstream),
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "GEMINI_GATEWAY_FAILED";
    const status = code === "REQUEST_TOO_LARGE" ? 413
      : code === "QUERY_NOT_ALLOWED" ? 400
      : code.includes("CREDENTIAL") || code.includes("DATABASE") ? 503
      : 502;
    return json(status, { ok: false, error: code });
  }
}
