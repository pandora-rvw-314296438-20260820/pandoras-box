const VERSION_RE = /^[0-9]+\.[0-9]+\.[0-9]+$/;
const KEY_RE = /^[a-z][a-z0-9_.-]{1,127}$/;
const CAPABILITY_RE = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;
const SCOPE_RE = /^[A-Za-z0-9][A-Za-z0-9:._/-]{0,199}$/;

export const CONNECTION_MANIFEST_SCHEMA_VERSION = "1.0.0";
export const AUTH_TYPES = Object.freeze([
  "oauth2",
  "oidc",
  "api_key",
  "service_credential",
  "workload_identity",
  "device_pairing",
  "partner_activation",
]);
export const RISK_CLASSES = Object.freeze(["low", "medium", "high", "regulated"]);
export const CONNECTION_STATES = Object.freeze([
  "disconnected",
  "connecting",
  "connected",
  "needs_attention",
  "revoked",
]);
export const BROKER_CONTRACTS = Object.freeze({
  oauth: Object.freeze([
    "beginAuthorization",
    "consumeCallback",
    "refresh",
    "revoke",
  ]),
  credential: Object.freeze([
    "store",
    "leaseForServerProbe",
    "rotate",
    "revoke",
  ]),
  liveConnections: Object.freeze([
    "recordProviderReadback",
    "listForOrganization",
    "setActiveAccount",
    "projectStatus",
  ]),
});

function assertObject(value, label) {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw new TypeError(`${label} must be an object`);
  }
}

function assertString(value, label, pattern) {
  if (typeof value !== "string" || value.length === 0 || (pattern && !pattern.test(value))) {
    throw new TypeError(`${label} is invalid`);
  }
}

function assertBoolean(value, label) {
  if (typeof value !== "boolean") throw new TypeError(`${label} must be boolean`);
}

function assertStringArray(value, label, pattern = null, { allowEmpty = false } = {}) {
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0)) {
    throw new TypeError(`${label} must be ${allowEmpty ? "an" : "a non-empty"} array`);
  }
  const unique = new Set();
  for (const item of value) {
    assertString(item, `${label} item`, pattern);
    if (unique.has(item)) throw new TypeError(`${label} contains a duplicate`);
    unique.add(item);
  }
}

function assertBoundedInteger(value, label, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new TypeError(`${label} must be an integer from ${minimum} to ${maximum}`);
  }
}

function clone(value) {
  return structuredClone(value);
}

function readPath(source, path) {
  return path.split(".").reduce((value, segment) => (
    value && typeof value === "object" ? value[segment] : undefined
  ), source);
}

