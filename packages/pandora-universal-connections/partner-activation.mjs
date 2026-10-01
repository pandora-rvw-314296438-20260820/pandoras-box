import { getProviderEntry } from "./provider-manifests.mjs";

export const PARTNER_ACTIVATION_STATES = Object.freeze({
  REQUESTED: "requested",
  AUTHORITY_REVIEW: "authority_review",
  PARTNER_ONBOARDING: "partner_onboarding",
  PROVIDER_VERIFICATION: "provider_verification",
  VERIFIED_FOR_RUNTIME_HANDOFF: "verified_for_runtime_handoff",
  CANCELLED: "cancelled",
});

const TENANT_FIELDS = ["organizationId", "tenantId", "connectionId", "tenantKey"];
const allowedCreateFields = new Set([
  "requestId", "providerKey", ...TENANT_FIELDS, "requesterRef", "contactEmail",
  "legalEntityName", "accountReference", "requestedCapabilities", "jurisdiction", "requestedAt",
]);
const allowedTransitionFields = new Set([
  "to", "at", "actorRef", ...TENANT_FIELDS, "authorityEvidenceRef", "providerContractRef",
  "vaultCredentialRef", "providerReadbackRef", "accountIdentityRef", "scopesEvidenceRef",
  "safeProbeEvidenceRef", "reason",
]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TENANT_KEY = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,319}$/;

const transitions = new Map([
  [PARTNER_ACTIVATION_STATES.REQUESTED, new Set([PARTNER_ACTIVATION_STATES.AUTHORITY_REVIEW, PARTNER_ACTIVATION_STATES.CANCELLED])],
  [PARTNER_ACTIVATION_STATES.AUTHORITY_REVIEW, new Set([PARTNER_ACTIVATION_STATES.PARTNER_ONBOARDING, PARTNER_ACTIVATION_STATES.CANCELLED])],
  [PARTNER_ACTIVATION_STATES.PARTNER_ONBOARDING, new Set([PARTNER_ACTIVATION_STATES.PROVIDER_VERIFICATION, PARTNER_ACTIVATION_STATES.CANCELLED])],
  [PARTNER_ACTIVATION_STATES.PROVIDER_VERIFICATION, new Set([PARTNER_ACTIVATION_STATES.VERIFIED_FOR_RUNTIME_HANDOFF, PARTNER_ACTIVATION_STATES.CANCELLED])],
]);

function assertPlainObject(value, label) {
  if (!value || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError(`${label} must be a plain object`);
  }
}

function assertAllowedFields(value, allowed, label) {
  const unexpected = Object.keys(value).filter((key) => !allowed.has(key));
  if (unexpected.length) throw new Error(`${label}_contains_forbidden_fields:${unexpected.join(",")}`);
}

function assertNoCredentialMaterial(value, label) {
  if (typeof value === "string") {
    if (
      /(?:github_pat_|gh[pousr]_|sb_secret_|AIza)[A-Za-z0-9_-]{16,}/.test(value)
      || /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(value)
      || /postgres(?:ql)?:\/\/[^\s:@]+:[^\s@]+@/i.test(value)
    ) throw new Error(`${label}_contains_credential_material`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => assertNoCredentialMaterial(item, label));
    return;
  }
  if (value && typeof value === "object") {
    Object.values(value).forEach((item) => assertNoCredentialMaterial(item, label));
  }
}

function requireText(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) throw new TypeError(`${label} required`);
  return value.trim();
}

function requireEvidence(transition, fields) {
  for (const field of fields) requireText(transition[field], field);
}

function assertTenantBinding(source, runtime, expected = null) {
  const organizationId = requireText(source.organizationId, "organizationId");
  const tenantId = requireText(source.tenantId, "tenantId");
  const connectionId = requireText(source.connectionId, "connectionId");
  const tenantKey = requireText(source.tenantKey, "tenantKey");
  if (!UUID.test(organizationId) || !UUID.test(tenantId) || !UUID.test(connectionId) || !TENANT_KEY.test(tenantKey)) {
    throw new Error("CONNECTION_IDENTITY_INVALID");
  }
  const trusted = runtime?.tenantBinding || runtime?.evidence?.tenantBinding;
  if (
    organizationId !== tenantId
    || !trusted
    || trusted.organizationId !== organizationId
    || trusted.tenantId !== tenantId
    || trusted.connectionId !== connectionId
    || trusted.tenantKey !== tenantKey
    || (expected && (
      expected.organizationId !== organizationId
      || expected.tenantId !== tenantId
      || expected.connectionId !== connectionId
      || expected.tenantKey !== tenantKey
    ))
  ) throw new Error("CONNECTION_ACCOUNT_TENANT_MISMATCH");
  return Object.freeze({ organizationId, tenantId, connectionId, tenantKey, vaultCredentialRef: trusted.vaultCredentialRef });
}

