import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");

const ownerApi = read("supabase/functions/pandora-owner-api/index.ts");
const broker = read("supabase/functions/pandora-connections-broker/index.ts");
const migration = read(
  "supabase/migrations/20261001143000_pandora_connections_provider_readback_hardening_v1.sql",
);
const providerManifests = read(
  "packages/pandora-universal-connections/provider-manifests.mjs",
);

test("owner API projects only canonical live provider readback as ready", () => {
  assert.match(ownerApi, /rpc\("pandora_live_connections_v1"/);
  assert.match(ownerApi, /legacy_installation_without_live_provider_readback/);
  assert.match(ownerApi, /connection\.authority\) === "live_provider_readback"/);
  assert.match(ownerApi, /activeAccount\.providerReadbackVerified === true/);
  assert.match(ownerApi, /requiredScopes\.every/);
  assert.match(ownerApi, /requiredCapabilities\.every/);
  assert.match(ownerApi, /new Set\(requiredScopes\)\.size === new Set\(scopes\)\.size/);
  assert.match(ownerApi, /new Set\(requiredCapabilities\)\.size === new Set\(capabilities\)\.size/);
  assert.match(ownerApi, /verifiedAtMs <= now \+ 60_000/);
  assert.match(ownerApi, /now - verifiedAtMs <= maxAgeSeconds \* 1000/);
  assert.match(ownerApi, /textValue\(activeAccount\.tenantId\) === organizationId/);
  assert.match(ownerApi, /credentialLive/);
  assert.match(ownerApi, /CONNECTION_TEST_UNSUPPORTED/);

  const legacy = ownerApi.slice(
    ownerApi.indexOf("function legacyConnectionSummary"),
    ownerApi.indexOf("function liveConnectionSummary"),
  );
  assert.match(legacy, /canRead: false/);
  assert.doesNotMatch(legacy, /state\s*=\s*"ready"/);
});

test("broker forwards exact successful readback evidence to health v2", () => {
  assert.match(broker, /identityVerified: true/);
  assert.match(broker, /rpc\("pandora_connection_health_commit_v2"/);
  assert.match(broker, /p_provider_subject: verification\.subject/);
  assert.match(broker, /p_granted_scopes: verification\.scopes/);
  assert.match(broker, /p_granted_capabilities: verification\.capabilities/);
  assert.match(broker, /p_provider_readback: verification\.readback/);
});

test("owner API hosts the server-only self-service provider route", () => {
  assert.match(ownerApi, /route === "\/connections\/providers\/actions"/);
  assert.match(ownerApi, /async function ownerProviderAction/);
  assert.match(ownerApi, /SELF_SERVICE_PROVIDERS = new Set\(\["posthog", "openai", "gemini", "kimi"\]\)/);
  assert.match(ownerApi, /pandora_connection_commit_verified_credential_v1/);
  assert.match(ownerApi, /pandora_connection_runtime_credential_v1/);
  assert.match(ownerApi, /pandora_connection_health_commit_v2/);
  assert.match(ownerApi, /pandora_connection_health_commit_v1/);
  assert.match(ownerApi, /p_healthy: false/);
  assert.match(ownerApi, /textValue\(runtime\.data\?\.organizationId\) !== organizationId/);
  assert.match(ownerApi, /textValue\(runtime\.data\?\.connectionId\) !== connectionId/);
  assert.match(ownerApi, /textValue\(runtime\.data\?\.tenantKey\) !== tenantKey/);
  assert.match(ownerApi, /context\.aal !== "aal2"/);
  assert.match(ownerApi, /CONNECTION_SECRET_INPUT_NOT_ALLOWED/);
  assert.match(ownerApi, /hasOwnProperty\.call\(body, "credential"\)/);
  const providerAction = ownerApi.slice(
    ownerApi.indexOf("async function ownerProviderAction"),
    ownerApi.indexOf("\nasync function connectionAction"),
  );
  const connectGuard = providerAction.slice(
    providerAction.indexOf('if (action === "connect")'),
    providerAction.indexOf("const credential"),
  );
  assert.match(connectGuard, /hasOwnProperty\.call\(body, "secret"\)/);
  assert.match(connectGuard, /hasOwnProperty\.call\(body, "token"\)/);
  assert.match(connectGuard, /CONNECTION_SECRET_INPUT_NOT_ALLOWED/);
  assert.match(ownerApi, /credentialStored: true/);
  assert.match(ownerApi, /credentialReturned: false/);
  assert.match(ownerApi, /CONNECTION_RUNTIME_UNAVAILABLE/);
  assert.match(ownerApi, /identityVerified: true/);
});

test("database projection and monitor fail closed on identity and stale credentials", () => {
  for (const fragment of [
    "pandora_connection_account_identity_mismatch",
    "pandora_connection_required_scopes_missing",
    "pandora_connection_required_capabilities_missing",
    "pandora_connection_safe_probe_not_verified",
    "provider_readback_hash is not null",
    "identityVerified",
    "rotation_due_at",
    "a.rotation_due_at is null",
    "clock_timestamp()+interval '1 minute'",
    "exists(select 1 from vault.secrets",
    "private.pandora_connection_reconcile_health_v1",
    "pandora-connections-health-reconcile-v1",
    "*/5 * * * *",
  ]) {
    assert.ok(migration.includes(fragment), `missing ${fragment}`);
  }
  assert.match(
    migration,
    /revoke all on function public\.pandora_google_workspace_oauth_commit_v1\([\s\S]*?from public,anon,authenticated;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.pandora_google_workspace_oauth_commit_v1\([\s\S]*?to service_role;/,
  );
});

test("every regulated provider is request-activation-only", () => {
  assert.match(
    providerManifests,
    /definition\.requestActivation === true \|\| definition\.riskClass === "regulated"/,
  );
  assert.match(providerManifests, /connectionMode: requestActivation \? "request_activation"/);
  assert.match(providerManifests, /type: requestActivation \? "partner_activation"/);
  assert.match(providerManifests, /primaryAction: requestActivation \? "request_activation"/);
  assert.match(providerManifests, /connectButtonVisible: !requestActivation/);
  assert.match(providerManifests, /publicConnectAllowed: false/);
});