function assertNoCredentialMaterial(value, label = "manifest") {
  if (typeof value === "string") {
    if (
      /(?:github_pat_|gh[pousr]_|sb_secret_|AIza)[A-Za-z0-9_-]{16,}/.test(value) ||
      /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(value) ||
      /postgres(?:ql)?:\/\/[^\s:@]+:[^\s@]+@/i.test(value)
    ) {
      throw new TypeError(`${label} contains credential material`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoCredentialMaterial(item, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      assertNoCredentialMaterial(item, `${label}.${key}`);
    }
  }
}

export function validateConnectionManifest(manifest) {
  assertObject(manifest, "manifest");
  assertNoCredentialMaterial(manifest);
  if (manifest.schemaVersion !== CONNECTION_MANIFEST_SCHEMA_VERSION) {
    throw new TypeError("schemaVersion is unsupported");
  }
  assertString(manifest.providerKey, "providerKey", KEY_RE);
  assertString(manifest.manifestVersion, "manifestVersion", VERSION_RE);
  assertString(manifest.displayName, "displayName");
  if (!RISK_CLASSES.includes(manifest.riskClass)) throw new TypeError("riskClass is invalid");

  assertObject(manifest.auth, "auth");
  if (!AUTH_TYPES.includes(manifest.auth.type)) throw new TypeError("auth.type is invalid");
  if (["oauth2", "oidc"].includes(manifest.auth.type)) {
    assertObject(manifest.auth.pkce, "auth.pkce");
    if (manifest.auth.pkce.required !== true || manifest.auth.pkce.method !== "S256") {
      throw new TypeError("OAuth/OIDC requires PKCE S256");
    }
    assertObject(manifest.auth.state, "auth.state");
    if (manifest.auth.state.required !== true) throw new TypeError("OAuth/OIDC requires state");
    assertBoundedInteger(manifest.auth.state.ttlSeconds, "auth.state.ttlSeconds", 60, 900);
    assertObject(manifest.auth.nonce, "auth.nonce");
    if (manifest.auth.nonce.required !== true) throw new TypeError("OAuth/OIDC requires nonce");
  }

  assertObject(manifest.scopes, "scopes");
  if (manifest.scopes.strategy !== "read_first") throw new TypeError("scopes.strategy must be read_first");
  assertStringArray(manifest.scopes.read, "scopes.read", SCOPE_RE);
  assertStringArray(manifest.scopes.write, "scopes.write", SCOPE_RE, { allowEmpty: true });

  assertObject(manifest.callback, "callback");
  assertString(manifest.callback.webPath, "callback.webPath");
  if (!manifest.callback.webPath.startsWith("/") || manifest.callback.webPath.includes("://")) {
    throw new TypeError("callback.webPath must be a relative HTTPS callback path");
  }
  assertObject(manifest.callback.mobile, "callback.mobile");
  if (manifest.callback.mobile.secureBrowser !== "custom_tab") {
    throw new TypeError("mobile OAuth must use a custom tab");
  }
  assertStringArray(manifest.callback.mobile.returnModes, "callback.mobile.returnModes");
  if (!manifest.callback.mobile.returnModes.some((mode) => ["app_link", "universal_link"].includes(mode))) {
    throw new TypeError("mobile callback requires an app or universal link return");
  }

  assertObject(manifest.accountIdentity, "accountIdentity");
  assertStringArray(manifest.accountIdentity.stableSubjectFields, "accountIdentity.stableSubjectFields");
  assertStringArray(manifest.accountIdentity.displayFields, "accountIdentity.displayFields");
  assertBoolean(manifest.accountIdentity.tenantSelector, "accountIdentity.tenantSelector");

  assertObject(manifest.health, "health");
  assertString(manifest.health.safeReadCapability, "health.safeReadCapability", CAPABILITY_RE);
  assertBoundedInteger(manifest.health.maxAgeSeconds, "health.maxAgeSeconds", 30, 86400);
  if (manifest.health.identityReadback !== true || manifest.health.scopesReadback !== true) {
    throw new TypeError("health requires identity and scope readback");
  }

  assertObject(manifest.credential, "credential");
  if (manifest.credential.storage !== "server_vault_reference") {
    throw new TypeError("credential.storage must be server_vault_reference");
  }
  if (manifest.credential.clientExposure !== "forbidden") {
    throw new TypeError("credential.clientExposure must be forbidden");
  }
  assertBoolean(manifest.credential.rotateSupported, "credential.rotateSupported");
  assertBoolean(manifest.credential.revokeSupported, "credential.revokeSupported");

  assertObject(manifest.dataResidency, "dataResidency");
  if (manifest.dataResidency.enforcement !== "tenant_policy") {
    throw new TypeError("dataResidency.enforcement must be tenant_policy");
  }
  assertStringArray(manifest.dataResidency.allowedPolicies, "dataResidency.allowedPolicies");

  if (!Array.isArray(manifest.capabilities) || manifest.capabilities.length === 0) {
    throw new TypeError("capabilities must be a non-empty array");
  }
  const declaredScopes = new Set([...manifest.scopes.read, ...manifest.scopes.write]);
  const declaredCapabilities = new Set();
  for (const capability of manifest.capabilities) {
    assertObject(capability, "capability");
    assertString(capability.capabilityKey, "capability.capabilityKey", CAPABILITY_RE);
    if (declaredCapabilities.has(capability.capabilityKey)) {
      throw new TypeError("duplicate capability");
    }
    declaredCapabilities.add(capability.capabilityKey);
    if (!["read", "write"].includes(capability.operationMode)) {
      throw new TypeError("capability.operationMode is invalid");
    }
    assertStringArray(capability.requiredScopes, "capability.requiredScopes", SCOPE_RE);
    for (const scope of capability.requiredScopes) {
      if (!declaredScopes.has(scope)) throw new TypeError("capability references an undeclared scope");
    }
    assertStringArray(capability.evidenceModes, "capability.evidenceModes");
    if (capability.operationMode === "write") {
      if (capability.requiresStepUp !== true) {
        throw new TypeError("write capability requires step-up approval");
      }
      if (!capability.requiredScopes.some((scope) => manifest.scopes.write.includes(scope))) {
        throw new TypeError("write capability requires a declared write scope");
      }
    }
  }
  const healthCapability = manifest.capabilities.find(
    (capability) => capability.capabilityKey === manifest.health.safeReadCapability,
  );
  if (!healthCapability || healthCapability.operationMode !== "read") {
    throw new TypeError("health.safeReadCapability must name a declared read capability");
  }

  return Object.freeze(clone(manifest));
}

export function validateBrokerImplementation(kind, implementation) {
  const methods = BROKER_CONTRACTS[kind];
  if (!methods) throw new TypeError("unknown broker contract");
  assertObject(implementation, `${kind} broker`);
  for (const method of methods) {
    if (typeof implementation[method] !== "function") {
      throw new TypeError(`${kind} broker must implement ${method}`);
    }
  }
  return Object.freeze({ kind, methods: [...methods] });
}

export function deriveConnectionStatus(manifestInput, runtimeEvidence, now = new Date()) {
  const manifest = validateConnectionManifest(manifestInput);
  assertObject(runtimeEvidence, "runtimeEvidence");
  const observedNow = now instanceof Date ? now : new Date(now);
  if (Number.isNaN(observedNow.getTime())) throw new TypeError("now is invalid");

  if (runtimeEvidence.revokedAt) {
    return Object.freeze({ state: "revoked", reason: "credential_revoked" });
  }
  if (!runtimeEvidence.credentialReference) {
    return Object.freeze({ state: "disconnected", reason: "credential_reference_missing" });
  }

  const readback = runtimeEvidence.providerReadback;
  if (!readback || readback.verified !== true) {
    return Object.freeze({ state: "connecting", reason: "provider_readback_missing" });
  }
  const verifiedAt = new Date(readback.verifiedAt);
  if (
    Number.isNaN(verifiedAt.getTime()) ||
    observedNow.getTime() - verifiedAt.getTime() > manifest.health.maxAgeSeconds * 1000
  ) {
    return Object.freeze({ state: "needs_attention", reason: "provider_readback_stale" });
  }
  if (readback.health?.state !== "healthy") {
    return Object.freeze({ state: "needs_attention", reason: "provider_health_not_healthy" });
  }
  const grantedScopes = new Set(Array.isArray(readback.grantedScopes) ? readback.grantedScopes : []);
  if (!manifest.scopes.read.every((scope) => grantedScopes.has(scope))) {
    return Object.freeze({ state: "needs_attention", reason: "required_read_scope_missing" });
  }
  if (!manifest.accountIdentity.stableSubjectFields.every(
    (path) => {
      const value = readPath(readback.accountIdentity, path);
      return typeof value === "string" && value.length > 0;
    },
  )) {
    return Object.freeze({ state: "needs_attention", reason: "account_identity_unverified" });
  }
  if (
    runtimeEvidence.accountBinding?.active !== true ||
    typeof runtimeEvidence.accountBinding?.organizationId !== "string" ||
    typeof runtimeEvidence.accountBinding?.connectionId !== "string"
  ) {
    return Object.freeze({ state: "needs_attention", reason: "account_binding_unverified" });
  }
  if (readback.probe?.capabilityKey !== manifest.health.safeReadCapability || readback.probe?.ok !== true) {
    return Object.freeze({ state: "needs_attention", reason: "safe_capability_probe_failed" });
  }

  return Object.freeze({
    state: "connected",
    reason: "fresh_provider_readback",
    providerKey: manifest.providerKey,
    connectionId: runtimeEvidence.accountBinding.connectionId,
    organizationId: runtimeEvidence.accountBinding.organizationId,
    verifiedAt: verifiedAt.toISOString(),
  });
}
