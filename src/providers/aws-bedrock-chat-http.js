"use strict";

const crypto = require("node:crypto");
const { resolveVercelWorkloadToken } = require("../runtime/vercel-workload-identity.js");
const { converseWithBedrockTarget, safeProviderRequestId } = require("./aws-bedrock-runtime.js");

const MAX_BODY_BYTES = 4096;
const MAX_CLAIM_BODY_BYTES = 1048576;
const CONTROL_URL = "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";

function sha(value) { return crypto.createHash("sha256").update(value, "utf8").digest("hex"); }

function abortable(promise, signal) {
  return new Promise((resolve, reject) => {
    const cleanup = () => signal?.removeEventListener("abort", abort);
    const abort = () => { cleanup(); reject(cancelError(signal)); };
    signal?.addEventListener("abort", abort, { once: true });
    Promise.resolve(promise).then((value) => { cleanup(); resolve(value); }, (error) => { cleanup(); reject(error); });
    if (signal?.aborted) abort();
  });
}

async function claimTicket(tokenSha256, {
  fetchFn = globalThis.fetch, resolveWorkloadToken = resolveVercelWorkloadToken, signal,
} = {}) {
  const oidc = await abortable(resolveWorkloadToken(), signal);
  if (signal?.aborted) throw Object.assign(Error("BEDROCK_CHAT_CANCELLED"), { status: 499 });
  if (!oidc) throw Error("BEDROCK_CHAT_WORKLOAD_IDENTITY_UNAVAILABLE");
  const response = await abortable(fetchFn(CONTROL_URL, {
    method: "POST",
    headers: { authorization: "Bearer " + oidc, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ action:"bedrock_chat_ticket_claim", tokenSha256 }),
    redirect: "error", signal,
  }), signal);
  const raw = await abortable(response.text(), signal);
  if (!response.ok) throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED");
  let payload;
  try { payload = raw ? JSON.parse(raw) : {}; } catch { throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED"); }
  if (payload?.ok !== true || !payload.operations || typeof payload.operations !== "object" || Array.isArray(payload.operations)) {
    throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED");
  }
  return { claim: payload.operations, oidc };
}

async function readBody(req) {
  let bytes = 0;
  const chunks = [];
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    bytes += buffer.length;
    if (bytes > MAX_BODY_BYTES) throw Object.assign(Error("BODY_TOO_LARGE"), { status: 413 });
    chunks.push(buffer);
  }
  try { return bytes ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {}; }
  catch { throw Object.assign(Error("INVALID_JSON"), { status: 400 }); }
}

function safeReceipt(value) {
  const number = (v) => Number.isFinite(v) && v >= 0 ? Math.round(v) : null;
  return {
    providerRequestId: safeProviderRequestId(value?.providerRequestId),
    providerHttpStatus: Number.isSafeInteger(value?.providerHttpStatus) && value.providerHttpStatus >= 100 && value.providerHttpStatus <= 599
      ? value.providerHttpStatus : null,
    providerLatencyMs: number(value?.providerLatencyMs),
    timeToFirstTokenMs: number(value?.timeToFirstTokenMs),
    providerReportedLatencyMs: number(value?.providerReportedLatencyMs),
    streaming: value?.streaming === true,
    streamMode: value?.streaming === true ? "converse_stream_v1" : "buffered_v1",
  };
}

