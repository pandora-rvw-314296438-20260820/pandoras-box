import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { collectArtifacts, changedFileManifest } from '../src/artifacts/artifact-collector.mjs';
import { createCacheManifest, validateCacheManifest } from '../src/cache/cache-integrity.mjs';
import { assertWorkerCAuthorization } from '../src/contracts/authorized-build-request.mjs';
import { redactText } from '../src/logs/log-records.mjs';
import { networkDecision } from '../src/network/network-policy.mjs';
import { createGitMaterializationPlan } from '../src/source/source-materializer.mjs';
import { validateToolchainInventory } from '../src/toolchains/toolchain-policy.mjs';
import { ADAPTERS } from '../src/adapters/adapter-registry.mjs';

const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

test('git materialization is exact-SHA, hook-disabled and credentialless', () => {
  const sha = 'a'.repeat(40);
  const plan = createGitMaterializationPlan({ kind: 'git_commit', repository: 'owner/repo', commitSha: sha });
  assert.equal(plan.commands.at(-1).verifyStdout, sha);
  assert.equal(plan.submodules, 'forbidden');
  assert.equal(plan.credentialPersistence, 'disabled');
  assert.ok(plan.commands.flatMap((x) => x.args).includes('credential.helper='));
  assert.ok(plan.commands.flatMap((x) => x.args).includes('core.hooksPath=.pandora/no-hooks'));
});

test('artifact collector rejects symlink outputs and creates deterministic digest', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'pandora-artifacts-'));
  await mkdir(path.join(root, 'dist'));
  await writeFile(path.join(root, 'dist', 'index.html'), 'hello');
  const first = await collectArtifacts({ workspaceRoot: root, outputs: [{ path: 'dist', kind: 'directory' }] });
  const second = await collectArtifacts({ workspaceRoot: root, outputs: [{ path: 'dist', kind: 'directory' }] });
  assert.equal(first.artifacts[0].digest, second.artifacts[0].digest);
  await symlink(path.join(root, 'dist', 'index.html'), path.join(root, 'escape'));
  await assert.rejects(() => collectArtifacts({ workspaceRoot: root, outputs: [{ path: 'escape', kind: 'file' }] }), /ARTIFACT_SYMLINK_FORBIDDEN/);
});

test('changed-file manifest records lineage and cache manifest rejects tampering', () => {
  assert.deepEqual(changedFileManifest({ 'a.txt': '1', 'b.txt': '2' }, { 'a.txt': '3', 'c.txt': '4' }).map((x) => x.operation), ['modify', 'delete', 'create']);
  const expected = { cacheKey: 'cache', scope: 'org:project', sourceDigest: 's', lockfileDigest: 'l', adapter: { id: 'static-web', version: '1.0.0' }, toolchainDigest: 't' };
  const manifest = createCacheManifest({ ...expected, entries: [{ path: 'x', sha256: 'a'.repeat(64), sizeBytes: 1 }] });
  assert.equal(validateCacheManifest(manifest, expected), true);
  assert.throws(() => validateCacheManifest({ ...manifest, entries: [] }, expected), /CACHE_MANIFEST_TAMPERED/);
});

test('authorization is exact project scope and production is forbidden', () => {
  const request = { projectId: uuid(1), projectVersionId: uuid(2), environment: 'sandbox' };
  const gateway = { tool: 'request_build', version: 1, capability: 'build.execute', authorizationId: 'auth-1', idempotencyKey: 'idem-12345678', projectId: uuid(1), projectVersionId: uuid(2), environment: 'preview' };
  assert.equal(assertWorkerCAuthorization({ gateway, request }).capability, 'build.execute');
  assert.throws(() => assertWorkerCAuthorization({ gateway: { ...gateway, projectId: uuid(3) }, request }), /PROJECT_SCOPE_MISMATCH/);
  assert.throws(() => assertWorkerCAuthorization({ gateway: { ...gateway, environment: 'production' }, request }), /PRODUCTION_FORBIDDEN/);
});

test('metadata endpoints remain blocked and secrets are redacted', () => {
  assert.equal(networkDecision({ mode: 'allowlist', allow: ['169.254.169.254'] }, '169.254.169.254').allowed, false);
  const secret = 'super-secret-value';
  const redacted = redactText(`Bearer abc.def ${secret} api_key=abcd1234`, [secret]);
  assert.ok(!redacted.includes(secret));
  assert.ok(!redacted.includes('abc.def'));
  assert.ok(!redacted.includes('abcd1234'));
});

test('toolchain policy pins current supported Flutter Android toolchain', () => {
  const inventory = validateToolchainInventory(ADAPTERS['flutter-android-apk'], { flutter: '3.47.0 stable', java: 'openjdk 17.0.20', androidPlatform: 'android-36', androidBuildTools: '36.0.0' });
  assert.equal(inventory.androidBuildTools, '36.0.0');
  assert.throws(() => validateToolchainInventory(ADAPTERS['flutter-android-apk'], { flutter: '4.0.0', java: '17.0.20', androidPlatform: 'android-36', androidBuildTools: '36.0.0' }), /TOOLCHAIN_VERSION_MISMATCH/);
});
