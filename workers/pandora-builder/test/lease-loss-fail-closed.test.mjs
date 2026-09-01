import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorkerAControlPlane } from '../src/control/worker-a-control-plane.mjs';

const jobId = '00000000-0000-4000-8000-000000000001';
const token = 'lease-token-1234567890';

test('Worker A heartbeat fails closed after lease ownership is lost', async () => {
  const control = createWorkerAControlPlane({
    workerIdentity: 'worker-d-stale',
    rpc: async (name) => name === 'pandora_heartbeat_build_job' ? false : true,
  });
  await assert.rejects(() => control.heartbeat(jobId, token), /LEASE_LOST/);
});

test('Worker A heartbeat accepts only an explicit authoritative renewal', async () => {
  const control = createWorkerAControlPlane({
    workerIdentity: 'worker-d-current',
    rpc: async (name) => name === 'pandora_heartbeat_build_job' ? true : true,
  });
  assert.equal(await control.heartbeat(jobId, token), true);
});

test('Worker A lease duration matches the database authority boundary', () => {
  assert.doesNotThrow(() => createWorkerAControlPlane({ workerIdentity: 'worker-d-ok', leaseSeconds: 1800, rpc: async () => true }));
  assert.throws(() => createWorkerAControlPlane({ workerIdentity: 'worker-d-too-long', leaseSeconds: 1801, rpc: async () => true }), /INVALID_LEASE_SECONDS/);
});
