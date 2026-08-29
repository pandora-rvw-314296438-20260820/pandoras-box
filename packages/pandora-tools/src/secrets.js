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
    return fn(this.entries.get(secretRef));
  }
}

class MemorySecretLeaseStore {
  constructor(records = []) { this.durability = "memory"; this.records = new Map(records.map((r) => [r.lease_id, structuredClone(r)])); }
  async put(record) { this.records.set(record.lease_id, structuredClone(record)); return structuredClone(record); }
  async get(leaseId) { const record = this.records.get(leaseId); return record ? structuredClone(record) : null; }
  async revoke(leaseId, revokedAt) { const record = this.records.get(leaseId); if (!record) return false; record.revoked_at = revokedAt; return true; }
}

class DurableSecretLeaseStore {
  constructor({ putLease, getLease, revokeLease }) {
    if (typeof putLease !== "function" || typeof getLease !== "function" || typeof revokeLease !== "function") throw new PandoraToolError("internal", "SECRET_LEASE_STORE_PORT_INVALID", "Credential lease store port is invalid");
    this.putLease = putLease; this.getLease = getLease; this.revokeLease = revokeLease; this.durability = "durable";
  }
  async put(record) { return this.putLease(structuredClone(record)); }
  async get(leaseId) { const record = await this.getLease(leaseId); return record ? structuredClone(record) : null; }
  async revoke(leaseId, revokedAt) { return this.revokeLease(leaseId, revokedAt); }
}

class SecretsBroker {
  constructor({ metadataStore, secretHolder, leaseStore = new MemorySecretLeaseStore(), auditSink = null, defaultTtlMs = 5 * 60_000, canaries = [] }) {
    if (!metadataStore || typeof metadataStore.get !== "function") throw new PandoraToolError("internal", "SECRET_METADATA_STORE_INVALID", "Secret metadata store is invalid");
    if (!secretHolder || typeof secretHolder.withSecret !== "function") throw new PandoraToolError("internal", "SECRET_HOLDER_INVALID", "Secret holder is invalid");
    if (!leaseStore || typeof leaseStore.put !== "function" || typeof leaseStore.get !== "function" || typeof leaseStore.revoke !== "function") throw new PandoraToolError("internal", "SECRET_LEASE_STORE_INVALID", "Credential lease store is invalid");
    this.metadataStore = metadataStore; this.secretHolder = secretHolder; this.leaseStore = leaseStore; this.auditSink = auditSink; this.defaultTtlMs = defaultTtlMs; this.canaries = canaries;
  }
  async issueLease({ secret_ref, purpose, scope, requested_by, ttl_ms = this.defaultTtlMs, handoff = "same_process" }, { actor_capabilities = [], now = new Date() } = {}) {
    if (!actor_capabilities.includes("secrets.use.scoped")) throw new PandoraToolError("authorization", "SECRET_CAPABILITY_MISSING", "Scoped secret capability is required");
    if (!scope?.organization_id || !scope?.project_id || !scope?.environment || !scope?.operation) throw new PandoraToolError("invalid_request", "SECRET_SCOPE_INVALID", "Credential scope is incomplete");
    if (!Number.isInteger(ttl_ms) || ttl_ms < 1000 || ttl_ms > 15 * 60_000) throw new PandoraToolError("authorization", "SECRET_TTL_INVALID", "Credential lease TTL is outside policy");
    if (!["same_process", "cross_worker"].includes(handoff)) throw new PandoraToolError("invalid_request", "SECRET_HANDOFF_INVALID", "Credential lease handoff mode is invalid");
    if (handoff === "cross_worker" && this.leaseStore.durability !== "durable") throw new PandoraToolError("policy_denied", "CREDENTIAL_LEASE_DURABLE_STORE_REQUIRED", "Cross-worker credential leases require durable lease state");
    const metadata = await this.metadataStore.get(secret_ref);
    if (!metadata || metadata.revoked_at) throw new PandoraToolError("authorization", "SECRET_UNAVAILABLE", "Required credential is unavailable");
    if (metadata.purpose !== purpose) throw new PandoraToolError("authorization", "SECRET_PURPOSE_MISMATCH", "Credential purpose does not match operation");
    if (!scopeMatches(metadata.scope, scope)) throw new PandoraToolError("authorization", "SECRET_SCOPE_MISMATCH", "Credential cannot be used for this project, environment, or operation");
    const lease = { lease_id: randomUUID(), provider: metadata.provider, purpose, scope: { ...scope }, requested_by, handoff, issued_at: now.toISOString(), expires_at: new Date(now.getTime() + ttl_ms).toISOString(), revoked_at: null };
    await this.leaseStore.put({ ...lease, secret_ref });
    await this.#audit("credential_lease_issued", lease);
    return Object.freeze({ ...lease });
  }
  async revoke(leaseId, now = new Date()) {
    const record = await this.leaseStore.get(leaseId); if (!record) return false;
    const revokedAt = now.toISOString(); const changed = await this.leaseStore.revoke(leaseId, revokedAt);
    if (changed) await this.#audit("credential_lease_revoked", { ...record, revoked_at: revokedAt });
    return Boolean(changed);
  }
  async assertLease(lease, scope, now = new Date()) {
    const record = await this.leaseStore.get(lease?.lease_id);
    if (!record || record.revoked_at || lease.revoked_at) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_REVOKED", "Credential lease is unavailable");
    if (record.handoff === "cross_worker" && this.leaseStore.durability !== "durable") throw new PandoraToolError("policy_denied", "CREDENTIAL_LEASE_DURABLE_STORE_REQUIRED", "Cross-worker credential leases require durable lease state");
    if (new Date(record.expires_at) <= now) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_EXPIRED", "Credential lease expired");
    if (!scopeMatches(record.scope, scope)) throw new PandoraToolError("authorization", "CREDENTIAL_LEASE_SCOPE_MISMATCH", "Credential lease scope does not match operation");
    return record;
  }
  async withCredential(lease, scope, fn, now = new Date()) {
    const record = await this.assertLease(lease, scope, now);
    await this.#audit("credential_lease_used", record);
    return this.secretHolder.withSecret(record.secret_ref, async (secret) => redactDeep(await fn(secret), { canaries: [secret, ...this.canaries] }));
  }
  async #audit(event, record) {
    if (!this.auditSink) return;
    const safe = redactDeep({ event, lease_id: record.lease_id, provider: record.provider, purpose: record.purpose, scope: record.scope, requested_by: record.requested_by, handoff: record.handoff, issued_at: record.issued_at, expires_at: record.expires_at, revoked_at: record.revoked_at }, { canaries: this.canaries });
    await this.auditSink.record(safe);
  }
}

module.exports = { scopeMatches, VaultSecretMetadataStore, VaultSecretHolder, MemorySecretMetadataStore, MemorySecretHolder, MemorySecretLeaseStore, DurableSecretLeaseStore, SecretsBroker };
