import {
  providerEntries as unboundProviderEntries,
} from "./provider-manifests.mjs";
import {
  getProviderConnectionManifest,
  providerConnectionManifests,
} from "./connection-manifests.mjs";
import {
  governmentConnectionManifests,
  governmentProviderAdapters,
  governmentProviderCatalog,
} from "../pandora-ph-government-connections/index.mjs";

const exactTenantBindingPolicy = Object.freeze({
  canonicalTenantColumn: "organization_id",
  canonicalTenantRequestField: "tenantId",
  requiredRequestFields: Object.freeze(["tenantId", "connectionId", "tenantKey"]),
  trustedRuntimeEvidencePath: "evidence.tenantBinding",
  mismatchPolicy: "fail_closed",
  crossTenantCredentialSharing: false,
  credentialsMayReachDevices: false,
  oauthStateBoundFields: Object.freeze(["tenantId", "connectionId", "tenantKey"]),
  vaultReferenceBoundFields: Object.freeze(["tenantId", "connectionId", "tenantKey"]),
  healthEvidenceBoundFields: Object.freeze(["tenantId", "connectionId", "tenantKey"]),
});

export const providerEntries = Object.freeze(unboundProviderEntries.map((entry) => Object.freeze({
  ...entry,
  connectionManifest: providerConnectionManifests[entry.providerKey],
  metadata: Object.freeze({
    ...entry.metadata,
    tenantBinding: exactTenantBindingPolicy,
  }),
})));

export const providerAdapterManifests = Object.freeze(providerEntries.map((entry) => entry.adapterManifest));

const providerByKey = new Map(providerEntries.map((entry) => [entry.providerKey, entry]));

export function getProviderEntry(providerKey) {
  return providerByKey.get(providerKey) ?? null;
}

export function listProviderEntries({ family, priority, connectionMode } = {}) {
  return providerEntries.filter((entry) =>
    (!family || entry.metadata.family === family)
    && (!priority || entry.metadata.priority === priority)
    && (!connectionMode || entry.metadata.connectionMode === connectionMode));
}

export function buildProviderCatalogView(providerKey, readinessEvidence = {}) {
  const entry = getProviderEntry(providerKey);
  if (!entry) throw new TypeError("unknown_provider");
  if (!readinessEvidence || Array.isArray(readinessEvidence) || typeof readinessEvidence !== "object") {
    throw new TypeError("readiness_evidence_must_be_an_object");
  }
  const allowedEvidenceFields = new Set(["serverConfigurationPresent", "source"]);
  const unexpectedFields = Object.keys(readinessEvidence).filter((field) => !allowedEvidenceFields.has(field));
  if (unexpectedFields.length > 0) {
    throw new TypeError(`unexpected_readiness_evidence:${unexpectedFields.sort().join(",")}`);
  }

  if (entry.metadata.connectionMode === "request_activation") {
    return Object.freeze({
      providerKey,
      catalogState: "request_activation",
      primaryAction: "request_activation",
      primaryLabel: "Request activation",
      connectButtonVisible: false,
      blockedReason: "partner_activation_required",
      connectionStatus: "not_connected",
      statusAuthority: "live_connections_runtime",
    });
  }

  const serverConfigured = readinessEvidence.serverConfigurationPresent === true
    && readinessEvidence.source === entry.metadata.readiness.serverConfigurationAuthority;
  return Object.freeze({
    providerKey,
    catalogState: serverConfigured ? "available_to_connect" : "implemented_awaiting_credential",
    primaryAction: serverConfigured ? "connect" : null,
    primaryLabel: serverConfigured ? "Connect" : "Awaiting credentials",
    connectButtonVisible: serverConfigured,
    blockedReason: serverConfigured ? null : entry.metadata.readiness.blockedReason,
    connectionStatus: "not_connected",
    statusAuthority: "live_connections_runtime",
  });
}

export {
  getProviderConnectionManifest,
  providerConnectionManifests,
};

export {
  PARTNER_ACTIVATION_STATES,
  buildPartnerActivationView,
  createPartnerActivationRequest,
  transitionPartnerActivation,
} from "./partner-activation.mjs";

export {
  createGovernmentActivationRequest,
  getGovernmentProvider,
  governmentConnectionManifests,
  governmentProviderAdapters,
  governmentProviderCatalog,
  governmentProviderManifests,
  listGovernmentProviders,
  runGovernmentSafeReadProbe,
} from "../pandora-ph-government-connections/index.mjs";

export const universalProviderCatalog = Object.freeze([
  ...providerEntries,
  ...governmentProviderCatalog,
]);

const universalByKey = new Map(universalProviderCatalog.map((entry) => [entry.providerKey, entry]));

export function getUniversalProviderCatalogEntry(providerKey) {
  return universalByKey.get(providerKey) ?? null;
}

export function listUniversalProviderCatalogEntries({ family, priority, connectionMode } = {}) {
  return universalProviderCatalog.filter((entry) =>
    (!family || entry.metadata.family === family)
    && (!priority || entry.metadata.priority === priority)
    && (!connectionMode || entry.metadata.connectionMode === connectionMode));
}

export const connectionManifestCatalog = Object.freeze({
  generic: providerConnectionManifests,
  government: governmentConnectionManifests,
});

export const providerAdapterCatalog = Object.freeze({
  generic: providerAdapterManifests,
  government: governmentProviderAdapters,
});
