"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createProviderExecutionStateMachine,
  ProviderExecutionOutcomeError,
} = require("../dist/runtime/provider-execution-state-machine.js");

const PLAN_ID = "11111111-1111-4111-8111-111111111111";

function createLedger() {
  const finishInputs = [];
  return {
    finishInputs,
    async finishPlan(_token, input) {
      finishInputs.push(structuredClone(input));
      return { planId: input.planId, status: input.status };
    },
  };
}

async function runAmbiguousCase(tool, args) {
  const ledger = createLedger();
  const machine = createProviderExecutionStateMachine({
    ledger,
    async execute() {
      throw Object.assign(new Error("private post-dispatch provider detail"), {
        status: 503,
        code: "provider_transport_failed",
      });
    },
  });

  let executionError;
  let finalizationError;
  await machine.run(async () => {
    try {
      await machine.execute(tool, args, {});
    } catch (error) {
      executionError = error;
    }
    try {
      await machine.ledger.finishPlan("server-workload-token", {
        planId: PLAN_ID,
        status: "failed",
        durationMs: 7,
        errorCode: "provider_execution_failed",
        error: "provider execution failed",
      });
    } catch (error) {
      finalizationError = error;
    }
  });

  assert.ok(executionError);
  assert.equal(finalizationError, executionError);
  assert.equal(ledger.finishInputs.length, 1);
  assert.equal(ledger.finishInputs[0].status, "failed");
  assert.equal(ledger.finishInputs[0].resultSummary, undefined);
  const summary = JSON.parse(ledger.finishInputs[0].error);
  assert.equal(summary.terminalClassification, "reconciliation_required");
  assert.equal(summary.reconciliationRequired, true);
  assert.doesNotMatch(executionError.message, /private post-dispatch provider detail/);
  return { executionError, summary };
}

test("an arbitrary idempotency-shaped field cannot make an unverified provider mutation retryable", async () => {
  const { executionError, summary } = await runAmbiguousCase(
    "github.create-issue",
    { idempotencyKey: "looks-idempotent-but-provider-support-is-unproven" },
  );
  const failure = JSON.parse(executionError.message);
  assert.equal(failure.providerOutcome, "ambiguous");
  assert.equal(failure.providerIdempotencySupported, false);
  assert.equal(failure.idempotencyIdentityHash, null);
  assert.equal(failure.retryable, false);
  assert.equal(failure.retryContract, "reconcile_before_retry");
  assert.equal(failure.reconciliationRequired, true);
  assert.equal(summary.providerIdempotencySupported, false);
  assert.equal(summary.idempotencyIdentityHash, null);
});

test("the published Memory candidate contract may reuse only its immutable provider idempotency identity", async () => {
  const { executionError, summary } = await runAmbiguousCase(
    "memory.submitEvidenceCandidate",
    { idempotencyKey: "worker1-explicit-memory-idempotency-contract" },
  );
  const failure = JSON.parse(executionError.message);
  assert.equal(failure.providerOutcome, "ambiguous");
  assert.equal(failure.providerIdempotencySupported, true);
  assert.match(failure.idempotencyIdentityHash, /^[0-9a-f]{64}$/);
  assert.equal(failure.retryable, true);
  assert.equal(failure.retryContract, "same_immutable_idempotency_identity_only");
  assert.equal(summary.idempotencyIdentityHash, failure.idempotencyIdentityHash);
});

test("request correlation alone is never treated as provider idempotency", async () => {
  const { executionError } = await runAmbiguousCase(
    "memory.submitEvidenceCandidate",
    { requestId: "correlation-only-not-provider-idempotency" },
  );
  const failure = JSON.parse(executionError.message);
  assert.equal(failure.providerOutcome, "ambiguous");
  assert.equal(failure.providerIdempotencySupported, false);
  assert.equal(failure.idempotencyIdentityHash, null);
  assert.equal(failure.retryable, false);
  assert.equal(failure.retryContract, "reconcile_before_retry");
});

test("provider outcome envelopes remain bounded when optional metadata is maximal", () => {
  const error = new ProviderExecutionOutcomeError({
    providerOutcome: "ambiguous",
    downstreamProcessingOutcome: "x".repeat(80),
    safeErrorCode: "x".repeat(80),
    validationCategory: "x".repeat(80),
    retryable: true,
    reconciliationRequired: true,
    status: 503,
    identity: {
      payloadHash: "a".repeat(64),
      providerIdempotencySupported: true,
      idempotencyIdentityHash: "b".repeat(64),
    },
    planId: PLAN_ID,
    providerFailure: {
      provider: "x".repeat(80),
      operation: "x".repeat(80),
      correlationId: "x".repeat(128),
      privacyScanVersion: "x".repeat(80),
      httpStatus: 599,
      retryAfterMs: 86_400_000,
    },
    summary: "x".repeat(200),
  });
  assert.ok(Buffer.byteLength(error.message, "utf8") <= 1000);
  const failure = JSON.parse(error.message);
  assert.equal(failure.providerOutcome, "ambiguous");
  assert.equal(failure.payloadHash, "a".repeat(64));
  assert.equal(failure.idempotencyIdentityHash, "b".repeat(64));
});
