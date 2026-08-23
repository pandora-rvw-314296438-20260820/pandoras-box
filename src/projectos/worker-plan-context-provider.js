"use strict";

const { createHash } = require("node:crypto");
const { ExecutionLedgerClient } = require("../runtime/execution-ledger-client.js");
const {
  PandoraPlanMemoryContextProvider,
} = require("../runtime/plan-memory-context.js");
const { PlanContextLedgerClient } = require("../runtime/plan-context-ledger-client.js");
const {
  resolveVercelWorkloadToken,
} = require("../runtime/vercel-workload-identity.js");

const CANONICAL_REPOSITORY = "banataosystems/Pandoras-box";
const WORKER_TOOL = "projectos.worker.verify";
const ALLOWED_JOB_CLASSES = new Set([
  "node_regression",
  "supabase_migration_replay",
]);

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, stableValue(nested)]),
    );
  }
  return value;
}

function payloadHash(tool, args) {
  return createHash("sha256")
    .update(JSON.stringify({ tool, args: stableValue(args) }), "utf8")
    .digest("hex");
}

function exactWorkerArgs(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const keys = Object.keys(value).sort();
  return JSON.stringify(keys) === JSON.stringify([
    "exactSha",
    "jobClass",
    "maxRuntimeSeconds",
    "productionMutationAllowed",
    "repository",
    "schemaVersion",
  ]) && value.schemaVersion === 1 &&
    value.repository === CANONICAL_REPOSITORY &&
    typeof value.exactSha === "string" && /^[0-9a-f]{40}$/.test(value.exactSha) &&
    ALLOWED_JOB_CLASSES.has(value.jobClass) &&
    Number.isInteger(value.maxRuntimeSeconds) &&
    value.maxRuntimeSeconds >= 30 && value.maxRuntimeSeconds <= 1800 &&
    value.productionMutationAllowed === false;
}

class WorkerPlanContextProvider {
  constructor(options = {}) {
    this.ledger = options.ledger || new ExecutionLedgerClient({
      contextProvider: null,
      contextLedger: null,
      intakeProvider: null,
    });
    this.memory = options.memory || new PandoraPlanMemoryContextProvider();
    this.contextLedger = options.contextLedger || new PlanContextLedgerClient();
    this.resolveToken = options.resolveToken || resolveVercelWorkloadToken;
  }

  async attachExactPlan(planId) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(planId)) {
      throw new Error("WORKER_PLAN_ID_INVALID");
    }
    const token = await this.resolveToken();
    if (!token) throw new Error("VERCEL_WORKLOAD_IDENTITY_UNAVAILABLE");
    const plans = await this.ledger.listPlans(token, 500);
    const plan = plans.find((candidate) => candidate.planId === planId);
    if (!plan) throw new Error("WORKER_PLAN_NOT_FOUND");
    if (
      plan.tool !== WORKER_TOOL || plan.risk !== "write" ||
      !exactWorkerArgs(plan.args) ||
      payloadHash(plan.tool, plan.args) !== plan.payloadHash ||
      !["pending_approval", "approved"].includes(plan.status) ||
      !plan.requestId || plan.requestId !== plan.intakeId
    ) {
      throw new Error("WORKER_PLAN_IDENTITY_MISMATCH");
    }
    if (plan.memoryContextRecorded === true && plan.memoryContextHash) {
      return {
        planId: plan.planId,
        requestId: plan.requestId,
        contextHash: plan.memoryContextHash,
        status: plan.memoryContext?.status || "available",
        idempotentReplay: true,
      };
    }

    const hydrated = await this.memory.hydrate(token, {
      tool: plan.tool,
      args: plan.args,
    });
    if (hydrated.envelope?.status !== "available") {
      throw new Error("PANDORA_MEMORY_CONTEXT_UNAVAILABLE");
    }
    const recorded = await this.contextLedger.attach(token, {
      planId: plan.planId,
      requestId: plan.requestId,
      contextHash: hydrated.contextHash,
      contextEnvelope: hydrated.envelope,
    });
    if (!recorded) throw new Error("PLAN_CONTEXT_ATTACH_FAILED");

    const readback = (await this.ledger.listPlans(token, 500))
      .find((candidate) => candidate.planId === plan.planId);
    if (
      !readback || readback.memoryContextRecorded !== true ||
      readback.memoryContextHash !== hydrated.contextHash
    ) {
      throw new Error("PLAN_CONTEXT_READBACK_MISMATCH");
    }
    return {
      planId: readback.planId,
      requestId: readback.requestId,
      contextHash: readback.memoryContextHash,
      status: readback.memoryContext?.status || "available",
      idempotentReplay: false,
    };
  }
}

module.exports = {
  WorkerPlanContextProvider,
  exactWorkerArgs,
  payloadHash,
};
