import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { resolveVercelWorkloadToken } from "../src/runtime/vercel-workload-identity.js";

const runtime = require("../src/providers/aws-bedrock-runtime.js") as {
  BEDROCK_ROLE_ARN: string;
  BEDROCK_REGION: string;
  assumeRoleWithVercelOidc: (input: Record<string, unknown>) => Promise<Record<string, string>>;
  converseWithBedrockTarget: (input: Record<string, unknown>) => Promise<any>;
};
const catalog = require("../src/providers/aws-bedrock-catalog-sync.js") as {
  discoverBedrockCatalog: (input: Record<string, unknown>) => Promise<any[]>;
  applyProbeResult: (row: any, probe: any) => any;
};

export const config = { api: { bodyParser: false }, maxDuration: 300 };

const SUPABASE_URL = "https://jcyqixttuebxqqfkjonq.supabase.co";
const ROUTE = "/api/bedrock-model-catalog-sync";
const MAX_BODY_BYTES = 64;
const CONCURRENCY = 8;

async function readBody(req: any) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const value = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += value.length;
    if (size > MAX_BODY_BYTES) throw new Error("BEDROCK_SYNC_BODY_INVALID");
    chunks.push(value);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  if (raw !== "{}") throw new Error("BEDROCK_SYNC_BODY_INVALID");
  return raw;
}
function safeEqualHex(a: string, b: string) {
  if (!/^[0-9a-f]{64}$/.test(a) || !/^[0-9a-f]{64}$/.test(b)) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}
