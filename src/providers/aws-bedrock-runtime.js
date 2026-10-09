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

function awsPercentEncode(value) {
  return encodeURIComponent(String(value)).replace(/[!'()*]/g, (char) =>
    "%" + char.charCodeAt(0).toString(16).toUpperCase());
}

function canonicalQuery(params = {}) {
  return Object.entries(params)
    .filter(([, value]) => value !== undefined && value !== null && String(value) !== "")
    .map(([key, value]) => [awsPercentEncode(key), awsPercentEncode(value)])
    .sort(([aKey, aValue], [bKey, bValue]) => aKey.localeCompare(bKey) || aValue.localeCompare(bValue))
    .map(([key, value]) => `${key}=${value}`)
    .join("&");
}

function signBedrockControlRequest({
  region,
  path,
  query = {},
  credentials,
  now = new Date(),
}) {
  if (region !== BEDROCK_REGION) throw new Error("AWS_BEDROCK_REGION_DENIED");
  if (typeof path !== "string" || !path.startsWith("/") || path.includes("..")) {
    throw new Error("AWS_BEDROCK_CONTROL_PATH_INVALID");
  }
  const service = "bedrock";
  const host = `bedrock.${region}.amazonaws.com`;
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const canonical = canonicalQuery(query);
  const payloadHash = sha256("");
  const canonicalHeaders =
    `host:${host}\n` +
    `x-amz-date:${amzDate}\n` +
    `x-amz-security-token:${credentials.sessionToken}\n`;
  const signedHeaders = "host;x-amz-date;x-amz-security-token";
  const canonicalRequest = ["GET", path, canonical, canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(canonicalRequest)].join("\n");
  const kDate = hmac(Buffer.from(`AWS4${credentials.secretAccessKey}`, "utf8"), dateStamp);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, service);
  const kSigning = hmac(kService, "aws4_request");
  const signature = crypto.createHmac("sha256", kSigning).update(stringToSign, "utf8").digest("hex");
  const authorization =
    `AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;
  return {
    url: `https://${host}${path}${canonical ? `?${canonical}` : ""}`,
    method: "GET",
    headers: {
      "x-amz-date": amzDate,
      "x-amz-security-token": credentials.sessionToken,
      authorization,
    },
  };
}

