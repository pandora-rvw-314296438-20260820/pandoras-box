import test from "node:test";
import assert from "node:assert/strict";

import {
  createGovernmentActivationRequest,
  governmentProviderAdapters,
  governmentProviderCatalog,
  governmentProviderManifests,
  runGovernmentSafeReadProbe,
} from "../packages/pandora-ph-government-connections/index.mjs";

const fixedClock = () => new Date("2026-10-01T12:30:00.000Z");
const tenantId = "11111111-1111-4111-8111-111111111111";
const connectionId = "22222222-2222-4222-8222-222222222222";
const tenantKey = "public-data.ph";
const boundRequest = Object.freeze({ organizationId: tenantId, tenantId, connectionId, tenantKey });
const tenantBinding = Object.freeze({ organizationId: tenantId, tenantId, connectionId, tenantKey });
const response = (body, contentType = "application/json") => new Response(body, {
  status: 200,
  headers: { "content-type": contentType },
});

test("public government APIs are SDK manifests with read-only provider-readback evidence", () => {
  assert.deepEqual(Object.keys(governmentProviderManifests).sort(), [
    "ph.namria.geoportal",
    "ph.phivolcs.hazard_gis",
    "ph.psa.openstat",
    "ph.psa.psgc",
  ]);
  for (const manifest of Object.values(governmentProviderManifests)) {
    assert.equal(manifest.capabilities.length, 1);
    assert.equal(manifest.capabilities[0].operationMode, "read");
    assert.equal(manifest.connectionPolicy.connectedAuthority, "fresh_provider_readback");
    assert.equal(manifest.connectionPolicy.falseConnectedForbidden, true);
    assert.equal(manifest.dataHandling.credentialsServerSideOnly, true);
    assert.equal(manifest.dataHandling.rawResponseLogging, false);
    assert.deepEqual(manifest.tenantBinding.requiredRequestFields, ["tenantId", "connectionId", "tenantKey"]);
    assert.equal(manifest.tenantBinding.canonicalTenantColumn, "organization_id");
    assert.equal(manifest.tenantBinding.crossTenantCredentialSharing, false);
    assert.equal(manifest.tenantBinding.credentialsMayReachDevices, false);
  }
});

test("anonymous safe-read probes validate provider-specific response shapes", async () => {
  const fixtures = {
    "ph.psa.openstat": response(JSON.stringify([{ dbid: "DB", text: "DB" }])),
    "ph.phivolcs.hazard_gis": response(JSON.stringify({ id: 0, name: "Ground Shaking (Deterministic)", type: "Feature Layer", capabilities: "Map,Query,Data" }), "text/plain"),
    "ph.namria.geoportal": response("<?xml version=\"1.0\"?><WMT_MS_Capabilities><Service><Title>Geoportal Philippines Web Map Service</Title></Service></WMT_MS_Capabilities>", "application/vnd.ogc.wms_xml"),
  };
  for (const [providerKey, fixture] of Object.entries(fixtures)) {
    const readback = await runGovernmentSafeReadProbe(providerKey, boundRequest, {
      transport: async () => fixture.clone(),
      evidence: { tenantBinding },
      clock: fixedClock,
    });
    assert.equal(readback.verificationState, "provider_readback_verified");
    assert.equal(readback.liveConnectionStatus, "not_connected");
    assert.equal(readback.connectedAuthority, "fresh_provider_readback");
    assert.equal(readback.tenantId, tenantId);
    assert.equal(readback.connectionId, connectionId);
    assert.equal(readback.tenantKey, tenantKey);
    assert.equal(readback.credentialReturned, false);
    assert.equal(readback.httpStatus, 200);
    assert.match(readback.bodySha256, /^[a-f0-9]{64}$/);
    assert.equal(readback.observedAt, "2026-10-01T12:30:00.000Z");
  }
});

test("PSGC token is represented only by an opaque Vault reference and injected by trusted transport", async () => {
  let observedRequest;
  const transport = {
    async request(request) {
      observedRequest = request;
      return response(JSON.stringify({ results: { psgc_data: [{ psgc_code: "0100000000", area_name: "Region I" }] } }));
    },
  };
  const readback = await runGovernmentSafeReadProbe(
    "ph.psa.psgc",
    { ...boundRequest, credentialRef: "vault://connections/psa-psgc" },
    { transport, evidence: { tenantBinding: { ...tenantBinding, vaultCredentialRef: "vault://connections/psa-psgc" } }, clock: fixedClock },
  );
  assert.equal(readback.verificationState, "provider_readback_verified");
  assert.equal(readback.liveConnectionStatus, "not_connected");
  assert.equal(observedRequest.credentialRef, "vault://connections/psa-psgc");
  assert.deepEqual(observedRequest.credentialPlacement, { type: "query", name: "token" });
  assert.doesNotMatch(observedRequest.url, /token=/);
  await assert.rejects(
    runGovernmentSafeReadProbe("ph.psa.psgc", boundRequest, { transport, evidence: { tenantBinding }, clock: fixedClock }),
    /vault_credential_reference_required/,
  );
  await assert.rejects(
    runGovernmentSafeReadProbe(
      "ph.psa.psgc",
      { ...boundRequest, credentialRef: "vault://connections/psa-psgc" },
      { transport, evidence: { tenantBinding: { ...tenantBinding, vaultCredentialRef: "vault://connections/another-account" } }, clock: fixedClock },
    ),
    /CONNECTION_VAULT_TENANT_MISMATCH/,
  );
});

