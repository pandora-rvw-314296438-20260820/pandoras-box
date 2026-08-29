import { createHash, timingSafeEqual } from 'node:crypto';

const TERMINAL = new Set(['succeeded', 'failed', 'cancelled']);
const ACTIVE = new Set(['claimed', 'running']);

function sha256Hex(value) {
  if (typeof value !== 'string' || value.length < 16) throw new Error('INVALID_LEASE_TOKEN');
  return createHash('sha256').update(value).digest('hex');
}

function secureEqualHex(a, b) {
  if (!/^[0-9a-f]{64}$/.test(a ?? '') || !/^[0-9a-f]{64}$/.test(b ?? '')) return false;
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

function assertLeaseOwnership({ job, workerIdentity, leaseToken, now = new Date() }) {
  if (!job || typeof job !== 'object') throw new Error('BUILD_JOB_REQUIRED');
  if (!ACTIVE.has(job.status)) throw new Error('BUILD_JOB_NOT_LEASED');
  if (job.lease_owner !== workerIdentity) throw new Error('LEASE_OWNER_MISMATCH');
  const digest = sha256Hex(leaseToken);
  if (!secureEqualHex(digest, job.lease_token_sha256)) throw new Error('LEASE_TOKEN_MISMATCH');
  const expires = Date.parse(job.lease_expires_at ?? '');
  if (!Number.isFinite(expires) || expires <= now.getTime()) throw new Error('LEASE_EXPIRED');
  return true;
}

function createWorkerAControlPlane({ rpc, workerIdentity, leaseSeconds = 300, loadJob = null, persistEvent = null, clock = () => new Date() }) {
  if (typeof rpc !== 'function') throw new Error('CONTROL_PLANE_RPC_REQUIRED');
  if (typeof workerIdentity !== 'string' || workerIdentity.length < 3) throw new Error('WORKER_IDENTITY_REQUIRED');
  if (!Number.isInteger(leaseSeconds) || leaseSeconds < 30 || leaseSeconds > 3600) throw new Error('INVALID_LEASE_SECONDS');

  const invoke = (name, args) => rpc(name, args);

  return Object.freeze({
    workerIdentity,
    leaseSeconds,
    async claim(jobId, leaseToken) {
      return invoke('pandora_claim_build_job', {
        p_job_id: jobId,
        p_worker_identity: workerIdentity,
        p_lease_token_sha256: sha256Hex(leaseToken),
        p_lease_seconds: leaseSeconds,
      });
    },
    async heartbeat(jobId, leaseToken) {
      return invoke('pandora_heartbeat_build_job', {
        p_job_id: jobId,
        p_worker_identity: workerIdentity,
        p_lease_token_sha256: sha256Hex(leaseToken),
        p_lease_seconds: leaseSeconds,
      });
    },
    async requeueExpired(limit = 100) {
      if (!Number.isInteger(limit) || limit < 1 || limit > 1000) throw new Error('INVALID_REQUEUE_LIMIT');
      return invoke('pandora_requeue_expired_build_jobs', { p_limit: limit });
    },
    async load(jobId) {
      if (typeof loadJob !== 'function') throw new Error('CONTROL_PLANE_LOAD_UNAVAILABLE');
      return loadJob(jobId);
    },
    async cancellationRequested(jobId) {
      if (typeof loadJob !== 'function') return false;
      const job = await loadJob(jobId);
      return Boolean(job?.cancel_requested_at) || job?.status === 'cancelled';
    },
    async checkpoint(event) {
      if (typeof persistEvent !== 'function') return null;
      const safeEvent = structuredClone(event);
      if ('credentials' in safeEvent || 'secrets' in safeEvent || 'token' in safeEvent || 'apiKey' in safeEvent) {
        throw new Error('UNSAFE_EVENT_PAYLOAD');
      }
      return persistEvent(safeEvent);
    },
    assertLease(job, leaseToken) {
      return assertLeaseOwnership({ job, workerIdentity, leaseToken, now: clock() });
    },
    isTerminal(status) {
      return TERMINAL.has(status);
    },
  });
}

export { assertLeaseOwnership, createWorkerAControlPlane, sha256Hex };
