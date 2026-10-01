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
  }
});

test("anonymous safe-read probes validate provider-specific response shapes", async () => {
  const fixtures = {
    "ph.psa.openstat": response(JSON.stringify([{ dbid: "DB", text: "DB" }])),
    "ph.phivolcs.hazard_gis": response(JSON.stringify({ id: 0, name: "Ground Shaking (Deterministic)", type: "Feature Layer", capabilities: "Map,Query,Data" }), "text/plain"),
    "ph.namria.geoportal": response("<?xml version=\"1.0\"?><WMT_MS_Capabilities><Service><Title>Geoportal Philippines Web Map Service</Title></Service></WMT_MS_Capabilities>", "application/vnd.ogc.wms_xml"),
  };
  for (const [providerKey, fixture] of Object.entries(fixtures)) {
    const readback = await runGovernmentSafeReadProbe(providerKey, {}, { transport: async () => fixture.clone(), clock: fixedClock });
    assert.equal(readback.connectionStatus, "connected_verified");
    assert.equal(readback.connectedAuthority, "fresh_provider_readback");
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
    { credentialRef: "vault://connections/psa-psgc" },
    { transport, clock: fixedClock },
  );
  assert.equal(readback.connectionStatus, "connected_verified");
  assert.equal(observedRequest.credentialRef, "vault://connections/psa-psgc");
  assert.deepEqual(observedRequest.credentialPlacement, { type: "query", name: "token" });
  assert.doesNotMatch(observedRequest.url, /token=/);
  await assert.rejects(
    runGovernmentSafeReadProbe("ph.psa.psgc", {}, { transport, clock: fixedClock }),
    /vault_credential_reference_required/,
  );
});

test("adapter receipt cannot claim evidence without a passing provider readback", async () => {
  const adapter = governmentProviderAdapters["ph.phivolcs.hazard_gis"];
  const request = {
    requestId: "gov-probe-1",
    capabilityKey: "hazard.layer.read",
    capabilityVersion: "1.0.0",
  };
  await assert.rejects(
    adapter.invoke(request, { transport: async () => response(JSON.stringify({ type: "Feature Layer", capabilities: "Map" })), clock: fixedClock }),
    /provider_probe_shape_invalid/,
  );
  const receipt = await adapter.invoke(request, {
    transport: async () => response(JSON.stringify({ id: 0, name: "Ground Shaking (Deterministic)", type: "Feature Layer", capabilities: "Map,Query,Data" }), "text/plain"),
    clock: fixedClock,
  });
  assert.equal(receipt.verificationState, "evidence_available");
  assert.equal(receipt.readback.connectionStatus, "connected_verified");
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
});

test("activation workflow rejects credential-shaped fields and never marks Connected", () => {
  const activation = createGovernmentActivationRequest({
    requestId: "activate-egov-1",
    providerKey: "ph.dict.egov",
    organizationId: "org-1",
    requesterRef: "user-1",
    contactEmail: "athena@example.invalid",
    legalEntityName: "Pandora",
    requestedUseCase: "Read-only government service integration",
    jurisdiction: "PH",
    requestedAt: "2026-10-01T12:30:00.000Z",
  });
  assert.equal(activation.catalogAction, "Request activation");
  assert.equal(activation.liveConnectionStatus, "not_connected");
  assert.throws(() => createGovernmentActivationRequest({ ...activation, password: "forbidden" }), /forbidden_fields/);
});