test("every probe fails closed on tenant, connection or tenant-key mismatch", async () => {
  const fixture = response(JSON.stringify([{ dbid: "DB", text: "DB" }]));
  for (const request of [
    { ...boundRequest, tenantId: "33333333-3333-4333-8333-333333333333" },
    { ...boundRequest, connectionId: "33333333-3333-4333-8333-333333333333" },
    { ...boundRequest, tenantKey: "other-tenant.ph" },
  ]) {
    await assert.rejects(
      runGovernmentSafeReadProbe("ph.psa.openstat", request, {
        transport: async () => fixture.clone(),
        evidence: { tenantBinding },
        clock: fixedClock,
      }),
      /CONNECTION_ACCOUNT_TENANT_MISMATCH/,
    );
  }
});

test("adapter receipt cannot claim evidence without a passing provider readback", async () => {
  const adapter = governmentProviderAdapters["ph.phivolcs.hazard_gis"];
  const request = {
    requestId: "gov-probe-1",
    capabilityKey: "hazard.layer.read",
    capabilityVersion: "1.0.0",
    ...boundRequest,
  };
  await assert.rejects(
    adapter.invoke(request, { transport: async () => response(JSON.stringify({ type: "Feature Layer", capabilities: "Map" })), evidence: { tenantBinding }, clock: fixedClock }),
    /provider_probe_shape_invalid/,
  );
  await assert.rejects(
    adapter.invoke(request, { transport: async () => response("<html>not json</html>", "text/html"), evidence: { tenantBinding }, clock: fixedClock }),
    /provider_probe_content_type_invalid/,
  );
  const receipt = await adapter.invoke(request, {
    transport: async () => response(JSON.stringify({ id: 0, name: "Ground Shaking (Deterministic)", type: "Feature Layer", capabilities: "Map,Query,Data" }), "text/plain"),
    evidence: { tenantBinding },
    clock: fixedClock,
  });
  assert.equal(receipt.verificationState, "evidence_available");
  assert.equal(receipt.readback.verificationState, "provider_readback_verified");
  assert.equal(receipt.readback.liveConnectionStatus, "not_connected");
});

test("unverified, credentialed, and regulated agencies expose Request activation only", () => {
  const requestOnly = governmentProviderCatalog.filter((entry) => entry.metadata.connectionMode === "request_activation");
  assert.equal(requestOnly.length, 14);
  for (const entry of requestOnly) {
    assert.equal(entry.metadata.catalogAction, "Request activation");
    assert.equal(entry.metadata.publicConnectAllowed, false);
    assert.equal(entry.metadata.liveConnectionStatus, "not_connected");
    assert.equal(entry.adapterManifest, null);
  }
  for (const key of ["ph.bir", "ph.sec", "ph.lto", "ph.sss", "ph.philhealth", "ph.pagibig", "ph.dfa", "ph.nbi", "ph.pnp"]) {
    assert.ok(requestOnly.some((entry) => entry.providerKey === key), key);
  }
  const pagasa = requestOnly.find((entry) => entry.providerKey === "ph.pagasa");
  assert.equal(pagasa.apiType, "restricted_rest_api");
  assert.match(pagasa.metadata.activationReason, /limited to government agencies/);
});

test("activation workflow rejects credential-shaped fields and never marks Connected", () => {
  const activation = createGovernmentActivationRequest({
    requestId: "activate-egov-1",
    providerKey: "ph.dict.egov",
    organizationId: tenantId,
    tenantId,
    connectionId,
    tenantKey,
    requesterRef: "user-1",
    contactEmail: "athena@example.invalid",
    legalEntityName: "Pandora",
    requestedUseCase: "Read-only government service integration",
    jurisdiction: "PH",
    requestedAt: "2026-10-01T12:30:00.000Z",
  });
  assert.equal(activation.catalogAction, "Request activation");
  assert.equal(activation.liveConnectionStatus, "not_connected");
  assert.equal(activation.tenantId, tenantId);
  assert.equal(activation.connectionId, connectionId);
  assert.equal(activation.tenantKey, tenantKey);
  assert.equal(activation.credentialReturned, false);
  assert.throws(() => createGovernmentActivationRequest({ ...activation, password: "forbidden" }), /forbidden_fields/);
  assert.throws(() => createGovernmentActivationRequest({
    requestId: "activate-egov-cross-tenant",
    providerKey: "ph.dict.egov",
    organizationId: tenantId,
    tenantId: "33333333-3333-4333-8333-333333333333",
    connectionId,
    tenantKey,
    requesterRef: "user-1",
    contactEmail: "athena@example.invalid",
    legalEntityName: "Pandora",
    requestedUseCase: "Read-only government service integration",
    jurisdiction: "PH",
    requestedAt: "2026-10-01T12:30:00.000Z",
  }), /CONNECTION_ACCOUNT_TENANT_MISMATCH/);
});
