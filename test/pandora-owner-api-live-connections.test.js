import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

const root = join(import.meta.dirname, "..");
const ownerApi = readFileSync(
  join(root, "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);
const providerVerification = readFileSync(
  join(
    root,
    "supabase/functions/_shared/pandora-connections-provider-verification.ts",
  ),
  "utf8",
);

test("owner API treats tenant-bound Live Connections as authority", () => {
  const start = ownerApi.indexOf("async function liveConnections(");
  const end = ownerApi.indexOf("\nfunction base64UrlBytes", start);
  const source = ownerApi.slice(start, end);
  assert.match(source, /rpc\("pandora_live_connections_v1"/);
  assert.match(source, /p_organization_id: context[.]organizationId/);
  assert.match(
    source,
    /payload[.]organizationId\) !== context[.]organizationId/,
  );
  assert.match(
    source,
    /payload[.]authority\) !== "live_connections_not_catalog"/,
  );
  assert.match(
    source,
    /const authoritative = await liveConnections\(context\)/,
  );
  assert.match(source, /authoritativeProviders[.]has/);
  assert.match(source, /from\("connector_installations"\)/);
  assert.match(source, /[.]eq\("organization_id", context[.]organizationId\)/);
});

test("provider actions fail closed on secret input or an account and tenant mismatch", () => {
  const start = ownerApi.indexOf(
    "async function liveProviderConnectionAction(",
  );
  const end = ownerApi.indexOf("\nasync function connectionAction(", start);
  const source = ownerApi.slice(start, end);
  assert.match(source, /hasOwnProperty[.]call\(body, "credential"\)/);
  assert.match(source, /CONNECTION_SECRET_INPUT_NOT_ALLOWED/);
  assert.match(source, /tenantId !== context[.]organizationId/);
  assert.match(source, /connectionId !== `provider:\$\{provider\}`/);
  assert.match(source, /textValue\(advanced[.]connectionId\) !== connectionId/);
  assert.match(source, /textValue\(advanced[.]tenantId\) !== tenantId/);
  assert.match(source, /textValue\(advanced[.]tenantKey\) !== tenantKey/);
  assert.match(source, /pandora_connection_runtime_credential_v1/);
  assert.match(
    source,
    /textValue\(runtimeData[.]connectionId\) !== connectionId/,
  );
  assert.match(source, /textValue\(runtimeData[.]tenantKey\) !== tenantKey/);
});

test("provider health and inference return only safe readback", () => {
  const start = ownerApi.indexOf(
    "async function liveProviderConnectionAction(",
  );
  const end = ownerApi.indexOf("\nasync function connectionAction(", start);
  const source = ownerApi.slice(start, end);
  assert.match(source, /verifyPandoraConnectionProvider/);
  assert.match(source, /pandora_connection_health_commit_v1/);
  assert.match(source, /p_healthy: true/);
  assert.match(source, /p_healthy: false/);
  assert.match(source, /credentialReturned: false/);
  assert.match(ownerApi, /provider-actions/);
});

test("provider connect requires step-up and commits only verified credentials", () => {
  const start = ownerApi.indexOf(
    "async function liveProviderConnectionAction(",
  );
  const end = ownerApi.indexOf("\nasync function connectionAction(", start);
  const source = ownerApi.slice(start, end);
  assert.match(source, /requestedAction === "connect"/);
  assert.match(source, /context[.]aal !== "aal2"/);
  assert.match(source, /body[.]runTestInference !== true/);
  assert.match(source, /pandora_connection_commit_verified_credential_v1/);
  assert.match(source, /p_actor_user_id: context[.]userId/);
  assert.match(source, /credentialStored: true/);
  assert.match(source, /credentialReturned: false/);
});

test("shared provider verification uses bounded allowlisted readbacks", () => {
  assert.match(providerVerification, /https:\/\/us[.]posthog[.]com/);
  assert.match(providerVerification, /https:\/\/eu[.]posthog[.]com/);
  assert.match(providerVerification, /tenantKey !== host/);
  assert.match(
    providerVerification,
    /https:\/\/api[.]openai[.]com\/v1\/models/,
  );
  assert.match(
    providerVerification,
    /https:\/\/api[.]openai[.]com\/v1\/responses/,
  );
  assert.match(
    providerVerification,
    /generativelanguage[.]googleapis[.]com\/v1beta\/models/,
  );
  assert.match(
    providerVerification,
    /https:\/\/api[.]moonshot[.]ai\/v1\/models/,
  );
  assert.match(providerVerification, /AbortSignal[.]timeout\(15_000\)/);
  assert.match(providerVerification, /redirect: "error"/);
  assert.match(providerVerification, /MODEL_NOT_AVAILABLE/);
  assert.match(providerVerification, /TEST_INFERENCE_FAILED/);
});
