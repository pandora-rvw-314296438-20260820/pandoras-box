"use strict";
const { createHmac, createHash, timingSafeEqual } = require("node:crypto");
const { demand, digest, exactKeys } = require("../pandora-operations-room/contracts");
const { bounded } = require("./http.cjs");
const { WorkspaceAgentClient } = require("./workspace-agents.cjs");
function reply(status, code) {
  return new Response(JSON.stringify({ code }), { status,
    headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
// Configure a separate per-worker signing key in the trusted callback transport.
// The key never belongs in the agent prompt, a browser, or a task/receipt payload.
function createWorkerAcknowledgementHandler({ agentClient, journal, getSigningKey, clock = Date.now }) {
  demand(agentClient instanceof WorkspaceAgentClient && journal?.durability === "durable" &&
    typeof journal.acknowledge === "function" && typeof getSigningKey === "function",
    "WORKER_CALLBACK_CONFIGURATION_REQUIRED");
  return async (request) => {
    if (request.method !== "POST" || request.headers.has("origin")) return reply(403, "WORKER_CALLBACK_DENIED");
    if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get("content-type") || ""))
      return reply(415, "WORKER_CALLBACK_CONTENT_TYPE");
    const timestamp = request.headers.get("x-pandora-timestamp") || "";
    const signature = request.headers.get("x-pandora-signature") || "";
    if (!/^\d{10}$/.test(timestamp) || !/^sha256=[a-f0-9]{64}$/.test(signature))
      return reply(401, "WORKER_CALLBACK_AUTH_REQUIRED");
    const age = Math.floor(clock() / 1000) - Number(timestamp);
    if (age < -30 || age > 300) return reply(401, "WORKER_CALLBACK_EXPIRED");
    try {
      const payload = await bounded(async (signal) => {
        demand(request.body, "WORKER_CALLBACK_BODY_REQUIRED");
        const reader = request.body.getReader();
        const chunks = []; let size = 0;
        const cancel = () => { reader.cancel().catch(() => {}); };
        signal.addEventListener("abort", cancel, { once: true });
        try {
          for (;;) {
            const { done, value } = await reader.read(); signal.throwIfAborted();
            if (done) break;
            size += value.byteLength;
            demand(size <= 8192, "WORKER_CALLBACK_TOO_LARGE");
            chunks.push(Buffer.from(value));
          }
        } finally { signal.removeEventListener("abort", cancel); reader.cancel().catch(() => {}); }
        const bytes = Buffer.concat(chunks);
        const key = await getSigningKey(signal);
        signal.throwIfAborted();
        demand(key instanceof Uint8Array && key.byteLength >= 32 && key.byteLength <= 128,
          "WORKER_CALLBACK_KEY_UNAVAILABLE");
        const expected = createHmac("sha256", key).update(timestamp).update(".").update(bytes).digest();
        const presented = Buffer.from(signature.slice(7), "hex");
        demand(timingSafeEqual(expected, presented), "WORKER_CALLBACK_SIGNATURE_INVALID");
        const value = JSON.parse(bytes.toString("utf8"));
        exactKeys(value, ["envelope", "runId", "accepted"]);
        const { channelId, ...raw } = value.envelope || {};
        const envelope = agentClient.envelope(raw);
        demand(channelId === envelope.channelId && value.accepted === true &&
          typeof value.runId === "string" && /^apirun_[A-Za-z0-9_-]{1,160}$/.test(value.runId),
          "WORKER_CALLBACK_IDENTITY_INVALID");
        return { envelope, receipt: { authenticated: true,
          principalKey: envelope.principalKey, runId: value.runId,
          envelopeDigest: digest(envelope), accepted: true,
          receiptRef: `ops-worker-ack:${createHash("sha256").update(bytes).digest("hex")}` } };
      });
      await journal.acknowledge(payload.envelope, payload.receipt);
      const readback = await journal.readAcknowledgement(payload.envelope);
      demand(readback && digest(readback) === digest(payload.receipt), "WORKER_CALLBACK_READBACK_MISMATCH");
      return reply(200, "WORKER_ACKNOWLEDGED");
    } catch (error) {
      if (/SIGNATURE|IDENTITY|SCOPE|ENVELOPE|PRINCIPAL|FENCED|EXPIRED|KEY_UNAVAILABLE/.test(error?.code || error?.message || ""))
        return reply(401, "WORKER_CALLBACK_DENIED");
      return reply(409, "WORKER_CALLBACK_RECONCILIATION_REQUIRED");
    }
  };
}
module.exports = { createWorkerAcknowledgementHandler };
