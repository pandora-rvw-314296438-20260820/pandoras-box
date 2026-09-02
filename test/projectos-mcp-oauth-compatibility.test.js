"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { createProjectOsMcpHandler } = require("../dist/projectos-mcp-handler.js");
const {
  SupabaseBearerAuthenticator,
} = require("../apps/meta-business-mcp/dist/auth/supabase-bearer.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const RESOURCE_ORIGIN = "https://mcpmaster.vercel.app";
const IDENTITY_SCOPES = ["openid", "email", "profile"];
const MCP_SCOPES = [
  ...IDENTITY_SCOPES,
  "projectos:read",
  "projectos:plan",
  "projectos:approve",
  "projectos:execute",
];
const CHALLENGE = `Bearer resource_metadata="${RESOURCE_ORIGIN}/.well-known/oauth-protected-resource/mcp", scope="${MCP_SCOPES.join(" ")}"`;
const ALLOWED_HEADERS = "Authorization,Content-Type,Mcp-Protocol-Version,Last-Event-ID,X-Request-Id";
const ALLOWED_METHODS = "GET,POST,DELETE,OPTIONS";
const EXPOSED_HEADERS = "WWW-Authenticate,Mcp-Protocol-Version,X-Request-Id";

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

function handlerWith(authenticator, membershipResolver = {
  async resolve() {
    return { organizationId: ORGANIZATION_ID, userId: USER_ID, role: "owner" };
  },
}) {
  return createProjectOsMcpHandler({
    organizationId: ORGANIZATION_ID,
    authenticator,
    membershipResolver,
    ledger: {
      async listPlans() { return []; },
    },
    workloadToken: () => "server-side-workload-token",
  });
}

function assertMcpHeaders(response) {
  assert.equal(response.headers["cache-control"], "no-store");
  assert.equal(response.headers["cdn-cache-control"], "no-store");
  assert.equal(response.headers["access-control-allow-headers"], ALLOWED_HEADERS);
  assert.equal(response.headers["access-control-allow-methods"], ALLOWED_METHODS);
  assert.equal(response.headers["access-control-expose-headers"], EXPOSED_HEADERS);
  assert.match(response.headers["x-request-id"], /^[0-9a-f-]{36}$/i);
}

function assertUnauthenticated(response, message = "A valid bearer access token is required") {
  assert.equal(response.statusCode, 401);
  assert.equal(response.headers["www-authenticate"], CHALLENGE);
  assert.deepEqual(response.body, {
    jsonrpc: "2.0",
    id: null,
    error: { code: -32001, message },
  });
  assertMcpHeaders(response);
}

test("only protected-resource discovery is public and matches the live metadata contract", async () => {
  let authentications = 0;
  const handler = handlerWith({
    async authenticate() { authentications += 1; throw new Error("must not authenticate metadata"); },
  });
  const expected = {
    resource: `${RESOURCE_ORIGIN}/mcp`,
    resource_name: "Banatao Systems ProjectOS",
    authorization_servers: ["https://jcyqixttuebxqqfkjonq.supabase.co/auth/v1"],
    scopes_supported: MCP_SCOPES,
    bearer_methods_supported: ["header"],
    resource_documentation: `${RESOURCE_ORIGIN}/control-tower`,
  };

  for (const request of [
    { method: "GET", url: "/.well-known/oauth-protected-resource" },
    { method: "GET", url: "/.well-known/oauth-protected-resource/mcp" },
    { method: "GET", url: "/api/mcp?metadata=root", query: { metadata: "root" } },
    { method: "GET", url: "/api/mcp?metadata=mcp", query: { metadata: "mcp" } },
  ]) {
    const response = await invoke(handler, request);
    assert.equal(response.statusCode, 200, request.url);
    assert.deepEqual(response.body, expected, request.url);
    assert.equal(response.headers["www-authenticate"], undefined, request.url);
    assertMcpHeaders(response);
  }
  assert.equal(authentications, 0);
});

test("unauthenticated MCP methods challenge before protocol parsing or tool discovery", async () => {
  let authentications = 0;
  const handler = handlerWith({
    async authenticate() { authentications += 1; throw new Error("missing authorization must be rejected first"); },
  });
  const initialize = {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } },
  };

  for (const request of [
    { method: "GET", url: "/mcp" },
    { method: "GET", url: "/api/mcp" },
    { method: "HEAD", url: "/mcp" },
    { method: "POST", url: "/mcp", body: initialize },
    { method: "POST", url: "/mcp", body: { jsonrpc: "2.0", id: 2, method: "tools/list" } },
    { method: "POST", url: "/mcp", body: { jsonrpc: "1.0", id: 3, method: "initialize" } },
    { method: "POST", url: "/mcp", body: { jsonrpc: "2.0", id: 4, method: "unknown/method" } },
    { method: "POST", url: "/mcp", body: "not-json" },
    { method: "DELETE", url: "/mcp" },
    { method: "PUT", url: "/mcp" },
    { method: "GET", url: "/mcp?metadata=", query: { metadata: "" } },
    { method: "GET", url: "/mcp?metadata=bogus", query: { metadata: "bogus" } },
    { method: "GET", url: "/mcp?metadata=mcp&metadata=bogus", query: { metadata: ["mcp", "bogus"] } },
  ]) {
    assertUnauthenticated(await invoke(handler, request));
  }
  assert.equal(authentications, 0);
});

