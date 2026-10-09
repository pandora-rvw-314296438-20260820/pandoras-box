'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const receiptPath = path.join(
  root,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
  '20261010-ledger-parity-recovery.json'
);
const migrationsDir = path.join(root, 'supabase', 'migrations');

test('supabase migration ledger parity against production jcyqixttuebxqqfkjonq', async (t) => {
  await t.test('(a) provenance receipt lists files that exist with exact sha256', () => {
    assert.ok(fs.existsSync(receiptPath), `Receipt file must exist at ${receiptPath}`);
    const receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8'));
    assert.ok(Array.isArray(receipt.files), 'receipt.files must be an array');
    assert.ok(receipt.files.length > 0, 'receipt.files must not be empty');

    for (const entry of receipt.files) {
      const fullPath = path.join(root, entry.file);
      assert.ok(fs.existsSync(fullPath), `Expected file ${entry.file} to exist`);
      const bytes = fs.readFileSync(fullPath);
      const computedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
      assert.equal(
        computedSha256,
        entry.sha256,
        `SHA256 mismatch for ${entry.file}: expected ${entry.sha256}, got ${computedSha256}`
      );
    }
  });

  await t.test('(b) no two files in supabase/migrations share a version prefix', () => {
    const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
    const versionMap = new Map();

    for (const file of files) {
      const match = file.match(/^(\d{14})_/);
      assert.ok(match, `Migration filename ${file} does not match expected 14-digit prefix pattern`);
      const version = match[1];
      if (versionMap.has(version)) {
        assert.fail(`Duplicate version prefix ${version} found: ${versionMap.get(version)} and ${file}`);
      }
      versionMap.set(version, file);
    }
  });

  await t.test('(c) supabase/migrations contains no file with version 20261009070000 or 20261009090000', () => {
    const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
    const forbiddenVersions = ['20261009070000', '20261009090000'];

    for (const file of files) {
      for (const forbidden of forbiddenVersions) {
        assert.ok(
          !file.startsWith(forbidden),
          `supabase/migrations must not contain version ${forbidden}, but found ${file}`
        );
      }
    }
  });

  await t.test(
    '(d) migrations directory contains at least 961 .sql files and all recovery receipt migration versions are present',
    () => {
      const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
      assert.ok(
        files.length >= 961,
        `Expected at least 961 .sql files, got ${files.length}`
      );

      const receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8'));
      const existingVersions = new Set(
        files.map((file) => {
          const match = file.match(/^(\d{14})_/);
          return match ? match[1] : null;
        }).filter(Boolean)
      );

      const receiptMigrationEntries = receipt.files.filter((entry) => {
        const targetPath = entry.path || entry.file || '';
        return targetPath.startsWith('supabase/migrations/');
      });

      assert.ok(
        receiptMigrationEntries.length > 0,
        'Expected at least one migration entry starting with supabase/migrations/ in receipt'
      );

      for (const entry of receiptMigrationEntries) {
        assert.ok(
          existingVersions.has(entry.version),
          `Expected version ${entry.version} (${entry.file || entry.path}) to be present in ${migrationsDir}`
        );
      }
    }
  );
});
