import { validateProviderManifest } from "../pandora-provider-sdk/index.mjs";

const RUNBOOK = "docs/connections/PHILIPPINE_GOVERNMENT_CONNECTIONS.md";

const publicDefinitions = [
  {
    providerKey: "ph.psa.openstat",
    displayName: "PSA OpenSTAT",
    agency: "Philippine Statistics Authority",
    authScheme: "public",
    capabilityKey: "statistics.catalog.read",
    apiType: "PXWeb REST API",
    documentationUrl: "https://openstat.psa.gov.ph/API-Documentation",
    probeUrl: "https://openstat.psa.gov.ph/PXWeb/api/v1/en",
    providerIdentity: "PSA OpenSTAT PXWeb",
    credentialMode: "none",
  },
  {
    providerKey: "ph.psa.psgc",
    displayName: "PSA PSGC",
    agency: "Philippine Statistics Authority",
    authScheme: "api_token",
    capabilityKey: "geography.psgc.read",
    apiType: "PSGC REST API",
    documentationUrl: "https://psa.gov.ph/classifications-api/psgc",
    probeUrl: "https://classification.psa.gov.ph/psgc/Q2_2024/regions",
    providerIdentity: "PSA Philippine Standard Geographic Code",
    credentialMode: "vault_query_token",
  },
  {
    providerKey: "ph.phivolcs.hazard_gis",
    displayName: "PHIVOLCS Hazard GIS",
    agency: "DOST-PHIVOLCS",
    authScheme: "public",
    capabilityKey: "hazard.layer.read",
    apiType: "ArcGIS REST",
    documentationUrl: "https://gisweb.phivolcs.dost.gov.ph/arcgis/rest/services/PHIVOLCS/GroundShaking/MapServer/0",
    probeUrl: "https://gisweb.phivolcs.dost.gov.ph/arcgis/rest/services/PHIVOLCS/GroundShaking/MapServer/0?f=pjson",
    providerIdentity: "PHIVOLCS Ground Shaking (Deterministic)",
    credentialMode: "none",
  },
  {
    providerKey: "ph.namria.geoportal",
    displayName: "NAMRIA Geoportal Philippines",
    agency: "National Mapping and Resource Information Authority",
    authScheme: "public",
    capabilityKey: "geospatial.catalog.read",
    apiType: "OGC WMS",
    documentationUrl: "https://www.geoportal.gov.ph/gpresources/HowtoConsumePhilippineGeoportalLayersinQGIS.pdf",
    probeUrl: "https://geoserver.geoportal.gov.ph/geoserver/ows?service=wms&version=1.1.1&request=GetCapabilities",
    providerIdentity: "Philippine Geoportal WMS",
    credentialMode: "none",
  },
];

function buildManifest(definition) {
  return validateProviderManifest({
    providerKey: definition.providerKey,
    manifestVersion: "1.0.0",
    displayName: definition.displayName,
    authScheme: definition.authScheme,
    regions: ["PH"],
    dataResidency: ["provider-managed:PH", "pandora-evidence:policy-controlled"],
    dataHandling: {
      classification: "public_government_data",
      readOnly: true,
      credentialsServerSideOnly: true,
      rawResponseLogging: false,
      bodyDigestOnly: true,
    },
    deprecationPolicy: {
      strategy: "monitor_official_documentation_and_fail_closed",
      compatibilityWindowDays: 0,
    },
    runbookRef: RUNBOOK,
    escalationRef: "government-provider-request-activation",
    capabilities: [{
      capabilityKey: definition.capabilityKey,
      capabilityVersion: "1.0.0",
      operationMode: "read",
      adapterVersion: "1.0.0",
      evidenceModes: ["provider_readback", "http_status", "sha256_digest"],
    }],
    connectionPolicy: {
      catalogAction: "Connect",
      connectedAuthority: "fresh_provider_readback",
      falseConnectedForbidden: true,
      credentialMode: definition.credentialMode,
      leastPrivilege: "read_only",
    },
    safeReadProbe: {
      method: "GET",
      url: definition.probeUrl,
      documentationUrl: definition.documentationUrl,
      providerIdentity: definition.providerIdentity,
      credentialMode: definition.credentialMode,
    },
  });
}

