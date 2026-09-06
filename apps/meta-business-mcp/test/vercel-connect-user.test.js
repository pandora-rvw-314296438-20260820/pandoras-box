const assert = require("node:assert/strict");
const test = require("node:test");

const {
  VercelConnectUserBroker,
  VercelConnectUserError,
} = require("../dist/operator/vercel-connect-user.js");

const USER_ID = "e5f5744e-554b-4f92-aad2-3f58ae6a33ad";
const PLATFORM_TOKEN = "trusted-platform-workload-token-".padEnd(96, "t");
const PROVIDER_TOKEN = "provider-user-token-that-must-never-leave-the-server";
const CONNECTOR = "mcpmaster.vercel.app/pandoras-box";

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

test("Vercel Connect probe binds exact Pandora user and keeps provider token server-side", async () => {
  const calls = [];
  const broker = new VercelConnectUserBroker({
    connector: CONNECTOR,
    providerUserinfoUrl: "https://example.supabase.co/auth/v1/oauth/userinfo",
    fetchImpl: async (url, options) => {
      calls.push({ url: String(url), options });
      if (calls.length === 1) {
        return jsonResponse(200, {
          token: PROVIDER_TOKEN,
          tokenId: "tok_123",
          expiresAt: Date.now() + 60_000,
        });
      }
      return jsonResponse(200, {
        sub: USER_ID,
        email: "owner@example.com",
        email_verified: true,
      });
    },
  });

  const result = await broker.probe({
    userId: USER_ID,
    vercelOidcToken: PLATFORM_TOKEN,
  });

  assert.deepEqual(result, { subjectId: USER_ID, emailVerified: true });
  assert.equal("token" in result, false);
  assert.equal(calls.length, 2);
  assert.equal(
    calls[0].url,
    "https://api.vercel.com/v1/connect/token/mcpmaster.vercel.app%2Fpandoras-box",
  );
  assert.equal(calls[0].options.headers.authorization, "Bearer " + PLATFORM_TOKEN);
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    subject: { type: "user", id: USER_ID },
  });
  assert.equal(
    calls[1].options.headers.authorization,
    "Bearer " + PROVIDER_TOKEN,
  );
});

test("Vercel Connect probe rejects provider subject mismatch", async () => {
  let call = 0;
  const broker = new VercelConnectUserBroker({
    providerUserinfoUrl: "https://example.supabase.co/auth/v1/oauth/userinfo",
    fetchImpl: async () => {
      call += 1;
      return call === 1
        ? jsonResponse(200, { token: PROVIDER_TOKEN })
        : jsonResponse(200, {
            sub: "f678af44-344d-412c-b5fd-63ec48dcce29",
            email_verified: true,
          });
    },
  });

  await assert.rejects(
    broker.probe({ userId: USER_ID, vercelOidcToken: PLATFORM_TOKEN }),
    (error) =>
      error instanceof VercelConnectUserError
      && error.code === "VERCEL_CONNECT_SUBJECT_MISMATCH"
      && error.status === 409,
  );
});

test("Vercel Connect 4xx token response becomes an authorization-required state", async () => {
  const broker = new VercelConnectUserBroker({
    providerUserinfoUrl: "https://example.supabase.co/auth/v1/oauth/userinfo",
    fetchImpl: async () =>
      jsonResponse(401, {
        error: "authorization_required",
      }),
  });

  await assert.rejects(
    broker.probe({ userId: USER_ID, vercelOidcToken: PLATFORM_TOKEN }),
    (error) =>
      error instanceof VercelConnectUserError
      && error.code === "VERCEL_CONNECT_USER_NOT_READY"
      && error.status === 409,
  );
});

test("Vercel Connect authorization uses exact user and bounded HTTPS return URL", async () => {
  const calls = [];
  const broker = new VercelConnectUserBroker({
    providerUserinfoUrl: "https://example.supabase.co/auth/v1/oauth/userinfo",
    fetchImpl: async (url, options) => {
      calls.push({ url: String(url), options });
      return jsonResponse(200, {
        url: "https://vercel.com/connect/authorize/example",
        request: "req_123",
      });
    },
  });

  const result = await broker.startAuthorization({
    userId: USER_ID,
    vercelOidcToken: PLATFORM_TOKEN,
    returnUrl: "https://mcpmaster.vercel.app/?connect=pandoras-box",
  });

  assert.deepEqual(result, {
    url: "https://vercel.com/connect/authorize/example",
  });
  assert.equal("request" in result, false);
  assert.equal(
    calls[0].url,
    "https://api.vercel.com/v1/connect/authorize/mcpmaster.vercel.app%2Fpandoras-box",
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    subject: { type: "user", id: USER_ID },
    returnUrl: "https://mcpmaster.vercel.app/?connect=pandoras-box",
  });
});

test("Vercel Connect rejects arbitrary non-user subjects before network access", async () => {
  let called = false;
  const broker = new VercelConnectUserBroker({
    providerUserinfoUrl: "https://example.supabase.co/auth/v1/oauth/userinfo",
    fetchImpl: async () => {
      called = true;
      return jsonResponse(200, {});
    },
  });

  await assert.rejects(
    broker.probe({
      userId: "usr_123",
      vercelOidcToken: PLATFORM_TOKEN,
    }),
    (error) =>
      error instanceof VercelConnectUserError
      && error.code === "VERCEL_CONNECT_SUBJECT_INVALID",
  );
  assert.equal(called, false);
});
