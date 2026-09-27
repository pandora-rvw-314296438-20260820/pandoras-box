"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { createPandoraMcpHandler } = require("../dist/pandora-mcp-handler.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const TOKEN = "verified-gemini-mcp-test-token-material-long-enough";

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
    body: { jsonrpc: "2.0", id: 19, method, params },
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
    now: () => Date.parse("2026-09-27T04:30:00.000Z"),
    ...overrides,
  };
}

test("Gemini MCP can expose only its explicitly allowed GitHub tools", async () => {
  const allowedToolNames = new Set([
    "github.get-repository",
    "github.create-issue",
  ]);
  const handler = createPandoraMcpHandler(dependencies({ allowedToolNames }));
  const listed = await invoke(handler, request("tools/list"));
  assert.equal(listed.statusCode, 200);
  const names = new Set(listed.body.result.tools.map((tool) => tool.name));
  assert.ok(names.has("github.get-repository"));
  assert.ok(names.has("pandora_plan_github_create-issue"));
  assert.equal(names.has("supabase.list-projects"), false);
  assert.equal(names.has("pandora_plan_github_delete-repository-api"), false);
});

test("Gemini MCP tool catalog and dispatch fail closed outside its allowlist", async () => {
  const allowedToolNames = new Set(["github.get-repository"]);
  const handler = createPandoraMcpHandler(dependencies({ allowedToolNames }));

  const catalog = await invoke(handler, request("tools/call", {
    name: "pandora_tool_catalog",
    arguments: {},
  }));
  assert.equal(catalog.statusCode, 200);
  assert.deepEqual(
    catalog.body.result.structuredContent.tools.map((tool) => tool.name),
    ["github.get-repository"],
  );

  const denied = await invoke(handler, request("tools/call", {
    name: "supabase.list-projects",
    arguments: {},
  }));
  assert.equal(denied.statusCode, 400);
  assert.match(denied.body.error.message, /Unknown ProjectOS MCP tool/);
});