function verifyWake(req: any, rawBody: string) {
  const secret = String(process.env.PANDORA_OPS_WAKE_HMAC_SECRET || "");
  if (secret.length < 32) throw new Error("BEDROCK_SYNC_WAKE_SECRET_UNAVAILABLE");
  const timestamp = String(req.headers?.["x-pandora-wake-timestamp"] || "");
  const nonce = String(req.headers?.["x-pandora-wake-nonce"] || "");
  const signature = String(req.headers?.["x-pandora-wake-signature"] || "").toLowerCase();
  const issuedAt = Number(timestamp);
  if (!/^\d{10}$/.test(timestamp) || !/^[0-9a-f-]{36}$/i.test(nonce) ||
      !Number.isSafeInteger(issuedAt) || Math.abs(Math.floor(Date.now() / 1000) - issuedAt) > 120) {
    throw new Error("BEDROCK_SYNC_WAKE_DENIED");
  }
  const expected = createHmac("sha256", secret)
    .update(`${timestamp}\n${nonce}\nPOST\n${ROUTE}\n${rawBody}`)
    .digest("hex");
  if (!safeEqualHex(signature, expected)) throw new Error("BEDROCK_SYNC_WAKE_DENIED");
  return { nonce, issuedAt };
}
async function rpc(name: string, body: Record<string, unknown>) {
  const service = String(process.env.SUPABASE_SERVICE_ROLE_KEY || "");
  if (service.length < 40) throw new Error("BEDROCK_SYNC_SUPABASE_UNAVAILABLE");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: service,
      authorization: `Bearer ${service}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    redirect: "error",
    signal: AbortSignal.timeout(15000),
  });
  const text = await response.text();
  let payload: any = null;
  try { payload = text ? JSON.parse(text) : null; } catch {}
  if (!response.ok) throw Object.assign(new Error("BEDROCK_SYNC_SUPABASE_RPC_FAILED"), { status: response.status });
  return payload;
}
async function mapLimit(items: any[], limit: number, worker: (item: any, index: number) => Promise<any>) {
  const output = new Array(items.length);
  let cursor = 0;
  async function run() {
    while (cursor < items.length) {
      const index = cursor++;
      output[index] = await worker(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length || 1) }, run));
  return output;
}
function classifyProbeError(error: any) {
  const status = Number(error?.status || 0);
  const detail = String(error?.awsCode || "").toLowerCase();
  if (status === 403 || /access denied|not authorized|not available for account/.test(detail)) return "access_denied";
  if (status === 429 || /throttl/.test(detail)) return "throttled";
  if (status === 400 || /validation|unsupported|invalid/.test(detail)) return "invalid_or_unsupported";
  if (/timeout|abort/.test(String(error?.name || "") + " " + String(error?.message || ""))) return "timeout";
  return "provider_unavailable";
}
function usageNumber(value: unknown) {
  const n = Number(value || 0);
  return Number.isSafeInteger(n) && n >= 0 ? n : 0;
}
function response(res: any, status: number, body: Record<string, unknown>) {
  res.status(status);
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.setHeader("cache-control", "no-store");
  res.setHeader("x-content-type-options", "nosniff");
  res.end(JSON.stringify(body));
}

export default async function bedrockCatalogSync(req: any, res: any) {
  let syncId: string | null = null;
  try {
    if (req.method !== "POST" || new URL(String(req.url || ROUTE), "https://mcpmaster.vercel.app").pathname !== ROUTE) {
      return response(res, 405, { ok: false, error: "BEDROCK_SYNC_METHOD_DENIED" });
    }
    const rawBody = await readBody(req);
    const wake = verifyWake(req, rawBody);
    const nonceAccepted = await rpc("pandora_bedrock_sync_nonce_consume_v1", {
      p_nonce: wake.nonce,
      p_issued_at: wake.issuedAt,
    });
    if (nonceAccepted !== true) throw new Error("BEDROCK_SYNC_WAKE_REPLAY");

    const claim = await rpc("pandora_bedrock_catalog_sync_claim_v1", {});
    if (!claim || claim.mode !== "execute" || typeof claim.syncId !== "string") {
      return response(res, 202, { ok: true, state: claim?.mode || "busy", probed: 0 });
    }
    syncId = claim.syncId;

    const oidc = process.env.VERCEL === "1" ? await resolveVercelWorkloadToken() : undefined;
    if (!oidc) throw new Error("BEDROCK_SYNC_WORKLOAD_IDENTITY_UNAVAILABLE");
    const credentials = await runtime.assumeRoleWithVercelOidc({
      roleArn: runtime.BEDROCK_ROLE_ARN,
      webIdentityToken: oidc,
      fetchFn: globalThis.fetch,
    });
    const observedAt = new Date().toISOString();
    const discovered = await catalog.discoverBedrockCatalog({
      credentials,
      fetchFn: globalThis.fetch,
      region: runtime.BEDROCK_REGION,
      observedAt,
    });
    const conversational = discovered.filter((row) =>
      Array.isArray(row.workflowScopes) && row.workflowScopes.includes("conversation") &&
      typeof row.invocationTarget === "string" && row.invocationTarget &&
      ["ACTIVE", "LEGACY"].includes(String(row.lifecycleStatus || "")));

    const probeResults = await mapLimit(conversational, CONCURRENCY, async (row) => {
      const started = Date.now();
      try {
        const value = await runtime.converseWithBedrockTarget({
          modelId: row.modelId,
          invocationTarget: row.invocationTarget,
          providerName: row.providerName,
          prompt: "OK",
          maxTokens: 1,
          credentials,
          fetchFn: globalThis.fetch,
          timeoutMs: 20000,
        });
        const usage = value?.usage || {};
        return {
          modelId: row.modelId,
          invocationTarget: row.invocationTarget,
          ok: true,
          inputTokens: usageNumber(usage.inputTokens),
          outputTokens: usageNumber(usage.outputTokens),
          totalTokens: usageNumber(usage.totalTokens) || usageNumber(usage.inputTokens) + usageNumber(usage.outputTokens),
          providerRequestId: value?.providerRequestId || null,
          observedAt: new Date().toISOString(),
          latencyMs: Date.now() - started,
        };
      } catch (error: any) {
        return {
          modelId: row.modelId,
          invocationTarget: row.invocationTarget,
          ok: false,
          errorCode: classifyProbeError(error),
          inputTokens: 0,
          outputTokens: 0,
          totalTokens: 0,
          providerRequestId: null,
          observedAt: new Date().toISOString(),
          latencyMs: Date.now() - started,
        };
      }
    });

    const probeById = new Map(probeResults.map((item) => [item.modelId, item]));
    const rows = discovered.map((row) => {
      const probe = probeById.get(row.modelId);
      return probe ? catalog.applyProbeResult(row, probe) : row;
    });

    const applied = await rpc("pandora_apply_bedrock_catalog_sync_v2", {
      p_sync_id: syncId,
      p_region: runtime.BEDROCK_REGION,
      p_observed_at: observedAt,
      p_models: rows,
    });
    const routable = rows.filter((row) => row.routable === true);
    return response(res, 200, {
      ok: true,
      syncId,
      state: "verified",
      discovered: rows.length,
      conversational: conversational.length,
      probed: probeResults.length,
      routable: routable.length,
      retired: Number(applied?.retired || 0),
      probes: probeResults,
    });
  } catch (error: any) {
    if (syncId) {
      try {
        await rpc("pandora_bedrock_catalog_sync_fail_v1", {
          p_sync_id: syncId,
          p_reason: String(error?.message || "BEDROCK_SYNC_FAILED").slice(0, 160),
        });
      } catch {}
    }
    return response(res, 503, { ok: false, error: String(error?.message || "BEDROCK_SYNC_FAILED").slice(0, 120) });
  }
}
