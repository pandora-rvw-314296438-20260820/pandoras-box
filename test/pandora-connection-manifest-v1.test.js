import assert from "node:assert/strict";
import test from "node:test";
import {
  BROKER_CONTRACTS,
  deriveConnectionStatus,
  validateBrokerImplementation,
  validateConnectionManifest,
} from "../packages/pandora-connections-core/index.mjs";

const manifest = {
  schemaVersion: "1.0.0",
  providerKey: "google_workspace",
  manifestVersion: "1.0.0",
  displayName: "Google Workspace",
  riskClass: "medium",
  auth: {
    type: "oauth2",
    pkce: { required: true, method: "S256" },
    state: { required: true, ttlSeconds: 300 },
    nonce: { required: true },
  },
  scopes: {
    strategy: "read_first",
    read: ["drive.metadata.readonly", "spreadsheets.readonly", "openid"],
    write: ["drive.file"],
  },
  callback: {
    webPath: "/connections/callback/google_workspace",
    mobile: { secureBrowser: "custom_tab", returnModes: ["app_link", "universal_link"] },
  },
  accountIdentity: {
    stableSubjectFields: ["subject", "tenantId"],
    displayFields: ["email", "displayName"],
    tenantSelector: true,
  },
  health: {
    safeReadCapability: "drive.read",
    maxAgeSeconds: 900,
    identityReadback: true,
    scopesReadback: true,
  },
  credential: {
    storage: "server_vault_reference",
    clientExposure: "forbidden",
    rotateSupported: true,
    revokeSupported: true,
  },
  dataResidency: {
    enforcement: "tenant_policy",
    allowedPolicies: ["provider_managed", "ap_southeast"],
  },
  capabilities: [
    {
      capabilityKey: "drive.read",
      operationMode: "read",
      requiredScopes: ["drive.metadata.readonly"],
      evidenceModes: ["provider_readback"],
    },
    {
      capabilityKey: "sheets.read",
      operationMode: "read",
      requiredScopes: ["spreadsheets.readonly"],
      evidenceModes: ["provider_readback"],
    },
    {
      capabilityKey: "drive.write",
      operationMode: "write",
      requiredScopes: ["drive.file"],
      evidenceModes: ["provider_receipt", "read_after_write"],
      requiresStepUp: true,
    },
  ],
};

const verifiedEvidence = {
  credentialReference: "vault-ref-opaque",
  accountBinding: {
    active: true,
    organizationId: "org-1",
    connectionId: "connection-1",
  },
  providerReadback: {
    verified: true,
    verifiedAt: "2026-10-01T11:30:00.000Z",
    health: { state: "healthy" },
    grantedScopes: ["drive.metadata.readonly", "spreadsheets.readonly", "openid"],
    accountIdentity: {
      subject: "provider-subject",
      tenantId: "workspace-tenant",
      email: "owner@example.invalid",
      displayName: "Owner",
    },
    probe: { capabilityKey: "drive.read", ok: true },
  },
};

test("connection manifest requires the full Phase 0 contract", () => {
  const validated = validateConnectionManifest(manifest);
  assert.equal(validated.providerKey, "google_workspace");
  assert.equal(validated.auth.pkce.method, "S256");
  assert.equal(validated.scopes.strategy, "read_first");
  assert.equal(validated.credential.clientExposure, "forbidden");
});

test("OAuth/OIDC cannot weaken PKCE, state or nonce", () => {
  assert.throws(
    () => validateConnectionManifest({ ...manifest, auth: { ...manifest.auth, pkce: { required: false, method: "plain" } } }),
    /PKCE S256/,
  );
  assert.throws(
    () => validateConnectionManifest({ ...manifest, auth: { ...manifest.auth, nonce: { required: false } } }),
    /requires nonce/,
  );
});

test("write capabilities require explicit scope and step-up approval", () => {
  const weakened = structuredClone(manifest);
  weakened.capabilities[2].requiresStepUp = false;
  assert.throws(() => validateConnectionManifest(weakened), /step-up approval/);
});

test("credential presence alone never produces Connected", () => {
  const status = deriveConnectionStatus(manifest, { credentialReference: "vault-ref-opaque" });
  assert.deepEqual(status, { state: "connecting", reason: "provider_readback_missing" });
});

test("stale or unhealthy provider evidence becomes Needs attention", () => {
  const stale = structuredClone(verifiedEvidence);
  stale.providerReadback.verifiedAt = "2026-10-01T10:00:00.000Z";
  assert.equal(
    deriveConnectionStatus(manifest, stale, new Date("2026-10-01T11:31:00.000Z")).state,
    "needs_attention",
  );
  const unhealthy = structuredClone(verifiedEvidence);
  unhealthy.providerReadback.health.state = "degraded";
  assert.equal(
    deriveConnectionStatus(manifest, unhealthy, new Date("2026-10-01T11:31:00.000Z")).reason,
    "provider_health_not_healthy",
  );
});

test("Connected requires fresh identity, scopes, binding and safe readback", () => {
  const status = deriveConnectionStatus(
    manifest,
    verifiedEvidence,
    new Date("2026-10-01T11:31:00.000Z"),
  );
  assert.equal(status.state, "connected");
  assert.equal(status.reason, "fresh_provider_readback");
});

test("broker implementations must expose every shared method", () => {
  const oauth = Object.fromEntries(BROKER_CONTRACTS.oauth.map((method) => [method, async () => ({})]));
  assert.equal(validateBrokerImplementation("oauth", oauth).kind, "oauth");
  assert.throws(
    () => validateBrokerImplementation("credential", { store() {} }),
    /leaseForServerProbe/,
  );
});
