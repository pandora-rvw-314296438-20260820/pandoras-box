import { getGovernmentProvider } from "./provider-manifests.mjs";

const ALLOWED_FIELDS = new Set([
  "requestId", "providerKey", "organizationId", "requesterRef", "contactEmail",
  "tenantId", "connectionId", "tenantKey", "legalEntityName", "requestedUseCase",
  "jurisdiction", "requestedAt",
]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TENANT_KEY = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,319}$/;

function requireText(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) throw new TypeError(`${label} required`);
  return value.trim();
}

function assertNoCredentialMaterial(value) {
  const serialized = JSON.stringify(value);
  if (
    /(?:password|secret|api[_-]?key|access[_-]?token|private[_-]?key)/i.test(serialized)
    || /(?:github_pat_|gh[pousr]_|sb_secret_|AIza)[A-Za-z0-9_-]{16,}/.test(serialized)
    || /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(serialized)
    || /postgres(?:ql)?:\/\/[^\s:@]+:[^\s@]+@/i.test(serialized)
  ) {
    throw new Error("activation_request_must_not_contain_credentials");
  }
}

export function createGovernmentActivationRequest(input, runtime = {}) {
  if (!input || Array.isArray(input) || typeof input !== "object") throw new TypeError("activation request must be an object");
  const unexpected = Object.keys(input).filter((key) => !ALLOWED_FIELDS.has(key));
  if (unexpected.length) throw new Error(`activation_request_contains_forbidden_fields:${unexpected.join(",")}`);
  assertNoCredentialMaterial(input);
  const provider = getGovernmentProvider(requireText(input.providerKey, "providerKey"));
  if (!provider || provider.metadata.connectionMode !== "request_activation") throw new Error("provider_does_not_use_request_activation");
  const organizationId = requireText(input.organizationId, "organizationId");
  const tenantId = requireText(input.tenantId, "tenantId");
  const connectionId = requireText(input.connectionId, "connectionId");
  const tenantKey = requireText(input.tenantKey, "tenantKey");
  if (!UUID.test(organizationId) || !UUID.test(tenantId) || !UUID.test(connectionId) || !TENANT_KEY.test(tenantKey)) {
    throw new Error("CONNECTION_IDENTITY_INVALID");
  }
  if (tenantId !== organizationId) {
    throw new Error("CONNECTION_ACCOUNT_TENANT_MISMATCH");
  }
  const trusted = runtime?.tenantBinding || runtime?.evidence?.tenantBinding;
  if (!trusted || trusted.organizationId !== organizationId || trusted.tenantId !== tenantId ||
      trusted.connectionId !== connectionId || trusted.tenantKey !== tenantKey) {
    throw new Error("CONNECTION_ACCOUNT_TENANT_MISMATCH");
  }
  const requestedAt = requireText(input.requestedAt, "requestedAt");
  if (!Number.isFinite(Date.parse(requestedAt))) throw new TypeError("requestedAt invalid");
  return Object.freeze({
    schemaVersion: 1,
    requestId: requireText(input.requestId, "requestId"),
    providerKey: provider.providerKey,
    organizationId,
    tenantId,
    connectionId,
    tenantKey,
    requesterRef: requireText(input.requesterRef, "requesterRef"),
    contactEmail: requireText(input.contactEmail, "contactEmail"),
    legalEntityName: requireText(input.legalEntityName, "legalEntityName"),
    requestedUseCase: requireText(input.requestedUseCase, "requestedUseCase"),
    jurisdiction: requireText(input.jurisdiction, "jurisdiction"),
    state: "requested",
    catalogAction: "Request activation",
    liveConnectionStatus: "not_connected",
    credentialReturned: false,
    requestedAt: new Date(requestedAt).toISOString(),
  });
}
