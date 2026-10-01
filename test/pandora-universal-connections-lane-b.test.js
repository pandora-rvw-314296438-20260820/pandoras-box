"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const modules = Promise.all([
  import("../packages/pandora-universal-connections/index.mjs"),
  import("../packages/pandora-provider-sdk/index.mjs"),
]);

const requestActivationKeys = [
  "pldt-enterprise", "smart", "globe", "dito", "ubivelox-philippines", "government-regulated",
];

test("Lane B registers every requested P1/P2 provider through Provider SDK manifests", async () => {
  const [{ providerEntries }, { validateProviderManifest }] = await modules;
  assert.equal(providerEntries.length, 28);
  for (const entry of providerEntries) {
    assert.doesNotThrow(() => validateProviderManifest(entry.adapterManifest));
    assert.equal(entry.metadata.ui.surface, "generic_connections_center");
    assert.equal(entry.metadata.ui.customProviderUi, false);
    assert.equal(entry.adapterManifest.dataHandling.credentialStorage, "server_side_vault_reference_only");
    assert.equal(entry.metadata.credential.clientExposure, "forbidden");
    assert.equal(entry.metadata.health.identityReadback, true);
    assert.equal(entry.metadata.health.scopesReadback, true);
    assert.equal(entry.metadata.health.noCredentialOnlyConnectedState, true);
    assert.equal(Object.isFrozen(entry.metadata), true);
  }
  const keys = new Set(providerEntries.map((item) => item.providerKey));
  for (const key of [
    "twilio", "vonage", "maya", "shopify", "woocommerce", "xero", "quickbooks", "google-ads",
    "voluum", "grab", "lalamove", "docusign", "google-maps", "aws", "google-cloud", "azure",
    "enterprise-idp", "device-pairing", "local-ai", "custom-openapi", "mcp", "file-sftp-email",
    ...requestActivationKeys,
  ]) assert.equal(keys.has(key), true, `missing ${key}`);
});

test("OAuth and OIDC metadata requires PKCE S256, state, nonce and mobile secure return", async () => {
  const [{ providerEntries }] = await modules;
  for (const entry of providerEntries) {
    if (!["oauth2", "oidc"].includes(entry.metadata.auth.type)) continue;
    assert.deepEqual(entry.metadata.auth.pkce, { required: true, method: "S256" });
    assert.equal(entry.metadata.auth.state.required, true);
    assert.equal(entry.metadata.auth.nonce.required, true);
    assert.equal(entry.metadata.callback.mobile.secureBrowser, "custom_tab");
    assert.ok(entry.metadata.callback.mobile.returnModes.includes("universal_link"));
  }
});

test("writes require separate scope, step-up approval, exact target preview, idempotency and readback", async () => {
  const [{ providerEntries }] = await modules;
  for (const entry of providerEntries) {
    const writes = entry.adapterManifest.capabilities.filter((item) => item.operationMode === "write");
    if (!writes.length) continue;
    assert.ok(entry.metadata.scopes.write.length > 0, entry.providerKey);
    assert.equal(entry.metadata.writePolicy.stepUpApprovalRequired, true, entry.providerKey);
    assert.equal(entry.metadata.writePolicy.exactTargetPreviewRequired, true, entry.providerKey);
    assert.equal(entry.metadata.writePolicy.providerReadbackRequired, true, entry.providerKey);
    for (const write of writes) {
      assert.equal(write.idempotencyStrategy, "pandora_request_id_plus_exact_target");
      assert.ok(write.evidenceModes.length > 0);
    }
  }
});

test("event providers require signatures, timestamp windows, replay defense and idempotency", async () => {
  const [{ getProviderEntry }] = await modules;
  for (const key of ["twilio", "vonage", "maya", "shopify", "woocommerce"]) {
    assert.deepEqual(getProviderEntry(key).metadata.webhookPolicy, {
      enabled: true,
      signatureRequired: true,
      timestampWindowRequired: true,
      replayDefenseRequired: true,
      idempotencyKeyRequired: true,
    });
  }
});