test("malformed and rejected bearer credentials retain the exact challenge and JSON-RPC code", async () => {
  let fetches = 0;
  const authenticator = new SupabaseBearerAuthenticator({
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "sb_publishable_example0123456789012345",
    async fetchFn() {
      fetches += 1;
      return new Response(JSON.stringify({ message: "invalid" }), { status: 401 });
    },
  });
  const handler = handlerWith(authenticator);

  for (const authorization of ["Basic abc", "Bearer short"]) {
    const response = await invoke(handler, { method: "GET", headers: { authorization } });
    assertUnauthenticated(response);
  }
  assert.equal(fetches, 0);

  const rejected = await invoke(handler, {
    method: "GET",
    headers: { authorization: "Bearer abcdefghijklmnopqrstuvwxyz1234567890" },
  });
  assertUnauthenticated(rejected, "The bearer access token is invalid or expired");
  assert.equal(fetches, 1);
});

test("OPTIONS remains a public no-content preflight with the live MCP headers", async () => {
  let authentications = 0;
  const handler = handlerWith({
    async authenticate() { authentications += 1; throw new Error("must not authenticate preflight"); },
  });
  const response = await invoke(handler, { method: "OPTIONS" });
  assert.equal(response.statusCode, 204);
  assert.equal(response.body, undefined);
  assert.equal(response.headers["www-authenticate"], undefined);
  assertMcpHeaders(response);
  assert.equal(authentications, 0);
});

test("CORS preflight echoes only an exact configured origin and rejects every other origin", async () => {
  const handler = handlerWith({
    async authenticate() { throw new Error("must not authenticate preflight"); },
  });
  const allowed = await invoke(handler, {
    method: "OPTIONS",
    headers: { origin: RESOURCE_ORIGIN },
  });
  assert.equal(allowed.statusCode, 204);
  assert.equal(allowed.headers["access-control-allow-origin"], RESOURCE_ORIGIN);
  assert.equal(allowed.headers.vary, "Origin");
  assertMcpHeaders(allowed);

  const forbidden = await invoke(handler, {
    method: "OPTIONS",
    headers: { origin: "https://attacker.example" },
  });
  assert.equal(forbidden.statusCode, 403);
  assert.deepEqual(forbidden.body, {
    jsonrpc: "2.0",
    id: null,
    error: { code: -32003, message: "Forbidden origin" },
  });
  assert.equal(forbidden.headers["access-control-allow-origin"], undefined);
  assert.equal(forbidden.headers["access-control-allow-headers"], undefined);
  assert.equal(forbidden.headers["access-control-allow-methods"], undefined);
  assert.equal(forbidden.headers["access-control-expose-headers"], undefined);
  assert.equal(forbidden.headers["www-authenticate"], undefined);
  assert.equal(forbidden.headers["cache-control"], "no-store");

  const forbiddenGet = await invoke(handler, {
    method: "GET",
    headers: { origin: "https://attacker.example" },
  });
  assert.equal(forbiddenGet.statusCode, 403);
  assert.equal(forbiddenGet.body.error.code, -32003);
});

test("verified identity-only bearer and exact organization membership reach MCP initialize", async () => {
  const accessToken = "verified-access-token-material-long-enough";
  const handler = handlerWith({
    async authenticate(authorization) {
      assert.equal(authorization, `Bearer ${accessToken}`);
      return {
        userId: USER_ID,
        accessToken,
        scopes: IDENTITY_SCOPES,
        scopeClaimsPresent: true,
        aal: "aal1",
      };
    },
  });
  const response = await invoke(handler, {
    method: "POST",
    headers: { authorization: `Bearer ${accessToken}` },
    body: { jsonrpc: "2.0", id: 9, method: "initialize", params: {} },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.result.protocolVersion, "2025-06-18");
  assert.equal(response.headers["www-authenticate"], undefined);
});
