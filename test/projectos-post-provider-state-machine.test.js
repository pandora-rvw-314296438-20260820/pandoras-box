"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { createProjectOsMcpHandler } = require("../dist/projectos-mcp-handler.js");
const { executionPayloadHash } = require("../dist/http-app.js");
const {
  markProviderOutcome,
} = require("../dist/runtime/provider-execution-state-machine.js");

const TOKEN = "worker-one-state-machine-token-material-long-enough";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const TOOL = "memory.submitEvidenceCandidate";
const PLAN_ID = "11111111-1111-4111-8111-111111111111";
const SECOND_PLAN_ID = "22222222-2222-4222-8222-222222222222";

function responseRecorder() {
  return {
    headers: {},
    statusCode: 200,
    body: undefined,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; return this; },
    end() { return this; },
  };
}

function request(planId = PLAN_ID) {
  return {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: {
      jsonrpc: "2.0",
      id: 91,
      method: "tools/call",
      params: {
        name: "projectos_execute_plan",
        arguments: { planId },
      },
    },
  };
}

function dependencies(overrides = {}) {
  return {
    organizationId: ORGANIZATION_ID,
    authenticator: {
      async authenticate() {
        return {
          userId: USER_ID,
          accessToken: TOKEN,
          scopes: ["openid", "projectos:execute"],
          scopeClaimsPresent: true,
          aal: "aal1",
        };
      },
    },
    membershipResolver: {
      async resolve() {
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role: "owner" };
      },
    },
    workloadToken: () => "server-side-vercel-oidc-token",
    toolConfiguration: () => ({ fixture: true }),
    ...overrides,
  };
}

function createLedger(args, options = {}) {
  const planId = options.planId || PLAN_ID;
  let claimed = false;
  let status = "approved";
  const finishInputs = [];
  return {
    finishInputs,
    get status() { return status; },
    get claimCount() { return claimed ? 1 : 0; },
    async claimPlan(_token, requestedPlanId) {
      assert.equal(requestedPlanId, planId);
      if (claimed) {
        throw Object.assign(new Error("Plan is no longer claimable"), { status: 409 });
      }
      claimed = true;
      status = "executing";
      return {
        planId,
        requestId: "33333333-3333-4333-8333-333333333333",
        tool: TOOL,
        risk: "write",
        args,
        payloadHash: executionPayloadHash(TOOL, args),
        status,
      };
    },
    async finishPlan(_token, input) {
      finishInputs.push(structuredClone(input));
      if (options.finishError) throw options.finishError;
      status = input.status;
      return {
        planId,
        requestId: "33333333-3333-4333-8333-333333333333",
        status,
      };
    },
  };
}

function failure(response) {
  assert.ok(response.statusCode >= 400);
  const parsed = JSON.parse(response.body.error.message);
  assert.equal(parsed.schemaVersion, "1.0.0");
  return parsed;
}

function durableReconciliation(input) {
  assert.equal(input.status, "failed");
  assert.equal(input.resultSummary, undefined);
  const parsed = JSON.parse(input.error);
  assert.equal(parsed.terminalClassification, "reconciliation_required");
  assert.equal(parsed.reconciliationRequired, true);
  return parsed;
}

function deeplyNested(depth) {
  let value = { leaf: true };
  for (let index = 0; index < depth; index += 1) value = { child: value };
  return value;
}

async function executeWithResult(result, args = { namespace: "real_life" }) {
  const ledger = createLedger(args);
  let providerCalls = 0;
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      providerCalls += 1;
      return typeof result === "function" ? result() : result;
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);
  return { ledger, providerCalls, handler, response };
}

for (const [name, resultFactory] of [
  ["oversized array", () => Array.from({ length: 501 }, (_, index) => ({ index }))],
  ["excessive nesting", () => deeplyNested(22)],
  ["non-plain object", () => new Date("2026-08-19T00:00:00.000Z")],
  ["cyclic value", () => { const value = { safe: true }; value.self = value; return value; }],
  ["unserializable value", () => ({ count: 1n })],
]) {
  test(`provider success plus ${name} becomes terminal reconciliation, never durable success`, async () => {
    const { ledger, providerCalls, handler, response } = await executeWithResult(resultFactory);
    assert.equal(providerCalls, 1);
    assert.equal(response.statusCode, 502);
    const parsed = failure(response);
    assert.equal(parsed.safeErrorCode, "provider_result_contract_error");
    assert.equal(parsed.providerOutcome, "succeeded");
    assert.equal(parsed.downstreamProcessingOutcome, "failed");
    assert.equal(parsed.retryable, false);
    assert.equal(parsed.reconciliationRequired, true);

    assert.equal(ledger.finishInputs.length, 1);
    assert.equal(ledger.status, "failed");
    const summary = durableReconciliation(ledger.finishInputs[0]);
    assert.equal(summary.providerOutcome, "succeeded");
    assert.equal(summary.downstreamProcessingOutcome, "failed");
    assert.equal(summary.reconciliationRequired, true);
    assert.equal(summary.retryable, false);
    assert.equal(summary.evidencePolicy, "privacy_safe_summary_only_v1");
    assert.match(summary.payloadHash, /^[0-9a-f]{64}$/);

    const replay = responseRecorder();
    await handler(request(), replay);
    assert.equal(replay.statusCode, 409);
    assert.equal(providerCalls, 1, "the already-applied mutation must not execute twice");
  });
}

