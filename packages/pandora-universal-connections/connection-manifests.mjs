import { validateConnectionManifest } from "../pandora-connections-core/index.mjs";
import { providerEntries } from "./provider-manifests.mjs";

function buildConnectionManifest(entry) {
  const { adapterManifest, metadata } = entry;
  const readScopes = [...metadata.scopes.read];
  const writeScopes = [...metadata.scopes.write];

  return validateConnectionManifest({
    schemaVersion: "1.0.0",
    providerKey: entry.providerKey,
    manifestVersion: adapterManifest.manifestVersion,
    displayName: adapterManifest.displayName,
    riskClass: metadata.riskClass,
    auth: structuredClone(metadata.auth),
    scopes: structuredClone(metadata.scopes),
    callback: structuredClone(metadata.callback),
    accountIdentity: structuredClone(metadata.accountIdentity),
    health: {
      safeReadCapability: metadata.health.safeReadCapability,
      maxAgeSeconds: metadata.health.maxAgeSeconds,
      identityReadback: metadata.health.identityReadback,
      scopesReadback: metadata.health.scopesReadback,
    },
    credential: structuredClone(metadata.credential),
    dataResidency: structuredClone(metadata.dataResidency),
    capabilities: adapterManifest.capabilities.map((capability) => ({
      capabilityKey: capability.capabilityKey,
      operationMode: capability.operationMode,
      requiredScopes: capability.operationMode === "write" ? writeScopes : readScopes,
      evidenceModes: [...capability.evidenceModes],
      ...(capability.operationMode === "write" ? { requiresStepUp: true } : {}),
    })),
  });
}

export const providerConnectionManifests = Object.freeze(Object.fromEntries(
  providerEntries.map((entry) => [entry.providerKey, buildConnectionManifest(entry)]),
));

export function getProviderConnectionManifest(providerKey) {
  return providerConnectionManifests[providerKey] ?? null;
}
