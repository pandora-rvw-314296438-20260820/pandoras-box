
"use strict";

const crypto = require("node:crypto");
const { resolveVercelWorkloadToken } = require("../runtime/vercel-workload-identity.js");

const DEFAULT_REGION = "us-east-1";
const DEFAULT_FAST_MODEL = "us.openai.gpt-5.6-luna";
const DEFAULT_STANDARD_MODEL = "us.openai.gpt-5.6-sol";
const HEALTH_OK = "PANDORA_BEDROCK_OK";
const HEALTHY_TTL_MS = 5 * 60 * 1000;
const DEGRADED_TTL_MS = 30 * 1000;

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

async function assumeRoleWithVercelOidc({
  roleArn,
  webIdentityToken,
  fetchFn = globalThis.fetch,
  sessionName = "pandora-vercel-bedrock",
  durationSeconds = 900,
}) {
  if (!roleArn || !webIdentityToken) {
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

async function converseWithBedrock({
  prompt,
  mode = "standard",
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveVercelWorkloadToken,
  now = new Date(),
  maxTokens = 256,
}) {
  const roleArn = environment.AWS_ROLE_ARN?.trim();
  const region = environment.AWS_REGION?.trim() || DEFAULT_REGION;
  const fastModel = environment.PANDORA_BEDROCK_FAST_MODEL?.trim() || DEFAULT_FAST_MODEL;
  const standardModel =
    environment.PANDORA_BEDROCK_STANDARD_MODEL?.trim() || DEFAULT_STANDARD_MODEL;
  const modelId = mode === "fast" ? fastModel : standardModel;
  const workloadToken = await resolveWorkloadToken();
  if (!workloadToken) {
    throw new Error("AWS_WORKLOAD_IDENTITY_UNAVAILABLE");
  }
  const credentials = await assumeRoleWithVercelOidc({
    roleArn,
    webIdentityToken: workloadToken,
    fetchFn,
  });
  const requestBody = {
    messages: [{ role: "user", content: [{ text: prompt }] }],
    inferenceConfig: {
      maxTokens,
      temperature: 0,
    },
  };
  const signed = signBedrockRequest({
    region,
    modelId,
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
  if (!text) {
    throw new Error("AWS_BEDROCK_RESPONSE_INVALID");
  }
  return {
    text,
    modelId,
    region,
    usage: payload?.usage || null,
    stopReason: payload?.stopReason || null,
  };
}

function createBedrockHealthProbe(
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveVercelWorkloadToken,
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
      const roleArn = environment.AWS_ROLE_ARN?.trim();
      if (!roleArn) {
        return {
          status: "degraded",
          service: "pandora-bedrock-runtime",
          authentication: "vercel_oidc_sts",
          checkedAt,
          reason: "aws_role_unconfigured",
        };
      }
      try {
        const result = await converseWithBedrock({
          prompt: `Return exactly ${HEALTH_OK}`,
          mode: "fast",
          environment,
          fetchFn,
          resolveWorkloadToken,
          now: new Date(now()),
          maxTokens: 16,
        });
        if (result.text !== HEALTH_OK) {
          throw new Error("AWS_BEDROCK_HEALTH_RESPONSE_MISMATCH");
        }
        return {
          status: "healthy",
          service: "pandora-bedrock-runtime",
          authentication: "vercel_oidc_sts",
          model: result.modelId,
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
  assumeRoleWithVercelOidc,
  signBedrockRequest,
  converseWithBedrock,
  createBedrockHealthProbe,
};