async function bedrockControlJson({
  path,
  query = {},
  credentials,
  region = BEDROCK_REGION,
  fetchFn = globalThis.fetch,
  now = new Date(),
  timeoutMs = 15000,
}) {
  const signed = signBedrockControlRequest({ region, path, query, credentials, now });
  const response = await fetchFn(signed.url, {
    ...signed,
    signal: typeof AbortSignal?.timeout === "function" ? AbortSignal.timeout(timeoutMs) : undefined,
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = {}; }
  if (!response.ok) {
    const error = new Error("AWS_BEDROCK_CONTROL_FAILED");
    error.status = response.status;
    error.awsCode = typeof payload?.message === "string" ? payload.message.slice(0, 240) : undefined;
    throw error;
  }
  return payload;
}

function xmlText(xml, tag) {
  const match = String(xml || "").match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  return match ? match[1] : "";
}

function rfc3986PathSegment(value) {
  return encodeURIComponent(String(value)).replace(/[!'()*]/g, (character) =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

function canonicalAwsPath(path) {
  if (typeof path !== "string" || !path.startsWith("/")) {
    throw new Error("AWS_BEDROCK_PATH_INVALID");
  }
  return path
    .split("/")
    .map((segment, index) => (index === 0 ? "" : rfc3986PathSegment(segment)))
    .join("/");
}

function modelPath(modelId, stream = false) {
  return `/model/${String(modelId)}/${stream ? "converse-stream" : "converse"}`;
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
  signal,
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
    signal,
    redirect: "error",
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
  stream = false,
}) {
  if (region !== BEDROCK_REGION) throw new Error("AWS_BEDROCK_REGION_DENIED");
  const service = "bedrock";
  const host = `bedrock-runtime.${region}.amazonaws.com`;
  const rawModelId = String(modelId || "");
  // SigV4 signs the RFC3986-encoded canonical URI, while the actual HTTP URL
  // keeps the Bedrock model identifier raw. Accepting a caller-preencoded
  // "%3A" target would make the wire path and canonical path disagree.
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/.test(rawModelId)) {
    throw new Error("AWS_BEDROCK_MODEL_DENIED");
  }
  const wirePath = modelPath(rawModelId, stream);
  const canonicalPath = canonicalAwsPath(wirePath);
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
    canonicalPath,
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
    url: `https://${host}${wirePath}`,
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

function normalizeMessages({ messages, prompt, parts }) {
  if (messages === undefined || messages === null) {
    return [{ role: "user", content: normalizeParts({ prompt, parts }) }];
  }
  // Native history is a separate contract. Never silently flatten it or choose
  // between two competing representations of the same conversation.
  if ((parts !== undefined && parts !== null) || prompt !== undefined ||
      !Array.isArray(messages) || messages.length < 1 || messages.length > 128) {
    throw new Error("AWS_BEDROCK_INPUT_INVALID");
  }
  return messages.map((message) => {
    if (!message || !["user", "assistant"].includes(message.role) ||
        !Array.isArray(message.content) || !message.content.length || message.content.length > 64) {
      throw new Error("AWS_BEDROCK_INPUT_INVALID");
    }
    const content = message.content.map((block) => {
      if (!block || typeof block !== "object" || Array.isArray(block) || Object.keys(block).length !== 1) {
        throw new Error("AWS_BEDROCK_INPUT_INVALID");
      }
      if (typeof block.text === "string" && block.text.trim()) return { text: block.text };
      const image = block.image;
      if (message.role === "user" && image && ["png", "jpeg", "webp"].includes(image.format) &&
          typeof image.source?.bytes === "string" && image.source.bytes.length > 0 &&
          /^[A-Za-z0-9+/]+={0,2}$/.test(image.source.bytes)) {
        return { image: { format: image.format, source: { bytes: image.source.bytes } } };
      }
      throw new Error("AWS_BEDROCK_INPUT_INVALID");
    });
    return { role: message.role, content };
  });
}

function normalizeSystem(system) {
  if (system === undefined || system === null || system === "") return undefined;
  if (typeof system === "string") return system.trim() ? [{ text: system.trim() }] : undefined;
  if (!Array.isArray(system) || system.length > 64 || system.some((part) =>
    !part || typeof part.text !== "string" || !part.text.trim() || Object.keys(part).length !== 1)) {
    throw new Error("AWS_BEDROCK_INPUT_INVALID");
  }
  return system.length ? system.map((part) => ({ text: part.text })) : undefined;
}

function abortError(signal) {
  const timeout = signal?.reason?.name === "TimeoutError";
  return Object.assign(new Error(timeout ? "AWS_BEDROCK_TIMEOUT" : "AWS_BEDROCK_CANCELLED"), {
    name: timeout ? "TimeoutError" : "AbortError", status: timeout ? 504 : 499,
  });
}

function checkActive(signal) {
  if (signal?.aborted) throw abortError(signal);
}

function waitWithSignal(promise, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => { cleanup(); reject(abortError(signal)); };
    const cleanup = () => signal?.removeEventListener("abort", abort);
    signal?.addEventListener("abort", abort, { once: true });
    Promise.resolve(promise).then((value) => { cleanup(); resolve(value); }, (error) => { cleanup(); reject(error); });
    if (signal?.aborted) abort();
  });
}

function requestLifetime(parentSignal, timeoutMs) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 180000) {
    throw new Error("AWS_BEDROCK_TIMEOUT_INVALID");
  }
  const controller = new AbortController();
  const abort = () => controller.abort(parentSignal?.reason);
  parentSignal?.addEventListener("abort", abort, { once: true });
  if (parentSignal?.aborted) abort();
  const timer = setTimeout(() => controller.abort(
    Object.assign(new Error("AWS_BEDROCK_TIMEOUT"), { name: "TimeoutError" }),
  ), timeoutMs);
  timer.unref?.();
  return {
    signal: controller.signal,
    abort: () => controller.abort(),
    dispose: () => { clearTimeout(timer); parentSignal?.removeEventListener("abort", abort); },
  };
}

