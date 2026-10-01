export const PANDORA_CONNECTION_PROVIDER_KEYS = new Set([
  "posthog",
  "openai",
  "gemini",
  "kimi",
]);

const MODEL_NAME = /^[A-Za-z0-9._:/-]{1,160}$/;
const TENANT_KEY = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,319}$/;
const POSTHOG_HOSTS = new Set([
  "https://us.posthog.com",
  "https://eu.posthog.com",
]);

export type PandoraProviderVerification = {
  subject: string;
  label: string;
  tenantKey: string;
  tenantLabel: string;
  scopes: string[];
  capabilities: string[];
  readback: Record<string, unknown>;
};

export const connectionText = (value: unknown) =>
  typeof value === "string" ? value.trim() : "";

export const isPandoraTenantKey = (value: string) => TENANT_KEY.test(value);

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function providerFetch(
  url: string,
  init: RequestInit,
  fetchImpl: typeof fetch,
): Promise<Response> {
  return await fetchImpl(url, {
    ...init,
    signal: AbortSignal.timeout(15_000),
    redirect: "error",
  });
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  return (await response.json().catch(() => ({}))) as Record<string, unknown>;
}

async function verifyPosthog(
  credential: string,
  host: string,
  projectId: string,
  tenantKey: string,
  fetchImpl: typeof fetch,
): Promise<PandoraProviderVerification> {
  if (
    !POSTHOG_HOSTS.has(host) ||
    tenantKey !== host ||
    !/^\d{1,24}$/.test(projectId)
  ) {
    throw new Error("POSTHOG_TARGET_INVALID");
  }
  const response = await providerFetch(
    `${host}/api/projects/${projectId}/`,
    {
      headers: {
        authorization: `Bearer ${credential}`,
        accept: "application/json",
      },
    },
    fetchImpl,
  );
  const body = await readJson(response);
  const id = String(body.id || "");
  const name = connectionText(body.name);
  if (!response.ok || id !== projectId || !name) {
    throw new Error("PROVIDER_READBACK_FAILED");
  }
  return {
    subject: id,
    label: name,
    tenantKey: host,
    tenantLabel: new URL(host).hostname,
    scopes: ["project.read"],
    capabilities: ["project.read", "insights.read"],
    readback: {
      probe: "projects.get",
      httpStatus: response.status,
      projectId: id,
      identityVerified: true,
    },
  };
}

async function verifyOpenAI(
  credential: string,
  model: string,
  runTest: boolean,
  fetchImpl: typeof fetch,
) {
  if (!MODEL_NAME.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = {
    authorization: `Bearer ${credential}`,
    accept: "application/json",
  };
  const models = await providerFetch(
    "https://api.openai.com/v1/models",
    { headers },
    fetchImpl,
  );
  const listed = await readJson(models);
  const available =
    Array.isArray(listed.data) &&
    listed.data.some(
      (item) =>
        typeof item === "object" &&
        item !== null &&
        String((item as Record<string, unknown>).id || "") === model,
    );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) {
    return {
      model,
      modelCount: Array.isArray(listed.data) ? listed.data.length : 0,
      testStatus: null,
    };
  }
  const inference = await providerFetch(
    "https://api.openai.com/v1/responses",
    {
      method: "POST",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({ model, input: "Reply OK.", max_output_tokens: 8 }),
    },
    fetchImpl,
  );
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return {
    model,
    modelCount: Array.isArray(listed.data) ? listed.data.length : 0,
    testStatus: inference.status,
  };
}

async function verifyGemini(
  credential: string,
  model: string,
  runTest: boolean,
  fetchImpl: typeof fetch,
) {
  if (!MODEL_NAME.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = { "x-goog-api-key": credential, accept: "application/json" };
  const models = await providerFetch(
    "https://generativelanguage.googleapis.com/v1beta/models",
    { headers },
    fetchImpl,
  );
  const listed = await readJson(models);
  const fullModel = model.startsWith("models/") ? model : `models/${model}`;
  const available =
    Array.isArray(listed.models) &&
    listed.models.some(
      (item) =>
        typeof item === "object" &&
        item !== null &&
        String((item as Record<string, unknown>).name || "") === fullModel,
    );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) {
    return {
      model: fullModel,
      modelCount: Array.isArray(listed.models) ? listed.models.length : 0,
      testStatus: null,
    };
  }
  const inference = await providerFetch(
    `https://generativelanguage.googleapis.com/v1beta/${fullModel}:generateContent`,
    {
      method: "POST",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: "Reply OK." }] }],
        generationConfig: { maxOutputTokens: 8 },
      }),
    },
    fetchImpl,
  );
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return {
    model: fullModel,
    modelCount: Array.isArray(listed.models) ? listed.models.length : 0,
    testStatus: inference.status,
  };
}

async function verifyKimi(
  credential: string,
  model: string,
  runTest: boolean,
  fetchImpl: typeof fetch,
) {
  if (!MODEL_NAME.test(model)) throw new Error("MODEL_REQUIRED");
  const headers = {
    authorization: `Bearer ${credential}`,
    accept: "application/json",
  };
  const models = await providerFetch(
    "https://api.moonshot.ai/v1/models",
    { headers },
    fetchImpl,
  );
  const listed = await readJson(models);
  const available =
    Array.isArray(listed.data) &&
    listed.data.some(
      (item) =>
        typeof item === "object" &&
        item !== null &&
        String((item as Record<string, unknown>).id || "") === model,
    );
  if (!models.ok || !available) throw new Error("MODEL_NOT_AVAILABLE");
  if (!runTest) {
    return {
      model,
      modelCount: Array.isArray(listed.data) ? listed.data.length : 0,
      testStatus: null,
    };
  }
  const inference = await providerFetch(
    "https://api.moonshot.ai/v1/chat/completions",
    {
      method: "POST",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: "Reply OK." }],
        max_tokens: 8,
      }),
    },
    fetchImpl,
  );
  if (!inference.ok) throw new Error("TEST_INFERENCE_FAILED");
  return {
    model,
    modelCount: Array.isArray(listed.data) ? listed.data.length : 0,
    testStatus: inference.status,
  };
}

export async function verifyPandoraConnectionProvider(
  provider: string,
  credential: string,
  body: Record<string, unknown>,
  fetchImpl: typeof fetch = fetch,
): Promise<PandoraProviderVerification> {
  if (!PANDORA_CONNECTION_PROVIDER_KEYS.has(provider)) {
    throw new Error("PROVIDER_NOT_SUPPORTED");
  }
  const tenantKey = connectionText(body.tenantKey);
  if (!isPandoraTenantKey(tenantKey)) throw new Error("TENANT_KEY_INVALID");
  if (provider === "posthog") {
    return await verifyPosthog(
      credential,
      connectionText(body.host),
      connectionText(body.projectId),
      tenantKey,
      fetchImpl,
    );
  }
  const model = connectionText(body.model);
  const runTest = body.runTestInference === true;
  const detail =
    provider === "openai"
      ? await verifyOpenAI(credential, model, runTest, fetchImpl)
      : provider === "gemini"
        ? await verifyGemini(credential, model, runTest, fetchImpl)
        : await verifyKimi(credential, model, runTest, fetchImpl);
  return {
    subject: await sha256(credential),
    label: `${provider[0].toUpperCase()}${provider.slice(1)} API credential`,
    tenantKey,
    tenantLabel: tenantKey,
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
