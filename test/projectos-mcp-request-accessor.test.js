"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { createProjectOsMcpHandler } = require("../dist/projectos-mcp-handler.js");

const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const RESOURCE_ORIGIN = "https://mcpmaster.vercel.app";

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

function handler() {
  return createProjectOsMcpHandler({
    organizationId: ORGANIZATION_ID,
    allowedOrigins: [RESOURCE_ORIGIN],
    authenticator: {
      async authenticate() {
        throw new Error("metadata and unauthenticated tests must not authenticate");
      },
    },
    membershipResolver: {
      async resolve() {
        throw new Error("metadata and unauthenticated tests must not resolve membership");
      },
    },
    workloadToken: async () => "unused-workload-token",
    ledger: {},
  });
}

function trappedRequest({ method = "GET", originalUrl, url }) {
  let queryReads = 0;
  let urlGetterReads = 0;
  const request = { method, headers: {} };

  if (typeof originalUrl === "string") {
    Object.defineProperty(request, "originalUrl", {
      value: originalUrl,
      enumerable: true,
      configurable: true,
      writable: true,
    });
  }
  if (typeof url === "string") {
    Object.defineProperty(request, "url", {
      value: url,
      enumerable: true,
      configurable: true,
      writable: true,
    });
  } else {
    Object.defineProperty(request, "url", {
      enumerable: true,
      configurable: true,
      get() {
        urlGetterReads += 1;
        throw new Error("request.url accessor was invoked");
      },
    });
  }
  Object.defineProperty(request, "query", {
    enumerable: true,
    configurable: true,
    get() {
      queryReads += 1;
      throw new Error("request.query accessor was invoked");
    },
  });

  return {
    request,
    reads() {
      return { queryReads, urlGetterReads };
    },
  };
}

async function invoke(request) {
  const response = responseRecorder();
  await handler()(request, response);
  return response;
}

function assertMetadata(response) {
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.resource, `${RESOURCE_ORIGIN}/mcp`);
  assert.deepEqual(response.body.scopes_supported, ["openid", "email", "profile"]);
  assert.equal(response.headers["www-authenticate"], undefined);
}

function assertUnauthenticated(response) {
  assert.equal(response.statusCode, 401);
  assert.equal(response.body.error.code, -32001);
  assert.equal(response.body.error.message, "A valid bearer access token is required");
  assert.match(response.headers["www-authenticate"], /^Bearer resource_metadata=/);
}

test("metadata selector uses an own originalUrl value without invoking Vercel query or url accessors", async () => {
  const trapped = trappedRequest({
    originalUrl: "/api/mcp?metadata=mcp",
  });

  assertMetadata(await invoke(trapped.request));
  assert.deepEqual(trapped.reads(), { queryReads: 0, urlGetterReads: 0 });
});

test("well-known metadata path uses an own originalUrl value without invoking accessors", async () => {
  const trapped = trappedRequest({
    originalUrl: "/.well-known/oauth-protected-resource/mcp",
  });

  assertMetadata(await invoke(trapped.request));
  assert.deepEqual(trapped.reads(), { queryReads: 0, urlGetterReads: 0 });
});

test("plain request mocks retain an own url data-property fallback", async () => {
  const trapped = trappedRequest({
    url: "/api/mcp?metadata=root",
  });

  assertMetadata(await invoke(trapped.request));
  assert.deepEqual(trapped.reads(), { queryReads: 0, urlGetterReads: 0 });
});

test("repeated metadata selectors remain non-public and never invoke accessors", async () => {
  const trapped = trappedRequest({
    originalUrl: "/api/mcp?metadata=mcp&metadata=bogus",
  });

  assertUnauthenticated(await invoke(trapped.request));
  assert.deepEqual(trapped.reads(), { queryReads: 0, urlGetterReads: 0 });
});

test("missing own URL data fails closed without reading inherited or accessor URL state", async () => {
  let inheritedUrlReads = 0;
  let inheritedQueryReads = 0;
  const prototype = {};
  Object.defineProperty(prototype, "url", {
    get() {
      inheritedUrlReads += 1;
      throw new Error("inherited request.url accessor was invoked");
    },
  });
  Object.defineProperty(prototype, "query", {
    get() {
      inheritedQueryReads += 1;
      throw new Error("inherited request.query accessor was invoked");
    },
  });
  const request = Object.assign(Object.create(prototype), {
    method: "GET",
    headers: {},
  });

  assertUnauthenticated(await invoke(request));
  assert.equal(inheritedUrlReads, 0);
  assert.equal(inheritedQueryReads, 0);
});

test("authenticated calls do not enumerate Vercel accessor-backed request state", async () => {
  const trapped = trappedRequest({
    method: "POST",
    originalUrl: "/mcp",
  });
  trapped.request.headers.authorization = "Bearer test-token";
  trapped.request.body = {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/list",
    params: {},
  };
  const response = responseRecorder();
  const authenticated = createProjectOsMcpHandler({
    organizationId: ORGANIZATION_ID,
    allowedOrigins: [RESOURCE_ORIGIN],
    authenticator: {
      async authenticate(header) {
        assert.equal(header, "Bearer test-token");
        return {
          userId: "11111111-1111-4111-8111-111111111111",
          accessToken: "test-token",
          scopes: ["openid", "email", "profile"],
        };
      },
    },
    membershipResolver: {
      async resolve(organizationId, userId) {
        return { organizationId, userId, role: "owner" };
      },
    },
    workloadToken: async () => "unused-workload-token",
    ledger: {},
  });

  await authenticated(trapped.request, response);

  assert.equal(response.statusCode, 200);
  assert.ok(Array.isArray(response.body.result.tools));
  assert.deepEqual(trapped.reads(), { queryReads: 0, urlGetterReads: 0 });
});
