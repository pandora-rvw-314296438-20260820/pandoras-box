"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../src");

const ORG = "org_m3_005";
const PROJECT = "project_m3_005";
const ACTOR = "actor_m3_005";
const fixedNow = () => new Date("2026-09-14T00:00:00Z");

function durableMemoryDeps(adapterRegistry) {
  const approvals = new T.MemoryApprovalStore();
  approvals.durability = "durable";
  const idempotencyStore = new T.MemoryIdempotencyStore();
  idempotencyStore.durability = "durable";
  const leaseStore = new T.MemoryLeaseStore();
  leaseStore.durability = "durable";
  const rateStore = new T.MemoryRateLimitStore();
  rateStore.durability = "durable";
  const lineage = new T.MemoryLineageSink();
  lineage.durability = "durable";

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
    approvalStore: approvals,
    idempotencyCoordinator: new T.IdempotencyCoordinator(idempotencyStore),
    leaseManager: new T.MutationLeaseManager(leaseStore),
    rateLimitGuard: new T.RateLimitGuard(rateStore),
    lineageSink: lineage,
    now: fixedNow,
  };
}

function context(capabilities, environment = "preview", extra = {}) {
  return {
    organization_id: ORG,
    actor: { id: ACTOR, organization_id: ORG, capabilities },
    environment,
    authorized_requirement_refs: ["REQ-M3-005"],
    rate_limit: { max_calls: 50, window_ms: 60_000 },
    ...extra,
  };
}

function readProposal(path, suffix) {
  return {
    tool: "read_file",
    version: 1,
    arguments: {
      project_id: PROJECT,
      environment: "preview",
      path,
    },
    requirement_refs: ["REQ-M3-005"],
    reason: `read ${suffix}`,
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
      verification_run_id: "verify-1",
      preview_id: "preview-1",
      artifact_digest: "a".repeat(64),
      target_environment: "production",
      request_id: "request-publish-1",
      idempotency_key: "idem-publish-1",
    },
    requirement_refs: ["REQ-M3-005"],
    reason: "publish exact verified version",
  };
}

function publishContext(extra = {}) {
  return context(
    ["production.publish", "production.access"],
    "production",
    {
      verification: {
        verification: "PASS",
        publish_eligible: true,
        verification_run_id: "verify-1",
        project_id: PROJECT,
        project_version_id: "v1",
        artifact_digest: "a".repeat(64),
        project_spec_version: "spec-v1",
      },
      project_spec_version: "spec-v1",
      expected_resource_version: "r1",
      budget: { remaining_units: 100 },
      ...extra,
    },
  );
}

function currentInstructionEvaluator() {
  return {
    async evaluate(request) {
      return {
        schema_version: T.AUTHORITY_SCHEMA_VERSION,
        decision: T.AUTHORITY_DECISIONS.AUTO_EXECUTE,
        authority_basis: "explicit_current_user_instruction",
        authorization_fingerprint: request.authorization_fingerprint,
        action_hash: request.action_hash,
        policy_version: request.policy_version,
        risk: request.risk,
        request_id: request.request_id,
        issued_at: "2026-09-13T23:55:00Z",
        expires_at: "2026-09-14T00:30:00Z",
        reason_code: "CURRENT_REQUEST_AUTHORIZED",
      };
    },
  };
}

test("routine read chain executes continuously without approval prompts", async () => {
  const calls = [];
  const adapters = new T.ExecutionAdapterRegistry().register("WorkspaceExecutor", {
    async execute(request) {
      calls.push(request.arguments.path);
      return { output: { path: request.arguments.path } };
    },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const authority = new T.PandoraAuthorityToolExecutor({ gateway, now: fixedNow });
  const chain = new T.PandoraToolChainExecutor({ executor: authority });

  const result = await chain.run({
    context: context(["workspace.files.read"]),
    steps: [
      { id: "read-a", proposal: readProposal("src/a.js", "a") },
      { id: "read-b", proposal: readProposal("src/b.js", "b") },
    ],
  });

  assert.equal(result.state, T.TOOL_CHAIN_STATES.COMPLETED);
  assert.equal(result.completed_steps, 2);
  assert.deepEqual(calls, ["src/a.js", "src/b.js"]);
});

test("exact current-user authority satisfies publish approval without a second prompt", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() {
      calls += 1;
      return { output: { status: "published" } };
    },
  });
  const deps = durableMemoryDeps(adapters);
  const gateway = new T.PandoraToolGateway(deps);
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    authorityEvaluator: currentInstructionEvaluator(),
    now: fixedNow,
  });

  const result = await executor.handle(publishProposal(), publishContext());

  assert.equal(result.executed, true);
  assert.equal(result.decision.disposition, T.TOOL_DECISIONS.ALLOW);
  assert.equal(calls, 1);
  const grants = [...deps.approvalStore.records.values()];
  assert.equal(grants.length, 1);
  assert.equal(grants[0].authority_basis, "explicit_current_user_instruction");
  assert.match(grants[0].authority_fingerprint, /^[0-9a-f]{64}$/);
  assert.equal(grants[0].one_time, true);
});

