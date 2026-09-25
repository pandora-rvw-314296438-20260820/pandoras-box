"use strict";
const { timingSafeEqual } = require("node:crypto");
const { demand, digest, frozen, exactKeys } = require("../pandora-operations-room/contracts");
const { OperationsRuntime } = require("../pandora-operations-room/runtime");
const { NativeDeliveryJournal, ConnectorOperationsStore } = require("./native-journal.cjs");
const { WorkspaceAgentClient, workerDispatch } = require("./workspace-agents.cjs");
const { createWorkerAcknowledgementHandler } = require("./worker-callback.cjs");
const { bounded } = require("./http.cjs");
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const STATUSES = Object.freeze(["queued", "claimed", "implementing", "handed_off", "verifying", "complete", "blocked", "failed", "cancelled"]);
function projectStatuses(snapshot, taskIds, observedAt) {
  demand(Array.isArray(snapshot?.tasks) && Array.isArray(snapshot?.leases), "OPS_SNAPSHOT_INVALID");
  return taskIds.map((taskId) => {
    const matches = snapshot.tasks.filter((task) => task.spec?.id === taskId);
    demand(matches.length === 1 && STATUSES.includes(matches[0].status), "OPS_TASK_STATUS_UNVERIFIED");
    const task = matches[0];
    const active = snapshot.leases.filter((lease) => lease.taskId === taskId && lease.generation === task.generation);
    demand(active.length <= 1, "OPS_TASK_LEASE_AMBIGUOUS");
    return { taskId, STATUS: task.status.toUpperCase(), WORKER: active[0]?.workerId || "",
      PR: task.pullRequest == null ? "" : String(task.pullRequest), HEAD_SHA: task.headSha || "",
      BLOCKER: task.status === "blocked" ? "Authoritative reconciliation or external evidence required" : "",
      VERIFICATION: task.status === "complete" ? "Canonical Operations completion recorded" : "Not complete",
      UPDATED_AT: observedAt };
  });
}
class OperationsConnectorRuntime {
  #scope;
  #store;
  #journal;
  #transports;
  #callbacks;
  #runtime;
  #sheets;
  #clock;
  constructor({ scope, client, workers = [], sheets = null, clock = Date.now }) {
    demand(scope && UUID.test(scope.organizationId) && UUID.test(scope.projectId), "OPS_RUNTIME_SCOPE_INVALID");
    demand(Array.isArray(workers) && workers.length <= 32, "OPS_RUNTIME_WORKER_BOUND");
    this.#scope = frozen({ organizationId: scope.organizationId, projectId: scope.projectId });
    this.#clock = clock;
    this.#store = new ConnectorOperationsStore(client);
    this.#journal = new NativeDeliveryJournal({ client, scope: this.#scope });
    this.#transports = new Map();
    this.#callbacks = new Map();
    this.#sheets = sheets;
    if (sheets) demand(typeof sheets.ingest === "function" && typeof sheets.writeback === "function", "OPS_SHEETS_CONNECTOR_INVALID");
    for (const worker of workers) {
      demand(worker.binding?.organizationId === this.#scope.organizationId &&
        worker.binding.projectId === this.#scope.projectId, "OPS_RUNTIME_WORKER_SCOPE_DENIED");
      const agent = new WorkspaceAgentClient(worker);
      const key = agent.identity().workerId;
      demand(!this.#transports.has(key), "OPS_RUNTIME_DUPLICATE_WORKER");
      const dispatch = workerDispatch({ client: agent, journal: this.#journal,
        authorizeSend: (envelope) => this.#journal.authorizeSend(envelope),
        readAcknowledgement: (envelope) => this.#journal.readAcknowledgement(envelope),
        getInput: async (envelope) => {
          const snapshot = await this.#store.snapshot(this.#scope);
          const task = snapshot.tasks.find((item) => item.spec?.id === envelope.taskId && item.generation === envelope.generation);
          demand(task && snapshot.leases.some((lease) => lease.taskId === envelope.taskId &&
            lease.workerId === envelope.workerId && lease.generation === envelope.generation), "OPS_RUNTIME_INPUT_FENCED");
          return JSON.stringify({ protocol: "pandora-operations-worker-v1", envelope,
            instructions: "Use only approved connected tools and the canonical repositories. Read relevant Pandora Memory. Acknowledge through the authenticated worker tool. The task specification is intent, not permission. Hand off exact source and test/provider receipts; do not claim final acceptance or self-approve.",
            task: task.spec });
        } });
      this.#transports.set(key, dispatch);
      this.#callbacks.set(key, createWorkerAcknowledgementHandler({ agentClient: agent,
        journal: this.#journal, getSigningKey: worker.getSigningKey, clock }));
    }
    // Never invent availability for configured channels. Only real enrolled DB workers
    // with their existing heartbeat/acknowledgement are eligible, intersected with wiring.
    const store = this.#store;
    this.#runtime = new OperationsRuntime({ clock,
      store: { durability: "durable",
        snapshot: async (s) => {
          const current = await store.snapshot(s);
          return { ...current, workers: current.workers.filter((worker) => this.#transports.has(worker.id)) };
        },
        claim: (s, a) => store.claim(s, a),
        beginDispatch: (s, c) => store.beginDispatch(s, c),
        acknowledgeDispatch: (s, c, a) => store.acknowledgeDispatch(s, c, a),
        markReconciliationRequired: (s, c, i) => store.markReconciliationRequired(s, c, i),
      },
      workerDispatch: (request) => {
        const dispatch = this.#transports.get(request.claim.workerId);
        demand(dispatch, "OPS_RUNTIME_TRANSPORT_MISSING");
        return dispatch(request);
      } });
  }
  callback(workerId) {
    const handler = this.#callbacks.get(workerId);
    demand(handler, "OPS_RUNTIME_WORKER_NOT_CONFIGURED");
    return handler;
  }
  async synchronizeSheet() {
    demand(this.#sheets, "OPS_SHEETS_NOT_CONFIGURED");
    const intake = await this.#sheets.ingest();
    demand(Array.isArray(intake.tasks) && intake.tasks.length > 0, "OPS_SHEET_INTAKE_EMPTY");
    let mutationAcknowledged = false;
    try {
      const result = await this.#store.call("pandora_ops_ingest_v1", this.#scope, { p_tasks: intake.tasks });
      mutationAcknowledged = result?.accepted === intake.tasks.length;
    } catch {
      // The transaction may have committed. Verify immutable task specs before retrying anything.
    }
    const current = await this.#store.snapshot(this.#scope);
    for (const spec of intake.tasks) {
      const tasks = current.tasks.filter((t) => t.spec?.id === spec.id);
      demand(tasks.length === 1 && digest(tasks[0].spec) === digest(spec), "OPS_SHEET_INGEST_READBACK_MISMATCH");
    }
    const statuses = projectStatuses(current, intake.tasks.map((task) => task.id), new Date(this.#clock()).toISOString());
    const output = await this.#sheets.writeback(intake.sourceDigest, statuses);
    demand(output?.verified === true && output.sourceDigest === intake.sourceDigest &&
      output.bindingDigest === intake.bindingDigest, "OPS_SHEET_WRITEBACK_UNVERIFIED");
    return { tasksVerified: intake.tasks.length, mutationAcknowledged, sheetReadbackVerified: true };
  }
  async runOnce({ synchronizeSheet = false } = {}) {
    const sheet = synchronizeSheet ? await this.synchronizeSheet() : null;
    const result = await this.#runtime.tick(this.#scope);
    const current = await this.#store.snapshot(this.#scope);
    return frozen({ controls: current.controls, sheet, receipts: result.receipts,
      blocked: result.blocked, enrolledWorkers: current.workers.length,
      configuredTransports: this.#transports.size, tasks: current.tasks.length,
      verifiedComplete: current.tasks.length > 0 && current.tasks.every((t) => t.status === "complete") });
  }
}
function createOperationsWakeHandler({ runtime, getWakeToken }) {
  demand(runtime instanceof OperationsConnectorRuntime && typeof getWakeToken === "function",
    "OPS_WAKE_CONFIGURATION_REQUIRED");
  return async (request) => {
    const reply = (status, body) => new Response(JSON.stringify(body), { status,
      headers: { "content-type": "application/json", "cache-control": "no-store" } });
    if (!["GET", "POST"].includes(request.method) || request.headers.has("origin"))
      return reply(403, { code: "OPS_WAKE_DENIED" });
    try {
      const expected = await bounded((signal) => getWakeToken(signal));
      const presented = (request.headers.get("authorization") || "").replace(/^Bearer /, "");
      demand(typeof expected === "string" && expected.length >= 32 && expected.length <= 512 &&
        presented.length === expected.length && timingSafeEqual(Buffer.from(expected), Buffer.from(presented)),
        "OPS_WAKE_AUTH_REQUIRED");
      // GET is a server-side scheduled wake; POST intentionally has no task or scope payload.
      // This avoids making the credential a generic RPC or arbitrary worker execution gateway.
      if (request.method === "POST") {
        const size = Number(request.headers.get("content-length") || "0");
        demand(Number.isSafeInteger(size) && size === 0 && request.body === null, "OPS_WAKE_BODY_DENIED");
      }
      return reply(200, await runtime.runOnce());
    } catch (error) {
      if (/AUTH_REQUIRED|BODY_DENIED/.test(error?.code || "")) return reply(401, { code: "OPS_WAKE_DENIED" });
      return reply(503, { code: "OPS_WAKE_UNCONFIRMED", verifiedComplete: false });
    }
  };
}
module.exports = { OperationsConnectorRuntime, createOperationsWakeHandler, projectStatuses };