function cloneAndFreeze(value) {
  const clone = structuredClone(value);
  Object.freeze(clone.history);
  return Object.freeze(clone);
}

export function createPartnerActivationRequest(input, runtime = {}) {
  assertPlainObject(input, "activation request");
  assertAllowedFields(input, allowedCreateFields, "activation_request");
  assertNoCredentialMaterial(input, "activation_request");
  const entry = getProviderEntry(requireText(input.providerKey, "providerKey"));
  if (!entry || entry.metadata.connectionMode !== "request_activation") {
    throw new Error("provider_does_not_use_partner_activation");
  }
  const binding = assertTenantBinding(input, runtime);
  if (!Array.isArray(input.requestedCapabilities) || input.requestedCapabilities.length === 0) {
    throw new TypeError("requestedCapabilities required");
  }
  const declared = new Set(entry.adapterManifest.capabilities.map((item) => item.capabilityKey));
  const undeclared = input.requestedCapabilities.filter((item) => !declared.has(item));
  if (undeclared.length) throw new Error(`undeclared_capabilities:${undeclared.join(",")}`);

  const requestedAt = requireText(input.requestedAt, "requestedAt");
  if (!Number.isFinite(Date.parse(requestedAt))) throw new TypeError("requestedAt invalid");
  return cloneAndFreeze({
    schemaVersion: 1,
    requestId: requireText(input.requestId, "requestId"),
    providerKey: entry.providerKey,
    organizationId: binding.organizationId,
    tenantId: binding.tenantId,
    connectionId: binding.connectionId,
    tenantKey: binding.tenantKey,
    requesterRef: requireText(input.requesterRef, "requesterRef"),
    contactEmail: requireText(input.contactEmail, "contactEmail"),
    legalEntityName: requireText(input.legalEntityName, "legalEntityName"),
    accountReference: input.accountReference ? String(input.accountReference) : null,
    requestedCapabilities: [...input.requestedCapabilities],
    jurisdiction: requireText(input.jurisdiction, "jurisdiction"),
    state: PARTNER_ACTIVATION_STATES.REQUESTED,
    liveConnectionStatus: "not_connected",
    requestedAt: new Date(requestedAt).toISOString(),
    history: [{ state: PARTNER_ACTIVATION_STATES.REQUESTED, at: new Date(requestedAt).toISOString(), actorRef: input.requesterRef }],
  });
}

export function transitionPartnerActivation(request, transition, runtime = {}) {
  assertPlainObject(request, "activation request");
  assertPlainObject(transition, "activation transition");
  assertAllowedFields(transition, allowedTransitionFields, "activation_transition");
  assertNoCredentialMaterial(transition, "activation_transition");
  const binding = assertTenantBinding(transition, runtime, request);
  const to = requireText(transition.to, "to");
  if (!transitions.get(request.state)?.has(to)) throw new Error(`invalid_activation_transition:${request.state}->${to}`);
  const at = requireText(transition.at, "at");
  if (!Number.isFinite(Date.parse(at))) throw new TypeError("at invalid");
  requireText(transition.actorRef, "actorRef");

  if (to === PARTNER_ACTIVATION_STATES.PARTNER_ONBOARDING) {
    requireEvidence(transition, ["authorityEvidenceRef", "providerContractRef"]);
  }
  if (to === PARTNER_ACTIVATION_STATES.PROVIDER_VERIFICATION) {
    requireEvidence(transition, ["vaultCredentialRef"]);
    if (binding.vaultCredentialRef !== transition.vaultCredentialRef) {
      throw new Error("CONNECTION_VAULT_TENANT_MISMATCH");
    }
  }
  if (to === PARTNER_ACTIVATION_STATES.VERIFIED_FOR_RUNTIME_HANDOFF) {
    requireEvidence(transition, ["providerReadbackRef", "accountIdentityRef", "scopesEvidenceRef", "safeProbeEvidenceRef"]);
  }

  const evidence = Object.fromEntries(Object.entries(transition).filter(([key, value]) =>
    key.endsWith("Ref") && typeof value === "string" && value.length > 0));
  return cloneAndFreeze({
    ...request,
    state: to,
    liveConnectionStatus: "not_connected",
    history: [...request.history, {
      state: to,
      at: new Date(at).toISOString(),
      actorRef: transition.actorRef,
      tenantId: binding.tenantId,
      connectionId: binding.connectionId,
      tenantKey: binding.tenantKey,
      evidence,
      reason: transition.reason ?? null,
    }],
  });
}

export function buildPartnerActivationView(providerKey) {
  const entry = getProviderEntry(providerKey);
  if (!entry || entry.metadata.connectionMode !== "request_activation") {
    throw new Error("provider_does_not_use_partner_activation");
  }
  return Object.freeze({
    providerKey,
    primaryAction: "request_activation",
    primaryLabel: "Request activation",
    connectButtonVisible: false,
    customProviderUi: false,
    connectionStatus: "not_connected",
  });
}