test("cloud adapters prefer workload identity and forbid long-lived keys by default", async () => {
  const [{ getProviderEntry }] = await modules;
  for (const key of ["aws", "google-cloud", "azure"]) {
    const entry = getProviderEntry(key);
    assert.equal(entry.metadata.auth.type, "workload_identity");
    assert.equal(entry.metadata.workloadIdentity.preferred, true);
    assert.equal(entry.metadata.workloadIdentity.longLivedKeysAllowedByDefault, false);
  }
});

test("closed and regulated providers expose Request activation and never a fake Connect action", async () => {
  const [{ buildPartnerActivationView, getProviderEntry }] = await modules;
  for (const key of requestActivationKeys) {
    const entry = getProviderEntry(key);
    assert.equal(entry.metadata.auth.type, "partner_activation");
    assert.equal(entry.metadata.connectionMode, "request_activation");
    assert.equal(entry.metadata.activation.publicConnectAllowed, false);
    const view = buildPartnerActivationView(key);
    assert.equal(view.primaryLabel, "Request activation");
    assert.equal(view.connectButtonVisible, false);
    assert.equal(view.connectionStatus, "not_connected");
  }
});

test("partner activation rejects credential material and needs authority plus provider evidence", async () => {
  const [{ PARTNER_ACTIVATION_STATES, createPartnerActivationRequest, transitionPartnerActivation }] = await modules;
  const input = {
    requestId: "activation-1",
    providerKey: "pldt-enterprise",
    pandoraOrganizationId: "org-1",
    requesterRef: "owner-1",
    contactEmail: "owner@example.com",
    legalEntityName: "Example Corp",
    requestedCapabilities: ["telecom.account.read"],
    jurisdiction: "PH",
    requestedAt: "2026-10-01T12:00:00.000Z",
  };
  assert.throws(() => createPartnerActivationRequest({ ...input, apiKey: "forbidden" }), /forbidden_fields:apiKey/);
  assert.throws(() => createPartnerActivationRequest({
    ...input, accountReference: "gh" + "p_" + "a".repeat(30),
  }), /credential_material/);
  let request = createPartnerActivationRequest(input);
  assert.equal(request.liveConnectionStatus, "not_connected");
  request = transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.AUTHORITY_REVIEW, at: "2026-10-01T12:01:00.000Z", actorRef: "reviewer-1",
  });
  assert.throws(() => transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.PARTNER_ONBOARDING, at: "2026-10-01T12:02:00.000Z", actorRef: "reviewer-1",
  }), /authorityEvidenceRef required/);
  request = transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.PARTNER_ONBOARDING, at: "2026-10-01T12:02:00.000Z", actorRef: "reviewer-1",
    authorityEvidenceRef: "evidence://authority/1", providerContractRef: "evidence://contract/1",
  });
  request = transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.PROVIDER_VERIFICATION, at: "2026-10-01T12:03:00.000Z", actorRef: "operator-1",
    vaultCredentialRef: "vault-ref://opaque/1",
  });
  assert.throws(() => transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.VERIFIED_FOR_RUNTIME_HANDOFF, at: "2026-10-01T12:04:00.000Z", actorRef: "verifier-1",
    providerReadbackRef: "evidence://provider/1",
  }), /accountIdentityRef required/);
  request = transitionPartnerActivation(request, {
    to: PARTNER_ACTIVATION_STATES.VERIFIED_FOR_RUNTIME_HANDOFF, at: "2026-10-01T12:04:00.000Z", actorRef: "verifier-1",
    providerReadbackRef: "evidence://provider/1", accountIdentityRef: "evidence://identity/1",
    scopesEvidenceRef: "evidence://scopes/1", safeProbeEvidenceRef: "evidence://probe/1",
  });
  assert.equal(request.state, "verified_for_runtime_handoff");
  assert.equal(request.liveConnectionStatus, "not_connected");
});

test("custom connectors are sandboxed and read-only first", async () => {
  const [{ getProviderEntry }] = await modules;
  for (const key of ["custom-openapi", "mcp", "file-sftp-email"]) {
    const policy = getProviderEntry(key).metadata.sandboxPolicy;
    assert.equal(policy.required, true);
    assert.equal(policy.readOnlyFirst, true);
    assert.equal(policy.operationClassificationRequired, true);
  }
});
