import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizedEnvironment } from '../src/environment/environment-policy.mjs';
import { networkDecision } from '../src/network/network-policy.mjs';
import { runSupervised } from '../src/process/process-supervisor.mjs';

test('environment does not inherit provider secrets', () => {
  const env = normalizedEnvironment({ hostEnv: { PATH: '/bin', GITHUB_TOKEN: 'secret', SUPABASE_SERVICE_ROLE_KEY: 'secret' } });
  assert.equal(env.PATH, '/bin');
  assert.equal(env.GITHUB_TOKEN, undefined);
  assert.equal(env.SUPABASE_SERVICE_ROLE_KEY, undefined);
});

test('metadata endpoints are denied even under allowlist policy', () => {
  assert.equal(networkDecision({ mode: 'allowlist', allow: ['169.254.169.254'] }, 'http://169.254.169.254/latest/meta-data').allowed, false);
});

test('argv metacharacters are data because shell is disabled', async () => {
  const result = await runSupervised({
    command: process.execPath,
    args: ['-e', 'console.log(process.argv[1])', '; echo PWNED'],
    cwd: process.cwd(),
    env: process.env,
    timeoutMs: 10_000,
    maxOutputBytes: 16_384,
  });
  assert.equal(result.status, 'completed');
  assert.match(result.stdout.text, /; echo PWNED/);
  assert.doesNotMatch(result.stdout.text, /^PWNED$/m);
});

test('supervisor enforces timeout', async () => {
  const result = await runSupervised({
    command: process.execPath,
    args: ['-e', 'setInterval(() => {}, 1000)'],
    cwd: process.cwd(),
    env: process.env,
    timeoutMs: 50,
    maxOutputBytes: 16_384,
  });
  assert.equal(result.status, 'failed');
  assert.equal(result.failureClass, 'timeout');
});

test('supervisor bounds output', async () => {
  const result = await runSupervised({
    command: process.execPath,
    args: ['-e', 'process.stdout.write("x".repeat(100000))'],
    cwd: process.cwd(),
    env: process.env,
    timeoutMs: 10_000,
    maxOutputBytes: 1024,
  });
  assert.equal(result.failureClass, 'resource_limit');
  assert.ok(result.stdout.bytes <= 1024);
});
