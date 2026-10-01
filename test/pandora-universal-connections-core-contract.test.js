"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const modules = Promise.all([
  import("../packages/pandora-universal-connections/index.mjs"),
  import("../packages/pandora-connections-core/index.mjs"),
]);

function identityFor(manifest) {
  return Object.fromEntries(
    manifest.accountIdentity.stableSubjectFields.map((field) => [field, `verified-${field}`]),
  );
}

function runtimeFor(manifest, overrides = {}) {
  return {
    credentialReference: "vault://opaque/reference",
    providerReadback: {
      verified: true,
      verifiedAt: "2026-10-01T13:59:30.000Z",
      health: { state: "healthy" },
      grantedScopes: [...manifest.scopes.read],
      accountIdentity: identityFor(manifest),
      probe: { capabilityKey: manifest.health.safeReadCapability, ok: true },
    },
    accountBinding: {
      active: true,
      organizationId: "organization-1",
      connectionId: "connection-1",
    },
    ...overrides,
  };
}

test("every Lane B provider publishes a valid Connection Manifest v1 contract", async () => {
  const [{ providerEntries, providerConnectionManifests }, { validateConnectionManifest }] = await modules;
  assert.equal(providerEntries.length, 28);
  assert.equal(Object.keys(providerConnectionManifests).length, 28);
  for (const entry of providerEntries) {
    const manifest = providerConnectionManifests[entry.providerKey];
    assert.equal(entry.connectionManifest, manifest);
    assert.doesNotThrow(() => validateConnectionManifest(manifest));
    assert.equal(manifest.providerKey, entry.providerKey);
    assert.equal(manifest.auth.type, entry.metadata.auth.type);
    assert.equal(manifest.health.safeReadCapability, entry.metadata.health.safeReadCapability);
    assert.equal(manifest.credential.clientExposure, "forbidden");
    assert.equal(manifest.dataResidency.enforcement, "tenant_policy");
    for (const capability of manifest.capabilities.filter((item) => item.operationMode === "write")) {
      assert.equal(capability.requiresStepUp, true);
      assert.ok(capability.requiredScopes.some((scope) => manifest.scopes.write.includes(scope)));
    }
  }
});

test("self-service providers require fresh provider readback before Connected", async () => {
  const [{ providerEntries }, { deriveConnectionStatus }] = await modules;
  const now = new Date("2026-10-01T14:00:00.000Z");
  for (const entry of providerEntries.filter((item) => item.metadata.connectionMode === "self_service")) {
    const manifest = entry.connectionManifest;
    assert.equal(
      deriveConnectionStatus(manifest, { credentialReference: "vault://opaque/reference" }, now).state,
      "connecting",
      entry.providerKey,
    );
    const projection = deriveConnectionStatus(manifest, runtimeFor(manifest), now);
    assert.equal(projection.state, "connected", entry.providerKey);
    assert.equal(projection.providerKey, entry.providerKey);
  }
});

test("catalog readiness never claims Connected and rejects client-supplied credential material", async () => {
  const [{ buildProviderCatalogView }] = await modules;
  const blocked = buildProviderCatalogView("twilio");
  assert.equal(blocked.catalogState, "implemented_awaiting_credential");
  assert.equal(blocked.connectButtonVisible, false);
  assert.equal(blocked.connectionStatus, "not_connected");
  const configured = buildProviderCatalogView("twilio", {
    serverConfigurationPresent: true,
    source: "server_runtime_config_registry",
  });
  assert.equal(configured.catalogState, "available_to_connect");
  assert.equal(configured.connectionStatus, "not_connected");
  assert.throws(
    () => buildProviderCatalogView("twilio", { serverConfigurationPresent: true, token: "no" }),
    /unexpected_readiness_evidence:token/,
  );
});

test("revoked and stale evidence fail closed", async () => {
  const [{ getProviderEntry }, { deriveConnectionStatus }] = await modules;
  const manifest = getProviderEntry("twilio").connectionManifest;
  const now = new Date("2026-10-01T14:20:00.000Z");
  assert.equal(
    deriveConnectionStatus(manifest, runtimeFor(manifest, {
      revokedAt: "2026-10-01T14:00:00.000Z",
    }), now).state,
    "revoked",
  );
  assert.deepEqual(
    deriveConnectionStatus(manifest, runtimeFor(manifest), now),
    { state: "needs_attention", reason: "provider_readback_stale" },
  );
});

test("partner-only providers remain Request activation entries without Connect", async () => {
  const [{ buildPartnerActivationView, providerEntries }] = await modules;
  for (const entry of providerEntries.filter((item) => item.metadata.connectionMode === "request_activation")) {
    assert.equal(entry.connectionManifest.auth.type, "partner_activation");
    assert.deepEqual(buildPartnerActivationView(entry.providerKey), {
      providerKey: entry.providerKey,
      primaryAction: "request_activation",
      primaryLabel: "Request activation",
      connectButtonVisible: false,
      customProviderUi: false,
      connectionStatus: "not_connected",
    });
  }
});
