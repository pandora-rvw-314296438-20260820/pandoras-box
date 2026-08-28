import { createHash } from 'node:crypto';
import { lstat, open, readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

function isWithin(root, candidate) {
  const rel = path.relative(root, candidate);
  return rel === '' || (!rel.startsWith(`..${path.sep}`) && rel !== '..' && !path.isAbsolute(rel));
}

async function digestFile(filePath) {
  const handle = await open(filePath, 'r');
  const hash = createHash('sha256');
  try {
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    let position = 0;
    while (true) {
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, position);
      if (!bytesRead) break;
      hash.update(buffer.subarray(0, bytesRead));
      position += bytesRead;
    }
  } finally { await handle.close(); }
  return hash.digest('hex');
}

async function scanArtifact(root, relativePath, limits, state) {
  if (typeof relativePath !== 'string' || relativePath.length === 0 || path.isAbsolute(relativePath) || relativePath.includes('\0')) throw new Error('INVALID_ARTIFACT_PATH');
  const rootResolved = path.resolve(root);
  const candidate = path.resolve(rootResolved, relativePath);
  if (!isWithin(rootResolved, candidate)) throw new Error('ARTIFACT_PATH_ESCAPE');
  const info = await lstat(candidate);
  if (info.isSymbolicLink()) throw new Error('ARTIFACT_SYMLINK_FORBIDDEN');
  if (!info.isFile() && !info.isDirectory()) throw new Error('ARTIFACT_SPECIAL_FILE_FORBIDDEN');
  if (info.isFile()) {
    state.files += 1;
    state.bytes += info.size;
    if (state.files > limits.fileCount) throw new Error('ARTIFACT_FILE_COUNT_EXCEEDED');
    if (state.bytes > limits.artifactBytes) throw new Error('ARTIFACT_SIZE_EXCEEDED');
    const digest = await digestFile(candidate);
    return { path: relativePath.replaceAll('\\', '/'), kind: 'file', sizeBytes: info.size, sha256: digest };
  }
  const entries = (await readdir(candidate)).sort();
  const children = [];
  for (const entry of entries) children.push(await scanArtifact(rootResolved, path.join(relativePath, entry), limits, state));
  const treeIdentity = children.map((item) => [item.path, item.kind, item.sizeBytes ?? null, item.sha256 ?? item.treeSha256]);
  return { path: relativePath.replaceAll('\\', '/'), kind: 'directory', fileCount: children.reduce((n, item) => n + (item.kind === 'file' ? 1 : item.fileCount), 0), sizeBytes: children.reduce((n, item) => n + (item.sizeBytes ?? 0), 0), treeSha256: createHash('sha256').update(JSON.stringify(treeIdentity)).digest('hex'), entries: children };
}

async function collectArtifacts({ workspaceRoot, outputs, limits = {} }) {
  const normalizedLimits = { fileCount: limits.fileCount ?? 100_000, artifactBytes: limits.artifactBytes ?? 512 * 1024 ** 2 };
  const state = { files: 0, bytes: 0 };
  const artifacts = [];
  for (const output of outputs ?? []) {
    const artifact = await scanArtifact(workspaceRoot, output.path, normalizedLimits, state);
    artifacts.push(Object.freeze({ ...artifact, expectedKind: output.kind ?? null, digest: artifact.sha256 ?? artifact.treeSha256 }));
  }
  return Object.freeze({ artifacts: Object.freeze(artifacts), totalFiles: state.files, totalBytes: state.bytes });
}

function changedFileManifest(before = {}, after = {}) {
  const paths = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return Object.freeze(paths.flatMap((file) => {
    const previous = before[file] ?? null; const current = after[file] ?? null;
    if (previous === current) return [];
    return [Object.freeze({ path: file, operation: previous == null ? 'create' : current == null ? 'delete' : 'modify', previousDigest: previous, digest: current })];
  }));
}

async function digestJsonFile(filePath) {
  const data = await readFile(filePath);
  return createHash('sha256').update(data).digest('hex');
}

export { changedFileManifest, collectArtifacts, digestFile, digestJsonFile };
