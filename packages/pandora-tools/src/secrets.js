"use strict";

const { randomUUID } = require("node:crypto");
const { PandoraToolError } = require("./errors");
const { redactDeep } = require("./redaction");

function scopeMatches(bound, requested) {
  return bound.organization_id === requested.organization_id &&
    bound.project_id === requested.project_id &&
    bound.environment === requested.environment &&
    bound.operation === requested.operation &&
    (bound.resource_id == null || bound.resource_id === requested.resource_id);
}

class VaultSecretMetadataStore {
  constructor(getMetadata) { if (typeof getMetadata !== "function") throw new PandoraToolError("internal", "VAULT_METADATA_PORT_INVALID", "Vault metadata port is invalid"); this.getMetadata = getMetadata; this.durability = "durable"; }
  async get(secretRef) { return this.getMetadata(secretRef); }
}

class VaultSecretHolder {
  constructor(withVaultSecret) { if (typeof withVaultSecret !== "function") throw new PandoraToolError("internal", "VAULT_SECRET_PORT_INVALID", "Vault secret holder port is invalid"); this.withVaultSecret = withVaultSecret; this.provider = "supabase-vault"; }
  async withSecret(secretRef, fn) { return this.withVaultSecret(secretRef, fn); }
}

class MemorySecretMetadataStore {
  constructor(records = []) { this.durability = "memory"; this.records = new Map(records.map((r) => [r.secret_ref, { ...r }])); }
  async get(secretRef) { const value = this.records.get(secretRef); return value ? { ...value } : null; }
}

class MemorySecretHolder {
  constructor(entries = {}) { this.entries = new Map(Object.entries(entries)); }
  async withSecret(secretRef, fn) {
    if (!this.entries.has(secretRef)) throw new PandoraToolError("authorization", "SECRET_UNAVAILABLE", "Required credential is unavailable");
    const value = this.entries.get(secretRef);
    return fn(value);
  }
}

class SecretsBroker {
  constructor({ metadataStore, secretHolder, auditSink = null, defaultTtlMs = 5 * 60_000, canaries = [] }) {
    this.metadataStore = metadataStore; this.secretHolder = secretHolder; this.auditSink = auditSink; this.defaultTtlMs = defaultTtlMs; this.canaries = canaries; this.leases = new Map();
  }
  async issueLease({ secret_ref, purpose, scope, requested_by, ttl_ms = this.defaultTtlMs }, { actor_capabilities = [], now = new Date() } = {}) {
    if (!actor_capabilities.includes("secrets.use.scoped")) throw new PandoraToolError("authorization", "SECRET_CAPABILITY_MISSING", "Scoped secret capability is required");
    if (!scope?.organization_id || !scope?.project_id || !scope?.environment || !scope?.operation) throw new PandoraToolError("invalid_request", "SECRET_SCOPE_INVALID", "Credential scope is incomplete");
    if (!Number.isInteger(ttl_ms) || ttl_ms < 1000 || ttl_ms > 15 * 60_000) throw new PandoraToolError("authorization", "SECRET_TTL_INVALID", "Credential lease TTL is outside policy");
    const metadata = await this.metadataStore.get(secret_ref);
    if (!metadata || metadata.revoked_at) throw new PandoraToolError("authorization", "SECRET_UNAVAILABLE", "Required credential is unavailable");
    if (metadata.purpose !== purpose) throw new PandoraToolError("authorization", "SECRET_PURPOSE_MISMATCH", "Credential purpose does not match operation");
    if (!scopeMatches(metadata.scope, scope)) throw new PandoraToolError("authorization", "SECRET_SCOPE_MISMATCH", "Credential cannot be used for this project, environment, or operation");
    const lease = { lease_id: randomUUID(), provider: metadata.provider, purpose, scope: { ...scope }, requested_by, issued_at: now.toISOString(), expires_at: new Date(now.getTime() + ttl_ms).toISOString(), revoked_at: null };
    this.leases.set(lease.lease_id, { ...lease, secret_ref });
    await this.#audit("credential_lease_issued", lease);
    return Object.freeze({ ...lease });
  }
  async revoke(leaseId, now = new Date()) {
    const record = this.leases.get(leaseId); if (!record) return false;
    record.revoked_at = now.toISOString(); await this.#audit("credential_lease_revoked", record); return true;
  }
  async assertLease(lease, scope, now = new Date()) {
    const record = this.leases.get(lease?.lease_id);
    if (!record || record.revoked_at || lease.revoked_at) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_REVOKED", "Credential lease is unavailable");
    if (new Date(record.expires_at) <= now) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_EXPIRED", "Credential lease expired");
    if (!scopeMatches(record.scope, scope)) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_SCOPE_MISMATCH", "Credential lease scope does not match operation");
    return record;
  }
  async withCredential(lease, scope, fn, now = new Date()) {
    const record = await this.assertLease(lease, scope, now);
    await this.#audit("credential_lease_used", record);
    return this.secretHolder.withSecret(record.secret_ref, async (secret) => {
      const result = await fn(secret);
      return redactDeep(result, { canaries: [secret, ...this.canaries] });
    });
  }
  async #audit(event, record) {
    if (!this.auditSink) return;
    const safe = redactDeep({ event, lease_id: record.lease_id, provider: record.provider, purpose: record.purpose, scope: record.scope, requested_by: record.requested_by, issued_at: record.issued_at, expires_at: record.expires_at, revoked_at: record.revoked_at }, { canaries: this.canaries });
    await this.auditSink.record(safe);
  }
}

module.exports = { scopeMatches, VaultSecretMetadataStore, VaultSecretHolder, MemorySecretMetadataStore, MemorySecretHolder, SecretsBroker };
