import test from 'node:test';
import assert from 'node:assert/strict';
import { executeTrustedCommand, installDependencies } from '../src/execution/operation-executor.mjs';
import { ADAPTERS } from '../src/adapters/adapter-registry.mjs';

const limits = { wallClockMs: 1000, dependencyInstallMs: 1000, outputBytes: 4096 };
const completed = { status: 'completed', exitCode: 0, stdout: { text: '' }, stderr: { text: '' } };

test('generic shell executables are never accepted', async () => {
  const sandbox = { execute: async () => completed };
  await assert.rejects(() => executeTrustedCommand({ sandbox, command: { executable: 'bash', args: ['-c', 'echo nope'] }, workspaceRoot: '/work', env: {}, limits, networkPolicy: { mode: 'deny', allow: [] } }), /GENERIC_SHELL_FORBIDDEN/);
});

test('dependency execution derives fixed argv from trusted adapter and requires authorized registry', async () => {
  const calls = [];
  const sandbox = { execute: async (value) => { calls.push(value); return completed; } };
  await assert.rejects(() => installDependencies({ sandbox, adapter: ADAPTERS['node-vite-web'], filenames: ['package.json', 'package-lock.json'], workspaceRoot: '/work', env: {}, limits, networkPolicy: { mode: 'deny', allow: [] } }), /NETWORK_POLICY_DENIES_REQUIRED_HOST/);
  const result = await installDependencies({ sandbox, adapter: ADAPTERS['node-vite-web'], filenames: ['package.json', 'package-lock.json'], workspaceRoot: '/work', env: {}, limits, networkPolicy: { mode: 'allowlist', allow: ['registry.npmjs.org'] } });
  assert.equal(result.status, 'completed');
  assert.equal(calls[0].executable, 'npm');
  assert.deepEqual(calls[0].args, ['ci', '--ignore-scripts', '--no-audit', '--no-fund']);
  assert.equal(calls[0].networkPolicy.mode, 'allowlist');
});
