"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { createHttpApp, executionPayloadHash } = require("../dist/http-app.js");

const ADMIN_TOKEN = "provider-contract-admin-token-longer-than-thirty-two";
const APPROVAL_TOKEN = "provider-contract-approval-token-longer-than-thirty-two";
const OIDC_TOKEN = "v".repeat(80);
const PLAN_ID = "11111111-1111-4111-8111-111111111111";
const OTHER_PLAN_ID = "22222222-2222-4222-8222-222222222222";
const REQUEST_ID = "33333333-3333-4333-8333-333333333333";
const TOOL = "github.create-issue";
const ARGS = {
  owner: "banataosystems",
  repo: "Pandoras-box",
  title: "Provider mutation truth fixture",
};

async function withServer(app, action) {
  const server = await new Promise((resolve) => {
    const value = app.listen(0, "127.0.0.1", () => resolve(value));
  });
  try {
    const address = server.address();
    return await action(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
}

function createLedger(options = {}) {
  const finishInputs = [];
  let claimed = false;
  return {
    finishInputs,
    async claimPlan(_token, requestedPlanId) {
      assert.equal(requestedPlanId, PLAN_ID);
      if (claimed) throw Object.assign(new Error("already claimed"), { status: 409 });
      claimed = true;
      return {
        planId: PLAN_ID,
        requestId: REQUEST_ID,
        tool: TOOL,
        risk: "write",
        args: ARGS,
        payloadHash: executionPayloadHash(TOOL, ARGS),
        status: "executing",
      };
    },
    async finishPlan(_token, input) {
      finishInputs.push(structuredClone(input));
      if (options.finishError) throw new Error("private ledger transport detail");
      return {
        planId: options.mismatchedFinalization ? OTHER_PLAN_ID : input.planId,
        requestId: REQUEST_ID,
        status: input.status,
      };
    },
  };
}

function runtime(ledger, execute) {
  const security = {
    adminToken: ADMIN_TOKEN,
    approvalToken: APPROVAL_TOKEN,
    allowedOrigins: ["https://mcpmaster.vercel.app"],
  };
  return createHttpApp({
    port: 3000,
    adminToken: ADMIN_TOKEN,
    approvalToken: APPROVAL_TOKEN,
    allowedOrigins: "https://mcpmaster.vercel.app",
    rateLimitRequests: 100,
    rateLimitWindowMs: 60_000,
  }, {
    async resolve() { return security; },
  }, ledger, {
    async consume() {
      return {
        allowed: true,
        limit: 100,
        remaining: 99,
        count: 1,
        resetAt: new Date(Date.now() + 60_000).toISOString(),
        windowSeconds: 60,
      };
    },
  }, async () => [], execute);
}

async function invoke({ execute, ledger = createLedger() }) {
  return withServer(runtime(ledger, execute), async (origin) => {
    const response = await fetch(`${origin}/tools/execute`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${ADMIN_TOKEN}`,
        "content-type": "application/json",
        "x-vercel-oidc-token": OIDC_TOKEN,
      },
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    return { response, body: await response.json(), ledger };
  });
}

function providerFailure(body) {
  const parsed = JSON.parse(body.error.message);
  assert.equal(parsed.schemaVersion, "1.0.0");
  return parsed;
}

function durableReconciliation(input) {
  assert.equal(input.status, "failed");
  assert.equal(input.resultSummary, undefined);
  const parsed = JSON.parse(input.error);
  assert.equal(parsed.terminalClassification, "reconciliation_required");
  assert.equal(parsed.reconciliationRequired, true);
  assert.equal(parsed.automaticRetryAllowed, false);
  return parsed;
}

test("HTTP keeps an unclassified post-dispatch mutation ambiguous and redacted", async () => {
  const secret = "private-provider-detail-after-dispatch";
  const { response, body, ledger } = await invoke({
    async execute() { throw new Error(secret); },
  });
  assert.equal(response.status, 503);
  const failure = providerFailure(body);
  assert.equal(failure.providerOutcome, "ambiguous");
  assert.equal(failure.retryable, false);
  assert.equal(failure.retryContract, "reconcile_before_retry");
  assert.equal(failure.reconciliationRequired, true);
  assert.doesNotMatch(JSON.stringify(body), new RegExp(secret));
  assert.equal(ledger.finishInputs.length, 1);
  assert.equal(durableReconciliation(ledger.finishInputs[0]).providerOutcome, "ambiguous");
});

test("HTTP records provider success when local result serialization is unsafe", async () => {
  const cyclic = { ok: true };
  cyclic.self = cyclic;
  const { response, body, ledger } = await invoke({
    async execute() { return cyclic; },
  });
  assert.equal(response.status, 502);
  const failure = providerFailure(body);
  assert.equal(failure.providerOutcome, "succeeded");
  assert.equal(failure.retryable, false);
  assert.equal(failure.reconciliationRequired, true);
  assert.equal(ledger.finishInputs.length, 1);
  const durable = durableReconciliation(ledger.finishInputs[0]);
  assert.equal(durable.providerOutcome, "succeeded");
  assert.equal(durable.downstreamProcessingOutcome, "failed");
  assert.equal(durable.retryContract, "do_not_repeat_provider_mutation");
});

test("HTTP rejects a mismatched durable finalization identity after one provider call", async () => {
  let providerCalls = 0;
  const ledger = createLedger({ mismatchedFinalization: true });
  const { response, body } = await invoke({
    ledger,
    async execute() {
      providerCalls += 1;
      return { ok: true, issueNumber: 91 };
    },
  });
  assert.equal(providerCalls, 1);
  assert.equal(response.status, 503);
  const failure = providerFailure(body);
  assert.equal(failure.safeErrorCode, "execution_finalization_ambiguous");
  assert.equal(failure.providerOutcome, "succeeded");
  assert.equal(failure.retryable, false);
  assert.ok(ledger.finishInputs.length >= 1);
  assert.equal(
    durableReconciliation(ledger.finishInputs.at(-1)).providerOutcome,
    "succeeded",
  );
});

test("HTTP successful finalization stores only a bounded outcome summary", async () => {
  const { response, body, ledger } = await invoke({
    async execute() {
      return { ok: true, privateReceipt: "not-durable" };
    },
  });
  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(ledger.finishInputs.length, 1);
  assert.equal(ledger.finishInputs[0].status, "completed");
  const summary = ledger.finishInputs[0].resultSummary;
  assert.equal(summary.providerOutcome, "succeeded");
  assert.equal(summary.retryContract, "do_not_repeat_provider_mutation");
  assert.equal(summary.reconciliationRequired, false);
  assert.doesNotMatch(JSON.stringify(summary), /privateReceipt|not-durable/);
});
