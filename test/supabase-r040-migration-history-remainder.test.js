const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migrations = join(root, 'supabase', 'migrations');
const manifest = JSON.parse(readFileSync(join(
  root,
  'docs',
  'status',
  'SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_REMAINDER_20260914.json',
), 'utf8'));
const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

test('R-040 remainder receipts preserve all provider history identities without replay', () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.projectRef, 'jcyqixttuebxqqfkjonq');
  assert.equal(manifest.repository, 'pandora-rvw-314296438-20260820/pandoras-box');
  assert.equal(manifest.mode, 'remote_history_receipts_without_replaying_applied_surfaces');
  assert.equal(manifest.observedMainSha, '1b2f7885b11a64386451633ea2fb04b0472a037b');
  assert.equal(manifest.missingCount, 36);
  assert.equal(manifest.entries.length, 36);
  assert.equal(new Set(manifest.entries.map((entry) => entry.version)).size, 36);
  assert.deepEqual(
    manifest.entries.map((entry) => entry.version),
    [...manifest.entries.map((entry) => entry.version)].sort(),
  );

  let providerOnly = 0;
  for (const entry of manifest.entries) {
    const receiptName = `${entry.version}_${entry.name}.sql`;
    const receipt = readFileSync(join(migrations, receiptName), 'utf8');
    const executableLines = receipt
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('--'));

    assert.match(entry.version, /^\d{14}$/);
    assert.match(entry.originalSqlSha256, /^[0-9a-f]{64}$/);
    assert.equal(entry.originalStatementCount, 1);
    assert.ok(entry.providerSqlBytes > 0);
    assert.equal(entry.replayMode, 'history_receipt_noop');
    assert.match(receipt, new RegExp(`-- Version: ${entry.version}`));
    assert.match(receipt, new RegExp(`-- Name: ${escapeRegex(entry.name)}`));
    assert.match(receipt, new RegExp(entry.originalSqlSha256));
    assert.match(receipt, new RegExp(`-- Provider SQL bytes: ${entry.providerSqlBytes}`));
    assert.match(receipt, /Replay mode: history_receipt_noop/);
    assert.deepEqual(executableLines, ['select 1;'], receiptName);

    if (entry.canonicalPath) {
      const canonical = readFileSync(join(root, entry.canonicalPath), 'utf8');
      assert.ok(canonical.length > 0, receiptName);
      assert.equal(entry.reconciliation, 'same_name_canonical_authority_preserved_without_replay');
      assert.match(receipt, new RegExp(`-- Canonical executable authority: ${escapeRegex(entry.canonicalPath)}`));
    } else {
      providerOnly += 1;
      assert.equal(entry.reconciliation, 'provider_only_history_identity_no_canonical_source');
      assert.match(receipt, /Provider-only history identity:/);
    }
  }
  assert.equal(providerOnly, 2);
  assert.equal(manifest.providerOnlyCount, 2);
});
