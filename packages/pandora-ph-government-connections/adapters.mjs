import { createHash } from "node:crypto";
import { buildProviderReceipt, defineProviderAdapter } from "../pandora-provider-sdk/index.mjs";
import { governmentProviderManifests } from "./provider-manifests.mjs";

const MAX_BODY_BYTES = 8 * 1024 * 1024;

function header(response, name) {
  if (response?.headers?.get) return response.headers.get(name);
  const entries = response?.headers || {};
  return entries[name] ?? entries[name.toLowerCase()] ?? null;
}

async function readBody(response) {
  const announced = Number(header(response, "content-length"));
  if (Number.isFinite(announced) && announced > MAX_BODY_BYTES) throw new Error("provider_probe_response_too_large");
  let body;
  if (typeof response.arrayBuffer === "function") body = Buffer.from(await response.arrayBuffer());
  else if (response.body instanceof Uint8Array || Buffer.isBuffer(response.body)) body = Buffer.from(response.body);
  else if (typeof response.body === "string") body = Buffer.from(response.body, "utf8");
  else throw new Error("provider_probe_body_unavailable");
  if (body.length > MAX_BODY_BYTES) throw new Error("provider_probe_response_too_large");
  return body;
}

function assertVaultReference(value) {
  if (typeof value !== "string" || !/^vault:\/\/[a-zA-Z0-9/_-]+$/.test(value)) throw new Error("vault_credential_reference_required");
}

async function dispatch(manifest, request, runtime) {
  const credentialMode = manifest.safeReadProbe.credentialMode;
  const transport = runtime.transport;
  const input = Object.freeze({
    method: "GET",
    url: manifest.safeReadProbe.url,
    headers: Object.freeze({
      accept: manifest.providerKey === "ph.namria.geoportal" ? "application/vnd.ogc.wms_xml, text/xml" : "application/json",
      "user-agent": "PandoraSafeReadProbe/1.0",
    }),
    redirect: "error",
    signal: runtime.signal,
    credentialRef: credentialMode === "vault_query_token" ? request.credentialRef : undefined,
    credentialPlacement: credentialMode === "vault_query_token" ? Object.freeze({ type: "query", name: "token" }) : undefined,
  });
  if (credentialMode === "vault_query_token") {
    assertVaultReference(request.credentialRef);
    if (!transport || typeof transport.request !== "function") throw new Error("trusted_credential_transport_required");
    return transport.request(input);
  }
  if (typeof transport === "function") return transport(input.url, input);
  if (transport && typeof transport.fetch === "function") return transport.fetch(input.url, input);
  if (transport && typeof transport.request === "function") return transport.request(input);
  return fetch(input.url, input);
}

function validateReadback(providerKey, body) {
  if (providerKey === "ph.namria.geoportal") {
    const text = body.toString("utf8");
    if (!/(?:WMT_MS_Capabilities|WMS_Capabilities)/.test(text) || !/<Service>/.test(text)) throw new Error("provider_probe_shape_invalid");
    const title = text.match(/<Title>([^<]*(?:Geoportal|GeoServer|Web Map)[^<]*)<\/Title>/i)?.[1] || "Philippine Geoportal WMS";
    return { providerIdentity: title.trim(), resourceCount: null, safeReadCapability: "WMS GetCapabilities" };
  }
  let json;
  try { json = JSON.parse(body.toString("utf8")); } catch { throw new Error("provider_probe_json_invalid"); }
  if (providerKey === "ph.psa.openstat") {
    if (!Array.isArray(json) || json.length === 0 || !json.every((item) => item && typeof item.dbid === "string" && typeof item.text === "string")) throw new Error("provider_probe_shape_invalid");
    return { providerIdentity: "PSA OpenSTAT PXWeb", resourceCount: json.length, safeReadCapability: "PXWeb catalog listing" };
  }
  if (providerKey === "ph.psa.psgc") {
    const rows = json?.results?.psgc_data;
    if (!Array.isArray(rows) || rows.length === 0 || !rows.every((item) => typeof item.psgc_code === "string")) throw new Error("provider_probe_shape_invalid");
    return { providerIdentity: "PSA Philippine Standard Geographic Code", resourceCount: rows.length, safeReadCapability: "PSGC regions read" };
  }
  if (providerKey === "ph.phivolcs.hazard_gis") {
    if (json?.type !== "Feature Layer" || !String(json.capabilities || "").split(",").includes("Query") || typeof json.name !== "string") throw new Error("provider_probe_shape_invalid");
    return { providerIdentity: `PHIVOLCS ${json.name}`, resourceCount: 1, safeReadCapability: "ArcGIS layer metadata" };
  }
  throw new Error("provider_probe_not_allowlisted");
}

export async function runGovernmentSafeReadProbe(providerKey, request = {}, runtime = {}) {
  const manifest = governmentProviderManifests[providerKey];
  if (!manifest) throw new Error("provider_probe_not_allowlisted");
  const response = await dispatch(manifest, request, runtime);
  if (!Number.isInteger(response?.status) || response.status !== 200) throw new Error(`provider_probe_http_${response?.status ?? "unknown"}`);
  const body = await readBody(response);
  const validated = validateReadback(providerKey, body);
  const observedAt = (runtime.clock ? runtime.clock() : new Date()).toISOString();
  return Object.freeze({
    connectionStatus: "connected_verified",
    connectedAuthority: "fresh_provider_readback",
    providerKey,
    providerIdentity: validated.providerIdentity,
    safeReadCapability: validated.safeReadCapability,
    resourceCount: validated.resourceCount,
    probeUrl: manifest.safeReadProbe.url,
    documentationUrl: manifest.safeReadProbe.documentationUrl,
    httpStatus: response.status,
    contentType: header(response, "content-type"),
    observedAt,
    responseBytes: body.length,
    bodySha256: createHash("sha256").update(body).digest("hex"),
  });
}

function makeAdapter(manifest) {
  const capability = manifest.capabilities[0];
  const id = `${capability.capabilityKey}@${capability.capabilityVersion}`;
  return defineProviderAdapter({
    manifest,
    handlers: {
      [id]: async (request, runtime) => {
        const readback = await runGovernmentSafeReadProbe(manifest.providerKey, request, runtime);
        return buildProviderReceipt({
          requestId: request.requestId,
          providerKey: manifest.providerKey,
          capabilityKey: capability.capabilityKey,
          capabilityVersion: capability.capabilityVersion,
          adapterVersion: capability.adapterVersion,
          providerOperationId: `${manifest.providerKey}:${readback.bodySha256.slice(0, 16)}`,
          accepted: true,
          evidenceRefs: [`sha256:${readback.bodySha256}`],
          readback,
        });
      },
    },
  });
}

export const governmentProviderAdapters = Object.freeze(Object.fromEntries(
  Object.entries(governmentProviderManifests).map(([providerKey, manifest]) => [providerKey, makeAdapter(manifest)]),
));
