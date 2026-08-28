const SAFE_ENV = /^[A-Z][A-Z0-9_]{0,63}$/;

async function withCredentialLeases({ leaseRefs = [], resolver, allowedEnv = [], execute }) {
  if (typeof resolver !== 'function' || typeof execute !== 'function') throw new Error('CREDENTIAL_LEASE_RUNTIME_REQUIRED');
  const allowed = new Set(allowedEnv); const claimedEnv = new Set();
  const env = {}; const secrets = []; const cleanups = [];
  try {
    for (const ref of leaseRefs) {
      if (!ref || typeof ref !== 'object' || !ref.leaseId || !SAFE_ENV.test(ref.envName ?? '') || !allowed.has(ref.envName) || claimedEnv.has(ref.envName)) throw new Error('CREDENTIAL_LEASE_SCOPE_DENIED');
      claimedEnv.add(ref.envName);
      const lease = await resolver(ref.leaseId);
      const revoke = typeof lease?.revoke === 'function' ? lease.revoke : null;
      if (!lease || lease.scope !== ref.scope || typeof lease.value !== 'string' || !lease.value || !Number.isFinite(new Date(lease.expiresAt).getTime()) || new Date(lease.expiresAt).getTime() <= Date.now()) {
        if (revoke) { try { await revoke(); } catch {} }
        throw new Error('CREDENTIAL_LEASE_INVALID_OR_EXPIRED');
      }
      env[ref.envName] = lease.value; secrets.push(lease.value);
      if (revoke) cleanups.push(revoke);
    }
    return await execute(Object.freeze({ env: Object.freeze({ ...env }), redact: Object.freeze([...secrets]) }));
  } finally {
    for (const key of Object.keys(env)) env[key] = '';
    for (const revoke of cleanups.reverse()) { try { await revoke(); } catch {} }
    secrets.fill('');
  }
}

export { withCredentialLeases };
