"use strict";

const crypto = require("node:crypto");
const {
  BEDROCK_REGION,
  BEDROCK_ROLE_ARN,
  getBedrockReasoningModel,
} = require("./aws-bedrock-catalog.js");

const DEFAULT_FAST_MODEL = "openai.gpt-6-luna";
const DEFAULT_STANDARD_MODEL = "openai.gpt-6-astra";
const HEALTH_OK = "PANDORA_BEDROCK_OK";
const HEALTHY_TTL_MS = 5 * 60 * 1000;
const DEGRADED_TTL_MS = 30 * 1000;

async function resolveDefaultWorkloadToken() {
  const { resolveVercelWorkloadToken } = require("../runtime/vercel-workload-identity.js");
  return resolveVercelWorkloadToken();
}

function hmac(key, value, encoding) {
  return crypto.createHmac("sha256", key).update(value, "utf8").digest(encoding);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

function xmlText(xml, tag) {
  const match = String(xml || "").match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  return match ? match[1] : "";
}

function encodeModelPath(modelId) {
  return `/model/${encodeURIComponent(modelId)}/converse`;
}

function runtimeConfig(environment = process.env) {
  const configuredRegion = String(environment.AWS_REGION || "").trim();
  if (configuredRegion && configuredRegion !== BEDROCK_REGION) {
    throw new Error("AWS_BEDROCK_REGION_DENIED");
  }
  // The role is a source-bound security constant. Legacy deployment env may
  // still name an older broad role, but runtime execution never consumes it.
  return { roleArn: BEDROCK_ROLE_ARN, region: BEDROCK_REGION };
}

async function assumeRoleWithVercelOidc({
  roleArn,
  webIdentityToken,
  fetchFn = globalThis.fetch,
  sessionName = "pandora-vercel-bedrock",
  durationSeconds = 900,
}) {
  if (roleArn !== BEDROCK_ROLE_ARN || !webIdentityToken) {
    throw new Error("AWS_WORKLOAD_IDENTITY_UNAVAILABLE");
  }
  const body = new URLSearchParams({
    Action: "AssumeRoleWithWebIdentity",
    Version: "2011-06-15",
    RoleArn: roleArn,
    RoleSessionName: sessionName,
    WebIdentityToken: webIdentityToken,
    DurationSeconds: String(durationSeconds),
  });
  const response = await fetchFn("https://sts.amazonaws.com/", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded; charset=utf-8" },
    body: body.toString(),
  });
  const raw = await response.text();
  if (!response.ok) {
    const error = new Error("AWS_STS_WEB_IDENTITY_FAILED");
    error.status = response.status;
    throw error;
  }
  const credentials = {
    accessKeyId: xmlText(raw, "AccessKeyId"),
    secretAccessKey: xmlText(raw, "SecretAccessKey"),
    sessionToken: xmlText(raw, "SessionToken"),
    expiration: xmlText(raw, "Expiration"),
  };
  if (!credentials.accessKeyId || !credentials.secretAccessKey || !credentials.sessionToken) {
    throw new Error("AWS_STS_CREDENTIAL_RESPONSE_INVALID");
  }
  return credentials;
}

function signBedrockRequest({
  region,
  modelId,
  body,
  credentials,
  now = new Date(),
}) {
  if (region !== BEDROCK_REGION) throw new Error("AWS_BEDROCK_REGION_DENIED");
  const service = "bedrock";
  const host = `bedrock-runtime.${region}.amazonaws.com`;
  const path = encodeModelPath(modelId);
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const payload = JSON.stringify(body);
  const payloadHash = sha256(payload);
  const canonicalHeaders =
    `content-type:application/json\n` +
    `host:${host}\n` +
    `x-amz-date:${amzDate}\n` +
    `x-amz-security-token:${credentials.sessionToken}\n`;
  const signedHeaders = "content-type;host;x-amz-date;x-amz-security-token";
  const canonicalRequest = [
    "POST",
    path,
    "",
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    sha256(canonicalRequest),
  ].join("\n");
  const kDate = hmac(Buffer.from(`AWS4${credentials.secretAccessKey}`, "utf8"), dateStamp);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, service);
  const kSigning = hmac(kService, "aws4_request");
  const signature = crypto
    .createHmac("sha256", kSigning)
    .update(stringToSign, "utf8")
    .digest("hex");
  const authorization =
    `AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;
  return {
    url: `https://${host}${path}`,
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-amz-date": amzDate,
      "x-amz-security-token": credentials.sessionToken,
      authorization,
    },
    body: payload,
  };
}

function normalizeParts({ prompt, parts }) {
  if (Array.isArray(parts) && parts.length) {
    return parts.map((part) => {
      if (part?.type === "text" && typeof part.text === "string" && part.text) {
        return { text: part.text };
      }
      if (
        part?.type === "image" &&
        typeof part.data === "string" &&
        ["image/png", "image/jpeg", "image/webp"].includes(part.mimeType)
      ) {
        const format = part.mimeType === "image/jpeg" ? "jpeg" : part.mimeType.split("/")[1];
        return { image: { format, source: { bytes: part.data } } };
      }
      throw new Error("AWS_BEDROCK_INPUT_INVALID");
    });
  }
  if (typeof prompt !== "string" || !prompt.trim()) throw new Error("AWS_BEDROCK_INPUT_INVALID");
  return [{ text: prompt }];
}

