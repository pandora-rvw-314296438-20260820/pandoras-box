#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { lstat, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const CANONICAL_ORIGIN = 'https://mcpmaster.vercel.app';
const MANIFEST_KEYS = ['source_sha', 'app_version', 'flutter_version', 'web_tree_sha256', 'artifact_class', 'production_release'];
const FILES = [
  { name: 'pandora-web-release-manifest.txt', limit: 16 * 1024, types: ['text/plain'] },
  { name: 'index.html', limit: 2 * 1024 * 1024, types: ['text/html'] },
  { name: 'main.dart.js', limit: 64 * 1024 * 1024, types: ['application/javascript', 'text/javascript'] },
];
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

export class ReleaseVerificationError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}
const requireThat = (condition, code) => { if (!condition) throw new ReleaseVerificationError(code); };

export function validateTargetUrl(value, target) {
  requireThat(typeof value === 'string' && value.length <= 253 && value === value.trim(), 'TARGET_URL_INVALID');
  let url;
  try { url = new URL(value); } catch { throw new ReleaseVerificationError('TARGET_URL_INVALID'); }
  requireThat(url.protocol === 'https:' && !url.username && !url.password && !url.port
    && !url.search && !url.hash && url.pathname === '/'
    && (value === url.origin || value === `${url.origin}/`), 'TARGET_URL_INVALID');
  if (target === 'canonical') {
    requireThat(url.origin === CANONICAL_ORIGIN, 'TARGET_ORIGIN_INVALID');
  } else {
    requireThat(target === 'candidate'
      && /^mcpmaster-[a-z0-9]+-mbanatao\.vercel\.app$/.test(url.hostname), 'TARGET_ORIGIN_INVALID');
  }
  return url.origin;
}

export function parseManifest(bytes, sourceSha) {
  requireThat(/^[0-9a-f]{40}$/.test(sourceSha), 'SOURCE_SHA_INVALID');
  requireThat(bytes.byteLength > 0 && bytes.byteLength <= FILES[0].limit, 'MANIFEST_SIZE_INVALID');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch { throw new ReleaseVerificationError('MANIFEST_ENCODING_INVALID'); }
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();
  const result = Object.create(null);
  for (const line of lines) {
    const match = /^([a-z][a-z0-9_]*)=([A-Za-z0-9.+-]+)$/.exec(line);
    requireThat(match && MANIFEST_KEYS.includes(match[1]), 'MANIFEST_FIELD_INVALID');
    requireThat(!Object.hasOwn(result, match[1]), 'MANIFEST_DUPLICATE_KEY');
    result[match[1]] = match[2];
  }
  requireThat(Object.keys(result).length === MANIFEST_KEYS.length, 'MANIFEST_FIELD_MISSING');
  requireThat(result.source_sha === sourceSha, 'MANIFEST_SOURCE_MISMATCH');
  requireThat(/^[0-9a-f]{64}$/.test(result.web_tree_sha256), 'MANIFEST_TREE_INVALID');
  requireThat(/^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?\+\d+$/.test(result.app_version), 'MANIFEST_VERSION_INVALID');
  requireThat(/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/.test(result.flutter_version), 'MANIFEST_FLUTTER_INVALID');
  requireThat(result.artifact_class === 'production-candidate'
    && result.production_release === 'true', 'MANIFEST_RELEASE_INVALID');
  return Object.freeze(result);
}

async function localFile(root, file) {
  const path = join(root, file.name);
  const info = await lstat(path);
  requireThat(info.isFile() && info.size > 0 && info.size <= file.limit, 'LOCAL_FILE_INVALID');
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of createReadStream(path)) {
    size += chunk.byteLength;
    requireThat(size <= file.limit, 'LOCAL_FILE_TOO_LARGE');
    hash.update(chunk);
  }
  requireThat(size === info.size, 'LOCAL_FILE_CHANGED');
  return { sha256: hash.digest('hex'), bytes: size };
}