test("confirmed provider success plus durable completion loss returns non-retryable reconciliation ambiguity", async () => {
  const args = { namespace: "real_life", idempotencyKey: "worker1-durable-completion-loss" };
  const ledger = createLedger(args, { finishError: new Error("private ledger transport detail") });
  let providerCalls = 0;
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      providerCalls += 1;
      return { ok: true, receipt: "bounded" };
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);

  assert.equal(providerCalls, 1);
  assert.equal(response.statusCode, 503);
  const parsed = failure(response);
  assert.equal(parsed.safeErrorCode, "execution_finalization_ambiguous");
  assert.equal(parsed.providerOutcome, "succeeded");
  assert.equal(parsed.downstreamProcessingOutcome, "durable_completion_unknown");
  assert.equal(parsed.retryable, false);
  assert.equal(parsed.reconciliationRequired, true);
  assert.doesNotMatch(response.body.error.message, /private ledger transport detail/);
  assert.equal(ledger.status, "executing");
});

test("an unclassified post-dispatch error fails closed as ambiguous for a non-idempotent mutation", async () => {
  const args = { namespace: "real_life" };
  const ledger = createLedger(args);
  let providerCalls = 0;
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      providerCalls += 1;
      throw new Error("socket reset after dispatch with private provider detail");
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);

  assert.equal(providerCalls, 1);
  assert.equal(response.statusCode, 503);
  const parsed = failure(response);
  assert.equal(parsed.providerOutcome, "ambiguous");
  assert.equal(parsed.retryable, false);
  assert.equal(parsed.retryContract, "reconcile_before_retry");
  assert.equal(parsed.reconciliationRequired, true);
  assert.doesNotMatch(response.body.error.message, /socket reset|private provider detail/);
  assert.equal(durableReconciliation(ledger.finishInputs[0]).providerOutcome, "ambiguous");
});

test("unmarked 408 and 429 remain ambiguous because status alone cannot prove no dispatch", async () => {
  for (const expected of [
    { status: 408, code: "provider_timeout" },
    { status: 429, code: "provider_rate_limited" },
  ]) {
    const args = { namespace: "real_life" };
    const ledger = createLedger(args);
    const handler = createProjectOsMcpHandler(dependencies({
      ledger,
      async execute() {
        throw Object.assign(new Error("sanitized transient failure"), {
          status: expected.status,
          code: expected.code,
          retryable: true,
        });
      },
    }));
    const response = responseRecorder();
    await handler(request(), response);
    assert.equal(response.statusCode, expected.status);
    const parsed = failure(response);
    assert.equal(parsed.safeErrorCode, expected.code);
    assert.equal(parsed.providerOutcome, "ambiguous");
    assert.equal(parsed.retryable, false);
    assert.equal(parsed.retryContract, "reconcile_before_retry");
    assert.equal(parsed.reconciliationRequired, true);
    assert.equal(durableReconciliation(ledger.finishInputs[0]).providerOutcome, "ambiguous");
  }
});

test("a reviewed adapter marker can prove a rejection occurred before side effects", async () => {
  const args = { namespace: "real_life" };
  const ledger = createLedger(args);
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      throw markProviderOutcome(
        Object.assign(new Error("bounded provider rejection"), {
          status: 429,
          code: "provider_rate_limited",
          retryable: true,
        }),
        "not_executed",
        "reviewed_adapter_rejection",
      );
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);
  const parsed = failure(response);
  assert.equal(parsed.providerOutcome, "not_executed");
  assert.equal(parsed.retryable, true);
  assert.equal(parsed.reconciliationRequired, false);
  assert.equal(ledger.finishInputs[0].status, "failed");
});

