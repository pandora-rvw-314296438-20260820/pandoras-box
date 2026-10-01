import {
  providerEntries as unboundProviderEntries,
} from "./provider-manifests.mjs";
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
  government: governmentConnectionManifests,
});

export const providerAdapterCatalog = Object.freeze({
  generic: providerAdapterManifests,
  government: governmentProviderAdapters,
});
