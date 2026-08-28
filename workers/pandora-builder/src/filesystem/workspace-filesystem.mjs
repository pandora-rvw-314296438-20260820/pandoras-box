import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, rename, rm, stat, writeFile, lstat } from 'node:fs/promises';
import path from 'node:path';

function sha256(value) { return createHash('sha256').update(value).digest('hex'); }

class WorkspaceFilesystem {
  constructor({ workspaceManager, root, maxReadBytes = 2 * 1024 ** 2, maxWriteBytes = 8 * 1024 ** 2 }) {
    this.workspaceManager = workspaceManager;
    this.root = root;
    this.maxReadBytes = maxReadBytes;
    this.maxWriteBytes = maxWriteBytes;
  }

  async listFiles(relative = '.') {
    const target = await this.workspaceManager.resolvePath(this.root, relative);
    const info = await lstat(target);
    if (info.isSymbolicLink()) throw new Error('WORKSPACE_SYMLINK_ESCAPE');
    if (!info.isDirectory()) throw new Error('NOT_A_DIRECTORY');
    const entries = await readdir(target, { withFileTypes: true });
    return entries.map((entry) => ({
      name: entry.name,
      type: entry.isFile() ? 'file' : entry.isDirectory() ? 'directory' : entry.isSymbolicLink() ? 'symlink' : 'other',
    })).sort((a, b) => a.name.localeCompare(b.name));
  }

  async readFile(relative) {
    const target = await this.workspaceManager.resolvePath(this.root, relative);
    const info = await stat(target);
    if (!info.isFile()) throw new Error('NOT_A_FILE');
    if (info.size > this.maxReadBytes) throw new Error('FILE_READ_LIMIT_EXCEEDED');
    const data = await readFile(target);
    return { data, size: data.length, sha256: sha256(data) };
  }

  async writeFile(relative, data) {
    const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
    if (buffer.length > this.maxWriteBytes) throw new Error('FILE_WRITE_LIMIT_EXCEEDED');
    const target = await this.workspaceManager.resolvePath(this.root, relative, { allowMissing: true });
    await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
    await this.workspaceManager.resolvePath(this.root, path.relative(this.root, path.dirname(target)) || '.', { allowMissing: false });
    let previousDigest = null;
    try { previousDigest = sha256(await readFile(target)); } catch (error) { if (error?.code !== 'ENOENT') throw error; }
    await writeFile(target, buffer, { mode: 0o600 });
    return { path: relative, operation: previousDigest ? 'modify' : 'create', size: buffer.length, digest: sha256(buffer), previousDigest };
  }

  async deleteFile(relative) {
    const target = await this.workspaceManager.resolvePath(this.root, relative);
    const info = await lstat(target);
    if (!info.isFile()) throw new Error('DELETE_NON_FILE_FORBIDDEN');
    const previous = await readFile(target);
    await rm(target, { force: false });
    return { path: relative, operation: 'delete', size: 0, digest: null, previousDigest: sha256(previous) };
  }

  async moveFile(from, to) {
    const source = await this.workspaceManager.resolvePath(this.root, from);
    const target = await this.workspaceManager.resolvePath(this.root, to, { allowMissing: true });
    const info = await lstat(source);
    if (!info.isFile()) throw new Error('MOVE_NON_FILE_FORBIDDEN');
    await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
    await rename(source, target);
    const data = await readFile(target);
    return { path: to, operation: 'move', from, size: data.length, digest: sha256(data), previousDigest: null };
  }
}

export { WorkspaceFilesystem, sha256 };