export const governmentProviderManifests = Object.freeze(Object.fromEntries(
  publicDefinitions.map((definition) => [definition.providerKey, buildManifest(definition)]),
));

const requestActivationDefinitions = [
  ["ph.data_gov", "Open Data Philippines", "Department of Information and Communications Technology", "Public dataset portal; no documented live CKAN/DKAN API verified", "https://data.gov.ph/index/home"],
  ["ph.dict.egov", "eGovPH / eGov API", "Department of Information and Communications Technology", "Reviewed organization account and scoped credentials required", "https://platforms.e.gov.ph/"],
  ["ph.pagasa", "PAGASA", "DOST-PAGASA", "No officially documented public API verified", "https://www.pagasa.dost.gov.ph/"],
  ["ph.bsp", "BSP Reference Rates", "Bangko Sentral ng Pilipinas", "Reference-rate publications found; no officially documented public API verified", "https://www.bsp.gov.ph/"],
  ["ph.philgeps", "PhilGEPS", "Procurement Service - PhilGEPS", "Open-data downloads found; no officially documented public API verified", "https://open.philgeps.gov.ph/"],
  ["ph.bir", "Bureau of Internal Revenue", "Bureau of Internal Revenue", "Accreditation or agency agreement required", "https://www.bir.gov.ph/"],
  ["ph.sec", "Securities and Exchange Commission", "Securities and Exchange Commission", "Accreditation or agency agreement required", "https://www.sec.gov.ph/"],
  ["ph.lto", "Land Transportation Office", "Land Transportation Office", "Accreditation or agency agreement required", "https://lto.gov.ph/"],
  ["ph.sss", "Social Security System", "Social Security System", "Accreditation or agency agreement required", "https://www.sss.gov.ph/"],
  ["ph.philhealth", "PhilHealth", "Philippine Health Insurance Corporation", "Accreditation or agency agreement required", "https://www.philhealth.gov.ph/"],
  ["ph.pagibig", "Pag-IBIG Fund", "Home Development Mutual Fund", "Accreditation or agency agreement required", "https://www.pagibigfund.gov.ph/"],
  ["ph.dfa", "Department of Foreign Affairs", "Department of Foreign Affairs", "Accreditation or agency agreement required", "https://dfa.gov.ph/"],
  ["ph.nbi", "National Bureau of Investigation", "National Bureau of Investigation", "Accreditation or agency agreement required", "https://nbi.gov.ph/"],
  ["ph.pnp", "Philippine National Police", "Philippine National Police", "Accreditation or agency agreement required", "https://pnp.gov.ph/"],
];

const publicCatalog = publicDefinitions.map((definition) => Object.freeze({
  providerKey: definition.providerKey,
  displayName: definition.displayName,
  agency: definition.agency,
  apiType: definition.apiType,
  officialUrl: definition.documentationUrl,
  adapterManifest: governmentProviderManifests[definition.providerKey],
  metadata: Object.freeze({
    connectionMode: definition.credentialMode === "none" ? "public_safe_read" : "self_service_credential",
    catalogAction: "Connect",
    publicConnectAllowed: true,
    liveConnectionStatus: "not_connected",
    statusAuthority: "fresh_provider_readback_only",
    credentialMode: definition.credentialMode,
  }),
}));

const requestCatalog = requestActivationDefinitions.map(([providerKey, displayName, agency, reason, officialUrl]) => Object.freeze({
  providerKey,
  displayName,
  agency,
  apiType: "partner_or_unverified",
  officialUrl,
  adapterManifest: null,
  metadata: Object.freeze({
    connectionMode: "request_activation",
    catalogAction: "Request activation",
    publicConnectAllowed: false,
    liveConnectionStatus: "not_connected",
    activationReason: reason,
  }),
}));

export const governmentProviderCatalog = Object.freeze([...publicCatalog, ...requestCatalog]);

export function getGovernmentProvider(providerKey) {
  return governmentProviderCatalog.find((entry) => entry.providerKey === providerKey) ?? null;
}

export function listGovernmentProviders() {
  return [...governmentProviderCatalog];
}
