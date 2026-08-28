import { createHash, randomBytes } from 'node:crypto';

function createLeaseIdentity({ jobId, workerIdentity, leaseSeconds = 300 }) {
  if (!jobId || !workerIdentity || !Number.isInteger(leaseSeconds) || leaseSeconds < 30 || leaseSeconds > 1800) throw new Error('INVALID_LEASE_IDENTITY');
  const entropy = randomBytes(32);
  const leaseTokenSha256 = createHash('sha256').update(entropy).digest('hex');
  entropy.fill(0);
  return Object.freeze({ jobId, workerIdentity, leaseTokenSha256, leaseSeconds });
}

export { createLeaseIdentity };
