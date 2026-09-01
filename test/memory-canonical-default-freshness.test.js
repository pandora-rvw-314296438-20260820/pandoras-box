const assert = require('node:assert/strict');
const test = require('node:test');

const { executeMemoryTool } = require('../dist/tools/memory.js');
const { evaluateCanonicalContext } = require('../dist/tools/memory-governance.js');

const CONFIG = {
  baseUrl: 'https://memory.example.test',
  oidcToken: 'o'.repeat(64),
  allowedNamespaces: ['real_life'],
  grantedScopes: ['memory:read'],
  timeoutMs: 8000,
  maxResponseBytes: 500000,
};

function responseFor(updatedAt) {
  const payload = {
    ok: true,
    namespace: 'real_life',
    canonical_records: [{
      id: 'canon-1',
      namespace: 'real_life',
      title: 'Canonical state',
      body: 'Approved project state',
      canon_status: 'hard_canon',
      approved: true,
      updated_at: updatedAt,
    }],
    warnings: [],
  };
  return {
    ok: true,
    status: 200,
    headers: { get: () => null },
    text: async () => JSON.stringify(payload),
  };
}

test('canonicalContext defaults to a 24-hour fail-closed freshness gate', async () => {
  const stale = new Date(Date.now() - (2 * 24 * 60 * 60 * 1000)).toISOString();
  const result = await executeMemoryTool(
    'memory.canonicalContext',
    { namespace: 'real_life', projectKey: 'mcpmaster-pandoras-box', query: 'current state' },
    CONFIG,
    async () => responseFor(stale),
  );
  assert.equal(result.degraded, true);
  assert.deepEqual(result.canonical, []);
  assert.match(result.degradedReasons.join(' '), /older than the configured freshness window/);
  assert.equal(result.freshnessScope, 'query_approved_records');
});

test('explicit wider freshness window still works and remains query-scoped', async () => {
  const recentEnough = new Date(Date.now() - (2 * 24 * 60 * 60 * 1000)).toISOString();
  const result = await executeMemoryTool(
    'memory.canonicalContext',
    { namespace: 'real_life', projectKey: 'mcpmaster-pandoras-box', query: 'current state', maxAgeMs: 7 * 24 * 60 * 60 * 1000 },
    CONFIG,
    async () => responseFor(recentEnough),
  );
  assert.equal(result.degraded, false);
  assert.equal(result.canonical.length, 1);
  assert.equal(result.freshnessScope, 'query_approved_records');
});

test('approved canonical records without a usable timestamp fail closed', async () => {
  const result = await executeMemoryTool(
    'memory.canonicalContext',
    { namespace: 'real_life', projectKey: 'mcpmaster-pandoras-box', query: 'current state' },
    CONFIG,
    async () => responseFor(null),
  );
  assert.equal(result.degraded, true);
  assert.deepEqual(result.canonical, []);
  assert.match(result.degradedReasons.join(' '), /usable freshness timestamp/);
});

test('governance evaluator owns the 24-hour default without schema parsing', () => {
  const now = Date.parse('2026-08-20T00:00:00.000Z');
  const result = evaluateCanonicalContext({
    canonical_records: [{
      id: 'canon-stale-direct',
      title: 'Stale direct record',
      body: 'Approved but stale',
      canon_status: 'hard_canon',
      approved: true,
      updated_at: '2026-08-18T00:00:00.000Z',
    }],
    warnings: [],
  }, { now: () => now });
  assert.equal(result.degraded, true);
  assert.deepEqual(result.canonical, []);
  assert.match(result.degradedReasons.join(' '), /older than the configured freshness window/);
});

test('one untimestamped approved record degrades the whole canonical set', () => {
  const now = Date.parse('2026-08-20T00:00:00.000Z');
  const result = evaluateCanonicalContext({
    canonical_records: [
      {
        id: 'canon-fresh',
        title: 'Fresh record',
        body: 'Fresh',
        canon_status: 'hard_canon',
        approved: true,
        updated_at: '2026-08-20T00:00:00.000Z',
      },
      {
        id: 'canon-unknown-time',
        title: 'Unknown freshness',
        body: 'No timestamp',
        canon_status: 'hard_canon',
        approved: true,
        updated_at: null,
      },
    ],
    warnings: [],
  }, { now: () => now });
  assert.equal(result.degraded, true);
  assert.deepEqual(result.canonical, []);
  assert.match(result.degradedReasons.join(' '), /usable freshness timestamp/);
});