test("authorization fingerprint binds cost privacy destination and protected-app scope", () => {
  const proposal = publishProposal();
  const binding = T.approvalBindingFromAction({
    proposal,
    organization_id: ORG,
    project_id: PROJECT,
    actor_id: ACTOR,
    environment: "production",
    target_resource: "production",
    project_version: "v1",
    project_state_hash: "state-v1",
    risk: T.RISK_LEVELS.HIGH,
    policy_version: T.POLICY_VERSION,
  });
  const definition = T.TOOL_REGISTRY.request_publish;
  const first = publishContext({
    destination_or_audience: "public",
    data_sensitivity: "internal",
    authority_cost: { unit: "credit", maximum: 5 },
    protected_app_scope: null,
  });
  const second = publishContext({
    destination_or_audience: "public",
    data_sensitivity: "confidential",
    authority_cost: { unit: "credit", maximum: 6 },
    protected_app_scope: "protected-zone",
  });
  const one = T.authorizationFingerprint(binding, definition, proposal, first);
  const two = T.authorizationFingerprint(binding, definition, proposal, second);
  assert.match(one, /^[0-9a-f]{64}$/);
  assert.match(two, /^[0-9a-f]{64}$/);
  assert.notEqual(one, two);
});

test("authority scope drift during evaluation fails closed before provider execution", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const ctx = publishContext({ authority_cost: { unit: "credit", maximum: 5 } });
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        ctx.authority_cost = { unit: "credit", maximum: 6 };
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.AUTO_EXECUTE,
          authority_basis: "explicit_current_user_instruction",
          authorization_fingerprint: request.authorization_fingerprint,
          action_hash: request.action_hash,
          policy_version: request.policy_version,
          risk: request.risk,
          request_id: request.request_id,
          issued_at: "2026-09-13T23:55:00Z",
          expires_at: "2026-09-14T00:30:00Z",
        };
      },
    },
  });
  await assert.rejects(executor.handle(publishProposal(), ctx), (error) => error?.code === "AUTHORITY_SCOPE_DRIFT");
  assert.equal(calls, 0);
});

test("prediction cannot be converted into authority even when fingerprint is exact", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.AUTO_EXECUTE,
          authority_basis: "prediction",
          authorization_fingerprint: request.authorization_fingerprint,
          action_hash: request.action_hash,
          policy_version: request.policy_version,
          risk: request.risk,
          request_id: request.request_id,
          issued_at: "2026-09-13T23:55:00Z",
          expires_at: "2026-09-14T00:30:00Z",
        };
      },
    },
  });

  await assert.rejects(
    executor.handle(publishProposal(), publishContext()),
    (error) => error?.code === "AUTHORITY_BASIS_INVALID",
  );
  assert.equal(calls, 0);
});

test("standing policy requires explicit match identity and exact action fingerprint", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; return { output: { status: "published" } }; },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.STANDING_AUTHORIZED,
          authority_basis: "active_explicit_standing_policy",
          standing_policy_id: "policy-deploy-production",
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
    },
  });

  const result = await executor.handle(publishProposal(), publishContext());
  assert.equal(result.executed, true);
  assert.equal(calls, 1);
});

test("standing-policy grant is one-time so later revocation cannot be bypassed by grant reuse", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; return { output: { status: "published" } }; },
  });
  const deps = durableMemoryDeps(adapters);
  const gateway = new T.PandoraToolGateway(deps);
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.STANDING_AUTHORIZED,
          authority_basis: "active_explicit_standing_policy",
          standing_policy_id: "policy-deploy-production",
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
    },
  });

  const first = await executor.handle(publishProposal(), publishContext());
  assert.equal(first.executed, true);
  assert.equal(calls, 1);
  const grants = [...deps.approvalStore.records.values()];
  assert.equal(grants.length, 1);
  assert.equal(grants[0].one_time, true);

  await assert.rejects(
    gateway.handle(publishProposal(), publishContext({ approval_id: grants[0].approval_id })),
    (error) => error?.code === "APPROVAL_REVOKED",
  );
  assert.equal(calls, 1);
});

