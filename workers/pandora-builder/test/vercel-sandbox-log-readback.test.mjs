import test from 'node:test';
import assert from 'node:assert/strict';
import { VercelSandboxProvider, parseCommandLogResponse } from '../src/sandbox/vercel-sandbox-provider.mjs';

const ids = {
  executionId: '11111111-1111-4111-8111-111111111111',
  buildJobId: '22222222-2222-4222-8222-222222222222',
  projectId: '33333333-3333-4333-8333-333333333333',
  organizationId: '44444444-4444-4444-8444-444444444444',
  versionId: '55555555-5555-4555-8555-555555555555',
};

function request() {
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
    resourceLimits: { wallClockMs: 60_000, memoryBytes: 2 * 1024 ** 3 },
    networkPolicy: { mode: 'deny' },
    credentialLeaseRefs: [],
    idempotencyKey: 'build:log-readback:1',
    attempt: 1,
    arguments: {},
  };
}

class FakeTransport {
  constructor() { this.calls = []; }
  async request(method, path, body) {
    this.calls.push({ method, path, body });
    if (method === 'POST' && path.startsWith('/v2/sandboxes?')) {
      return { status: 200, body: { sandbox: { name: body.name }, session: { id: 'sbx_ABC123', cwd: '/vercel/sandbox', status: 'running' } } };
    }
    if (method === 'POST' && /\/cmd\?/.test(path)) {
      return { status: 200, body: { command: { id: path.match(/cmdId=(cmd_[^&]+)/)?.[1] ?? 'cmd_A', exitCode: null } } };
    }
    if (method === 'GET' && /\/cmd\/cmd_[^?]+\/logs\?/.test(path)) {
      return {
        status: 200,
        body: {
          raw: [
            JSON.stringify({ stream: 'stdout', data: { message: 'real compiler output\n' } }),
            JSON.stringify({ stream: 'stderr', data: { message: 'src/app.ts:4:2 - error TS2304: missing\n' } }),
          ].join('\n'),
        },
      };
    }
    if (method === 'GET' && /\/cmd\/cmd_/.test(path)) {
      return { status: 200, body: { command: { id: path.match(/\/cmd\/(cmd_[^?]+)/)[1], exitCode: 1, durationMs: 12 } } };
    }
    return { status: 500, body: { error: { message: `${method} ${path}` } } };
  }
}

test('completed command reads back the exact Vercel command logs before returning result', async () => {
  const transport = new FakeTransport();
  const provider = new VercelSandboxProvider({ transport, teamId: 'team_ABC', projectId: 'prj_ABCDE', pollIntervalMs: 50 });
  const handle = await provider.create(request());
  const result = await provider.execute(handle, {
    executable: 'npm',
    args: ['run', 'build'],
    cwd: '/vercel/sandbox',
    env: {},
    timeoutMs: 30_000,
    maxOutputBytes: 4096,
  });
  assert.equal(result.status, 'failed');
  assert.equal(result.exitCode, 1);
  assert.equal(result.outputReadback, 'completed');
  assert.equal(result.stdout.text, 'real compiler output\n');
  assert.match(result.stderr.text, /TS2304/);
  const start = transport.calls.find((call) => call.method === 'POST' && call.path.includes('/cmd?'));
  assert.equal(start.body.logs, false);
  assert.equal(start.body.sudo, false);
  assert.ok(transport.calls.some((call) => call.method === 'GET' && /\/logs\?/.test(call.path)));
});

test('ND-JSON command output parser separates streams, ignores malformed rows and caps bytes', () => {
  const parsed = parseCommandLogResponse({
    raw: [
      '{not-json}',
      JSON.stringify({ stream: 'stdout', data: { message: 'a'.repeat(900) } }),
      JSON.stringify({ stream: 'stdout', data: { message: 'b'.repeat(900) } }),
      JSON.stringify({ stream: 'error', data: { message: 'provider stream note' } }),
    ].join('\n'),
  }, 1024);
  assert.equal(parsed.parseErrors, 1);
  assert.equal(Buffer.byteLength(parsed.stdout) <= 1024, true);
  assert.equal(parsed.truncated, true);
  assert.match(parsed.stderr, /provider stream note/);
});
