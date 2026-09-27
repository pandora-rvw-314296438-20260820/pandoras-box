const assert = require("node:assert/strict");
const test = require("node:test");

const ENV_KEYS = [
  "GITHUB_TOKEN",
  "MCPMASTER_GITHUB_ACCOUNT_ID",
  "GITHUB_ACCOUNT_LABEL",
  "GITHUB_LOGIN",
  "VERCEL_OIDC_TOKEN",
  "PANDORA_GITHUB_CONNECT_ENABLED",
  "PANDORA_GITHUB_CONNECTOR_UID",
  "PANDORA_GITHUB_CONNECT_INSTALLATION_ID",
  "PANDORA_GITHUB_CONNECT_ALLOWED_REPOSITORIES",
  "PANDORA_GITHUB_CONNECT_GRANTED_SCOPES",
  "PANDORA_GITHUB_CONNECT_ALLOW_MUTATIONS",
];

const REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";

function saveEnvironment() {
  return Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
}

function restoreEnvironment(before) {
  for (const key of ENV_KEYS) {
    if (before[key] === undefined) delete process.env[key];
    else process.env[key] = before[key];
  }
}

function enableConnect() {
  delete process.env.GITHUB_TOKEN;
  delete process.env.VERCEL_OIDC_TOKEN;
  process.env.MCPMASTER_GITHUB_ACCOUNT_ID = "github-primary";
  process.env.GITHUB_ACCOUNT_LABEL = "Pandora GitHub";
  process.env.GITHUB_LOGIN = "pandora-rvw-314296438-20260820";
  process.env.PANDORA_GITHUB_CONNECT_ENABLED = "true";
  process.env.PANDORA_GITHUB_CONNECTOR_UID = "github/pandora";
  process.env.PANDORA_GITHUB_CONNECT_INSTALLATION_ID = "158056492";
  process.env.PANDORA_GITHUB_CONNECT_ALLOWED_REPOSITORIES = REPOSITORY;
  process.env.PANDORA_GITHUB_CONNECT_GRANTED_SCOPES = [
    "identity:read",
    "repositories:read",
    "repositories:write",
    "contents:read",
    "contents:write",
    "issues:read",
    "issues:write",
    "pull_requests:read",
    "pull_requests:write",
    "workflows:read",
    "workflows:write",
  ].join(",");
  process.env.PANDORA_GITHUB_CONNECT_ALLOW_MUTATIONS = "true";
}

test("repository-scoped GitHub tools use Vercel Connect before the Vault catalog", async () => {
  const before = saveEnvironment();
  const originalFetch = globalThis.fetch;
  try {
    enableConnect();
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      assert.match(String(url), /^https:\/\/api\.vercel\.com\/v1\/connect\/token\//);
      const body = JSON.parse(init.body);
      assert.equal(body.subject.type, "app");
      assert.equal(body.installationId, "158056492");
      assert.deepEqual(body.authorizationDetails[0].repositories, [REPOSITORY]);
      assert.deepEqual(body.authorizationDetails[0].permissions, ["contents:read"]);
      return new Response(JSON.stringify({
        token: "fixture-short-lived-connect-token-value-123456789",
        expiresAt: Date.now() + 3_600_000,
        installationId: "158056492",
        connector: { id: "scl_fixture", uid: "github/pandora", type: "github" },
      }), { status: 200, headers: { "content-type": "application/json" } });
    };
    const { buildToolConfiguration } = require("../src/runtime/service-config.js");
    const configuration = await buildToolConfiguration(
      "github.get-repository",
      { vercelOidcToken: "v".repeat(80) },
    );
    assert.equal(calls.length, 1);
    assert.equal(configuration.github.authMode, "github_app_connect");
    assert.equal(configuration.github.token, "fixture-short-lived-connect-token-value-123456789");
    assert.deepEqual(configuration.github.allowedRepositories, [REPOSITORY]);
    assert.equal(configuration.github.allowMutations, true);
  } finally {
    globalThis.fetch = originalFetch;
    restoreEnvironment(before);
  }
});

test("account-scoped GitHub identity remains on the staged Vault fallback", async () => {
  const before = saveEnvironment();
  const originalFetch = globalThis.fetch;
  try {
    enableConnect();
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      assert.equal(
        String(url),
        "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control",
      );
      return new Response(JSON.stringify({
        ok: true,
        accounts: [{
          id: "github-primary",
          label: "GitHub Account — pandora-rvw-314296438-20260820",
          authMode: "github_app",
          token: "governed-vault-token",
          allowMutations: true,
          baseUrl: "https://api.github.com",
          login: "pandora-rvw-314296438-20260820",
          allowedRepositories: [REPOSITORY],
          grantedScopes: ["identity:read"],
        }],
      }), { status: 200, headers: { "content-type": "application/json" } });
    };
    const { buildToolConfiguration } = require("../src/runtime/service-config.js");
    const configuration = await buildToolConfiguration(
      "github.get-me",
      { vercelOidcToken: "v".repeat(80) },
    );
    assert.equal(calls.length, 1);
    assert.equal(configuration.github.authMode, "github_app");
    assert.equal(configuration.github.token, "governed-vault-token");
  } finally {
    globalThis.fetch = originalFetch;
    restoreEnvironment(before);
  }
});
