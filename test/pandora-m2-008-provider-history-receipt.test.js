const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const manifest = JSON.parse(readFileSync(join(
  root,
  'docs',
  'status',
  'SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_M2_008_20260917.json',
), 'utf8'));
const entry = manifest.entries[0];
const canonical = readFileSync(join(root, entry.canonicalPath));
const receipt = readFileSync(join(
  root,
  'supabase',
  'migrations',
  `${entry.version}_${entry.name}.sql`,
), 'utf8');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

test('M2-008 governed rollout preserves the provider timestamp as a no-replay history receipt', () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.entries.length, 1);
  assert.equal(entry.version, '20260917051010');
  assert.equal(entry.name, 'pandora_activity_history_v1');
  assert.equal(entry.replayMode, 'history_receipt_noop');
  assert.equal(entry.originalStatementCount, 1);
  assert.equal(entry.providerSqlBytes, 10141);
  assert.equal(entry.originalSqlSha256, '3dfa0e08319212620398324bd41e676bad0d8a670277a1ae2c7d70c3d10aadb5');
  assert.equal(canonical.length, entry.canonicalSqlBytes);
  assert.equal(sha256(canonical), entry.canonicalSqlSha256);
  assert.equal(entry.originalSqlSha256, entry.canonicalSqlSha256);
  assert.equal(entry.providerSqlBytes, entry.canonicalSqlBytes);
  const executableLines = receipt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('--'));
  assert.deepEqual(executableLines, ['select 1;']);
  assert.match(receipt, /Replay mode: history_receipt_noop/);
});
