"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  WorkerPlanContextProvider,
  exactWorkerArgs,
  payloadHash,
} = require("../src/projectos/worker-plan-context-provider.js");

const PLAN_ID = "8ec3acda-4fb7-48b2-81f4-6885c005f561";
const args = {
  exactSha: "0123456789abcdef0123456789abcdef01234567",
  jobClass: "node_regression",
  maxRuntimeSeconds: 1800,
  productionMutationAllowed: false,
  repository: "pandora-rvw-314296438-20260820/pandoras-box",
  schemaVersion: 1,
};

function plan(overrides = {}) {
  return {
    planId: PLAN_ID,
    requestId: "a4c6e81c-89d0-4a63-9b8f-18e41bd2619a",
    intakeId: "a4c6e81c-89d0-4a63-9b8f-18e41bd2619a",
    projectKey: "mcpmaster",
    tool: "projectos.worker.verify",
    risk: "write",
    args,
    payloadHash: payloadHash("projectos.worker.verify", args),
    status: "pending_approval",
    ...overrides,
  };
}

test("worker plan context accepts only the closed exact-source contract", () => {
  assert.equal(exactWorkerArgs(args), true);
  assert.equal(exactWorkerArgs({ ...args, repository: "attacker/fork" }), false);
  assert.equal(exactWorkerArgs({ ...args, command: "npm test" }), false);
  assert.equal(exactWorkerArgs({ ...args, productionMutationAllowed: true }), false);
});

test("fresh Memory context is attached and verified by durable readback", async () => {
  let reads = 0;
  let attached;
  let hydrationInput;
  const envelope = { status: "available", namespace: "real_life" };
  const provider = new WorkerPlanContextProvider({
    resolveToken: async () => "v".repeat(80),
    ledger: {
      listPlans: async () => {
        reads += 1;
        return reads === 1
          ? [plan()]
          : [plan({
            memoryContextRecorded: true,
            memoryContextHash: "a".repeat(64),
            memoryContext: envelope,
          })];
      },
    },
    memory: {
      hydrate: async (_token, input) => {
        hydrationInput = input;
        return { envelope, contextHash: "a".repeat(64) };
      },
    },
    contextLedger: {
      attach: async (_token, input) => {
        attached = input;
        return true;
      },
    },
  });
  const result = await provider.attachExactPlan(PLAN_ID);
  assert.equal(result.contextHash, "a".repeat(64));
  assert.equal(result.idempotentReplay, false);
  assert.equal(attached.planId, PLAN_ID);
  assert.equal(hydrationInput.args.projectKey, "mcpmaster-pandoras-box");
  assert.equal(Object.hasOwn(args, "projectKey"), false);
  assert.equal(reads, 2);
});

test("unavailable Memory, payload mismatch, and missing workload identity fail closed", async () => {
  const base = {
    ledger: { listPlans: async () => [plan()] },
    contextLedger: { attach: async () => true },
  };
  await assert.rejects(
    new WorkerPlanContextProvider({
      ...base,
      resolveToken: async () => undefined,
      memory: { hydrate: async () => ({}) },
    }).attachExactPlan(PLAN_ID),
    /VERCEL_WORKLOAD_IDENTITY_UNAVAILABLE/,
  );
  await assert.rejects(
    new WorkerPlanContextProvider({
      ...base,
      resolveToken: async () => "v".repeat(80),
      memory: {
        hydrate: async () => ({
          envelope: { status: "unavailable" },
          contextHash: "b".repeat(64),
        }),
      },
    }).attachExactPlan(PLAN_ID),
    /PANDORA_MEMORY_CONTEXT_UNAVAILABLE/,
  );
  await assert.rejects(
    new WorkerPlanContextProvider({
      ...base,
      resolveToken: async () => "v".repeat(80),
      ledger: {
        listPlans: async () => [plan({ payloadHash: "f".repeat(64) })],
      },
      memory: { hydrate: async () => ({}) },
    }).attachExactPlan(PLAN_ID),
    /WORKER_PLAN_IDENTITY_MISMATCH/,
  );
});

test("already attached exact context is an idempotent read-only replay", async () => {
  let hydrateCalls = 0;
  const provider = new WorkerPlanContextProvider({
    resolveToken: async () => "v".repeat(80),
    ledger: {
      listPlans: async () => [plan({
        memoryContextRecorded: true,
        memoryContextHash: "c".repeat(64),
        memoryContext: { status: "available" },
      })],
    },
    memory: { hydrate: async () => { hydrateCalls += 1; } },
    contextLedger: { attach: async () => false },
  });
  const result = await provider.attachExactPlan(PLAN_ID);
  assert.equal(result.idempotentReplay, true);
  assert.equal(hydrateCalls, 0);
});
