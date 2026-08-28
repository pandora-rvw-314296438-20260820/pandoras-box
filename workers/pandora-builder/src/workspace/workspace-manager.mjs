import { mkdir, readFile, realpath, rm, stat, writeFile, lstat } from 'node:fs/promises';
import path from 'node:path';

const SAFE_SEGMENT = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

function safeSegment(value, label) {
  const text = String(value ?? '');
  if (!SAFE_SEGMENT.test(text) || text === '.' || text === '..') throw new Error(`INVALID_WORKSPACE_${label.toUpperCase()}`);
  return text;
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

async function rejectSymlinkChain(root, candidate) {
  if (!isWithin(root, candidate)) throw new Error('WORKSPACE_PATH_ESCAPE');
  const relative = path.relative(root, candidate);
  if (!relative) return;
  let cursor = root;
  for (const part of relative.split(path.sep)) {
    cursor = path.join(cursor, part);
    try {
      const info = await lstat(cursor);
      if (info.isSymbolicLink()) throw new Error('WORKSPACE_SYMLINK_ESCAPE');
    } catch (error) {
      if (error?.code === 'ENOENT') return;
      throw error;
    }
  }
}

class WorkspaceManager {
  constructor({ baseRoot }) {
    if (!path.isAbsolute(baseRoot)) throw new Error('WORKSPACE_ROOT_MUST_BE_ABSOLUTE');
    this.baseRoot = path.resolve(baseRoot);
  }

  workspacePath({ organizationId, projectId, buildJobId, attempt }) {
    const parts = [
      safeSegment(organizationId, 'organization'),
      safeSegment(projectId, 'project'),
      safeSegment(buildJobId, 'job'),
      `attempt-${Number(attempt)}`,
    ];
    if (!Number.isInteger(attempt) || attempt < 1 || attempt > 100) throw new Error('INVALID_WORKSPACE_ATTEMPT');
    const candidate = path.resolve(this.baseRoot, ...parts);
    if (!isWithin(this.baseRoot, candidate)) throw new Error('WORKSPACE_PATH_ESCAPE');
    return candidate;
  }

  async create(identity) {
    await mkdir(this.baseRoot, { recursive: true, mode: 0o700 });
    const root = this.workspacePath(identity);
    await mkdir(path.dirname(root), { recursive: true, mode: 0o700 });
    await mkdir(root, { recursive: false, mode: 0o700 });
    const meta = Object.freeze({ schemaVersion: 1, ...identity, root, createdAt: new Date().toISOString() });
    await writeFile(path.join(root, '.pandora-workspace.json'), JSON.stringify(meta), { encoding: 'utf8', mode: 0o600, flag: 'wx' });
    return meta;
  }

  async resume(identity) {
    const root = this.workspacePath(identity);
    const actual = await realpath(root);
    if (actual !== root) throw new Error('WORKSPACE_REALPATH_MISMATCH');
    const meta = JSON.parse(await readFile(path.join(root, '.pandora-workspace.json'), 'utf8'));
    for (const key of ['organizationId', 'projectId', 'buildJobId', 'attempt']) {
      if (String(meta[key]) !== String(identity[key])) throw new Error('WORKSPACE_IDENTITY_MISMATCH');
    }
    return Object.freeze(meta);
  }

  async resolvePath(root, relativePath, { allowMissing = false } = {}) {
    if (typeof relativePath !== 'string' || relativePath.length === 0 || relativePath.includes('\0') || path.isAbsolute(relativePath)) {
      throw new Error('INVALID_WORKSPACE_PATH');
    }
    const rootResolved = path.resolve(root);
    const candidate = path.resolve(rootResolved, relativePath);
    if (!isWithin(rootResolved, candidate)) throw new Error('WORKSPACE_PATH_ESCAPE');
    await rejectSymlinkChain(rootResolved, candidate);
    if (!allowMissing) {
      const info = await stat(candidate);
      if (!info.isFile() && !info.isDirectory()) throw new Error('WORKSPACE_SPECIAL_FILE_FORBIDDEN');
    }
    return candidate;
  }

  async cleanup(identity) {
    const root = this.workspacePath(identity);
    if (!isWithin(this.baseRoot, root) || root === this.baseRoot) throw new Error('WORKSPACE_CLEANUP_REFUSED');
    await rm(root, { recursive: true, force: true, maxRetries: 2 });
    return { status: 'cleaned', root };
  }
}

export { WorkspaceManager, isWithin };
