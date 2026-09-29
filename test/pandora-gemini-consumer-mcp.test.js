"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");

const { createPandoraMcpHandler } = require("../dist/pandora-mcp-handler.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const TOKEN = "consumer-gemini-mcp-test-token-material-long-enough";

const PROVIDERS = new Set([
  "github.get-repository",
  "github.create-issue",
  "supabase.list-projects",
  "supabase.write-project-api",
]);

const CONTROLS = new Set([
  "pandora_tool_catalog",
  "pandora_list_plans",
  "pandora_list_audit",
  "pandora_verify_audit",
  "pandora_create_plan",
  "pandora_execute_plan",
]);

const OAUTH_SCOPES = [
  "openid",
  "email",
  "profile",
];

const SERVER_INSTRUCTIONS =
  "Pandora is an active authenticated MCP server for this Gemini session.";

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

async function invoke(handler, request) {
  const response = responseRecorder();
  await handler(request, response);
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
          scopes: OAUTH_SCOPES,
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
    ledger: {
      async createPlan(_token, input) {
        return {
          planId: "f7fe7dd6-8d16-4f17-a5ea-021b36f7d64d",
          status: "pending",
          ...input,
        };
      },
      async listPlans() { return []; },
      async listAudit() { return []; },
      async verifyAudit() { return { valid: true }; },
    },
    workloadToken: () => "server-side-vercel-oidc-token",
    now: () => Date.parse("2026-09-30T00:00:00.000Z"),
    allowedToolNames: PROVIDERS,
    allowedControlToolNames: CONTROLS,
    resourcePath: "/gemini-consumer-mcp",
    resourceMetadataPath:
      "/.well-known/oauth-protected-resource/gemini-consumer-mcp",
    metadataSelector: "gemini-consumer-mcp",
    resourceName: "Pandora for Gemini",
    serverInstructions: SERVER_INSTRUCTIONS,
    oauthScopes: OAUTH_SCOPES,
    ...overrides,
  };
}

test("consumer Gemini publishes its own protected-resource metadata without approval scope", async () => {
  const handler = createPandoraMcpHandler(dependencies());
  const response = await invoke(handler, {
    method: "GET",
    url: "/api/gemini-consumer-mcp?metadata=gemini-consumer-mcp",
    headers: {},
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.resource, "https://mcpmaster.vercel.app/gemini-consumer-mcp");
  assert.equal(response.body.resource_name, "Pandora for Gemini");
  assert.deepEqual(response.body.scopes_supported, OAUTH_SCOPES);
  assert.equal(response.body.scopes_supported.includes("pandora:approve"), false);
});

test("consumer Gemini initialize explicitly tells the model that Pandora is live", async () => {
  const handler = createPandoraMcpHandler(dependencies());
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: {
      jsonrpc: "2.0",
      id: 10,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "Google", version: "test" },
      },
    },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.result.serverInfo.name, "Pandora for Gemini");
  assert.equal(response.body.result.instructions, SERVER_INSTRUCTIONS);
});

test("consumer Gemini production source forbids false disconnected fallback", () => {
  const source = fs.readFileSync("api/mcp.ts", "utf8");
  assert.match(source, /serverInstructions: GEMINI_CONSUMER_SERVER_INSTRUCTIONS/);
  assert.match(source, /active authenticated MCP server/);
  assert.match(source, /not examples or simulations/);
  assert.match(source, /Do not claim that no MCP connection, runtime bridge, or credentials are available/);
});

test("consumer Gemini challenge requests only OAuth-server-supported identity scopes", async () => {
  const handler = createPandoraMcpHandler(dependencies());
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: {},
    body: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} },
  });
  assert.equal(response.statusCode, 401);
  assert.match(
    response.headers["www-authenticate"],
    /\.well-known\/oauth-protected-resource\/gemini-consumer-mcp/,
  );
  assert.doesNotMatch(response.headers["www-authenticate"], /pandora:/);
});

test("consumer Gemini exposes bounded reads and plan-only provider mutations", async () => {
  const handler = createPandoraMcpHandler(dependencies());
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
  });
  assert.equal(response.statusCode, 200);
  const names = new Set(response.body.result.tools.map((tool) => tool.name));

  assert.ok(names.has("github.get-repository"));
  assert.ok(names.has("supabase.list-projects"));
  assert.ok(names.has("pandora_plan_github_create-issue"));
  assert.ok(names.has("pandora_plan_supabase_write-project-api"));
  assert.ok(names.has("pandora_execute_plan"));
  assert.equal(names.has("pandora_approve_plan"), false);
  assert.equal(names.has("supabase.delete-organization-api"), false);
});

test("consumer Gemini cannot call the hidden Pandora approval control", async () => {
  const handler = createPandoraMcpHandler(dependencies());
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: "pandora_approve_plan",
        arguments: { planId: "f7fe7dd6-8d16-4f17-a5ea-021b36f7d64d" },
      },
    },
  });
  assert.equal(response.statusCode, 400);
  assert.match(response.body.error.message, /Unknown Pandora MCP tool/);
});

test("consumer Gemini mutation request creates a durable plan without provider execution", async () => {
  let executed = false;
  const handler = createPandoraMcpHandler(dependencies({
    execute: async () => {
      executed = true;
      throw new Error("provider execution must not occur");
    },
  }));
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: {
      jsonrpc: "2.0",
      id: 4,
      method: "tools/call",
      params: {
        name: "pandora_plan_supabase_write-project-api",
        arguments: {
          accountId: "pandoras-box",
          projectRef: "jcyqixttuebxqqfkjonq",
          pathSegments: ["config", "auth"],
          method: "PATCH",
          confirmation: "PATCH PROJECT jcyqixttuebxqqfkjonq/config/auth",
        },
      },
    },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(executed, false);
  assert.equal(
    response.body.result.structuredContent.plan.tool,
    "supabase.write-project-api",
  );
});

test("consumer Gemini rejects non-owner Pandora memberships", async () => {
  const handler = createPandoraMcpHandler(dependencies({
    allowedMembershipRoles: new Set(["owner"]),
    membershipResolver: {
      async resolve() {
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role: "admin" };
      },
    },
  }));
  const response = await invoke(handler, {
    method: "POST",
    url: "/gemini-consumer-mcp",
    headers: { authorization: `Bearer ${TOKEN}` },
    body: { jsonrpc: "2.0", id: 5, method: "tools/list", params: {} },
  });
  assert.equal(response.statusCode, 403);
  assert.match(response.body.error.message, /membership role is not authorized/);
});
