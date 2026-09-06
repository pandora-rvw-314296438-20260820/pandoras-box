const assert = require("node:assert/strict");
const test = require("node:test");
const express = require("express");

const { createOperatorApiApp } = require("../dist/operator/api.js");
const { VercelConnectUserError } = require("../dist/operator/vercel-connect-user.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const ACCESS_TOKEN = "human-access-token-that-is-long-enough-for-the-test";
const PLATFORM_TOKEN = "trusted-platform-workload-token-".padEnd(96, "t");

async function withServer(app, action) {
  const server = await new Promise((resolve) => {
    const value = app.listen(0, "127.0.0.1", () => resolve(value));
  });
  try {
    return await action("http://127.0.0.1:" + server.address().port);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

function appFor(connectUserBroker, identityOverrides = {}, platformOidc = PLATFORM_TOKEN) {
  const app = express();
  app.use(express.json());
  app.use((request, _response, next) => {
    Object.defineProperty(request, "__canonicalVercelOidcToken", {
      configurable: false,
      enumerable: false,
      writable: false,
      value: platformOidc,
    });
    next();
  });
  app.use(createOperatorApiApp({
    authenticator: {
      async authenticate(header) {
        if (header !== "Bearer " + ACCESS_TOKEN) {
          throw Object.assign(new Error("invalid session"), { status: 401 });
        }
        return {
          userId: USER_ID,
          accessToken: ACCESS_TOKEN,
          aal: "aal1",
          ...identityOverrides,
        };
      },
    },
    membershipResolver: {
      async resolve() {
        return {
          organizationId: ORGANIZATION_ID,
          userId: USER_ID,
          role: "owner",
        };
      },
    },
    organizationId: ORGANIZATION_ID,
    supabaseUrl: "https://example.supabase.co",
    supabasePublishableKey: "sb_publishable_testkey012345678901234567890",
    allowedOrigins: ["https://mcpmaster.vercel.app"],
    requestsPerMinute: 100,
    connectUserBroker,
    runtimeFactory: () => express.Router(),
  }));
  return app;
}

test("operator Connect status uses exact Supabase user and canonical platform OIDC only", async () => {
  const seen = [];
  const broker = {
    connector: "mcpmaster.vercel.app/pandoras-box",
    async probe(input) {
      seen.push(input);
      return { subjectId: input.userId, emailVerified: true };
    },
  };

  await withServer(appFor(broker, {
    scopeClaimsPresent: true,
    scopes: ["openid", "projectos:read"],
  }), async (origin) => {
    const response = await fetch(origin + "/connect/pandoras-box/status", {
      headers: {
        authorization: "Bearer " + ACCESS_TOKEN,
        "x-vercel-oidc-token": "attacker-controlled-oidc",
      },
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    const body = await response.json();
    assert.equal(body.connected, true);
    assert.equal(body.subject.id, USER_ID);
    assert.equal("token" in body, false);
  });

  assert.deepEqual(seen, [{
    userId: USER_ID,
    vercelOidcToken: PLATFORM_TOKEN,
  }]);
});

test("operator Connect authorization derives exact subject and fixed allowed return origin", async () => {
  const seen = [];
  const broker = {
    connector: "mcpmaster.vercel.app/pandoras-box",
    async startAuthorization(input) {
      seen.push(input);
      return { url: "https://vercel.com/connect/authorize/example" };
    },
  };

  await withServer(appFor(broker, {
    scopeClaimsPresent: true,
    scopes: ["openid", "projectos:read"],
  }), async (origin) => {
    const response = await fetch(origin + "/connect/pandoras-box/authorize", {
      method: "POST",
      headers: {
        authorization: "Bearer " + ACCESS_TOKEN,
        "content-type": "application/json",
        "x-vercel-oidc-token": "attacker-controlled-oidc",
      },
      body: "{}",
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(
      body.authorizationUrl,
      "https://vercel.com/connect/authorize/example",
    );
    assert.equal("token" in body, false);
  });

  assert.deepEqual(seen, [{
    userId: USER_ID,
    vercelOidcToken: PLATFORM_TOKEN,
    returnUrl: "https://mcpmaster.vercel.app/?connect=pandoras-box",
  }]);
});

test("operator Connect authorization rejects caller-supplied identity or redirect fields", async () => {
  let called = false;
  const broker = {
    connector: "mcpmaster.vercel.app/pandoras-box",
    async startAuthorization() {
      called = true;
      return { url: "https://vercel.com/connect/authorize/example" };
    },
  };

  await withServer(appFor(broker), async (origin) => {
    const response = await fetch(origin + "/connect/pandoras-box/authorize", {
      method: "POST",
      headers: {
        authorization: "Bearer " + ACCESS_TOKEN,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        userId: "f678af44-344d-412c-b5fd-63ec48dcce29",
        returnUrl: "https://attacker.example/callback",
      }),
    });
    assert.equal(response.status, 400);
    assert.equal(
      (await response.json()).error.code,
      "VERCEL_CONNECT_AUTHORIZATION_BODY_NOT_ALLOWED",
    );
  });
  assert.equal(called, false);
});

test("operator Connect routes require ProjectOS read scope when OAuth scopes are present", async () => {
  let called = false;
  const broker = {
    connector: "mcpmaster.vercel.app/pandoras-box",
    async probe() {
      called = true;
      return { subjectId: USER_ID, emailVerified: true };
    },
  };

  await withServer(appFor(broker, {
    scopeClaimsPresent: true,
    scopes: ["openid", "projectos:plan"],
  }), async (origin) => {
    const response = await fetch(origin + "/connect/pandoras-box/status", {
      headers: { authorization: "Bearer " + ACCESS_TOKEN },
    });
    assert.equal(response.status, 403);
    assert.match(response.headers.get("www-authenticate"), /projectos:read/);
  });
  assert.equal(called, false);
});

test("operator Connect status exposes authorization path but not token on first-use state", async () => {
  const broker = {
    connector: "mcpmaster.vercel.app/pandoras-box",
    async probe() {
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_USER_NOT_READY",
        "authorization required",
        409,
      );
    },
  };

  await withServer(appFor(broker), async (origin) => {
    const response = await fetch(origin + "/connect/pandoras-box/status", {
      headers: { authorization: "Bearer " + ACCESS_TOKEN },
    });
    assert.equal(response.status, 409);
    const body = await response.json();
    assert.equal(body.connected, false);
    assert.equal(
      body.authorizationPath,
      "/api/operator/connect/pandoras-box/authorize",
    );
    assert.equal("token" in body, false);
  });
});
