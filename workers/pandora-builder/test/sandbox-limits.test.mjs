import assert from 'node:assert/strict';
import test from 'node:test';
import { SandboxManager } from '../src/sandbox/sandbox-manager.mjs';
import { providerLimitSupport, resourceLimitFailure } from '../src/limits/resource-limits.mjs';

test('sandbox manager is provider-independent', async () => {
  const calls = [];
  const provider = Object.fromEntries(['create','resume','execute','cancel','destroy','inspect'].map((method) => [method, async (...args) => { calls.push([method, ...args]); return method; }]));
  const manager = new SandboxManager({ provider });
  assert.equal(await manager.create({ id: 1 }), 'create');
  assert.equal(await manager.execute('handle', { operation: 'build_project' }), 'execute');
  assert.deepEqual(calls.map(([name]) => name), ['create', 'execute']);
});

test('reports unsupported provider limits instead of pretending enforcement', () => {
  const support = providerLimitSupport({ wallClock: true, output: true }, { cpuMillis: 1, memoryBytes: 1, diskBytes: 1, processCount: 1, wallClockMs: 1, outputBytes: 1 });
  assert.equal(support.enforceable, false);
  assert.deepEqual(support.unsupported.sort(), ['cpu','disk','memory','processCount'].sort());
  assert.equal(resourceLimitFailure('memory').failureClass, 'resource_limit');
});