test("fresh standing-authority evaluation on idempotent replay retires the new derived grant", async () => {
  let calls = 0;
  let evaluations = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; return { output: { status: "published" } }; },
  });
  const deps = durableMemoryDeps(adapters);
  const gateway = new T.PandoraToolGateway(deps);
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        evaluations += 1;
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.STANDING_AUTHORIZED,
          authority_basis: "active_explicit_standing_policy",
          standing_policy_id: "policy-deploy-production",
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
    },
  });

  const first = await executor.handle(publishProposal(), publishContext());
  const second = await executor.handle(publishProposal(), publishContext());
  assert.equal(first.executed, true);
  assert.equal(second.replayed, true);
  assert.equal(calls, 1);
  assert.equal(evaluations, 2);
  const grants = [...deps.approvalStore.records.values()];
  assert.equal(grants.length, 2);
  assert.notEqual(grants[0].approval_id, grants[1].approval_id);
  assert.ok(grants.every((grant) => grant.revoked_at));
});

test("tampered authority fingerprint fails closed before provider execution", async () => {
  let calls = 0;
  const adapters = new T.ExecutionAdapterRegistry().register("DeploymentExecutor", {
    productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
    async execute() { calls += 1; },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.AUTO_EXECUTE,
          authority_basis: "explicit_current_user_instruction",
          authorization_fingerprint: "0".repeat(64),
          action_hash: request.action_hash,
          policy_version: request.policy_version,
          risk: request.risk,
          request_id: request.request_id,
          issued_at: "2026-09-13T23:55:00Z",
          expires_at: "2026-09-14T00:30:00Z",
        };
      },
    },
  });

  await assert.rejects(
    executor.handle(publishProposal(), publishContext()),
    (error) => error?.code === "AUTHORITY_FINGERPRINT_MISMATCH",
  );
  assert.equal(calls, 0);
});

test("chain stops at unresolved approval boundary and does not execute later steps", async () => {
  let publishCalls = 0;
  let readCalls = 0;
  const adapters = new T.ExecutionAdapterRegistry()
    .register("DeploymentExecutor", {
      productionConcurrency: { durability: "durable", mode: "compare_and_set", owner: "deployment-provider" },
      async execute() { publishCalls += 1; },
    })
    .register("WorkspaceExecutor", {
      async execute() { readCalls += 1; return { output: { ok: true } }; },
    });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const executor = new T.PandoraAuthorityToolExecutor({
    gateway,
    now: fixedNow,
    authorityEvaluator: {
      async evaluate(request) {
        return {
          schema_version: T.AUTHORITY_SCHEMA_VERSION,
          decision: T.AUTHORITY_DECISIONS.NEEDS_APPROVAL,
          authority_basis: "none",
          authorization_fingerprint: request.authorization_fingerprint,
          action_hash: request.action_hash,
          policy_version: request.policy_version,
          risk: request.risk,
          issued_at: "2026-09-13T23:55:00Z",
          expires_at: "2026-09-14T00:30:00Z",
          reason_code: "AUTHORIZATION_REQUIRED",
        };
      },
    },
  });
  const chain = new T.PandoraToolChainExecutor({ executor });

  const result = await chain.run({
    context: publishContext(),
    steps: [
      { id: "publish", proposal: publishProposal() },
      { id: "later-read", proposal: readProposal("src/later.js", "later"), context: context(["workspace.files.read"]) },
    ],
  });

  assert.equal(result.state, T.TOOL_CHAIN_STATES.NEEDS_APPROVAL);
  assert.equal(result.blocked_step, 0);
  assert.equal(publishCalls, 0);
  assert.equal(readCalls, 0);
});

test("chain stops on ambiguous mutation and requires readback before retry", async () => {
  const adapters = new T.ExecutionAdapterRegistry().register("BuildExecutor", {
    async execute() {
      const error = new Error("provider connection lost after dispatch");
      error.mutation_may_have_committed = true;
      throw error;
    },
  });
  const gateway = new T.PandoraToolGateway(durableMemoryDeps(adapters));
  const chain = new T.PandoraToolChainExecutor({
    executor: new T.PandoraAuthorityToolExecutor({ gateway, now: fixedNow }),
  });

  const proposal = {
    tool: "request_build",
    version: 1,
    arguments: {
      project_id: PROJECT,
      environment: "preview",
      version_id: "v1",
      request_id: "request-build-1",
      idempotency_key: "idem-build-1",
    },
    requirement_refs: ["REQ-M3-005"],
    reason: "build",
  };

  const result = await chain.run({
    context: context(["build.execute"], "preview", { budget: { remaining_units: 100 } }),
    steps: [{ id: "build", proposal }],
  });

  assert.equal(result.state, T.TOOL_CHAIN_STATES.VERIFICATION_REQUIRED);
  assert.equal(result.blocked_step, 0);
});
