"use strict";

const { secureEqualHex, IDEMPOTENCY_MODES, RETRY_MODES } = require("./contracts");
const { PandoraToolError } = require("./errors");

const EXECUTION_STATES = Object.freeze({
  NEVER_EXECUTED: "never_executed",
  STARTED: "started",
  SUCCEEDED: "succeeded",
  FAILED_SAFE: "failed_safe",
  AMBIGUOUS: "ambiguous",
});

function idempotencyScopeKey({ organization_id, project_id, environment, tool, idempotency_key }) {
  return [organization_id, project_id, environment, tool, idempotency_key].join("|");
}

class MemoryIdempotencyStore {
  constructor() { this.durability = "memory"; this.records = new Map(); }
  async get(scope) { const value = this.records.get(idempotencyScopeKey(scope)); return value ? structuredClone(value) : null; }
  async createStarted(scope, record) {
    const key = idempotencyScopeKey(scope);
    if (this.records.has(key)) return false;
    this.records.set(key, structuredClone({ ...scope, ...record, state: EXECUTION_STATES.STARTED }));
    return true;
  }
  async update(scope, patch) {
    const key = idempotencyScopeKey(scope);
    const current = this.records.get(key);
    if (!current) throw new PandoraToolError("internal", "IDEMPOTENCY_RECORD_MISSING", "Idempotency record is missing");
    Object.assign(current, structuredClone(patch));
    return structuredClone(current);
  }
}

class IdempotencyCoordinator {
  constructor(store) { this.store = store; }

  async begin({ definition, scope, action_hash, request_id, now = new Date(), metadata = null }) {
    if (definition.idempotency === IDEMPOTENCY_MODES.REQUIRED && !scope.idempotency_key) {
      throw new PandoraToolError("invalid_request", "IDEMPOTENCY_KEY_REQUIRED", "Mutation requires an idempotency key");
    }
    if (definition.idempotency === IDEMPOTENCY_MODES.NONE) return { mode: "execute", state: EXECUTION_STATES.NEVER_EXECUTED };
    const previous = await this.store.get(scope);
    if (previous) {
      if (!secureEqualHex(previous.action_hash, action_hash)) throw new PandoraToolError("conflict", "IDEMPOTENCY_KEY_REUSED_FOR_DIFFERENT_ACTION", "Idempotency key is already bound to another action");
      if (previous.state === EXECUTION_STATES.SUCCEEDED) return { mode: "replay", state: previous.state, receipt: previous.receipt };
      if (previous.state === EXECUTION_STATES.AMBIGUOUS) throw new PandoraToolError("ambiguous_mutation", "AMBIGUOUS_PRIOR_MUTATION", "Prior mutation outcome is ambiguous and cannot be retried automatically");
      if (previous.state === EXECUTION_STATES.STARTED) throw new PandoraToolError("conflict", "MUTATION_ALREADY_IN_PROGRESS", "Equivalent mutation is already in progress");
      if (previous.state === EXECUTION_STATES.FAILED_SAFE && definition.retry === RETRY_MODES.NO_AUTOMATIC_RETRY) throw new PandoraToolError("conflict", "RETRY_NOT_ALLOWED", "Tool does not permit automatic retry");
      if (previous.state === EXECUTION_STATES.FAILED_SAFE) {
        await this.store.update(scope, { state: EXECUTION_STATES.STARTED, request_id, restarted_at: now.toISOString() });
        return { mode: "execute", state: EXECUTION_STATES.FAILED_SAFE, retry: true };
      }
    }
    const created = await this.store.createStarted(scope, { action_hash, request_id, started_at: now.toISOString(), metadata });
    if (!created) throw new PandoraToolError("conflict", "IDEMPOTENCY_RACE", "Equivalent mutation raced with another executor");
    return { mode: "execute", state: EXECUTION_STATES.NEVER_EXECUTED };
  }

  async succeeded(scope, receipt, now = new Date()) { return this.store.update(scope, { state: EXECUTION_STATES.SUCCEEDED, receipt, finished_at: now.toISOString() }); }
  async failedSafe(scope, error, now = new Date()) { return this.store.update(scope, { state: EXECUTION_STATES.FAILED_SAFE, error, finished_at: now.toISOString() }); }
  async ambiguous(scope, error, now = new Date()) { return this.store.update(scope, { state: EXECUTION_STATES.AMBIGUOUS, error, finished_at: now.toISOString() }); }
}

module.exports = { EXECUTION_STATES, idempotencyScopeKey, MemoryIdempotencyStore, IdempotencyCoordinator };
