const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migrations = join(root, 'supabase', 'migrations');
const manifest = JSON.parse(readFileSync(join(
  root,
  'docs',
  'status',
  'SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_20260914.json',
), 'utf8'));

const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const gitBlob = (value) => createHash('sha1')
  .update(Buffer.from(`blob ${value.length}\0`))
  .update(value)
  .digest('hex');

test('R-040 receipts bind provider history to canonical executable authority without replay', () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.projectRef, 'jcyqixttuebxqqfkjonq');
  assert.equal(manifest.repository, 'pandora-rvw-314296438-20260820/pandoras-box');
  assert.equal(manifest.mode, 'remote_history_receipts_without_replaying_applied_surfaces');
  assert.equal(manifest.entries.length, 4);
  assert.equal(new Set(manifest.entries.map((entry) => entry.version)).size, 4);

  for (const entry of manifest.entries) {
    const receiptName = `${entry.version}_${entry.name}.sql`;
    const receipt = readFileSync(join(migrations, receiptName), 'utf8');
    const canonical = readFileSync(join(root, entry.canonicalPath));
    const executableLines = receipt
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('--'));

    assert.match(entry.version, /^\d{14}$/);
    assert.match(entry.originalSqlSha256, /^[0-9a-f]{64}$/);
    assert.equal(entry.originalStatementCount, 1);
    assert.equal(entry.replayMode, 'history_receipt_noop');
    assert.equal(canonical.length, entry.canonicalSqlBytes, receiptName);
    assert.equal(sha256(canonical), entry.canonicalSqlSha256, receiptName);
    assert.equal(gitBlob(canonical), entry.canonicalGitBlob, receiptName);
    assert.match(receipt, new RegExp(`-- Version: ${entry.version}`));
    assert.match(receipt, new RegExp(`-- Name: ${entry.name}`));
    assert.match(receipt, new RegExp(entry.originalSqlSha256));
    assert.match(receipt, new RegExp(`-- Provider SQL bytes: ${entry.providerSqlBytes}`));
    assert.match(receipt, new RegExp(entry.canonicalGitBlob));
    assert.match(receipt, new RegExp(entry.canonicalSqlSha256));
    assert.match(receipt, /Replay mode: history_receipt_noop/);
    assert.deepEqual(executableLines, ['select 1;'], receiptName);
  }
});

test('R-040 reconciliation records distinguish newline, comment-only, and exact duplicate identities', () => {
  const byVersion = new Map(manifest.entries.map((entry) => [entry.version, entry]));
  const v11 = byVersion.get('20260913115101');
  const v12 = byVersion.get('20260913115242');
  const v13a = byVersion.get('20260913123852');
  const v13b = byVersion.get('20260913125207');

  assert.equal(v11.reconciliation, 'trailing_newline_only');
  assert.equal(v11.canonicalSqlBytes, v11.providerSqlBytes + 1);
  assert.equal(v12.reconciliation, 'comment_header_plus_trailing_newline');
  assert.ok(v12.canonicalSqlBytes > v12.providerSqlBytes);
  assert.equal(v13a.reconciliation, 'trailing_newline_only');
  assert.equal(v13a.canonicalSqlBytes, v13a.providerSqlBytes + 1);
  assert.equal(v13b.reconciliation, 'exact_canonical_duplicate_history_identity');
  assert.equal(v13b.canonicalSqlBytes, v13b.providerSqlBytes);
  assert.equal(v13b.originalSqlSha256, v13b.canonicalSqlSha256);
  assert.equal(v13a.canonicalGitBlob, v13b.canonicalGitBlob);
});