function safeProviderRequestId(value) {
  return typeof value === "string" && /^[A-Za-z0-9._:-]{1,200}$/.test(value) &&
    !/^(?:Bearer|Basic|sk[-_]|sb_(?:secret|publishable)_|gh[pousr]_|github_pat_|eyJ|(?:AKIA|ASIA)[A-Z0-9]{16})/i.test(value) ? value : null;
}

function safeAwsCode(value) {
  if (typeof value !== "string") return undefined;
  const code = value.split("#").pop().split(":")[0];
  return /^[A-Za-z][A-Za-z0-9]{0,100}$/.test(code) ? code : undefined;
}

function safeUsage(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const usage = {};
  for (const key of ["inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens"]) {
    if (Number.isSafeInteger(value[key]) && value[key] >= 0) usage[key] = value[key];
  }
  return Object.keys(usage).length ? usage : null;
}

function measuredMs(value) {
  return Number.isFinite(value) && value >= 0 ? Math.round(value) : null;
}

// Application resource budgets, not AWS protocol size limits. Validate the
// prelude CRC before trusting its lengths or allocating a complete frame.
const MAX_STREAM_FRAME_BYTES = 32 * 1024 * 1024;
const MAX_STREAM_BYTES = 64 * 1024 * 1024;
const MAX_STREAM_TEXT_BYTES = 2 * 1024 * 1024;
const crcTable = Uint32Array.from({ length: 256 }, (_, n) => {
  let crc = n;
  for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  return crc >>> 0;
});
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function streamHeaders(bytes) {
  const headers = new Map(), decoder = new TextDecoder("utf-8", { fatal: true });
  let offset = 0;
  const take = (length) => {
    if (offset + length > bytes.length) throw new Error("AWS_BEDROCK_STREAM_HEADERS_INVALID");
    const value = bytes.subarray(offset, offset + length); offset += length; return value;
  };
  while (offset < bytes.length) {
    const length = take(1)[0];
    if (!length) throw new Error("AWS_BEDROCK_STREAM_HEADERS_INVALID");
    const name = decoder.decode(take(length)), type = take(1)[0];
    if (headers.has(name)) throw new Error("AWS_BEDROCK_STREAM_HEADERS_INVALID");
    let value;
    if (type === 0 || type === 1) value = type === 0;
    else if (type === 2) value = take(1).readInt8();
    else if (type === 3) value = take(2).readInt16BE();
    else if (type === 4) value = take(4).readInt32BE();
    else if (type === 5 || type === 8) value = take(8).readBigInt64BE();
    else if (type === 6 || type === 7) {
      const data = take(take(2).readUInt16BE());
      value = type === 7 ? decoder.decode(data) : data;
    } else if (type === 9) value = take(16);
    else throw new Error("AWS_BEDROCK_STREAM_HEADERS_INVALID");
    headers.set(name, value);
  }
  return headers;
}

