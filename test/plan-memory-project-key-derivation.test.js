"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  memoryProjectKeyForPlanArgs,
} = require("../src/runtime/source-authority.js");
const {
  ExecutionLedgerClient,
} = require("../src/runtime/execution-ledger-client.js");

test("memoryProjectKeyForPlanArgs derives canonical or explicit project keys and fails closed otherwise", () => {
  assert.equal(
    memoryProjectKeyForPlanArgs({
      owner: "pandora-rvw-314296438-20260820",
      repo: "pandoras-box",
    }),
    "mcpmaster-pandoras-box",
  );

  assert.equal(
    memoryProjectKeyForPlanArgs({
      repository: "pandora-rvw-314296438-20260820/pandoras-box-memory",
    }),
    "mcpmaster-pandoras-box",
  );

  assert.equal(
    memoryProjectKeyForPlanArgs({
      projectRef: "jcyqixttuebxqqfkjonq",
    }),
    "mcpmaster-pandoras-box",
  );

  assert.equal(
    memoryProjectKeyForPlanArgs({
      projectKey: "custom-project",
    }),
    "custom-project",
  );

  assert.equal(
    memoryProjectKeyForPlanArgs({
      owner: "unrelated-org",
      repo: "unrelated-repo",
    }),
    undefined,
  );

  assert.equal(memoryProjectKeyForPlanArgs({}), undefined);
  assert.equal(memoryProjectKeyForPlanArgs(undefined), undefined);
});

test("ExecutionLedgerClient.createPlan injects derived projectKey into contextArgs while keeping createPayload args immutable", async () => {
  let hydratedInput = null;
  let capturedRequestBody = null;

  const planId = "11111111-2222-4333-8444-555555555555";
  const requestId = "66666666-7777-4888-9999-aaaaaaaaaaaa";
  const providerArgs = {
    owner: "pandora-rvw-314296438-20260820",
    repo: "pandoras-box",
    method: "POST",
    pathSegments: ["git", "refs"],
  };

  const client = new ExecutionLedgerClient({
    contextLedger: null,
    contextProvider: {
      hydrate: async (_token, input) => {
        hydratedInput = input;
        return {
          envelope: { status: "available" },
          contextHash: "a".repeat(64),
        };
      },
    },
    fetchFn: async (_url, init) => {
      capturedRequestBody = JSON.parse(init.body);
      const body = JSON.stringify({
        ok: true,
        plan: {
          planId,
          requestId,
          tool: "github.write-repository-api",
          risk: "write",
          args: capturedRequestBody.args,
          payloadHash: "b".repeat(64),
          status: "pending_approval",
        },
      });
      return {
        ok: true,
        status: 200,
        headers: { get: () => null },
        text: async () => body,
      };
    },
  });

  const result = await client.createPlan("v".repeat(32), {
    requestId,
    tool: "github.write-repository-api",
    risk: "write",
    args: providerArgs,
    payloadHash: "b".repeat(64),
  });

  assert.ok(hydratedInput);
  assert.equal(hydratedInput.tool, "github.write-repository-api");
  assert.equal(hydratedInput.args.projectKey, "mcpmaster-pandoras-box");
  assert.equal(hydratedInput.args.owner, "pandora-rvw-314296438-20260820");
  assert.equal(hydratedInput.args.repo, "pandoras-box");

  assert.ok(capturedRequestBody);
  assert.equal(capturedRequestBody.args.projectKey, undefined);
  assert.equal(
    Object.prototype.hasOwnProperty.call(capturedRequestBody.args, "projectKey"),
    false,
  );
  assert.equal(
    Object.prototype.hasOwnProperty.call(providerArgs, "projectKey"),
    false,
  );
  assert.equal(result.planId, planId);
  assert.equal(result.memoryContextHash, "a".repeat(64));
});
