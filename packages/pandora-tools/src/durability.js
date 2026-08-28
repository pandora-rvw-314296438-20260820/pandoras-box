"use strict";

const { SIDE_EFFECTS } = require("./contracts");
const { PandoraToolError } = require("./errors");

function isDurablePort(port) { return port?.durability === "durable"; }
function requireDurable(port, code, label) {
  if (!isDurablePort(port)) throw new PandoraToolError("policy_denied", code, `${label} must use durable control-plane storage for production mutations`);
}

function assertProductionStatePorts(definition, environment, { approvalStore, idempotencyCoordinator, leaseManager, rateLimitGuard, lineageSink }) {
  const mutation = ![SIDE_EFFECTS.NONE, SIDE_EFFECTS.READ].includes(definition.sideEffect);
  if (environment !== "production" || !mutation) return true;
  requireDurable(approvalStore, "DURABLE_APPROVAL_STORE_REQUIRED", "Approval state");
  if (definition.idempotency !== "NONE") requireDurable(idempotencyCoordinator?.store, "DURABLE_IDEMPOTENCY_STORE_REQUIRED", "Idempotency state");
  requireDurable(leaseManager?.store, "DURABLE_LEASE_STORE_REQUIRED", "Mutation lease state");
  requireDurable(rateLimitGuard?.store, "DURABLE_RATE_LIMIT_STORE_REQUIRED", "Rate-limit state");
  requireDurable(lineageSink, "DURABLE_LINEAGE_SINK_REQUIRED", "Lineage");
  return true;
}

module.exports = { isDurablePort, assertProductionStatePorts };