function envelope(error) {
  let status = Number(error?.status) || 0;
  if (error?.name === "AbortError" || /^(?:AWS_BEDROCK|BEDROCK_CHAT)_CANCELLED$/.test(error?.message || "")) status = 499;
  if (error?.name === "TimeoutError" || error?.message === "AWS_BEDROCK_TIMEOUT") status = 504;
  if (error?.message === "AWS_BEDROCK_STREAM_UNSUPPORTED_CONTENT") status = 404;
  if (/^AWS_BEDROCK_(?:INPUT|OUTPUT_LIMIT|TEMPERATURE|STREAM_OPTIONS|TIMEOUT)_INVALID$/.test(error?.message || "")) status = 400;
  if (error?.message === "BEDROCK_CHAT_REQUEST_INVALID") status = 400;
  if (!status && /^AWS_BEDROCK_(?:STREAM_|RESPONSE_INVALID)/.test(error?.message || "")) status = 502;
  if (status < 400 || status > 599) status = 503;
  const kind = status === 499 ? "cancelled"
    : status === 401 || status === 403 ? "authorization"
    : status === 429 ? "rate_limit"
    : status === 400 || status === 413 ? "invalid_request"
    : status === 404 ? "unsupported_capability"
    : status === 408 || status === 504 ? "timeout"
    : status >= 500 ? "provider_unavailable" : "provider_error";
  return { status, ok: false, error: { kind, retryable: status === 408 || status === 424 || status === 429 || status >= 500 }, ...safeReceipt(error) };
}

function acceptsEventStream(value) {
  if (typeof value !== "string") return false;
  return value.split(",").some((item) => {
    const [media, ...params] = item.trim().toLowerCase().split(";");
    if (media.trim() !== "text/event-stream") return false;
    const quality = params.find((param) => /^\s*q\s*=/.test(param));
    return !quality || Number(quality.split("=")[1].trim()) > 0;
  });
}

function cancelError(signal) {
  const timeout = signal?.reason?.name === "TimeoutError";
  return Object.assign(Error(timeout ? "AWS_BEDROCK_TIMEOUT" : "BEDROCK_CHAT_CANCELLED"), {
    name: timeout ? "TimeoutError" : "AbortError", status: timeout ? 504 : 499,
  });
}

function waitForDrain(res, signal) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      res.removeListener("drain", drained); res.removeListener("error", closed); res.removeListener("close", closed);
      signal.removeEventListener("abort", closed);
    };
    const drained = () => { cleanup(); resolve(); };
    const closed = () => { cleanup(); reject(cancelError(signal)); };
    res.once("drain", drained); res.once("error", closed); res.once("close", closed);
    signal.addEventListener("abort", closed, { once: true });
    if (signal.aborted || res.destroyed || res.writableEnded) closed();
  });
}