async function converseWithBedrockModel({
  modelId,
  prompt,
  parts,
  system,
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveDefaultWorkloadToken,
  now = new Date(),
  maxTokens = 256,
}) {
  const model = getBedrockReasoningModel(modelId);
  if (!model) throw new Error("AWS_BEDROCK_MODEL_DENIED");
  if (!Number.isSafeInteger(maxTokens) || maxTokens < 1 || maxTokens > 8192) {
    throw new Error("AWS_BEDROCK_OUTPUT_LIMIT_INVALID");
  }
  const { roleArn, region } = runtimeConfig(environment);
  const workloadToken = await resolveWorkloadToken();
  if (!workloadToken) throw new Error("AWS_WORKLOAD_IDENTITY_UNAVAILABLE");
  const credentials = await assumeRoleWithVercelOidc({
    roleArn,
    webIdentityToken: workloadToken,
    fetchFn,
  });
  const requestBody = {
    messages: [{ role: "user", content: normalizeParts({ prompt, parts }) }],
    inferenceConfig: { maxTokens, temperature: 0 },
  };
  if (typeof system === "string" && system.trim()) {
    requestBody.system = [{ text: system.trim() }];
  }
  const signed = signBedrockRequest({
    region,
    modelId: model.invocationTarget,
    body: requestBody,
    credentials,
    now,
  });
  const response = await fetchFn(signed.url, signed);
  const raw = await response.text();
  let payload;
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = {};
  }
  if (!response.ok) {
    const error = new Error("AWS_BEDROCK_CONVERSE_FAILED");
    error.status = response.status;
    error.awsCode =
      typeof payload?.message === "string" ? payload.message.slice(0, 240) : undefined;
    throw error;
  }
  const content = Array.isArray(payload?.output?.message?.content)
    ? payload.output.message.content
    : [];
  const text = content
    .map((item) => (typeof item?.text === "string" ? item.text : ""))
    .join("")
    .trim();
  if (!text) throw new Error("AWS_BEDROCK_RESPONSE_INVALID");
  return {
    text,
    modelId: model.modelId,
    invocationTarget: model.invocationTarget,
    providerName: model.providerName,
    region,
    usage: payload?.usage || null,
    stopReason: payload?.stopReason || null,
    providerRequestId: response.headers?.get?.("x-amzn-requestid") || null,
  };
}

async function converseWithBedrock({
  prompt,
  mode = "standard",
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveDefaultWorkloadToken,
  now = new Date(),
  maxTokens = 256,
}) {
  const requestedFast = String(environment.PANDORA_BEDROCK_FAST_MODEL || "").trim();
  const requestedStandard = String(environment.PANDORA_BEDROCK_STANDARD_MODEL || "").trim();
  // Accept only canonical foundation-model IDs from the governed catalog.
  // Legacy inference-profile IDs are ignored instead of becoming authority.
  const fastModel = getBedrockReasoningModel(requestedFast) ? requestedFast : DEFAULT_FAST_MODEL;
  const standardModel = getBedrockReasoningModel(requestedStandard)
    ? requestedStandard
    : DEFAULT_STANDARD_MODEL;
  return converseWithBedrockModel({
    modelId: mode === "fast" ? fastModel : standardModel,
    prompt,
    environment,
    fetchFn,
    resolveWorkloadToken,
    now,
    maxTokens,
  });
}

function createBedrockHealthProbe(
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveDefaultWorkloadToken,
  now = Date.now,
) {
  let cached;
  let inFlight;
  return async () => {
    const current = now();
    if (cached && cached.expiresAt > current) return cached.value;
    if (inFlight) return inFlight;
    inFlight = (async () => {
      const checkedAt = new Date(now()).toISOString();
      try {
        const result = await converseWithBedrockModel({
          modelId: DEFAULT_FAST_MODEL,
          prompt: `Return exactly ${HEALTH_OK}`,
          environment,
          fetchFn,
          resolveWorkloadToken,
          now: new Date(now()),
          maxTokens: 16,
        });
        if (result.text !== HEALTH_OK) throw new Error("AWS_BEDROCK_HEALTH_RESPONSE_MISMATCH");
        return {
          status: "healthy",
          service: "pandora-bedrock-runtime",
          authentication: "vercel_oidc_sts",
          model: result.modelId,
          invocationTarget: result.invocationTarget,
          region: result.region,
          checkedAt,
        };
      } catch (error) {
        return {
          status: "degraded",
          service: "pandora-bedrock-runtime",
          authentication: "vercel_oidc_sts",
          checkedAt,
          reason:
            error instanceof Error
              ? error.message.toLowerCase()
              : "aws_bedrock_unavailable",
        };
      }
    })();
    try {
      const value = await inFlight;
      cached = {
        expiresAt:
          now() + (value.status === "healthy" ? HEALTHY_TTL_MS : DEGRADED_TTL_MS),
        value,
      };
      return value;
    } finally {
      inFlight = undefined;
    }
  };
}

module.exports = {
  DEFAULT_FAST_MODEL,
  DEFAULT_STANDARD_MODEL,
  BEDROCK_ROLE_ARN,
  BEDROCK_REGION,
  runtimeConfig,
  assumeRoleWithVercelOidc,
  signBedrockRequest,
  converseWithBedrock,
  converseWithBedrockModel,
  createBedrockHealthProbe,
};
