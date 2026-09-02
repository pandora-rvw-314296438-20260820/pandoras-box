"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const { createProjectOsMcpHandler } = require("../dist/projectos-mcp-handler.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const RESOURCE_ORIGIN = "https://mcpmaster.vercel.app";
const MCP_SCOPES = [
  "openid",
  "email",
  "profile",
  "projectos:read",
  "projectos:plan",
  "projectos:approve",
  "projectos:execute",
];

function responseRecorder() {
  return {
    headers: {},
    statusCode: 200,
    body: undefined,
    ended: false,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; this.ended = true; return this; },
    end() { this.ended = true; return this; },
  };
}

async function invoke(handler, request) {
  const response = responseRecorder();
  await handler({ headers: {}, url: "/mcp", ...request }, response);
  return response;
}

function handlerWithScopes(scopes) {
  return createProjectOsMcpHandler({
    organizationId: ORGANIZATION_ID,
    allowedOrigins: [RESOURCE_ORIGIN],
    authenticator: {
      async authenticate() {
        return {
          userId: USER_ID,
          accessToken: "verified-grok-access-token-material-long-enough",
          scopes,
          scopeClaimsPresent: true,
        };
      },
    },
    membershipResolver: {
      async resolve() {
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role: "owner" };
      },
    },
    workloadToken: () => "server-side-workload-token",
  });
}

test("protected-resource metadata advertises ProjectOS action scopes", async () => {
  const handler = handlerWithScopes(["openid", "email", "profile"]);
  const response = await invoke(handler, {
    method: "GET",
    url: "/.well-known/oauth-protected-resource/mcp",
  });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.scopes_supported, MCP_SCOPES);
});

test("Grok standard identity grant with phone remains bounded-legacy compatible", async () => {
  const handler = handlerWithScopes(["openid", "profile", "email", "phone", "offline_access"]);
  const response = await invoke(handler, {
    method: "POST",
    headers: { authorization: "Bearer verified-grok-access-token-material-long-enough" },
    body: {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "projectos_tool_catalog", arguments: {} },
    },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["www-authenticate"], undefined);
  assert.ok(Array.isArray(response.body.result.structuredContent.tools));
});

test("unrelated non-ProjectOS scopes remain fail closed", async () => {
  const handler = handlerWithScopes(["openid", "profile", "email", "phone", "offline_access", "secrets:read"]);
  const response = await invoke(handler, {
    method: "POST",
    headers: { authorization: "Bearer verified-grok-access-token-material-long-enough" },
    body: {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: "projectos_tool_catalog", arguments: {} },
    },
  });
  assert.equal(response.statusCode, 403);
  assert.equal(response.headers["www-authenticate"], 'Bearer error="insufficient_scope", scope="projectos:read"');
});