async function writeEvent(res, event, signal) {
  if (signal.aborted || res.destroyed || res.writableEnded) throw cancelError(signal);
  if (!res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`)) await waitForDrain(res, signal);
  if (signal.aborted || res.destroyed || res.writableEnded) throw cancelError(signal);
}

function claimedInput(claim) {
  const { modelId, invocationTarget, requestBody } = claim || {};
  if (typeof modelId !== "string" || typeof invocationTarget !== "string" ||
      !requestBody || typeof requestBody !== "object" || Array.isArray(requestBody)) throw Error("BEDROCK_CHAT_TICKET_INVALID");
  if (Object.keys(requestBody).some((key) => !["parts", "messages", "system", "maxTokens", "stream"].includes(key)) ||
      Buffer.byteLength(JSON.stringify(requestBody)) > MAX_CLAIM_BODY_BYTES ||
      (requestBody.stream !== undefined && typeof requestBody.stream !== "boolean")) throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  const native = requestBody.messages !== undefined;
  if (native ? requestBody.parts !== undefined || !Array.isArray(requestBody.messages) ||
      requestBody.messages.length < 1 || requestBody.messages.length > 128
    : !Array.isArray(requestBody.parts) || requestBody.parts.length < 1 || requestBody.parts.length > 64) {
    throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  }
  const maxTokens = Number(requestBody.maxTokens), system = requestBody.system ?? "";
  if (!Number.isSafeInteger(maxTokens) || maxTokens < 1 || maxTokens > 8192 ||
      (typeof system !== "string" && !Array.isArray(system)) ||
      (typeof system === "string" && system.length > 100000)) throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  return {
    modelId, invocationTarget,
    providerName: typeof claim.providerName === "string" ? claim.providerName : null,
    ...(native ? { messages: requestBody.messages } : { parts: requestBody.parts }),
    system, maxTokens,
  };
}

function createBedrockChatHandler({
  fetchFn = globalThis.fetch,
  resolveWorkloadToken = resolveVercelWorkloadToken,
  converse = converseWithBedrockTarget,
  timeoutMs = 150000,
} = {}) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 180000) throw Error("BEDROCK_CHAT_TIMEOUT_INVALID");
  return async function handleBedrockChat(req, res) {
    if (req.method !== "POST" || req.headers?.origin) return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    const controller = new AbortController();
    const abort = () => controller.abort();
    const close = () => { if (!res.writableEnded) controller.abort(); };
    req.once("aborted", abort); res.once("close", close); res.once("error", abort);
    const timer = setTimeout(() => controller.abort(Object.assign(Error("AWS_BEDROCK_TIMEOUT"), { name: "TimeoutError" })), timeoutMs);
    timer.unref?.();
    let streaming = false, invocationStarted = false;
    try {
      const body = await abortable(readBody(req), controller.signal), ticket = body?.ticket;
      if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).some((key) => key !== "ticket") ||
          typeof ticket !== "string" || !/^[0-9a-f]{64}$/.test(ticket)) {
        return res.status(404).json({ ok: false, error: "BEDROCK_CHAT_DENIED" });
      }
      const claimed = await claimTicket(sha(ticket), { fetchFn, resolveWorkloadToken, signal: controller.signal });
      if (controller.signal.aborted) throw cancelError(controller.signal);
      const input = claimedInput(claimed.claim);
      // An opaque ticket authorizes the exact provider request. Accept alone
      // cannot turn a legacy buffered ticket into a streaming invocation.
      streaming = claimed.claim.requestBody.stream === true && acceptsEventStream(req.headers?.accept);
      if (streaming) {
        res.status(200);
        res.setHeader("content-type", "text/event-stream; charset=utf-8");
        res.setHeader("cache-control", "no-store, no-transform");
        res.setHeader("x-accel-buffering", "no");
        res.setHeader("x-content-type-options", "nosniff");
        res.flushHeaders?.();
      }
      invocationStarted = true;
      const result = await abortable(converse({
        ...input, temperature:null, stream: streaming,
        signal: controller.signal,
        timeoutMs: streaming ? 120000 : 30000,
        resolveWorkloadToken: () => Promise.resolve(claimed.oidc),
        fetchFn,
        ...(streaming ? { onDelta: async (text) => writeEvent(res, { type: "delta", text }, controller.signal) } : {}),
      }), controller.signal);
      if (controller.signal.aborted) throw cancelError(controller.signal);
      const reply = { model: result.modelId, text: result.text, usage: result.usage || {}, ...safeReceipt(result) };
      if (streaming) {
        await writeEvent(res, { type: "completed", body: reply }, controller.signal);
        res.end();
        return;
      }
      return res.status(200).json({ status: 200, ok: true, body: reply });
    } catch (error) {
      if (res.destroyed || res.writableEnded) return;
      const failure = envelope(controller.signal.aborted ? cancelError(controller.signal) : error);
      if (streaming && res.headersSent) {
        // A timeout can still be reported on a live socket. A closed client
        // cannot receive a late completion, and no provider retry is hidden here.
        if (failure.error.kind !== "cancelled") res.write(`event: failed\ndata: ${JSON.stringify({ type: "failed", ...failure })}\n\n`);
        res.end();
        return;
      }
      return res.status(invocationStarted ? 200 : failure.error.kind === "invalid_request" ? failure.status : 503).json(failure);
    } finally {
      clearTimeout(timer); req.removeListener("aborted", abort); res.removeListener("close", close); res.removeListener("error", abort);
    }
  };
}

const handleBedrockChat = createBedrockChatHandler();
module.exports = { handleBedrockChat, createBedrockChatHandler, envelope, claimTicket };
