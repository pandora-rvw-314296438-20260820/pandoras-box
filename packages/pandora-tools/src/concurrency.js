"use strict";

const { randomUUID } = require("node:crypto");
const { PandoraToolError } = require("./errors");

class MemoryLeaseStore {
  constructor() { this.durability = "memory"; this.leases = new Map(); }
  async get(resourceKey) { const value = this.leases.get(resourceKey); return value ? { ...value } : null; }
  async compareAndSet(resourceKey, expectedLeaseId, next) {
    const current = this.leases.get(resourceKey);
    if ((current?.lease_id ?? null) !== (expectedLeaseId ?? null)) return false;
    if (next === null) this.leases.delete(resourceKey); else this.leases.set(resourceKey, { ...next });
    return true;
  }
}

class MutationLeaseManager {
  constructor(store) { this.store = store; }
  async acquire({ resource_key, owner_id, expected_version = null, current_version = null, ttl_ms = 60_000, now = new Date() }) {
    if (!resource_key || !owner_id || !Number.isInteger(ttl_ms) || ttl_ms < 1000 || ttl_ms > 10 * 60_000) throw new PandoraToolError("invalid_request", "LEASE_REQUEST_INVALID", "Mutation lease request is invalid");
    if (expected_version !== null && current_version !== null && expected_version !== current_version) throw new PandoraToolError("conflict", "EXPECTED_STATE_MISMATCH", "Resource state changed before mutation");
    const current = await this.store.get(resource_key);
    const nowMs = now.getTime();
    if (current && new Date(current.expires_at).getTime() > nowMs) throw new PandoraToolError("conflict", "MUTATION_LOCKED", "A conflicting mutation already holds this resource");
    const lease = { lease_id: randomUUID(), resource_key, owner_id, expected_version, acquired_at: now.toISOString(), expires_at: new Date(nowMs + ttl_ms).toISOString() };
    const ok = await this.store.compareAndSet(resource_key, current?.lease_id ?? null, lease);
    if (!ok) throw new PandoraToolError("conflict", "LEASE_RACE", "Another mutation acquired the resource first");
    return Object.freeze(lease);
  }
  async assertActive(lease, now = new Date()) {
    const current = await this.store.get(lease.resource_key);
    if (!current || current.lease_id !== lease.lease_id || current.owner_id !== lease.owner_id) throw new PandoraToolError("conflict", "LEASE_NOT_HELD", "Mutation lease is no longer held");
    if (new Date(current.expires_at) <= now) throw new PandoraToolError("conflict", "LEASE_EXPIRED", "Mutation lease expired");
    return true;
  }
  async release(lease) {
    const current = await this.store.get(lease.resource_key);
    if (!current || current.lease_id !== lease.lease_id) return false;
    return this.store.compareAndSet(lease.resource_key, lease.lease_id, null);
  }
}

module.exports = { MemoryLeaseStore, MutationLeaseManager };