test("an arbitrary thrown providerOutcome property cannot forge a safe retry", async () => {
  const args = { namespace: "real_life" };
  const ledger = createLedger(args);
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      throw Object.assign(new Error("untrusted provider-shaped error"), {
        status: 429,
        code: "provider_rate_limited",
        providerOutcome: "not_executed",
        retryable: true,
      });
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);
  const parsed = failure(response);
  assert.equal(parsed.providerOutcome, "ambiguous");
  assert.equal(parsed.retryable, false);
  assert.equal(parsed.retryContract, "reconcile_before_retry");
  assert.equal(durableReconciliation(ledger.finishInputs[0]).providerOutcome, "ambiguous");
});

test("a provider failure explicitly proven before side effects remains a truthful failed plan", async () => {
  const args = { namespace: "real_life" };
  const ledger = createLedger(args);
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    async execute() {
      throw markProviderOutcome(Object.assign(new Error("validation rejected before dispatch"), {
        status: 422,
        code: "provider_validation_failed",
        retryable: false,
      }), "failed_before_side_effects", "reviewed_adapter_validation");
    },
  }));
  const response = responseRecorder();
  await handler(request(), response);
  assert.equal(response.statusCode, 422);
  const parsed = failure(response);
  assert.equal(parsed.providerOutcome, "failed_before_side_effects");
  assert.equal(parsed.retryable, false);
  assert.equal(ledger.finishInputs[0].status, "failed");
});

test("ambiguous provider-supported replay reuses one immutable idempotency identity", async () => {
  const args = {
    namespace: "real_life",
    idempotencyKey: "worker1-provider-idempotency-identity",
  };
  const appliedKeys = new Set();
  let sideEffects = 0;
  const execute = async (_tool, receivedArgs) => {
    if (!appliedKeys.has(receivedArgs.idempotencyKey)) {
      appliedKeys.add(receivedArgs.idempotencyKey);
      sideEffects += 1;
      throw new Error("response lost after provider accepted the idempotent mutation");
    }
    return { ok: true, deduplicated: true };
  };

  const firstLedger = createLedger(args, { planId: PLAN_ID });
  const firstHandler = createProjectOsMcpHandler(dependencies({ ledger: firstLedger, execute }));
  const firstResponse = responseRecorder();
  await firstHandler(request(PLAN_ID), firstResponse);
  const firstFailure = failure(firstResponse);
  assert.equal(firstFailure.providerOutcome, "ambiguous");
  assert.equal(firstFailure.providerIdempotencySupported, true);
  assert.equal(firstFailure.retryable, true);
  assert.equal(firstFailure.retryContract, "same_immutable_idempotency_identity_only");
  assert.match(firstFailure.idempotencyIdentityHash, /^[0-9a-f]{64}$/);

  const secondLedger = createLedger(args, { planId: SECOND_PLAN_ID });
  const secondHandler = createProjectOsMcpHandler(dependencies({ ledger: secondLedger, execute }));
  const secondResponse = responseRecorder();
  await secondHandler(request(SECOND_PLAN_ID), secondResponse);
  assert.equal(secondResponse.statusCode, 200);
  assert.equal(sideEffects, 1, "provider idempotency must prevent a second side effect");
  assert.equal(
    durableReconciliation(firstLedger.finishInputs[0]).idempotencyIdentityHash,
    secondLedger.finishInputs[0].resultSummary.idempotencyIdentityHash,
  );
});

test("authorization remains fail-closed before claim or provider execution", async () => {
  const args = { namespace: "real_life" };
  const ledger = createLedger(args);
  let providerCalls = 0;
  const handler = createProjectOsMcpHandler(dependencies({
    ledger,
    authenticator: {
      async authenticate() {
        return {
          userId: USER_ID,
          accessToken: TOKEN,
          scopes: ["openid", "projectos:read"],
          scopeClaimsPresent: true,
          aal: "aal1",
        };
      },
    },
    async execute() { providerCalls += 1; return { ok: true }; },
  }));
  const response = responseRecorder();
  await handler(request(), response);
  assert.equal(response.statusCode, 403);
  assert.equal(providerCalls, 0);
  assert.equal(ledger.claimCount, 0);
  assert.equal(ledger.finishInputs.length, 0);
});

test("sensitive provider payload is never persisted in reconciliation evidence", async () => {
  const secret = "super-secret-provider-token-material";
  const value = { secret };
  value.self = value;
  const { ledger, response } = await executeWithResult(() => value, {
    namespace: "real_life",
    idempotencyKey: "worker1-sensitive-result-redaction",
  });
  assert.equal(response.statusCode, 502);
  assert.doesNotMatch(response.body.error.message, new RegExp(secret));
  assert.doesNotMatch(JSON.stringify(ledger.finishInputs), new RegExp(secret));
  assert.equal(
    durableReconciliation(ledger.finishInputs[0]).evidencePolicy,
    "privacy_safe_summary_only_v1",
  );
});
