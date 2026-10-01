import { getGovernmentProvider } from "./provider-manifests.mjs";

const ALLOWED_FIELDS = new Set([
  "requestId", "providerKey", "organizationId", "requesterRef", "contactEmail",
  "legalEntityName", "requestedUseCase", "jurisdiction", "requestedAt",
]);

function requireText(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) throw new TypeError(`${label} required`);
  return value.trim();
}

function assertNoCredentialMaterial(value) {
  const serialized = JSON.stringify(value);
  if (/(?:password|secret|api[_-]?key|access[_-]?token|private[_-]?key)/i.test(serialized)) {
    throw new Error("activation_request_must_not_contain_credentials");
  }
}

export function createGovernmentActivationRequest(input) {
  if (!input || Array.isArray(input) || typeof input !== "object") throw new TypeError("activation request must be an object");
  const unexpected = Object.keys(input).filter((key) => !ALLOWED_FIELDS.has(key));
  if (unexpected.length) throw new Error(`activation_request_contains_forbidden_fields:${unexpected.join(",")}`);
  assertNoCredentialMaterial(input);
  const provider = getGovernmentProvider(requireText(input.providerKey, "providerKey"));
  if (!provider || provider.metadata.connectionMode !== "request_activation") throw new Error("provider_does_not_use_request_activation");
  const requestedAt = requireText(input.requestedAt, "requestedAt");
  if (!Number.isFinite(Date.parse(requestedAt))) throw new TypeError("requestedAt invalid");
  return Object.freeze({
    schemaVersion: 1,
    requestId: requireText(input.requestId, "requestId"),
    providerKey: provider.providerKey,
    organizationId: requireText(input.organizationId, "organizationId"),
    requesterRef: requireText(input.requesterRef, "requesterRef"),
    contactEmail: requireText(input.contactEmail, "contactEmail"),
    legalEntityName: requireText(input.legalEntityName, "legalEntityName"),
    requestedUseCase: requireText(input.requestedUseCase, "requestedUseCase"),
    jurisdiction: requireText(input.jurisdiction, "jurisdiction"),
    state: "requested",
    catalogAction: "Request activation",
    liveConnectionStatus: "not_connected",
    requestedAt: new Date(requestedAt).toISOString(),
  });
}
