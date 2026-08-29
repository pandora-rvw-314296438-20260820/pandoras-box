import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { executeBuildPipeline } from '../src/execution/build-pipeline.mjs';

const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

function request(root) {
  return {
    schemaVersion: 1,
    executionId: uuid(1), buildJobId: uuid(2), projectId: uuid(3), organizationId: uuid(4), projectVersionId: uuid(5),
    source: { kind: 'artifact_snapshot', artifactId: 'source-artifact', sha256: 'a'.repeat(64) },
    authorizedCapability: 'build.project.execute', operation: 'build_project', environment: 'sandbox', timeoutMs: 10_000,
    resourceLimits: { wallClockMs: 10_000, cpuMillis: 10_000, memoryBytes: 128 * 1024 ** 2, diskBytes: 128 * 1024 ** 2, processCount: 16, outputBytes: 4096, fileCount: 100, artifactBytes: 1024 * 1024, dependencyInstallMs: 5000 },
    networkPolicy: { mode: 'deny', allow: [] }, credentialLeaseRefs: [], idempotencyKey: 'pipeline-test', attempt: 1, arguments: { root },
  };
}

test('static disposable build produces source-bound artifact manifest and truthful events', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'pandora-build-pipeline-'));
  const raw = request(root);
  const events = [];
  let sandboxCalls = 0;
  const result = await executeBuildPipeline({
    request: raw,
    gatewayAuthorization: { tool: 'request_build', version: 1, capability: 'build.execute', authorizationId: 'auth-1', idempotencyKey: raw.idempotencyKey, projectId: raw.projectId, projectVersionId: raw.projectVersionId, environment: 'preview' },
    workspace: { root },
    materializer: { materialize: async () => { await writeFile(path.join(root, 'index.html'), '<h1>Pandora</h1>'); return { sha256: 'a'.repeat(64) }; } },
    sandbox: { execute: async () => { sandboxCalls += 1; return { status: 'completed', exitCode: 0, stdout: { text: '' }, stderr: { text: '' } }; } },
    projectMetadata: { buildAdapter: 'static-web' }, filenames: ['index.html'], toolchainInventory: {}, eventSink: (e) => events.push(e),
  });
  assert.equal(result.status, 'completed');
  assert.equal(sandboxCalls, 0);
  assert.match(result.artifacts.artifacts[0].digest, /^[0-9a-f]{64}$/);
  assert.match(result.manifest.manifestSha256, /^[0-9a-f]{64}$/);
  assert.equal(result.manifest.sourceDigest.length, 64);
  assert.equal(events.at(-1).stage, 'ready_for_verification');
  assert.deepEqual(events.map((e) => e.sequence), events.map((_, i) => i + 1));
});

test('pipeline fails closed before dependency execution when network permission is absent', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'pandora-build-network-'));
  const raw = request(root);
  let calls = 0;
  await assert.rejects(() => executeBuildPipeline({
    request: raw,
    gatewayAuthorization: { tool: 'request_build', version: 1, capability: 'build.execute', authorizationId: 'auth-2', idempotencyKey: raw.idempotencyKey, projectId: raw.projectId, projectVersionId: raw.projectVersionId, environment: 'preview' },
    workspace: { root }, materializer: { materialize: async () => ({ sha256: 'a'.repeat(64) }) },
    sandbox: { execute: async () => { calls += 1; return { status: 'completed', exitCode: 0, stdout: { text: '' }, stderr: { text: '' } }; } },
    projectMetadata: { buildAdapter: 'node-vite-web' }, filenames: ['package.json', 'package-lock.json'], packageJson: { dependencies: { vite: '1.0.0' }, scripts: {} }, toolchainInventory: { node: '24.1.0' },
  }), /NETWORK_POLICY_DENIES_REQUIRED_HOST/);
  assert.equal(calls, 0);
});
