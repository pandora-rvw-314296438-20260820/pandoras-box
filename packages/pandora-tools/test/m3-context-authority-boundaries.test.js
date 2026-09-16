"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../src");

const ORG = "org_m3_context";
const PROJECT = "project_m3_context";
const ACTOR = "actor_m3_context";
const fixedNow = () => new Date("2026-09-14T00:00:00Z");

function durableDeps(adapterRegistry) {
  const approvalStore = new T.MemoryApprovalStore(); approvalStore.durability = "durable";
  const idempotencyStore = new T.MemoryIdempotencyStore(); idempotencyStore.durability = "durable";
  const leaseStore = new T.MemoryLeaseStore(); leaseStore.durability = "durable";
  const rateStore = new T.MemoryRateLimitStore(); rateStore.durability = "durable";
  const lineageSink = new T.MemoryLineageSink(); lineageSink.durability = "durable";
  return {
    resourceResolver: {
      async resolve({ environment }) {
        return {
          project: { id: PROJECT, organization_id: ORG, version_id: "v1" },
          resource: { id: environment, project_id: PROJECT, organization_id: ORG },
          target_resource: environment,
          project_version: "v1",
          project_state_hash: "state-v1",
          resource_version: "r1",
        };
      },
    },
    adapterRegistry,
    approvalStore,
    idempotencyCoordinator: new T.IdempotencyCoordinator(idempotencyStore),
    leaseManager: new T.MutationLeaseManager(leaseStore),
    rateLimitGuard: new T.RateLimitGuard(rateStore),
    lineageSink,
    now: fixedNow,
  };
}

function publishProposal() {
  return {
    tool: "request_publish",
    version: 1,
    arguments: {
      project_id: PROJECT,
      environment: "production",
      version_id: "v1",
      verification_run_id: "verify-context-1",
      preview_id: "preview-context-1",
      artifact_digest: "b".repeat(64),
      target_environment: "production",
      request_id: "request-context-1",
      idempotency_key: "idem-context-1",
    },
    requirement_refs: ["REQ-M3-CONTEXT"],
    reason: "verify trusted context boundary",
  };
}

function publishContext(capabilities) {
  return {
    organization_id: ORG,
    actor: { id: ACTOR, organization_id: ORG, capabilities },
    environment: "production",
    authorized_requirement_refs: ["REQ-M3-CONTEXT"],
    verification: {
      verification: "PASS",
      publish_eligible: true,
      verification_run_id: "verify-context-1",
      project_id: PROJECT,
      project_version_id: "v1",
      artifact_digest: "b".repeat(64),
      project_spec_version: "spec-context-1",
    },
    project_spec_version: "spec-context-1",
    expected_resource_version: "r1",
    budget: { remaining_units: 100 },
    data_sensitivity: "confidential",
    authority_cost: { unit: "credit", maximum: 5 },
    protected_app_scope: null,
    rate_limit: { max_calls: 50, window_ms: 60_000 },
  };
}

function standingAuthorityEvaluator() {
  return {
    async evaluate(request) {
      return {
        schema_version: T.AUTHORITY_SCHEMA_VERSION,
        decision: T.AUTHORITY_DECISIONS.STANDING_AUTHORIZED,
        authority_basis: "active_explicit_standing_policy",
        standing_policy_id: "policy-context-production",
        standing_policy_match: true,
        authorization_fingerprint: request.authorization_fingerprint,
        action_hash: request.action_hash,
        policy_version: request.policy_version,
        risk: request.risk,
        issued_at: "2026-09-13T23:55:00Z",
        expires_at: "2026-09-14T00:30:00Z",
        reason_code: "STANDING_POLICY_MATCHED",
      };
    },
  };
}

test("R-055 step context cannot override trusted authority or security fields", async () => {
  let calls = 0;
  const chain = new T.PandoraToolChainExecutor({
    executor: {
      async handle() {
        calls += 1;
        return { executed: true };
      },
    },
  });

  await assert.rejects(
    chain.run({
      context: {
        organization_id: ORG,
        actor: { id: ACTOR, organization_id: ORG, capabilities: ["workspace.files.read"] },
        environment: "preview",
        budget: { remaining_units: 1 },
      },
      steps: [{
        id: "escalate",
        proposal: { tool: "read_file" },
        context: {
          actor: { id: ACTOR, organization_id: ORG, capabilities: ["production.publish", "production.access"] },
          environment: "production",
          budget: { remaining_units: 999999 },
        },
      }],
    }),
    (error) => error?.code === "TOOL_CHAIN_STEP_CONTEXT_FORBIDDEN",
  );
  assert.equal(calls, 0);
});

test("R-057 post-evaluator caller mutation cannot widen the frozen Gateway context", async () => {
  let providerCalls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() {
      providerCalls += 1;
      return { output: { status: "published" } };
    },
  });
  const deps = durableDeps(adapters);
  const callerContext = publishContext(["production.access"]);
  const originalRecord = deps.lineageSink.record.bind(deps.lineageSink);
  deps.lineageSink.record = async (event) => {
    if (event.kind === "authority_decision") {
      callerContext.actor.capabilities.push("production.publish");
      callerContext.data_sensitivity = "public";
      callerContext.authority_cost.maximum = 999999;
      callerContext.protected_app_scope = "widened-after-authorization";
    }
    return originalRecord(event);
  };

  const gateway = new T.PandoraToolGateway(deps);
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    authorityEvaluator: standingAuthorityEvaluator(),
    now: fixedNow,
  });

  const result = await executor.handle(publishProposal(), callerContext);
  assert.equal(result.executed, false);
  assert.equal(result.decision.disposition, T.TOOL_DECISIONS.DENY);
  assert.equal(result.decision.reason_code, "CAPABILITY_MISSING");
  assert.deepEqual(result.decision.missing_capabilities, ["production.publish"]);
  assert.equal(providerCalls, 0);
});
