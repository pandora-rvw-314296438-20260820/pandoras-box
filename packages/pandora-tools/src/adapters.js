"use strict";

const { PandoraToolError } = require("./errors");

const FAILURE_CLASSES = new Set(["authorization","rate_limit","timeout","network","conflict","invalid_request","provider_unavailable","resource_missing","budget","policy_denied","approval_required","verification_required","ambiguous_mutation","internal"]);

function normalizeExecutionFailure(error) {
  if (error instanceof PandoraToolError) return { error_class: error.errorClass, code: error.code, retryable: ["rate_limit","timeout","network","provider_unavailable"].includes(error.errorClass) && error.errorClass !== "ambiguous_mutation", ambiguous: error.errorClass === "ambiguous_mutation", owner: error.toOwnerSafe() };
  const status = Number(error?.status || error?.statusCode || 0);
  const code = String(error?.code || "").toUpperCase();
  let error_class = "internal";
  if (status === 401 || status === 403) error_class = "authorization";
  else if (status === 404) error_class = "resource_missing";
  else if (status === 409 || status === 412) error_class = "conflict";
  else if (status === 429) error_class = "rate_limit";
  else if ([500,502,503,504].includes(status)) error_class = "provider_unavailable";
  else if (["ETIMEDOUT","TIMEOUT","ABORT_ERR"].includes(code)) error_class = "timeout";
  else if (["ECONNRESET","ECONNREFUSED","ENETUNREACH","EAI_AGAIN"].includes(code)) error_class = "network";
  if (error?.mutation_may_have_committed === true || error?.mutationMayHaveCommitted === true) error_class = "ambiguous_mutation";
  if (!FAILURE_CLASSES.has(error_class)) error_class = "internal";
  return { error_class, code: error_class.toUpperCase(), retryable: ["rate_limit","timeout","network","provider_unavailable"].includes(error_class) && error_class !== "ambiguous_mutation", ambiguous: error_class === "ambiguous_mutation", owner: { error_class, code: error_class.toUpperCase(), message: "Pandora could not complete this operation yet." } };
}

async function executeWithTimeout(adapter, request, runtime = {}, { timeoutMs = 30_000, mutation = false } = {}) {
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15 * 60_000) throw new PandoraToolError("internal", "EXECUTION_TIMEOUT_INVALID", "Execution timeout is invalid");
  const controller = new AbortController();
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      const error = new Error("bounded tool execution timed out");
      error.code = "ETIMEDOUT";
      error.mutation_may_have_committed = mutation;
      reject(error);
    }, timeoutMs);
  });
  try {
    return await Promise.race([Promise.resolve().then(() => adapter.execute(request, { ...runtime, signal: controller.signal })), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

class ExecutionAdapterRegistry {
  constructor() { this.adapters = new Map(); }
  register(executor, adapter) {
    if (!/^[A-Za-z][A-Za-z0-9]+Executor$/.test(executor) || !adapter || typeof adapter.execute !== "function") throw new PandoraToolError("internal", "ADAPTER_INVALID", "Execution adapter is invalid");
    if (adapter.productionConcurrency != null) { const c = adapter.productionConcurrency; if (c.durability !== "durable" || !["claim","compare_and_set"].includes(c.mode) || typeof c.owner !== "string" || !c.owner) throw new PandoraToolError("internal", "ADAPTER_CONCURRENCY_INVALID", "Production concurrency contract is invalid"); }\n    if (this.adapters.has(executor)) throw new PandoraToolError("conflict", "ADAPTER_ALREADY_REGISTERED", "Execution adapter is already registered");
    this.adapters.set(executor, adapter); return this;
  }
  get(executor) { const adapter = this.adapters.get(executor); if (!adapter) throw new PandoraToolError("provider_unavailable", "EXECUTOR_UNAVAILABLE", "Required execution adapter is unavailable"); return adapter; }
}

module.exports = { FAILURE_CLASSES, normalizeExecutionFailure, executeWithTimeout, ExecutionAdapterRegistry };
