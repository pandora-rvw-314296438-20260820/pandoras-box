import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const admin = createClient(supabaseUrl, serviceRole, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const modelName = /^[A-Za-z0-9._:/-]{1,160}$/;
const providers = new Set(["posthog", "openai", "gemini", "kimi"]);
const posthogHosts = new Set(["https://us.posthog.com", "https://eu.posthog.com"]);

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const json = (status: number, body: Record<string, unknown>, origin = "") =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      ...(allowedOrigin(origin) ? { "access-control-allow-origin": origin, vary: "origin" } : {}),
    },
  });

function allowedOrigin(origin: string): boolean {
  if (!origin) return false;
  return origin === "https://mcpmaster.vercel.app" ||
    /^https:\/\/mcpmaster-[a-z0-9-]+\.vercel\.app$/.test(origin);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function providerFetch(url: string, init: RequestInit): Promise<Response> {
  return await fetch(url, { ...init, signal: AbortSignal.timeout(15_000), redirect: "error" });
}

async function authenticate(req: Request, organizationId: string) {
  const authorization = req.headers.get("authorization") || "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1] || "";
  if (!token || token.length > 8192) throw new Error("AUTH_REQUIRED");
  const user = await admin.auth.getUser(token);
  const userId = user.data.user?.id || "";
  if (user.error || !uuid.test(userId)) throw new Error("AUTH_REQUIRED");
  const membership = await admin.from("memberships").select("role,status")
    .eq("organization_id", organizationId).eq("user_id", userId).maybeSingle();
  if (membership.error || membership.data?.status !== "active" ||
      !["owner", "admin"].includes(String(membership.data?.role || ""))) {
    throw new Error("ADMIN_REQUIRED");
  }
  return userId;
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  return await response.json().catch(() => ({})) as Record<string, unknown>;
}

async function verifyPosthog(credential: string, host: string, projectId: string) {
  if (!posthogHosts.has(host) || !/^\d{1,24}$/.test(projectId)) throw new Error("POSTHOG_TARGET_INVALID");
  const response = await providerFetch(`${host}/api/projects/${projectId}/`, {
    headers: { authorization: `Bearer ${credential}`, accept: "application/json" },
  });
  const body = await readJson(response);
  const id = String(body.id || "");
  const name = text(body.name);
  if (!response.ok || id !== projectId || !name) throw new Error("PROVIDER_READBACK_FAILED");
  return {
    subject: id,
    label: name,
    tenantKey: host,
    tenantLabel: new URL(host).hostname,
    scopes: ["project.read"],
    capabilities: ["project.read", "insights.read"],
    readback: { probe: "projects.get", httpStatus: response.status, projectId: id, identityVerified: true },
  };
}

async function verifyOpenAI(credential: string, model: string, runTest: boolean) {
  if (!modelName.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = { authorization: `Bearer ${credential}`, accept: "application/json" };
  const models = await providerFetch("https://api.openai.com/v1/models", { headers });
  const listed = await readJson(models);
  const available = Array.isArray(listed.data) && listed.data.some((item) =>
    typeof item === "object" && item !== null && String((item as Record<string, unknown>).id || "") === model
  );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) return { model, modelCount: Array.isArray(listed.data) ? listed.data.length : 0, testStatus: null };
  const inference = await providerFetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { ...headers, "content-type": "application/json" },
    body: JSON.stringify({ model, input: "Reply OK.", max_output_tokens: 8 }),
  });
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return { model, modelCount: Array.isArray(listed.data) ? listed.data.length : 0, testStatus: inference.status };
}

async function verifyGemini(credential: string, model: string, runTest: boolean) {
  if (!modelName.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = { "x-goog-api-key": credential, accept: "application/json" };
  const models = await providerFetch("https://generativelanguage.googleapis.com/v1beta/models", { headers });
  const listed = await readJson(models);
  const fullModel = model.startsWith("models/") ? model : `models/${model}`;
  const available = Array.isArray(listed.models) && listed.models.some((item) =>
    typeof item === "object" && item !== null && String((item as Record<string, unknown>).name || "") === fullModel
  );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) return { model: fullModel, modelCount: Array.isArray(listed.models) ? listed.models.length : 0, testStatus: null };
  const inference = await providerFetch(`https://generativelanguage.googleapis.com/v1beta/${fullModel}:generateContent`, {
    method: "POST",
    headers: { ...headers, "content-type": "application/json" },
    body: JSON.stringify({ contents: [{ parts: [{ text: "Reply OK." }] }], generationConfig: { maxOutputTokens: 8 } }),
  });
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return { model: fullModel, modelCount: Array.isArray(listed.models) ? listed.models.length : 0, testStatus: inference.status };
}

async function verifyKimi(credential: string, model: string, runTest: boolean) {
  if (!modelName.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = { authorization: `Bearer ${credential}`, accept: "application/json" };
  const models = await providerFetch("https://api.moonshot.ai/v1/models", { headers });
  const listed = await readJson(models);
  const available = Array.isArray(listed.data) && listed.data.some((item) =>
    typeof item === "object" && item !== null && String((item as Record<string, unknown>).id || "") === model
  );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) return { model, modelCount: Array.isArray(listed.data) ? listed.data.length : 0, testStatus: null };
  const inference = await providerFetch("https://api.moonshot.ai/v1/chat/completions", {
    method: "POST",
    headers: { ...headers, "content-type": "application/json" },
    body: JSON.stringify({ model, messages: [{ role: "user", content: "Reply OK." }], max_tokens: 8 }),
  });
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return { model, modelCount: Array.isArray(listed.data) ? listed.data.length : 0, testStatus: inference.status };
}

