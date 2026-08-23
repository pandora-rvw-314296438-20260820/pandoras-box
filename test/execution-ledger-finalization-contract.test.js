"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ExecutionLedgerClient,
  ExecutionLedgerFinalizationError,
} = require("../src/runtime/execution-ledger-client.js");

const TOKEN = "server-side-vercel-oidc-token-material-long-enough";
const PLAN_ID = "11111111-1111-4111-8111-111111111111";
const REQUEST_ID = "22222222-2222-4222-8222-222222222222";

function terminalOutcome(overrides = {}) {
  return {
    schemaVersion: "1.0.0",
    terminalClassification: "succeeded",
    providerOutcome: "succeeded",
    mutationState: "PROVIDER_SUCCEEDED",
    downstreamProcessingOutcome: "succeeded",
    retryable: false,
    automaticRetryAllowed: false,
    retryContract: "do_not_repeat_provider_mutation",
    reconciliationRequired: false,
    providerIdempotencySupported: false,
    evidencePolicy: "privacy_safe_summary_only_v1",
    ...overrides,
  };
}

function plan(status, outcome) {
  return {
    planId: PLAN_ID,
    requestId: REQUEST_ID,
    tool: "memory.submitEvidenceCandidate",
    risk: "write",
    args: { idempotencyKey: "projectos-contract:0000000000000000" },
    payloadHash: "a".repeat(64),
    status,
    ...(outcome ? { terminalOutcome: outcome } : {}),
  };
}

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

test("invalid execution-ledger runtime limits resolve to finite bounded defaults", () => {
  for (const value of [Number.NaN, Number.POSITIVE_INFINITY, -1, 0, "invalid"]) {
    const client = new ExecutionLedgerClient({
      timeoutMs: value,
      maxResponseBytes: value,
      fetchFn: async () => jsonResponse({ ok: true, plans: [] }),
      intakeProvider: null,
      contextProvider: null,
      contextLedger: null,
    });
    assert.equal(client.timeoutMs, 10000);
    assert.equal(client.maxResponseBytes, 512000);
  }
});

test("finishPlan recovers a lost finalization response through exact durable-state readback", async () => {
  let finishAttempts = 0;
  let listAttempts = 0;
  const client = new ExecutionLedgerClient({
    intakeProvider: null,
    contextProvider: null,
    contextLedger: null,
    async fetchFn(_url, init) {
      const payload = JSON.parse(init.body);
      if (payload.action === "execution_plan_finish") {
        finishAttempts += 1;
        throw new Error("simulated response loss");
      }
      assert.equal(payload.action, "execution_plan_list");
      listAttempts += 1;
      return jsonResponse({ ok: true, plans: [plan("completed", terminalOutcome())] });
    },
  });

  const result = await client.finishPlan(TOKEN, {
    planId: PLAN_ID,
    status: "completed",
    durationMs: 10,
    resultSummary: { type: "memory_evidence_candidate" },
  });
  assert.equal(result.planId, PLAN_ID);
  assert.equal(result.status, "completed");
  assert.equal(finishAttempts, 1);
  assert.equal(listAttempts, 1);
});

test("unresolved durable executing state throws an explicit non-retryable reconciliation obligation", async () => {
  const client = new ExecutionLedgerClient({
    intakeProvider: null,
    contextProvider: null,
    contextLedger: null,
    async fetchFn(_url, init) {
      const payload = JSON.parse(init.body);
      if (payload.action === "execution_plan_finish") {
        return jsonResponse({ ok: false, error: "temporary_unavailable" }, 503);
      }
      return jsonResponse({ ok: true, plans: [plan("executing")] });
    },
  });

  await assert.rejects(
    () => client.finishPlan(TOKEN, {
      planId: PLAN_ID,
      status: "completed",
      durationMs: 10,
      resultSummary: { type: "memory_evidence_candidate" },
    }),
    (error) => {
      assert.ok(error instanceof ExecutionLedgerFinalizationError);
      assert.equal(error.status, 503);
      assert.equal(error.code, "execution_finalization_ambiguous");
      assert.equal(error.retryable, false);
      assert.equal(error.reconciliationRequired, true);
      const failure = JSON.parse(error.message);
      assert.equal(failure.planId, PLAN_ID);
      assert.equal(failure.expectedStatus, "completed");
      assert.equal(failure.observedStatus, "executing");
      assert.equal(failure.reconciliationRequired, true);
      return true;
    },
  );
});

