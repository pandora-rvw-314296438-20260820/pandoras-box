
import test from 'node:test';
import assert from 'node:assert/strict';
import { VercelSandboxProvider, vercelSandboxNetworkPolicy } from '../src/sandbox/vercel-sandbox-provider.mjs';

const ids = {
  executionId: '11111111-1111-4111-8111-111111111111',
  buildJobId: '22222222-2222-4222-8222-222222222222',
  projectId: '33333333-3333-4333-8333-333333333333',
  organizationId: '44444444-4444-4444-8444-444444444444',
  versionId: '55555555-5555-4555-8555-555555555555',
};

function request(overrides = {}) {
  return {
    schemaVersion: 1,
    executionId: ids.executionId,
    buildJobId: ids.buildJobId,
    projectId: ids.projectId,
    organizationId: ids.organizationId,
    projectVersionId: ids.versionId,
    source: { kind: 'git_commit', repository: 'pandora-rvw-314296438-20260820/pandoras-box', commitSha: 'a'.repeat(40) },
    authorizedCapability: 'build.project.execute',
    operation: 'build_project',
    environment: 'preview-build',
    timeoutMs: 60_000,
    resourceLimits: { wallClockMs: 60_000, memoryBytes: 512 * 1024 ** 2 },
    networkPolicy: { mode: 'deny' },
    credentialLeaseRefs: [],
    idempotencyKey: 'build:test:1',
    attempt: 1,
    arguments: {},
    ...overrides,
  };
}

class FakeTransport {
  constructor() { this.calls = []; this.polls = 0; }
  async request(method, path, body) {
    this.calls.push({ method, path, body });
    if (method === 'POST' && path.startsWith('/v2/sandboxes?')) {
      return { status: 200, body: { sandbox: { name: body.name }, session: { id: 'sbx_ABC123', cwd: '/vercel/sandbox', status: 'running' } } };
    }
    if (method === 'POST' && /\/cmd\?/.test(path)) {
      return { status: 200, body: { command: { id: path.match(/cmdId=(cmd_[^&]+)/)?.[1] ?? 'cmd_A', exitCode: null } } };
    }
    if (method === 'GET' && /\/cmd\/cmd_/.test(path)) {
      this.polls += 1;
      return { status: 200, body: { command: { id: path.match(/\/cmd\/(cmd_[^?]+)/)[1], exitCode: this.polls >= 1 ? 0 : null, durationMs: 12 } } };
    }
    if (method === 'POST' && path.includes('/stop?')) return { status: 200, body: { session: { status: 'stopped' } } };
    if (method === 'DELETE' && path.startsWith('/v2/sandboxes/')) return { status: 200, body: { sandbox: {} } };
    if (method === 'GET' && path.startsWith('/v2/sandboxes/')) return { status: 200, body: { sandbox: { name: 'pandora-d-11111111111141118111111111111111' }, session: { id: 'sbx_ABC123', cwd: '/vercel/sandbox', status: 'running' } } };
    return { status: 500, body: { error: { message: `${method} ${path}` } } };
  }
}

test('maps Worker D deny policy to a non-persistent deny-all microVM without credentials', async () => {
  const transport = new FakeTransport();
  const provider = new VercelSandboxProvider({ transport, teamId: 'team_ABC', projectId: 'prj_ABCDE', pollIntervalMs: 50 });
  const handle = await provider.create(request());
  assert.equal(handle.sessionId, 'sbx_ABC123');
  const create = transport.calls[0];
  assert.equal(create.body.persistent, false);
  assert.equal(create.body.networkPolicy.mode, 'deny-all');
  assert.deepEqual(create.body.env, {});
  assert.equal(create.body.ports.length, 0);
  assert.equal(typeof create.body.resources.vcpus, 'number');
  assert.equal(typeof create.body.resources.memory, 'number');
  assert.equal(typeof create.body.timeout, 'number');
  assert.equal(JSON.stringify(create.body).match(/token|password|api.?key|authorization/gi), null);
});

test('executes only a bounded direct executable with sudo disabled', async () => {
  const transport = new FakeTransport();
  const provider = new VercelSandboxProvider({ transport, teamId: 'team_ABC', projectId: 'prj_ABCDE', pollIntervalMs: 50 });
  const handle = await provider.create(request());
  const result = await provider.execute(handle, { executable: 'npm', args: ['test'], cwd: '/vercel/sandbox', env: { NODE_ENV: 'test' }, timeoutMs: 30_000 });
  assert.equal(result.status, 'completed');
  assert.equal(result.exitCode, 0);
  const exec = transport.calls.find((call) => call.method === 'POST' && call.path.includes('/cmd?'));
  assert.equal(exec.body.sudo, false);
  assert.equal(exec.body.wait, false);
  assert.equal(exec.body.logs, false);
  const poll = transport.calls.find((call) => call.method === 'GET' && call.path.includes('/cmd/cmd_'));
  assert.ok(poll);
  assert.match(poll.path, /[?&]wait=true(?:&|$)/);
});

test('fails closed for shell execution, secret-shaped env and production authority', async () => {
  const transport = new FakeTransport();
  const provider = new VercelSandboxProvider({ transport, teamId: 'team_ABC', projectId: 'prj_ABCDE' });
  const handle = await provider.create(request());
  await assert.rejects(() => provider.execute(handle, { executable: 'sh', args: ['-c','echo no'], env: {} }), /GENERIC_SHELL_FORBIDDEN/);
  await assert.rejects(() => provider.execute(handle, { executable: 'node', args: ['app.js'], env: { API_KEY: 'fake' } }), /SANDBOX_CREDENTIAL_ENV_FORBIDDEN/);
  await assert.rejects(() => provider.create(request({ environment: 'production' })), /ENVIRONMENT_NOT_ALLOWED/);
});

test('allowlist network policy remains explicit and host-only', () => {
  assert.deepEqual(vercelSandboxNetworkPolicy({ mode: 'allowlist', allow: ['github.com','registry.npmjs.org'] }), {
    mode: 'custom', allowedDomains: ['github.com','registry.npmjs.org'], allowedCIDRs: [], deniedCIDRs: [],
  });
  assert.throws(() => vercelSandboxNetworkPolicy({ mode: 'allowlist', allow: ['https://github.com/path'] }), /INVALID_NETWORK_POLICY_HOST/);
});
