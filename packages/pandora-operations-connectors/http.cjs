"use strict";
const { demand, integer } = require("../pandora-operations-room/contracts");
const ORIGINS = Object.freeze([
  "https://api.chatgpt.com",
  "https://sheets.googleapis.com",
]);
function failure(code, extra = {}) {
  return Object.assign(new Error(code), { code, ...extra });
}
// The deadline includes credential resolution and reading the entire response body.
// Aborting a request never proves a remote mutation was cancelled.
async function bounded(work, { timeoutMs = 15000, signal } = {}) {
  integer(timeoutMs, 1, 30000, "CONNECTOR_DEADLINE_INVALID");
  const control = new AbortController();
  let timer;
  let abort;
  let rejectAbort;
  const stopped = new Promise((_, reject) => { rejectAbort = reject; });
  const stop = (code) => {
    if (control.signal.aborted) return;
    const error = failure(code);
    control.abort(error);
    rejectAbort(error);
  };
  abort = () => stop("CONNECTOR_CANCELLED");
  if (signal?.aborted) abort();
  else signal?.addEventListener("abort", abort, { once: true });
  timer = setTimeout(() => stop("CONNECTOR_DEADLINE"), timeoutMs);
  try {
    return await Promise.race([
      stopped,
      Promise.resolve().then(() => {
        control.signal.throwIfAborted();
        return work(control.signal);
      }),
    ]);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", abort);
  }
}
class NativeJsonClient {
  #origin;
  #token;
  #fetch;
  #timeout;
  #maxBytes;
  constructor({ origin, getToken, fetchImpl = globalThis.fetch,
    timeoutMs = 15000, maxBytes = 2097152 }) {
    demand(ORIGINS.includes(origin), "CONNECTOR_ORIGIN_DENIED");
    demand(typeof getToken === "function", "CONNECTOR_CREDENTIAL_LOADER_REQUIRED");
    demand(typeof fetchImpl === "function", "CONNECTOR_FETCH_REQUIRED");
    integer(timeoutMs, 1, 30000, "CONNECTOR_DEADLINE_INVALID");
    integer(maxBytes, 1, 2097152, "CONNECTOR_RESPONSE_BOUND_INVALID");
    this.#origin = origin;
    this.#token = getToken;
    this.#fetch = fetchImpl;
    this.#timeout = timeoutMs;
    this.#maxBytes = maxBytes;
  }
  async request(path, { method = "GET", body, headers = {}, signal,
    mutation = method !== "GET" } = {}) {
    demand(typeof path === "string" && path.startsWith("/") &&
      !path.startsWith("//") && !/[\\#\r\n]/.test(path), "CONNECTOR_PATH_DENIED");
    const target = new URL(path, this.#origin);
    demand(target.origin === this.#origin && !target.username && !target.password,
      "CONNECTOR_ORIGIN_DENIED");
    demand(["GET", "POST"].includes(method), "CONNECTOR_METHOD_DENIED");
    demand(headers && Object.keys(headers).every((k) =>
      ["Idempotency-Key", "OpenAI-Beta"].includes(k)), "CONNECTOR_HEADER_DENIED");
    demand(Object.values(headers).every((v) => typeof v === "string" &&
      v.length <= 256 && !/[\r\n]/.test(v)), "CONNECTOR_HEADER_DENIED");
    const encoded = body === undefined ? undefined : JSON.stringify(body);
    demand(encoded === undefined || Buffer.byteLength(encoded) <= 2097152,
      "CONNECTOR_REQUEST_TOO_LARGE");
    let dispatched = false;
    try {
      return await bounded(async (abortSignal) => {
        let token;
        try { token = await this.#token(abortSignal); }
        catch { throw failure("CONNECTOR_CREDENTIAL_UNAVAILABLE"); }
        abortSignal.throwIfAborted();
        demand(typeof token === "string" && token.length >= 8 &&
          token.length <= 8192 && !/\s/.test(token), "CONNECTOR_CREDENTIAL_UNAVAILABLE");
        dispatched = true;
        const response = await this.#fetch(target.href, {
          method, body: encoded, redirect: "error", signal: abortSignal,
          headers: { "accept": "application/json", "content-type": "application/json",
            ...headers, "authorization": `Bearer ${token}` },
        });
        abortSignal.throwIfAborted();
        demand(response && Number.isInteger(response.status), "CONNECTOR_RESPONSE_INVALID");
        if (response.status < 200 || response.status >= 300) {
          response.body?.cancel().catch(() => {});
          throw failure("CONNECTOR_HTTP_FAILURE", { status: response.status });
        }
        if (response.status === 204) return { status: 204, data: null };
        demand(/application\/(?:[a-z0-9.+-]+\+)?json/i.test(
          response.headers.get("content-type") || ""), "CONNECTOR_RESPONSE_INVALID");
        const stated = Number(response.headers.get("content-length"));
        if (Number.isFinite(stated) && stated > this.#maxBytes) {
          response.body?.cancel().catch(() => {});
          throw failure("CONNECTOR_RESPONSE_TOO_LARGE");
        }
        demand(response.body && typeof response.body.getReader === "function",
          "CONNECTOR_RESPONSE_INVALID");
        const reader = response.body.getReader();
        const chunks = [];
        let length = 0;
        const cancelReader = () => { reader.cancel().catch(() => {}); };
        abortSignal.addEventListener("abort", cancelReader, { once: true });
        try {
          for (;;) {
            const { done, value } = await reader.read();
            abortSignal.throwIfAborted();
            if (done) break;
            length += value.byteLength;
            demand(length <= this.#maxBytes, "CONNECTOR_RESPONSE_TOO_LARGE");
            chunks.push(Buffer.from(value));
          }
          let data;
          try { data = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
          catch { throw failure("CONNECTOR_RESPONSE_INVALID"); }
          return { status: response.status, data };
        } finally {
          abortSignal.removeEventListener("abort", cancelReader);
          reader.cancel().catch(() => {});
          reader.releaseLock();
        }
      }, { timeoutMs: this.#timeout, signal });
    } catch (error) {
      const safe = /^CONNECTOR_[A-Z_]+$/.test(error?.code || "")
        ? error.code : "CONNECTOR_NETWORK_FAILURE";
      throw failure(safe, { outcomeUnknown: mutation && dispatched,
        ...(Number.isInteger(error?.status) ? { status: error.status } : {}) });
    }
  }
}
module.exports = { NativeJsonClient, bounded, failure };
