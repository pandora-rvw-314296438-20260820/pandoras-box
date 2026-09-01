import test from 'node:test';
import assert from 'node:assert/strict';
import { executeManagedBuild } from '../src/execution/managed-build-runtime.mjs';
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

test('durable checkpoint precedes customer projection', async () => {
  const order = [];
  const result = await executeManagedBuild({
    request: { buildJobId: uuid(2), projectId: uuid(3), organizationId: uuid(4), idempotencyKey: 'trust-order', attempt: 1, credentialLeaseRefs: [] },
    leaseToken: 'lease-token-1234567890',
    controlPlane: { leaseSeconds: 300, claim: async () => {}, heartbeat: async () => {}, cancellationRequested: async () => false, checkpoint: async () => order.push('durable') },
    admissionController: { decide: () => ({ admitted: true }) }, admissionSnapshot: {},
    journal: { prepare: async () => ({ action: 'execute', inputSha256: 'a'.repeat(64) }), begin: async () => {}, complete: async () => {}, fail: async () => {} },
    credentialManager: { acquire: async () => ({ environment: {}, redactionValues: [], refs: [] }), release: async () => {} },
    execute: async ({ eventSink }) => { await eventSink({ eventType: 'command_completed', safePayload: { status: 'completed' } }); return { status: 'completed' }; },
    eventSink: async () => order.push('projection'), heartbeatIntervalMs: 60_000,
  });
  assert.equal(result.status, 'completed');
  assert.deepEqual(order, ['durable', 'projection']);
});
