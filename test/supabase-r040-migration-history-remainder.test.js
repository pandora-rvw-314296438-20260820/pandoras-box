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
  'SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_REMAINDER_20260915.json',
), 'utf8'));
const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

test('R-040 remainder preserves provider history and executable provider-only security hardening', () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.projectRef, 'jcyqixttuebxqqfkjonq');
  assert.equal(manifest.repository, 'pandora-rvw-314296438-20260820/pandoras-box');
  assert.equal(manifest.mode, 'remote_history_source_reconciliation');
  assert.equal(manifest.observedMainSha, '83758d53da31359a82731d5f5f25e4a40f39f64c');
  assert.equal(manifest.missingCount, 40);
  assert.equal(manifest.entries.length, 40);
  assert.equal(manifest.historyReceiptCount, 39);
  assert.equal(manifest.providerOnlyCount, 1);
  assert.equal(manifest.executableProviderOnlyCount, 1);
  assert.equal(manifest.providerHistoryMutated, false);
  assert.equal(manifest.productionLiveSchemaReplayed, false);
  assert.equal(manifest.freshEnvironmentSecurityHardeningExecutable, true);
  assert.equal(new Set(manifest.entries.map((entry) => entry.version)).size, 40);
  assert.deepEqual(
    manifest.entries.map((entry) => entry.version),
    [...manifest.entries.map((entry) => entry.version)].sort(),
  );

  let receiptCount = 0;
  let executableCount = 0;
  for (const entry of manifest.entries) {
    const migrationName = `${entry.version}_${entry.name}.sql`;
    const migration = readFileSync(join(migrations, migrationName), 'utf8');
    assert.match(entry.version, /^\d{14}$/);
    assert.match(entry.originalSqlSha256, /^[0-9a-f]{64}$/);
    assert.equal(entry.originalStatementCount, 1);
    assert.ok(entry.providerSqlBytes > 0);

    if (entry.replayMode === 'history_receipt_noop') {
      receiptCount += 1;
      const executableLines = migration
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line && !line.startsWith('--'));
      assert.ok(entry.canonicalPath, migrationName);
      assert.ok(readFileSync(join(root, entry.canonicalPath), 'utf8').length > 0, migrationName);
      assert.match(migration, new RegExp(`-- Version: ${entry.version}`));
      assert.match(migration, new RegExp(`-- Name: ${escapeRegex(entry.name)}`));
      assert.match(migration, new RegExp(entry.originalSqlSha256));
      assert.match(migration, new RegExp(`-- Provider SQL bytes: ${entry.providerSqlBytes}`));
      assert.match(migration, /Replay mode: history_receipt_noop/);
      assert.deepEqual(executableLines, ['select 1;'], migrationName);
    } else {
      executableCount += 1;
      assert.equal(entry.version, '20260910051901');
      assert.equal(entry.name, 'revoke_anon_dangerous_table_grants_20260910');
      assert.equal(entry.replayMode, 'provider_exact_executable');
      assert.equal(entry.canonicalPath, null);
      assert.equal(entry.reconciliation, 'provider_only_security_executable_source_authority');
      const providerBody = migration.endsWith('\n') ? migration.slice(0, -1) : migration;
      assert.equal(Buffer.byteLength(providerBody), entry.providerSqlBytes);
      assert.equal(sha256(providerBody), entry.originalSqlSha256);
      assert.match(migration, /revoke insert, update, delete, truncate, references, trigger/i);
      assert.doesNotMatch(migration, /Replay mode: history_receipt_noop/);
    }
  }
  assert.equal(receiptCount, 39);
  assert.equal(executableCount, 1);

  const liveRead = manifest.entries.find((entry) => entry.version === '20260912190059');
  assert.equal(liveRead.canonicalPath, 'supabase/migrations/20260911131000_pandora_universal_capability_router_v2.sql');
  assert.equal(liveRead.reconciliation, 'promotion_wrapper_canonical_router_preserved_without_replay');
  const normalizedExact = new Set(['20260915041615','20260915041659','20260915041750','20260915041841']);
  for (const version of normalizedExact) {
    const entry = manifest.entries.find((candidate) => candidate.version === version);
    assert.equal(entry.replayMode, 'history_receipt_noop');
    assert.equal(entry.reconciliation, 'same_name_canonical_authority_exact_provider_body_preserved_without_replay');
    const canonical = readFileSync(join(root, entry.canonicalPath), 'utf8');
    const providerBody = canonical.endsWith('\n') ? canonical.slice(0, -1) : canonical;
    assert.equal(Buffer.byteLength(providerBody), entry.providerSqlBytes, version);
    assert.equal(sha256(providerBody), entry.originalSqlSha256, version);
  }
});
