
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migrationPath = 'supabase/migrations/20260909024500_projectos_publish_separation_reconciliation_v1.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');
const vercel = JSON.parse(fs.readFileSync('vercel.json', 'utf8'));

test('Git merges cannot auto-deploy Pandora production', () => {
  assert.equal(vercel.git.deploymentEnabled, false);
});

test('canonical GitHub reconciliation reads the exact expected ref', () => {
  assert.match(migration, /\/git\/ref\//);
  assert.match(migration, /v_branch->'object'->>'sha'/);
  assert.match(migration, /GitHub exact ref readback failed/);
});

test('only verified production receipts can promote release_state to released', () => {
  assert.match(
    migration,
    /v_result\.status = 'verified'[\s\S]*registry\.canonical_sha = v_result\.source_sha then 'released'/,
  );
  assert.match(
    migration,
    /v_result\.status = 'ready'[\s\S]*registry\.canonical_sha = v_result\.source_sha then 'ready'/,
  );
  assert.match(migration, /receipt\.status = 'ready'/);
  assert.match(migration, /receipt\.status = 'verified'/);
});