test("failed readback preserves an explicit reconciliation-required no-repeat outcome", async () => {
  const payloadHash = "c".repeat(64);
  const durableError = JSON.stringify({
    schemaVersion: "1.0.0",
    terminalClassification: "reconciliation_required",
    providerOutcome: "succeeded",
    mutationState: "PROVIDER_SUCCEEDED_LOCAL_FINALIZATION_FAILED",
    downstreamProcessingOutcome: "local_processing_failed",
    safeErrorCode: "provider_result_contract_error",
    retryable: false,
    automaticRetryAllowed: false,
    retryContract: "do_not_repeat_provider_mutation",
    reconciliationRequired: true,
    providerIdempotencySupported: false,
    payloadHash,
    idempotencyIdentityHash: null,
    evidencePolicy: "privacy_safe_summary_only_v1",
  });
  const client = new ExecutionLedgerClient({
    intakeProvider: null,
    contextProvider: null,
    contextLedger: null,
    async fetchFn(_url, init) {
      const payload = JSON.parse(init.body);
      if (payload.action === "execution_plan_finish") {
        return jsonResponse({ ok: true, plan: plan("failed") });
      }
      return jsonResponse({
        ok: true,
        plans: [plan("failed", terminalOutcome({
          terminalClassification: "reconciliation_required",
          providerOutcome: "succeeded",
          mutationState: "PROVIDER_SUCCEEDED_LOCAL_FINALIZATION_FAILED",
          downstreamProcessingOutcome: "local_processing_failed",
          safeErrorCode: "provider_result_contract_error",
          retryContract: "do_not_repeat_provider_mutation",
          reconciliationRequired: true,
          payloadHash,
        }))],
      });
    },
  });

  const result = await client.finishPlan(TOKEN, {
    planId: PLAN_ID,
    status: "failed",
    durationMs: 9,
    error: durableError,
  });
  assert.equal(result.status, "failed");
  assert.equal(result.terminalOutcome.terminalClassification, "reconciliation_required");
  assert.equal(result.terminalOutcome.providerOutcome, "succeeded");
  assert.equal(result.terminalOutcome.retryable, false);
  assert.equal(result.terminalOutcome.automaticRetryAllowed, false);
  assert.equal(result.terminalOutcome.retryContract, "do_not_repeat_provider_mutation");
  assert.equal(result.terminalOutcome.reconciliationRequired, true);
  assert.equal(result.terminalOutcome.payloadHash, payloadHash);
});

test("invalid max-response configuration cannot disable the execution-ledger size guard", async () => {
  const client = new ExecutionLedgerClient({
    maxResponseBytes: Number.NaN,
    intakeProvider: null,
    contextProvider: null,
    contextLedger: null,
    async fetchFn() {
      return jsonResponse({ ok: true, plans: [] }, 200, {
        "content-length": "512001",
      });
    },
  });
  await assert.rejects(
    () => client.listPlans(TOKEN, 10),
    /Execution ledger response is too large/,
  );
});

test("execution-ledger provider error text is reduced to an allowlisted bounded code", async () => {
  const secret = "private control-plane database detail";
  const client = new ExecutionLedgerClient({
    intakeProvider: null,
    contextProvider: null,
    contextLedger: null,
    async fetchFn() {
      return jsonResponse({ ok: false, error: secret }, 503);
    },
  });
  await assert.rejects(
    () => client.listPlans(TOKEN, 10),
    (error) => {
      assert.equal(error.status, 503);
      assert.match(error.message, /request_failed/);
      assert.doesNotMatch(error.message, new RegExp(secret));
      assert.ok(Buffer.byteLength(error.message, "utf8") <= 200);
      return true;
    },
  );
});
