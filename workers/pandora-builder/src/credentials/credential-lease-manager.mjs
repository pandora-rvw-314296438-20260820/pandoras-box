const SAFE_ENV = /^[A-Z][A-Z0-9_]{0,63}$/;
const FORBIDDEN_PERSISTENCE = new Set(['GITHUB_TOKEN', 'GH_TOKEN', 'VERCEL_TOKEN', 'GEMINI_API_KEY', 'SUPABASE_SERVICE_ROLE_KEY']);

function validateLease(lease, ref, now, maxLifetimeMs) {
  if (!lease || typeof lease !== 'object') throw new Error('CREDENTIAL_LEASE_NOT_FOUND');
  if (lease.ref !== ref) throw new Error('CREDENTIAL_LEASE_REF_MISMATCH');
  if (lease.revoked === true) throw new Error('CREDENTIAL_LEASE_REVOKED');
  const expiresAt = Date.parse(lease.expiresAt ?? '');
  if (!Number.isFinite(expiresAt) || expiresAt <= now.getTime()) throw new Error('CREDENTIAL_LEASE_EXPIRED');
  if (expiresAt - now.getTime() > maxLifetimeMs) throw new Error('CREDENTIAL_LEASE_TOO_LONG');
  if (typeof lease.scope !== 'string' || lease.scope.length < 1 || lease.scope.length > 200) throw new Error('CREDENTIAL_LEASE_SCOPE_REQUIRED');
  if (!lease.environment || typeof lease.environment !== 'object' || Array.isArray(lease.environment)) throw new Error('CREDENTIAL_LEASE_ENV_REQUIRED');
  const entries = Object.entries(lease.environment);
  if (!entries.length || entries.length > 16) throw new Error('CREDENTIAL_LEASE_ENV_INVALID');
  for (const [name, value] of entries) {
    if (!SAFE_ENV.test(name) || typeof value !== 'string' || value.length < 1 || value.length > 8192) throw new Error('CREDENTIAL_LEASE_ENV_INVALID');
    if (FORBIDDEN_PERSISTENCE.has(name) && lease.credentialClass !== 'temporary_scoped') throw new Error('STANDING_PROVIDER_CREDENTIAL_FORBIDDEN');
  }
  return { ...lease, expiresAt, environment: Object.fromEntries(entries) };
}

function createCredentialLeaseManager({ resolveLease, releaseLease = async () => {}, clock = () => new Date(), maxLifetimeMs = 60 * 60_000 }) {
  if (typeof resolveLease !== 'function') throw new Error('CREDENTIAL_RESOLVER_REQUIRED');
  if (typeof releaseLease !== 'function') throw new Error('CREDENTIAL_RELEASE_REQUIRED');
  const active = new Map();

  return Object.freeze({
    async acquire(refs = []) {
      if (!Array.isArray(refs) || refs.length > 16) throw new Error('INVALID_CREDENTIAL_LEASE_REFS');
      const environment = {};
      const redactionValues = [];
      const acquired = [];
      try {
        for (const ref of refs) {
          if (typeof ref !== 'string' || ref.length < 1 || active.has(ref)) throw new Error('INVALID_CREDENTIAL_LEASE_REF');
          const lease = validateLease(await resolveLease(ref), ref, clock(), maxLifetimeMs);
          active.set(ref, lease);
          acquired.push(ref);
          for (const [name, value] of Object.entries(lease.environment)) {
            if (Object.hasOwn(environment, name) && environment[name] !== value) throw new Error('CREDENTIAL_ENV_COLLISION');
            environment[name] = value;
            redactionValues.push(value);
          }
        }
        return Object.freeze({ environment: Object.freeze({ ...environment }), redactionValues: Object.freeze([...redactionValues]), refs: Object.freeze([...acquired]) });
      } catch (error) {
        await Promise.allSettled(acquired.map((ref) => releaseLease(ref)));
        for (const ref of acquired) active.delete(ref);
        throw error;
      }
    },
    async release(refs = [...active.keys()]) {
      const unique = [...new Set(refs)];
      await Promise.allSettled(unique.map((ref) => releaseLease(ref)));
      for (const ref of unique) active.delete(ref);
      return { released: unique.length };
    },
    activeRefs() {
      return Object.freeze([...active.keys()]);
    },
  });
}

async function withCredentialLeases(manager, refs, fn) {
  const leaseSet = await manager.acquire(refs);
  try {
    return await fn(leaseSet);
  } finally {
    await manager.release(leaseSet.refs);
  }
}

export { createCredentialLeaseManager, withCredentialLeases };
