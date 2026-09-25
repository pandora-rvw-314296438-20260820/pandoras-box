"use strict";
const { demand, digest, exactKeys, frozen, ID, integer } = require("../pandora-operations-room/contracts");
const { NativeJsonClient, failure } = require("./http.cjs");
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CHANNEL = /^agtch_[A-Za-z0-9_-]{1,160}$/;
const RUN = /^apirun_[A-Za-z0-9_-]{1,160}$/;
const RUN_STATES = Object.freeze(["queued", "in_progress", "suspended", "completed", "failed"]);
const credentialPattern = /(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{16,}|gh[pousr]_[A-Za-z0-9_]{16,}|AIza[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer\s+\S{16,})/;
function safeInput(input) {
  demand(typeof input === "string" && input.trim().length > 0 &&
    Buffer.byteLength(input) <= 16384 && !credentialPattern.test(input),
    "WORKER_INPUT_REJECTED");
  return input;
}
function conversationUrl(value) {
  demand(typeof value === "string" &&
    /^https:\/\/chatgpt\.com\/c\/[A-Za-z0-9-]{1,160}$/.test(value),
    "WORKER_CONVERSATION_INVALID");
  return value;
}
// Bindings are server-owned enrollment configuration, not a task's requested authority.
class WorkspaceAgentClient {
  #binding;
  #http;
  constructor({ binding, getAccessToken, fetchImpl, timeoutMs }) {
    exactKeys(binding, ["organizationId", "projectId", "workerId", "principalKey", "channelId"]);
    demand(UUID.test(binding.organizationId) && UUID.test(binding.projectId) &&
      ID.test(binding.workerId) && ID.test(binding.principalKey) &&
      CHANNEL.test(binding.channelId), "WORKER_BINDING_INVALID");
    demand(typeof getAccessToken === "function", "WORKER_ACCESS_TOKEN_REQUIRED");
    this.#binding = frozen(structuredClone(binding));
    this.#http = new NativeJsonClient({ origin: "https://api.chatgpt.com", fetchImpl,
      timeoutMs, maxBytes: 65536, getToken: async (signal) => {
        const token = await getAccessToken(signal);
        // A Platform API key is not a Workspace Agent access token.
        demand(typeof token === "string" && !token.startsWith("sk-"),
          "CONNECTOR_CREDENTIAL_UNAVAILABLE");
        return token;
      } });
  }
  identity() { return this.#binding; }
  envelope(raw) {
    exactKeys(raw, ["organizationId", "projectId", "workerId", "principalKey",
      "taskId", "dispatchId", "leaseId", "generation"]);
    for (const key of ["organizationId", "projectId", "workerId", "principalKey"])
      demand(raw[key] === this.#binding[key], "WORKER_SCOPE_DENIED");
    demand(ID.test(raw.taskId) && UUID.test(raw.dispatchId) && UUID.test(raw.leaseId),
      "WORKER_DISPATCH_INVALID");
    integer(raw.generation, 1, Number.MAX_SAFE_INTEGER, "WORKER_GENERATION_INVALID");
    return frozen({ ...structuredClone(raw), channelId: this.#binding.channelId });
  }
  async trigger(raw, input, { signal } = {}) {
    const envelope = this.envelope(raw);
    safeInput(input);
    const requestDigest = digest({ envelope, input });
    const response = await this.#http.request(`/v1/workspace_agents/${envelope.channelId}/trigger`, {
      method: "POST", signal,
      headers: { "Idempotency-Key": `pandora-${requestDigest}`,
        "OpenAI-Beta": "workspace_agent_runs=v1" },
      body: { input, conversation_key: `pandora-${digest(envelope)}` },
    });
    demand(response.status === 202 && RUN.test(response.data?.agent_trigger_run_id),
      "WORKER_TRIGGER_RECEIPT_INVALID");
    return frozen({ envelope, requestDigest,
      runId: response.data.agent_trigger_run_id,
      conversationUrl: conversationUrl(response.data.conversation_url),
      state: "provider_queued", workerAcknowledged: false, taskComplete: false });
  }
  async status(receipt, { signal } = {}) {
    const { channelId, ...raw } = receipt?.envelope || {};
    const envelope = this.envelope(raw);
    demand(channelId === envelope.channelId && RUN.test(receipt.runId),
      "WORKER_RUN_SCOPE_INVALID");
    const response = await this.#http.request(
      `/v1/workspace_agents/${channelId}/runs/${receipt.runId}`, { signal });
    const data = response.data;
    demand(data?.object === "workspace_agent.trigger_run" && data.id === receipt.runId &&
      data.api_trigger_id === channelId && RUN_STATES.includes(data.status),
      "WORKER_RUN_READBACK_MISMATCH");
    demand(conversationUrl(data.conversation_url) === receipt.conversationUrl,
      "WORKER_CONVERSATION_MISMATCH");
    return frozen({ envelope, runId: data.id, state: data.status,
      terminal: ["completed", "failed"].includes(data.status),
      workerAcknowledged: false, taskComplete: false });
  }
}
// A queue receipt must be persisted before checking a separately authenticated ACK.
// The durable journal must grant canSend once and bind the immutable input digest.
function workerDispatch({ client, journal, authorizeSend, getInput, readAcknowledgement }) {
  demand(client instanceof WorkspaceAgentClient && journal?.durability === "durable",
    "WORKER_DURABLE_DELIVERY_REQUIRED");
  for (const method of ["prepare", "recordDelivery", "markUnknown", "read"])
    demand(typeof journal[method] === "function", "WORKER_DURABLE_DELIVERY_REQUIRED");
  demand([authorizeSend, getInput, readAcknowledgement].every((f) => typeof f === "function"),
    "WORKER_AUTHENTICATED_ADAPTER_REQUIRED");
  return async ({ scope, claim, dispatchId }) => {
    const identity = client.identity();
    const raw = { organizationId: scope.organizationId, projectId: scope.projectId,
      workerId: claim.workerId, principalKey: identity.principalKey, taskId: claim.taskId,
      leaseId: claim.leaseId, dispatchId, generation: claim.generation };
    const envelope = client.envelope(raw);
    const input = safeInput(await getInput(envelope));
    const requestDigest = digest({ envelope, input });
    const slot = await journal.prepare(envelope, requestDigest);
    demand(slot?.requestDigest === requestDigest, "WORKER_DELIVERY_CONFLICT");
    if (slot.canSend === true) {
      try {
        // Recheck control revision, active binding, cancellation and lease at the send boundary.
        const admission = await authorizeSend(envelope);
        demand(admission?.allowed === true && admission.envelopeDigest === digest(envelope),
          "WORKER_SEND_DENIED");
        const receipt = await client.trigger(raw, input);
        await journal.recordDelivery(envelope, receipt);
      } catch {
        await journal.markUnknown(envelope);
        throw failure("WORKER_DELIVERY_RECONCILIATION_REQUIRED");
      }
    }
    const delivery = await journal.read(envelope);
    demand(delivery?.requestDigest === requestDigest && delivery.receipt?.runId &&
      digest(delivery.receipt.envelope) === digest(envelope), "WORKER_DELIVERY_UNCONFIRMED");
    const ack = await readAcknowledgement(envelope, delivery.receipt);
    demand(ack?.authenticated === true && ack.principalKey === identity.principalKey &&
      ack.runId === delivery.receipt.runId && ack.envelopeDigest === digest(envelope) &&
      ack.accepted === true && typeof ack.receiptRef === "string" && ack.receiptRef.length > 0,
      "WORKER_ACK_PENDING");
    return frozen({ accepted: true, dispatchId, workerId: claim.workerId,
      taskId: claim.taskId, generation: claim.generation, receiptRef: ack.receiptRef });
  };
}
module.exports = { WorkspaceAgentClient, workerDispatch, RUN_STATES };
