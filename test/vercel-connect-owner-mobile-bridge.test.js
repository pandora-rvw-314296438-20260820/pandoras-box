const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const root = join(__dirname, "..");
const ownerApi = readFileSync(
  join(root, "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);
const mobileRepository = readFileSync(
  join(root, "apps/pandora-mobile/lib/core/data/remote_pandora_repository.dart"),
  "utf8",
);
const mobileContract = readFileSync(
  join(root, "apps/pandora-mobile/lib/core/data/pandora_repository.dart"),
  "utf8",
);
const connectionsScreen = readFileSync(
  join(root, "apps/pandora-mobile/lib/features/connections/connections_screen.dart"),
  "utf8",
);
const mobileConfig = readFileSync(
  join(root, "apps/pandora-mobile/lib/pandora_config.dart"),
  "utf8",
);

function between(source, start, end) {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, "start anchor must exist");
  const to = source.indexOf(end, from + start.length);
  assert.notEqual(to, -1, "end anchor must exist");
  return source.slice(from, to);
}

test("owner API bridges authenticated user to fixed MCPMaster Connect route", () => {
  const bridge = between(
    ownerApi,
    "async function ownerConnectBridge(",
    "function createOwnerWorkerAdapter(",
  );
  assert.match(
    ownerApi,
    /const MCPMASTER_CONNECT_ORIGIN = "https:\/\/mcpmaster\.vercel\.app";/,
  );
  assert.match(
    ownerApi,
    /const MCPMASTER_CONNECT_PATH = "\/api\/operator\/connect\/pandoras-box";/,
  );
  assert.match(bridge, /authorization: context\.authorization/);
  assert.match(bridge, /redirect: "error"/);
  assert.match(bridge, /textValue\(subject\.id\) === context\.userId/);
  assert.match(bridge, /VERCEL_CONNECT_USER_NOT_READY/);
  assert.doesNotMatch(bridge, /decoded\.token|providerToken|refreshToken/);
});

test("owner API exposes only bounded Connect status and authorize routes", () => {
  assert.match(ownerApi, /route === "\/connect\/pandoras-box\/status"/);
  assert.match(ownerApi, /ownerConnectBridge\(context, "status"\)/);
  assert.match(ownerApi, /route === "\/connect\/pandoras-box\/authorize"/);
  assert.match(ownerApi, /ownerConnectBridge\(context, "authorize"\)/);
  assert.match(
    ownerApi,
    /VERCEL_CONNECT_AUTHORIZATION_BODY_NOT_ALLOWED/,
  );
  assert.match(ownerApi, /CONNECT_BRIDGE_MAX_RESPONSE_BYTES = 64 \* 1024/);
});

test("connection capability is account-scoped, not poisoned by project health", () => {
  const summary = between(
    ownerApi,
    "function connectionSummary(",
    "function approvalSummary(",
  );
  assert.match(summary, /connectorFresh/);
  assert.doesNotMatch(
    summary,
    /projectos_integration_health|healthRows|healthProblem|healthFresh/,
  );

  const read = between(
    ownerApi,
    "async function connections(",
    "function base64UrlBytes(",
  );
  assert.doesNotMatch(read, /projectos_integration_health/);
});

test("Vercel connection test uses the Vault-backed broker and no provider token", () => {
  const verifyStart = ownerApi.indexOf("async function verifyVercelConnection");
  const actionStart = ownerApi.indexOf("async function connectionAction", verifyStart);
  assert.notEqual(verifyStart, -1);
  assert.notEqual(actionStart, -1);
  const verifyBlock = ownerApi.slice(verifyStart, actionStart);
  assert.match(verifyBlock, /pandora_worker_f_vercel_request_20260829/);
  assert.match(verifyBlock, /mcpmaster_project_id/);
  assert.match(verifyBlock, /config_key", "team_id"/);
  assert.doesNotMatch(
    verifyBlock,
    /PANDORA_VERCEL_TOKEN|VERCEL_TOKEN|api\.vercel\.com/,
  );

  const actionBlock = between(
    ownerApi,
    "async function connectionAction(",
    "async function approvals(",
  );
  assert.match(actionBlock, /normalizedProvider === "vercel"/);
  assert.match(actionBlock, /verifyVercelConnection\(context, connectionId\)/);
});

test("mobile keeps the single Supabase owner API transport for Connect", () => {
  assert.match(mobileContract, /UserConnectAuthorizationSource/);
  assert.match(
    mobileRepository,
    /pathSegments: const <String>\['connect', 'pandoras-box', 'status'\]/,
  );
  assert.match(
    mobileRepository,
    /pathSegments: const <String>\['connect', 'pandoras-box', 'authorize'\]/,
  );
  assert.doesNotMatch(
    mobileRepository,
    /mcpmaster\.vercel\.app\/api\/operator/,
  );
  assert.doesNotMatch(
    mobileConfig,
    /mcpmaster\.vercel\.app\/api\/operator/,
  );
});

test("mobile opens only the validated authorization URL and never receives a provider token", () => {
  assert.match(connectionsScreen, /launchUrl\(/);
  assert.match(connectionsScreen, /LaunchMode\.externalApplication/);
  assert.match(connectionsScreen, /Needs your permission/);
  assert.match(connectionsScreen, /Check user access/);
  assert.doesNotMatch(
    mobileRepository,
    /providerToken|refreshToken|connectToken/,
  );
});