async function* readAwsEventStream(body, signal) {
  if (!body || typeof body.getReader !== "function") throw new Error("AWS_BEDROCK_STREAM_BODY_INVALID");
  const reader = body.getReader(), prelude = Buffer.alloc(12);
  let preludeOffset = 0, frame = null, frameOffset = 0, headersLength = 0, bytesRead = 0, complete = false;
  const cancel = () => { reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", cancel, { once: true });
  try {
    checkActive(signal);
    while (true) {
      const { value, done } = await waitWithSignal(reader.read(), signal);
      checkActive(signal);
      if (done) break;
      if (!(value instanceof Uint8Array)) throw new Error("AWS_BEDROCK_STREAM_BODY_INVALID");
      const chunk = Buffer.from(value.buffer, value.byteOffset, value.byteLength);
      bytesRead += chunk.length;
      if (bytesRead > MAX_STREAM_BYTES) throw new Error("AWS_BEDROCK_STREAM_LIMIT");
      let offset = 0;
      while (offset < chunk.length) {
        if (!frame) {
          const length = Math.min(12 - preludeOffset, chunk.length - offset);
          chunk.copy(prelude, preludeOffset, offset, offset + length);
          preludeOffset += length; offset += length;
          if (preludeOffset !== 12) continue;
          if (crc32(prelude.subarray(0, 8)) !== prelude.readUInt32BE(8)) throw new Error("AWS_BEDROCK_STREAM_CRC_INVALID");
          const totalLength = prelude.readUInt32BE(0);
          headersLength = prelude.readUInt32BE(4);
          if (totalLength < 16 || headersLength > totalLength - 16) throw new Error("AWS_BEDROCK_STREAM_FRAME_INVALID");
          if (totalLength > MAX_STREAM_FRAME_BYTES) throw new Error("AWS_BEDROCK_STREAM_LIMIT");
          frame = Buffer.alloc(totalLength); prelude.copy(frame); frameOffset = 12;
        }
        const length = Math.min(frame.length - frameOffset, chunk.length - offset);
        chunk.copy(frame, frameOffset, offset, offset + length);
        frameOffset += length; offset += length;
        if (frameOffset !== frame.length) continue;
        if (crc32(frame.subarray(0, -4)) !== frame.readUInt32BE(frame.length - 4)) throw new Error("AWS_BEDROCK_STREAM_CRC_INVALID");
        const event = { headers: streamHeaders(frame.subarray(12, 12 + headersLength)), payload: frame.subarray(12 + headersLength, -4) };
        frame = null; frameOffset = 0; preludeOffset = 0;
        checkActive(signal);
        yield event;
      }
    }
    if (frame || preludeOffset) throw new Error("AWS_BEDROCK_STREAM_TRUNCATED");
    complete = true;
  } finally {
    signal?.removeEventListener("abort", cancel);
    if (!complete) await waitWithSignal(reader.cancel(), signal).catch(() => {});
    reader.releaseLock();
  }
}

function streamException(headers) {
  const code = safeAwsCode(headers.get(":exception-type") || headers.get(":error-code"));
  const statusByCode = { accessdeniedexception: 403, throttlingexception: 429, validationexception: 400,
    resourcenotfoundexception: 404, modeltimeoutexception: 408, modelstreamerrorexception: 424,
    internalserverexception: 500, internalerror: 500, serviceunavailableexception: 503 };
  return Object.assign(new Error("AWS_BEDROCK_STREAM_FAILED"), { status: statusByCode[code?.toLowerCase()] || 502, awsCode: code });
}

async function consumeConverseStream(body, { signal, onDelta, onFirstToken }) {
  const text = [], blocks = new Map(), decoder = new TextDecoder("utf-8", { fatal: true });
  let started = false, stopped = false, metadataSeen = false, stopReason = null, usage = null;
  let textBytes = 0, providerReportedLatencyMs = null;
  const badOrder = () => { throw new Error("AWS_BEDROCK_STREAM_SEQUENCE_INVALID"); };
  for await (const event of readAwsEventStream(body, signal)) {
    const messageType = event.headers.get(":message-type"), type = event.headers.get(":event-type");
    if (messageType === "exception" || messageType === "error") throw streamException(event.headers);
    if (messageType !== "event" || typeof type !== "string" ||
        (event.headers.has(":content-type") && event.headers.get(":content-type") !== "application/json")) badOrder();
    let payload;
    try { payload = JSON.parse(decoder.decode(event.payload)); } catch { throw new Error("AWS_BEDROCK_STREAM_JSON_INVALID"); }
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) badOrder();
    if (type === "messageStart") {
      if (started || stopped || payload.role !== "assistant") badOrder();
      started = true;
    } else if (["contentBlockStart", "contentBlockDelta", "contentBlockStop"].includes(type)) {
      if (!started || stopped) badOrder();
      const index = payload.contentBlockIndex;
      if (!Number.isSafeInteger(index) || index < 0) badOrder();
      if (!blocks.has(index) && blocks.size >= 256) throw new Error("AWS_BEDROCK_STREAM_LIMIT");
      if (type === "contentBlockStart") {
        if (blocks.has(index)) badOrder();
        blocks.set(index, "open");
        if (payload.start?.toolUse) throw new Error("AWS_BEDROCK_STREAM_UNSUPPORTED_CONTENT");
      } else if (type === "contentBlockStop") {
        if (blocks.get(index) !== "open") badOrder();
        blocks.set(index, "closed");
      } else {
        if (blocks.get(index) === "closed") badOrder();
        // Bedrock may omit contentBlockStart for a plain text block.
        blocks.set(index, "open");
        if (!payload.delta || typeof payload.delta !== "object" || Array.isArray(payload.delta)) badOrder();
        if (payload.delta.toolUse) throw new Error("AWS_BEDROCK_STREAM_UNSUPPORTED_CONTENT");
        if (typeof payload.delta.text === "string" && payload.delta.text) {
          const delta = payload.delta.text;
          textBytes += Buffer.byteLength(delta);
          if (textBytes > MAX_STREAM_TEXT_BYTES) throw new Error("AWS_BEDROCK_STREAM_LIMIT");
          if (!text.length) onFirstToken();
          text.push(delta);
          checkActive(signal);
          if (onDelta) await waitWithSignal(onDelta(delta), signal);
          checkActive(signal);
        }
        // reasoningContent and other non-text blocks never enter the visible stream.
      }
    } else if (type === "messageStop") {
      if (!started || stopped || [...blocks.values()].some((state) => state !== "closed") ||
          typeof payload.stopReason !== "string" || !/^[a-z_]{1,80}$/.test(payload.stopReason)) badOrder();
      stopped = true; stopReason = payload.stopReason;
    } else if (type === "metadata") {
      if (!stopped || metadataSeen) badOrder();
      metadataSeen = true; usage = safeUsage(payload.usage);
      providerReportedLatencyMs = measuredMs(payload.metrics?.latencyMs);
    } else badOrder();
  }
  checkActive(signal);
  if (!started || !stopped || !metadataSeen) throw new Error("AWS_BEDROCK_STREAM_TRUNCATED");
  if (!text.join("").trim()) throw new Error("AWS_BEDROCK_RESPONSE_INVALID");
  return { text: text.join(""), usage, stopReason, providerReportedLatencyMs };
}

