'use strict';

const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

const CODING_SANDBOX_VERSION = 'pandora-kimi-coding-sandbox-v1';
const MAX_EDIT_FILES = 32;
const MAX_EDIT_BYTES = 1024 * 1024;

/** @param {string} root @param {string} candidate */
function assertWithin(root, candidate) {
  const normalizedRoot = path.resolve(root) + path.sep;
  const normalizedCandidate = path.resolve(candidate);
  if (!normalizedCandidate.startsWith(normalizedRoot)) throw new Error('benchmark workspace path escape rejected');
  return normalizedCandidate;
}

/** @param {string} workspaceRoot @param {string} relativePath */
function resolveWorkspacePath(workspaceRoot, relativePath) {
  if (typeof relativePath !== 'string' || !relativePath.trim() || path.isAbsolute(relativePath)) throw new Error('benchmark edit path must be relative');
  return assertWithin(workspaceRoot, path.join(workspaceRoot, relativePath));
}

/** @param {string} root */
async function fingerprintTree(root) {
  const hash = crypto.createHash('sha256');
  /** @param {string} current @param {string} prefix */
  async function walk(current, prefix) {
    const entries = await fs.readdir(current, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const full = path.join(current, entry.name);
      if (entry.isSymbolicLink()) throw new Error('benchmark fixture symlinks are not permitted');
      if (entry.isDirectory()) await walk(full, relative);
      else if (entry.isFile()) {
        hash.update(relative);
        hash.update('\0');
        hash.update(await fs.readFile(full));
        hash.update('\0');
      }
    }
  }
  await walk(root, '');
  return hash.digest('hex');
}

/**
 * @param {string} workspaceRoot
 * @param {unknown} artifact
 * @param {string[]} [allowedPaths]
 */
async function applyFileEdits(workspaceRoot, artifact, allowedPaths = []) {
  if (!artifact || typeof artifact !== 'object' || Array.isArray(artifact)) throw new Error('coding benchmark artifact must be an object');
  const files = Array.isArray(artifact.files) ? artifact.files : [];
  if (!files.length || files.length > MAX_EDIT_FILES) throw new Error('coding benchmark artifact has invalid file count');
  const allow = new Set(allowedPaths.map(String));
  let totalBytes = 0;
  for (const edit of files) {
    if (!edit || typeof edit !== 'object' || Array.isArray(edit)) throw new Error('coding benchmark edit must be an object');
    const relativePath = typeof edit.path === 'string' ? edit.path : '';
    const content = typeof edit.content === 'string' ? edit.content : null;
    if (content == null) throw new Error('coding benchmark edit content must be text');
    if (allow.size && !allow.has(relativePath)) throw new Error(`benchmark edit path not allowed: ${relativePath}`);
    totalBytes += Buffer.byteLength(content, 'utf8');
    if (totalBytes > MAX_EDIT_BYTES) throw new Error('coding benchmark edits exceed size budget');
    const destination = resolveWorkspacePath(workspaceRoot, relativePath);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, content, { encoding: 'utf8', flag: 'w' });
  }
  return Object.freeze({ editedFiles: files.length, editedBytes: totalBytes });
}

/**
 * @param {{
 *   benchmarkCase: Record<string, any>,
 *   fixturePath: string,
 *   executeProvider: (request: Record<string, any>) => Promise<Record<string, any>>,
 *   validateWorkspace: (request: Record<string, any>) => Promise<Record<string, any>> | Record<string, any>,
 *   allowedPaths?: string[]
 * }} input
 */
async function runCodingBenchmarkSandbox(input) {
  if (!input || typeof input !== 'object') throw new TypeError('coding sandbox input is required');
  if (typeof input.executeProvider !== 'function' || typeof input.validateWorkspace !== 'function') throw new TypeError('coding sandbox executors are required');
  const sourceRoot = path.resolve(input.fixturePath);
  const sourceStat = await fs.stat(sourceRoot);
  if (!sourceStat.isDirectory()) throw new Error('coding benchmark fixture must be a directory');
  const sourceBefore = await fingerprintTree(sourceRoot);
  const sandboxRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'pandora-kimi-benchmark-'));
  const workspaceRoot = path.join(sandboxRoot, 'workspace');
  try {
    await fs.cp(sourceRoot, workspaceRoot, { recursive: true, force: false, errorOnExist: true, dereference: false });
    const request = Object.freeze({
      benchmarkCase: input.benchmarkCase,
      shadow: true,
      toolPolicy: Object.freeze({ mode: 'disabled', allowedTools: Object.freeze([]), sideEffectsAllowed: false }),
      metadata: Object.freeze({ evaluationOnly: true, sandboxed: true, exposeToUser: false }),
    });
    const providerResult = await input.executeProvider(request);
    assertNoCredentialMaterial(providerResult);
    const editSummary = await applyFileEdits(workspaceRoot, providerResult.output, input.allowedPaths ?? []);
    const validation = await input.validateWorkspace(Object.freeze({ workspaceRoot, benchmarkCase: input.benchmarkCase }));
    assertNoCredentialMaterial(validation);
    const sourceAfter = await fingerprintTree(sourceRoot);
    if (sourceAfter !== sourceBefore) throw new Error('authoritative coding fixture mutated during benchmark');
    return Object.freeze({
      version: CODING_SANDBOX_VERSION,
      provider: providerResult.provider ?? null,
      model: providerResult.model ?? null,
      output: providerResult.output,
      usage: providerResult.usage ?? null,
      edits: editSummary,
      validation,
      sourceFixtureUnchanged: true,
      workspaceWasDisposable: true,
    });
  } finally {
    await fs.rm(sandboxRoot, { recursive: true, force: true });
  }
}

module.exports = Object.freeze({ CODING_SANDBOX_VERSION, resolveWorkspacePath, fingerprintTree, applyFileEdits, runCodingBenchmarkSandbox });
