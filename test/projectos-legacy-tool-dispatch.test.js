"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { executionPayloadHash } = require("../dist/http-app.js");
const { createProjectOsMcpHandler } = require("../dist/projectos-mcp-handler.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const PLAN_ID = "ed34d145-f738-47b7-a985-15e75342ba2c";
const TOKEN = "verified-legacy-identity-token-material-long-enough";

function responseRecorder() {
  return {
    headers: {}, statusCode: 200, body: undefined,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; return this; },
    end() { return this; },
  };
}

function request(method, params) {
  return {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: { jsonrpc: "2.0", id: 11, method, params },
  };
}

async function invoke(handler, value) {
  const response = responseRecorder();
  await handler(value, response);
  return response;
}

function dependencies(overrides = {}) {
  return {
    organizationId: ORGANIZATION_ID,
    authenticator: {
      async authenticate() {
        return {
          userId: USER_ID,
          accessToken: TOKEN,
          scopes: ["openid", "email", "profile"],
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
    ledger: { async listPlans() { return []; } },
    workloadToken: () => "server-side-vercel-oidc-token",
    now: () => Date.parse("2026-08-13T02:40:00.000Z"),
    ...overrides,
  };
}

test("tools/list preserves cached provider reads and durable plan aliases", async () => {
  const handler = createProjectOsMcpHandler(dependencies());
  const response = await invoke(handler, request("tools/list"));
  assert.equal(response.statusCode, 200);
  const tools = new Map(response.body.result.tools.map((tool) => [tool.name, tool]));
  assert.ok(tools.has("github.read-repository-api"));
  assert.ok(tools.has("flutterflow.inspect-readiness"));
  assert.ok(tools.has("projectos_plan_github_write-repository-api"));
  assert.ok(tools.has("projectos_approve_plan"));
  assert.ok(tools.has("projectos_list_audit"));
  assert.ok(tools.has("projectos_verify_audit"));
  assert.equal(tools.has("github.write-repository-api"), false);
  assert.equal(tools.has("projectos_plan_flutterflow_inspect-readiness"), false);
});

test("tool catalog resolves registry names into complete definitions", async () => {
  const handler = createProjectOsMcpHandler(dependencies());
  const response = await invoke(handler, request("tools/call", {
    name: "projectos_tool_catalog",
    arguments: {},
  }));
  assert.equal(response.statusCode, 200);
  const github = response.body.result.structuredContent.tools.find((tool) => tool.name === "github.get-repository");
  assert.equal(github.provider, "github");
  assert.equal(github.risk, "read");
  assert.ok(Array.isArray(github.requiredProviderScopes));
});

test("cached audit controls use the server workload identity", async () => {
  const calls = [];
  const handler = createProjectOsMcpHandler(dependencies({
    ledger: {
      async listAudit(token, limit) {
        calls.push({ action: "list", token, limit });
        return [{ sequence: 1 }];
      },
      async verifyAudit(token) {
        calls.push({ action: "verify", token });
        return { valid: true };
      },
    },
  }));
  const listed = await invoke(handler, request("tools/call", {
    name: "projectos_list_audit",
    arguments: { limit: 7 },
  }));
  const verified = await invoke(handler, request("tools/call", {
    name: "projectos_verify_audit",
    arguments: {},
  }));
  assert.equal(listed.statusCode, 200);
  assert.deepEqual(listed.body.result.structuredContent.events, [{ sequence: 1 }]);
  assert.equal(verified.statusCode, 200);
  assert.deepEqual(verified.body.result.structuredContent.verification, { valid: true });
  assert.deepEqual(calls, [
    { action: "list", token: "server-side-vercel-oidc-token", limit: 7 },
    { action: "verify", token: "server-side-vercel-oidc-token" },
  ]);
});

test("cached direct read names execute through server-side provider configuration", async () => {
  const calls = [];
  const args = { owner: "banataosystems", repo: "fxpass", pathSegments: ["git", "ref", "heads", "main"] };
  const handler = createProjectOsMcpHandler(dependencies({
    async toolConfiguration(name, context) {
      calls.push({ stage: "configuration", name, context });
      return { fixture: true };
    },
    async execute(name, receivedArgs, configuration) {
      calls.push({ stage: "execute", name, args: receivedArgs, configuration: await configuration });
      return { ref: "refs/heads/main" };
    },
  }));
  const response = await invoke(handler, request("tools/call", {
    name: "github.read-repository-api",
    arguments: args,
  }));
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.result.structuredContent, { ref: "refs/heads/main" });
  assert.deepEqual(calls, [
    {
      stage: "configuration",
      name: "github.read-repository-api",
      context: { vercelOidcToken: "server-side-vercel-oidc-token" },
    },
    {
      stage: "execute",
      name: "github.read-repository-api",
      args,
      configuration: { fixture: true },
    },
  ]);
});

test("MCP structured content wraps provider arrays and primitives in object envelopes", async () => {
  const args = {
    owner: "banataosystems",
    repo: "Pandoras-box",
    pathSegments: ["pulls"],
  };
  const cases = [
    {
      providerValue: [{ number: 65 }, { number: 55 }],
      structuredContent: { items: [{ number: 65 }, { number: 55 }] },
    },
    {
      providerValue: "ready",
      structuredContent: { value: "ready" },
    },
    {
      providerValue: null,
      structuredContent: { value: null },
    },
  ];

  for (const testCase of cases) {
    const handler = createProjectOsMcpHandler(dependencies({
      async toolConfiguration() { return { fixture: true }; },
      async execute() { return testCase.providerValue; },
    }));
    const response = await invoke(handler, request("tools/call", {
      name: "github.read-repository-api",
      arguments: args,
    }));

    assert.equal(response.statusCode, 200);
    assert.deepEqual(
      JSON.parse(response.body.result.content[0].text),
      testCase.providerValue,
    );
    assert.deepEqual(
      response.body.result.structuredContent,
      testCase.structuredContent,
    );
    assert.equal(Array.isArray(response.body.result.structuredContent), false);
  }
});

test("cached plan aliases bind the underlying mutation without executing it", async () => {
  const calls = [];
  const args = {
    owner: "banataosystems",
    repo: "fxpass",
    method: "POST",
    pathSegments: ["git", "trees"],
    confirmation: "POST banataosystems/fxpass/git/trees",
    body: { base_tree: "a".repeat(40), tree: [] },
  };
  const handler = createProjectOsMcpHandler(dependencies({
    ledger: {
      async createPlan(token, input) {
        calls.push({ token, input });
        return { planId: PLAN_ID, status: "pending_approval", ...input };
      },
    },
    async execute() { throw new Error("provider mutation must not execute during planning"); },
  }));
  const response = await invoke(handler, request("tools/call", {
    name: "projectos_plan_github_write-repository-api",
    arguments: args,
  }));
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.result.structuredContent.plan.planId, PLAN_ID);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].input.tool, "github.write-repository-api");
  assert.equal(calls[0].input.risk, "write");
  assert.deepEqual(calls[0].input.args, args);
  assert.equal(calls[0].input.payloadHash, executionPayloadHash("github.write-repository-api", args));
});

test("cached direct mutation names cannot bypass durable planning", async () => {
  let executions = 0;
  const handler = createProjectOsMcpHandler(dependencies({
    async execute() { executions += 1; },
  }));
  const response = await invoke(handler, request("tools/call", {
    name: "github.write-repository-api",
    arguments: {
      owner: "banataosystems",
      repo: "fxpass",
      method: "POST",
      pathSegments: ["git", "trees"],
      confirmation: "POST banataosystems/fxpass/git/trees",
    },
  }));
  assert.equal(response.statusCode, 409);
  assert.match(response.body.error.message, /durable ProjectOS plan is required/i);
  assert.equal(executions, 0);
});