async function verifyModel(provider: string, credential: string, model: string, runTest: boolean) {
  const detail = provider === "openai" ? await verifyOpenAI(credential, model, runTest)
    : provider === "gemini" ? await verifyGemini(credential, model, runTest)
    : await verifyKimi(credential, model, runTest);
  return {
    subject: await sha256(credential),
    label: `${provider[0].toUpperCase()}${provider.slice(1)} API credential`,
    tenantKey: "",
    tenantLabel: null,
    scopes: ["models.read", "inference.test"],
    capabilities: ["models.read", "inference.test"],
    readback: {
      probe: "models.list",
      httpStatus: 200,
      model: detail.model,
      modelCount: detail.modelCount,
      testInference: runTest ? "passed" : "not_run",
      testStatus: detail.testStatus,
    },
  };
}

async function verifyProvider(provider: string, credential: string, body: Record<string, unknown>) {
  if (provider === "posthog") return await verifyPosthog(credential, text(body.host), text(body.projectId));
  return await verifyModel(provider, credential, text(body.model), body.runTestInference === true);
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  if (req.method === "OPTIONS") {
    if (!allowedOrigin(origin)) return new Response(null, { status: 403 });
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": origin,
        "access-control-allow-headers": "authorization, content-type, x-client-info, apikey",
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-max-age": "600",
        vary: "origin",
      },
    });
  }
  if (req.method !== "POST") return json(405, { ok: false, code: "METHOD_NOT_ALLOWED" }, origin);
  const contentLength = Number(req.headers.get("content-length") || "0");
  if (contentLength > 16_384) return json(413, { ok: false, code: "REQUEST_TOO_LARGE" }, origin);

  let organizationId = "";
  let connectionId = "";
  try {
    const body = await req.json() as Record<string, unknown>;
    organizationId = text(body.organizationId);
    const action = text(body.action);
    if (!uuid.test(organizationId) || !["connect", "health", "test_inference"].includes(action)) {
      return json(400, { ok: false, code: "REQUEST_INVALID" }, origin);
    }
    const userId = await authenticate(req, organizationId);

    if (action === "connect") {
      const provider = text(body.provider).toLowerCase();
      const credential = text(body.credential);
      if (!providers.has(provider) || credential.length < 16 || credential.length > 8192) {
        return json(400, { ok: false, code: "CONNECTION_INPUT_INVALID" }, origin);
      }
      if (provider !== "posthog" && body.runTestInference !== true) {
        return json(400, { ok: false, code: "TEST_INFERENCE_REQUIRED" }, origin);
      }
      const verified = await verifyProvider(provider, credential, body);
      const committed = await admin.rpc("pandora_connection_commit_verified_credential_v1", {
        p_organization_id: organizationId,
        p_provider_key: provider,
        p_actor_user_id: userId,
        p_credential: credential,
        p_provider_subject: verified.subject,
        p_account_label: verified.label,
        p_tenant_key: verified.tenantKey,
        p_tenant_label: verified.tenantLabel,
        p_granted_scopes: verified.scopes,
        p_granted_capabilities: verified.capabilities,
        p_verified_at: new Date().toISOString(),
        p_expires_at: null,
        p_provider_readback: verified.readback,
      });
      if (committed.error || committed.data?.ok !== true) throw new Error("CONNECTION_COMMIT_FAILED");
      return json(200, { ...committed.data, credential: undefined }, origin);
    }

    connectionId = text(body.connectionId);
    if (!uuid.test(connectionId)) return json(400, { ok: false, code: "CONNECTION_ID_INVALID" }, origin);
    const runtime = await admin.rpc("pandora_connection_runtime_credential_v1", { p_connection_id: connectionId });
    if (runtime.error || runtime.data?.organizationId !== organizationId) throw new Error("CONNECTION_RUNTIME_UNAVAILABLE");
    const provider = text(runtime.data.provider);
    const credential = text(runtime.data.credential);
    const verification = await verifyProvider(provider, credential, {
      ...body,
      host: body.host || runtime.data.tenantKey,
      projectId: body.projectId || runtime.data.metadata?.projectId,
      model: body.model || runtime.data.metadata?.model,
      runTestInference: action === "test_inference" ? true : body.runTestInference,
    });
    const health = await admin.rpc("pandora_connection_health_commit_v1", {
      p_connection_id: connectionId,
      p_healthy: true,
      p_verified_at: new Date().toISOString(),
      p_failure_code: null,
    });
    if (health.error) throw new Error("HEALTH_COMMIT_FAILED");
    return json(200, {
      ok: true,
      connectionId,
      provider,
      healthy: true,
      testInference: action === "test_inference" ? "passed" : undefined,
      model: "model" in verification.readback ? verification.readback.model : undefined,
      verifiedAt: health.data?.verifiedAt,
    }, origin);
  } catch (error) {
    const code = error instanceof Error && /^[A-Z0-9_]{3,80}$/.test(error.message)
      ? error.message
      : "CONNECTION_BROKER_FAILED";
    if (uuid.test(connectionId)) {
      await admin.rpc("pandora_connection_health_commit_v1", {
        p_connection_id: connectionId,
        p_healthy: false,
        p_verified_at: new Date().toISOString(),
        p_failure_code: code,
      });
    }
    const status = code === "AUTH_REQUIRED" ? 401 : code === "ADMIN_REQUIRED" ? 403 : 400;
    return json(status, { ok: false, code, organizationId: uuid.test(organizationId) ? organizationId : undefined }, origin);
  }
});