async function remoteFile(origin, file, { fetchImpl, timeoutMs }) {
  const url = `${origin}/pandora-web/${file.name}`;
  const controller = new AbortController();
  let reader;
  let rejectDeadline;
  const deadline = new Promise((_, reject) => { rejectDeadline = reject; });
  const timer = setTimeout(() => {
    rejectDeadline(new ReleaseVerificationError('REMOTE_TIMEOUT'));
    controller.abort();
  }, timeoutMs);
  try {
    const response = await Promise.race([fetchImpl(url, {
      redirect: 'manual',
      signal: controller.signal,
      headers: { accept: file.types.join(', '), 'cache-control': 'no-cache' },
    }), deadline]);
    requireThat(response.status === 200 && !response.redirected && response.url === url, 'REMOTE_RESPONSE_INVALID');
    const type = (response.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
    requireThat(file.types.includes(type), 'REMOTE_CONTENT_TYPE_INVALID');
    const length = response.headers.get('content-length');
    requireThat(length === null || (/^(0|[1-9][0-9]*)$/.test(length)
      && Number.isSafeInteger(Number(length)) && Number(length) > 0
      && Number(length) <= file.limit), 'REMOTE_SIZE_INVALID');
    requireThat(response.body !== null, 'REMOTE_BODY_MISSING');
    reader = response.body.getReader();
    const hash = createHash('sha256');
    const chunks = [];
    let size = 0;
    for (;;) {
      const { done, value } = await Promise.race([reader.read(), deadline]);
      if (done) break;
      requireThat(value instanceof Uint8Array, 'REMOTE_BODY_INVALID');
      size += value.byteLength;
      requireThat(size <= file.limit, 'REMOTE_BODY_TOO_LARGE');
      hash.update(value);
      if (file === FILES[0]) chunks.push(value);
    }
    requireThat(size > 0, 'REMOTE_BODY_EMPTY');
    return { sha256: hash.digest('hex'), bytes: size,
      ...(file === FILES[0] ? { manifest: Buffer.concat(chunks) } : {}) };
  } catch (error) {
    if (error instanceof ReleaseVerificationError) throw error;
    throw new ReleaseVerificationError('REMOTE_REQUEST_FAILED');
  } finally {
    clearTimeout(timer);
    controller.abort();
    if (reader) void reader.cancel().catch(() => {});
  }
}

export async function verifyWebRelease({ url, sourceSha, target,
  localRoot = resolve('public/pandora-web'), fetchImpl = globalThis.fetch, timeoutMs = 20_000 }) {
  const origin = validateTargetUrl(url, target);
  requireThat(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 30_000, 'DEADLINE_INVALID');
  requireThat(/^[0-9a-f]{40}$/.test(sourceSha), 'SOURCE_SHA_INVALID');
  const local = [];
  for (const file of FILES) local.push(await localFile(localRoot, file));
  const manifestBytes = await readFile(join(localRoot, FILES[0].name));
  requireThat(digest(manifestBytes) === local[0].sha256, 'LOCAL_MANIFEST_CHANGED');
  const manifest = parseManifest(manifestBytes, sourceSha);
  const files = [];
  for (let index = 0; index < FILES.length; index += 1) {
    const file = FILES[index];
    const remote = await remoteFile(origin, file, { fetchImpl, timeoutMs });
    if (remote.manifest) {
      const actual = parseManifest(remote.manifest, sourceSha);
      requireThat(MANIFEST_KEYS.every((key) => actual[key] === manifest[key]), 'REMOTE_MANIFEST_MISMATCH');
    }
    requireThat(remote.sha256 === local[index].sha256 && remote.bytes === local[index].bytes, 'REMOTE_BYTES_MISMATCH');
    files.push({ url: `${origin}/pandora-web/${file.name}`, sha256: remote.sha256, bytes: remote.bytes });
  }
  return Object.freeze({ schemaVersion: 1, verified: true, target, url: origin,
    source_sha: sourceSha, web_tree_sha256: manifest.web_tree_sha256,
    app_version: manifest.app_version, flutter_version: manifest.flutter_version, files });
}

export async function runCli(argv, { stdout = process.stdout, stderr = process.stderr } = {}) {
  try {
    if (argv.length === 2 && argv[0] === '--validate-candidate-url') {
      // Vercel deploy stdout is a single URL. Never echo its unvalidated output.
      stdout.write(`${validateTargetUrl(argv[1].trim(), 'candidate')}\n`);
      return 0;
    }
    requireThat(argv.length === 6 && argv[0] === '--url' && argv[2] === '--source-sha'
      && argv[4] === '--target', 'ARGUMENTS_INVALID');
    const receipt = await verifyWebRelease({ url: argv[1], sourceSha: argv[3], target: argv[5] });
    stdout.write(`${JSON.stringify(receipt)}\n`);
    return 0;
  } catch (error) {
    // Do not print network bodies, arbitrary exception text, headers or tokens.
    const code = error instanceof ReleaseVerificationError ? error.code : 'LOCAL_VERIFICATION_FAILED';
    stderr.write(`Pandora web release verification failed: ${code}\n`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await runCli(process.argv.slice(2));
}
