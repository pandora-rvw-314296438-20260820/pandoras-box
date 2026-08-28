import assert from 'node:assert/strict';
import { mkdtemp, mkdir, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { WorkspaceManager } from '../src/workspace/workspace-manager.mjs';
import { WorkspaceFilesystem } from '../src/filesystem/workspace-filesystem.mjs';

const identity = { organizationId: 'org-1', projectId: 'project-1', buildJobId: 'job-1', attempt: 1 };

test('creates, resumes and cleans deterministic workspace', async () => {
  const parent = await mkdtemp(path.join(os.tmpdir(), 'pandora-workspace-test-'));
  const manager = new WorkspaceManager({ baseRoot: path.join(parent, 'workspaces') });
  const created = await manager.create(identity);
  const resumed = await manager.resume(identity);
  assert.equal(resumed.root, created.root);
  assert.equal((await manager.cleanup(identity)).status, 'cleaned');
});

test('filesystem operations stay within workspace', async () => {
  const parent = await mkdtemp(path.join(os.tmpdir(), 'pandora-fs-test-'));
  const manager = new WorkspaceManager({ baseRoot: path.join(parent, 'workspaces') });
  const created = await manager.create(identity);
  const fsx = new WorkspaceFilesystem({ workspaceManager: manager, root: created.root });
  const manifest = await fsx.writeFile('src/index.txt', 'hello');
  assert.equal(manifest.operation, 'create');
  assert.equal((await fsx.readFile('src/index.txt')).data.toString(), 'hello');
  await assert.rejects(() => manager.resolvePath(created.root, '../../outside'), /WORKSPACE_PATH_ESCAPE/);
  await manager.cleanup(identity);
});

test('rejects symlink escape', async () => {
  const parent = await mkdtemp(path.join(os.tmpdir(), 'pandora-symlink-test-'));
  const outside = path.join(parent, 'outside');
  await mkdir(outside);
  await writeFile(path.join(outside, 'secret.txt'), 'secret');
  const manager = new WorkspaceManager({ baseRoot: path.join(parent, 'workspaces') });
  const created = await manager.create(identity);
  await symlink(outside, path.join(created.root, 'escape'));
  await assert.rejects(() => manager.resolvePath(created.root, 'escape/secret.txt'), /WORKSPACE_SYMLINK_ESCAPE/);
  await manager.cleanup(identity);
});