async function converseWithBedrockTarget({
  modelId,
  invocationTarget,
  providerName = null,
  prompt,
  parts,
  messages,
  system,
  environment = process.env,
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveDefaultWorkloadToken,
  now = new Date(),
  maxTokens = 256,
  temperature = null,
  credentials = null,
  timeoutMs = 30000,
  stream = false,
  signal,
  onDelta,
  clock = () => performance.now(),
}) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/.test(String(modelId || "")) ||
      !/^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/.test(String(invocationTarget || ""))) {
    throw new Error("AWS_BEDROCK_MODEL_DENIED");
  }
  if (!Number.isSafeInteger(maxTokens) || maxTokens < 1 || maxTokens > 8192) {
    throw new Error("AWS_BEDROCK_OUTPUT_LIMIT_INVALID");
  }
  if (temperature !== null && (!Number.isFinite(temperature) || temperature < 0 || temperature > 1)) {
    throw new Error("AWS_BEDROCK_TEMPERATURE_INVALID");
  }
  if (typeof stream !== "boolean" || (onDelta !== undefined && (typeof onDelta !== "function" || !stream))) {
    throw new Error("AWS_BEDROCK_STREAM_OPTIONS_INVALID");
  }
  const { roleArn, region } = runtimeConfig(environment);
  const inferenceConfig = { maxTokens };
  if (temperature !== null) inferenceConfig.temperature = temperature;
  const requestBody = { messages: normalizeMessages({ messages, prompt, parts }), inferenceConfig };
  const systemBlocks = normalizeSystem(system);
  if (systemBlocks) requestBody.system = systemBlocks;
  const lifetime = requestLifetime(signal, timeoutMs);
  let startedAt = null, providerRequestId = null, timeToFirstTokenMs = null, providerHttpStatus = null, streaming = false;
  const receipt = () => ({
    providerRequestId,
    providerHttpStatus,
    providerLatencyMs: startedAt === null ? null : measuredMs(clock() - startedAt),
    timeToFirstTokenMs,
    streaming,
    streamMode: streaming ? "converse_stream_v1" : "buffered_v1",
  });
  try {
    checkActive(lifetime.signal);
    let activeCredentials = credentials;
    if (!activeCredentials) {
      const workloadToken = await waitWithSignal(resolveWorkloadToken(), lifetime.signal);
      checkActive(lifetime.signal);
      if (!workloadToken) throw new Error("AWS_WORKLOAD_IDENTITY_UNAVAILABLE");
      activeCredentials = await waitWithSignal(assumeRoleWithVercelOidc({
        roleArn, webIdentityToken: workloadToken, fetchFn, signal: lifetime.signal,
      }), lifetime.signal);
    }
    checkActive(lifetime.signal);
    const signed = signBedrockRequest({ region, modelId: invocationTarget, body: requestBody,
      credentials: activeCredentials, now, stream });
    startedAt = clock();
    const response = await waitWithSignal(fetchFn(signed.url, {
      ...signed,
      headers: { ...signed.headers, accept: stream ? "application/vnd.amazon.eventstream" : "application/json" },
      signal: lifetime.signal,
      redirect: "error",
    }), lifetime.signal);
    checkActive(lifetime.signal);
    providerRequestId = safeProviderRequestId(response.headers?.get?.("x-amzn-requestid"));
    providerHttpStatus = Number.isSafeInteger(response.status) ? response.status : null;
    let result;
    if (stream && response.ok) {
      if (response.headers?.get?.("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/vnd.amazon.eventstream") {
        response.body?.cancel?.().catch(() => {});
        throw new Error("AWS_BEDROCK_STREAM_CONTENT_TYPE_INVALID");
      }
      streaming = true;
      result = await consumeConverseStream(response.body, {
        signal: lifetime.signal, onDelta,
        onFirstToken: () => { timeToFirstTokenMs = measuredMs(clock() - startedAt); },
      });
    } else {
      const raw = await waitWithSignal(response.text(), lifetime.signal);
      checkActive(lifetime.signal);
      let payload;
      try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = {}; }
      if (!response.ok) {
        throw Object.assign(new Error("AWS_BEDROCK_CONVERSE_FAILED"), {
          status: response.status,
          awsCode: safeAwsCode(response.headers?.get?.("x-amzn-errortype") || payload?.__type),
        });
      }
      const content = Array.isArray(payload?.output?.message?.content) ? payload.output.message.content : [];
      const text = content.map((item) => (typeof item?.text === "string" ? item.text : "")).join("").trim();
      if (!text) throw new Error("AWS_BEDROCK_RESPONSE_INVALID");
      result = { text, usage: safeUsage(payload?.usage), stopReason: payload?.stopReason || null,
        providerReportedLatencyMs: measuredMs(payload?.metrics?.latencyMs) };
    }
    checkActive(lifetime.signal);
    return { ...result, modelId, invocationTarget, providerName, region, ...receipt() };
  } catch (error) {
    const safeError = lifetime.signal.aborted ? abortError(lifetime.signal)
      : error instanceof Error && /^AWS_[A-Z0-9_]+$/.test(error.message) ? error
      : new Error("AWS_BEDROCK_TRANSPORT_FAILED");
    Object.assign(safeError, receipt());
    lifetime.abort();
    throw safeError;
  } finally {
    lifetime.dispose();
  }
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
  return converseWithBedrockTarget({
    modelId: model.modelId,
    invocationTarget: model.invocationTarget,
    providerName: model.providerName,
    prompt,
    parts,
    system,
    environment,
    fetchFn,
    resolveWorkloadToken,
    now,
    maxTokens,
  });
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
  canonicalAwsPath,
  assumeRoleWithVercelOidc,
  signBedrockRequest,
  signBedrockControlRequest,
  bedrockControlJson,
  safeProviderRequestId,
  converseWithBedrockTarget,
  converseWithBedrock,
  converseWithBedrockModel,
  createBedrockHealthProbe,
};
