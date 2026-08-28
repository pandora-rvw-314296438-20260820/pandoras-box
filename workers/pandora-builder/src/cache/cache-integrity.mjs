import { createHash } from 'node:crypto';

function canonical(value) { if (Array.isArray(value)) return value.map(canonical); if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((k) => [k, canonical(value[k])])); return value; }

function createCacheManifest({ cacheKey, scope, sourceDigest, lockfileDigest, adapter, toolchainDigest, entries }) {
  if (!cacheKey || !scope || !sourceDigest || !lockfileDigest || !adapter?.id || !adapter?.version || !toolchainDigest) throw new Error('INVALID_CACHE_MANIFEST');
  const normalizedEntries = (entries ?? []).map((entry) => {
    if (typeof entry.path !== 'string' || !/^[0-9a-f]{64}$/.test(entry.sha256 ?? '')) throw new Error('INVALID_CACHE_ENTRY');
    return { path: entry.path, sha256: entry.sha256, sizeBytes: entry.sizeBytes ?? null };
  }).sort((a, b) => a.path.localeCompare(b.path));
  const payload = canonical({ schemaVersion: 1, cacheKey, scope, sourceDigest, lockfileDigest, adapter: { id: adapter.id, version: adapter.version }, toolchainDigest, writable: false, entries: normalizedEntries });
  return Object.freeze({ ...payload, manifestSha256: createHash('sha256').update(JSON.stringify(payload)).digest('hex') });
}

function validateCacheManifest(manifest, expected) {
  if (!manifest || manifest.writable !== false) throw new Error('WRITABLE_CACHE_FORBIDDEN');
  for (const field of ['cacheKey', 'scope', 'sourceDigest', 'lockfileDigest', 'toolchainDigest']) if (manifest[field] !== expected[field]) throw new Error('CACHE_IDENTITY_MISMATCH');
  if (manifest.adapter?.id !== expected.adapter?.id || manifest.adapter?.version !== expected.adapter?.version) throw new Error('CACHE_ADAPTER_MISMATCH');
  const { manifestSha256, ...payload } = manifest;
  const digest = createHash('sha256').update(JSON.stringify(canonical(payload))).digest('hex');
  if (digest !== manifestSha256) throw new Error('CACHE_MANIFEST_TAMPERED');
  return true;
}

export { createCacheManifest, validateCacheManifest };
