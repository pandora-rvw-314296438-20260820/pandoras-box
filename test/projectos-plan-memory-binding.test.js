"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildExecutionIntakeRequest,
} = require("../dist/runtime/mandatory-intake.js");
const {
  ExecutionLedgerClient,
} = require("../dist/runtime/execution-ledger-client.js");

const CONTROL_PROJECT_KEY = "mcpmaster";
const MEMORY_PROJECT_KEY = "mcpmaster-pandoras-box";
const REQUEST_ID = "11111111-1111-4111-8111-111111111111";
const INTAKE_ID = "22222222-2222-4222-8222-222222222222";
const PROJECT_ID = "33333333-3333-4333-8333-333333333333";
const PLAN_ID = "44444444-4444-4444-8444-444444444444";

test("mandatory intake keeps provider work in the canonical ProjectOS control workspace", () => {
  const request = buildExecutionIntakeRequest({
    requestId: REQUEST_ID,
    tool: "supabase.write-project-api",
    args: {
      accountId: "battle-realmatch",
      projectRef: "jcyqixttuebxqqfkjonq",
    },
  });

  assert.equal(request.projectKey, CONTROL_PROJECT_KEY);
  assert.equal(request.repository, undefined);
});

test("execution ledger hydrates Memory from accepted intake without contaminating provider args", async () => {
  const providerArgs = {
    accountId: "battle-realmatch",
    projectRef: "jcyqixttuebxqqfkjonq",
    method: "POST",
    path: "/v1/projects/jcyqixttuebxqqfkjonq/database/query",
    body: { query: "select 1" },
  };
  let intakeInput;
  let hydrationInput;
  let controlPayload;
  let attachedContext;

  const client = new ExecutionLedgerClient({
    intakeProvider: {
      accept: async (_token, input) => {
        intakeInput = input;
        return {
          intakeId: INTAKE_ID,
          projectId: PROJECT_ID,
          projectKey: CONTROL_PROJECT_KEY,
          projectName: "Pandora's Box",
          status: "planned",
          idempotencyKey: `execution:${REQUEST_ID}`,
        };
      },
    },
    contextProvider: {
      hydrate: async (_token, input) => {
        hydrationInput = input;
        return {
          envelope: {
            schemaVersion: "1.0.0",
            status: "available",
            source: "pandora-memory",
            namespace: "real_life",
          },
          contextHash: "c".repeat(64),
        };
      },
    },
    contextLedger: {
      attach: async (_token, input) => {
        attachedContext = input;
        return true;
      },
    },
    fetchFn: async (_url, init) => {
      controlPayload = JSON.parse(init.body);
      return new Response(JSON.stringify({
        ok: true,
        plan: {
          planId: PLAN_ID,
          requestId: REQUEST_ID,
          status: "pending_approval",
        },
      }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  });

  const plan = await client.createPlan("o".repeat(64), {
    requestId: REQUEST_ID,
    tool: "supabase.write-project-api",
    risk: "write",
    args: providerArgs,
    payloadHash: "d".repeat(64),
    expiresAt: "2026-09-02T08:00:00.000Z",
  });

  assert.deepEqual(intakeInput.args, providerArgs);
  assert.equal(Object.hasOwn(intakeInput.args, "projectKey"), false);
  assert.equal(hydrationInput.args.projectKey, MEMORY_PROJECT_KEY);
  assert.equal(hydrationInput.args.accountId, providerArgs.accountId);
  assert.equal(hydrationInput.args.projectRef, providerArgs.projectRef);
  assert.deepEqual(controlPayload.args, providerArgs);
  assert.equal(Object.hasOwn(controlPayload.args, "projectKey"), false);
  assert.equal(controlPayload.intakeId, INTAKE_ID);
  assert.equal(plan.projectKey, CONTROL_PROJECT_KEY);
  assert.equal(plan.memoryContextRecorded, true);
  assert.equal(attachedContext.planId, PLAN_ID);
  assert.equal(attachedContext.requestId, REQUEST_ID);
  assert.equal(attachedContext.contextHash, "c".repeat(64));
});
