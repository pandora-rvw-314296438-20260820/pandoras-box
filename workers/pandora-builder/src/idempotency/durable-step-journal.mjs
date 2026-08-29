import { createHash } from 'node:crypto';

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
}

function digest(value) {
  return createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');
}

function createDurableStepJournal({ store, clock = () => new Date() }) {
  if (!store || typeof store.get !== 'function' || typeof store.put !== 'function') throw new Error('STEP_STORE_REQUIRED');

  return Object.freeze({
    async prepare({ stepKey, idempotencyKey, input, leaseExpiresAt = null }) {
      if (typeof stepKey !== 'string' || typeof idempotencyKey !== 'string') throw new Error('STEP_IDENTITY_REQUIRED');
      const inputSha256 = digest(input);
      const existing = await store.get(stepKey, idempotencyKey);
      if (!existing) return { action: 'execute', inputSha256 };
      if (existing.inputSha256 !== inputSha256) throw new Error('IDEMPOTENCY_CONFLICT');
      if (existing.status === 'completed') return { action: 'replay', inputSha256, result: existing.result, resultSha256: existing.resultSha256 };
      if (existing.status === 'running') {
        const expiry = Date.parse(existing.leaseExpiresAt ?? leaseExpiresAt ?? '');
        if (!Number.isFinite(expiry) || expiry <= clock().getTime()) return { action: 'ambiguous', inputSha256, reason: 'LEASE_EXPIRED_OUTCOME_UNKNOWN' };
        return { action: 'in_progress', inputSha256 };
      }
      if (existing.status === 'failed' && existing.retryable === true && (existing.attemptCount ?? 1) < (existing.maxAttempts ?? 1)) {
        return { action: 'execute', inputSha256, retryOf: existing.resultSha256 ?? null };
      }
      return { action: 'blocked', inputSha256, reason: existing.status === 'failed' ? 'NON_RETRYABLE_FAILURE' : 'STEP_STATE_BLOCKED' };
    },
    async begin({ stepKey, idempotencyKey, inputSha256, attemptCount, maxAttempts, leaseExpiresAt }) {
      const record = { status: 'running', stepKey, idempotencyKey, inputSha256, attemptCount, maxAttempts, leaseExpiresAt, startedAt: clock().toISOString() };
      await store.put(record);
      return record;
    },
    async complete({ stepKey, idempotencyKey, inputSha256, result }) {
      const resultSha256 = digest(result);
      const record = { status: 'completed', stepKey, idempotencyKey, inputSha256, resultSha256, result: structuredClone(result), completedAt: clock().toISOString() };
      await store.put(record);
      return record;
    },
    async fail({ stepKey, idempotencyKey, inputSha256, failureClass, retryable, attemptCount, maxAttempts }) {
      const result = { failureClass, retryable: Boolean(retryable), attemptCount, maxAttempts };
      const record = { status: 'failed', stepKey, idempotencyKey, inputSha256, resultSha256: digest(result), result, retryable: Boolean(retryable), attemptCount, maxAttempts, completedAt: clock().toISOString() };
      await store.put(record);
      return record;
    },
    digest,
  });
}

export { createDurableStepJournal, digest as durableStepDigest };
