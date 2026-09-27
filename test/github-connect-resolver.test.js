const assert = require("node:assert/strict");
const test = require("node:test");

const {
  GitHubConnectResolver,
  GitHubConnectResolverError,
} = require("../src/runtime/github-connect-resolver.js");

const OIDC = "v".repeat(80);
const REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const CONNECTOR = "github/pandora";
const INSTALLATION = "158056492";

function tokenResponse(overrides = {}) {
  return new Response(JSON.stringify({
    token: "ghs_fixture_short_lived_token_value",
    expiresAt: Date.now() + 3_600_000,
    installationId: INSTALLATION,
    connector: { id: "scl_fixture", uid: CONNECTOR, type: "github" },
    ...overrides,
  }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function options(overrides = {}) {
  return {
    connectorUid: CONNECTOR,
    installationId: INSTALLATION,
    accountId: "github-primary",
    label: "Pandora GitHub",
    login: "pandora-rvw-314296438-20260820",
    allowMutations: true,
    allowedRepositories: [REPOSITORY],
    grantedScopes: [
      "repositories:read",
      "contents:read",
      "issues:read",
      "issues:write",
      "pull_requests:read",
      "pull_requests:write",
      "workflows:read",
    ],
    requiredProviderScopes: ["issues:read"],
    toolName: "github.get-issue",
    ...overrides,
  };
}

test("GitHub Connect requests a short-lived app token scoped to the canonical repository", async () => {
  const calls = [];
  const resolver = new GitHubConnectResolver({
    fetchFn: async (url, init) => {
      calls.push({ url, init });
      return tokenResponse();
    },
  });
  const resolved = await resolver.resolve(OIDC, options());
  assert.equal(resolved.authMode, "github_app_connect");
  assert.equal(resolved.token, "ghs_fixture_short_lived_token_value");
  assert.deepEqual(resolved.allowedRepositories, [REPOSITORY]);
  assert.equal(resolved.allowMutations, true);
  assert.equal(calls.length, 1);
  const body = JSON.parse(calls[0].init.body);
  assert.deepEqual(body.subject, { type: "app" });
  assert.equal(body.installationId, INSTALLATION);
  assert.deepEqual(body.authorizationDetails, [{
    type: "github_app_installation",
    repositories: [REPOSITORY],
    permissions: ["issues:read"],
  }]);
});
test("merge requests add contents:write to pull-request write permission", async () => {
  let requestBody;
  const resolver = new GitHubConnectResolver({
    fetchFn: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return tokenResponse();
    },
  });
  await resolver.resolve(OIDC, options({
    requiredProviderScopes: ["pull_requests:write"],
    toolName: "github.merge-pull-request",
  }));
  assert.deepEqual(
    requestBody.authorizationDetails[0].permissions,
    ["contents:write", "pull_requests:write"],
  );
});

test("identity-only tools fail closed instead of minting an over-broad app token", async () => {
  const resolver = new GitHubConnectResolver({ fetchFn: async () => tokenResponse() });
  await assert.rejects(
    () => resolver.resolve(OIDC, options({
      requiredProviderScopes: ["identity:read"],
      toolName: "github.get-me",
    })),
    (error) => error instanceof GitHubConnectResolverError
      && /legacy user-bound resolver/.test(error.message),
  );
});
