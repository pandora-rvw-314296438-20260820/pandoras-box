"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { assertProductionStatePorts } = require("../src/durability");
const { ExecutionAdapterRegistry } = require("../src/adapters");
const { durableExecutorConcurrency } = require("../src/control-plane");

const durable = Object.freeze({ durability: "durable" });
const productionDefinition = Object.freeze({ sideEffect: "PRODUCTION_MUTATION", idempotency: "REQUIRED" });
const ports = {
  approvalStore: durable,
  idempotencyCoordinator: { store: durable },
  leaseManager: null,
  rateLimitGuard: { store: durable },
  lineageSink: durable,
};

test("production accepts trusted executor-owned durable CAS without a duplicate Worker C lease", () => {
  assert.equal(assertProductionStatePorts(productionDefinition, "production", {
    ...ports,
    concurrencyPort: durableExecutorConcurrency("compare_and_set", "worker-f"),
  }), true);
});

test("production still fails closed without durable lease or executor concurrency", () => {
  assert.throws(() => assertProductionStatePorts(productionDefinition, "production", ports), /durable lease, claim, or compare-and-set/i);
});

test("adapter registry rejects untrusted production concurrency declarations", () => {
  const registry = new ExecutionAdapterRegistry();
  assert.throws(() => registry.register("DeploymentExecutor", {
    execute: async () => ({}),
    productionConcurrency: { durability: "memory", mode: "compare_and_set", owner: "worker-f" },
  }), /concurrency/i);
  assert.doesNotThrow(() => registry.register("DeploymentExecutor", {
    execute: async () => ({}),
    productionConcurrency: durableExecutorConcurrency("compare_and_set", "worker-f"),
  }));
});
