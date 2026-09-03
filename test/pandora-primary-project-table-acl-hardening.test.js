const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migration = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260903053000_pandora_primary_project_table_acl_hardening_v1.sql'),
  'utf8',
);

const tables = [
  'pandora_project_versions',
  'pandora_project_deployments',
  'pandora_project_domains',
];

test('anonymous role has no direct table privileges on customer project truth', () => {
  for (const table of tables) {
    assert.match(migration, new RegExp(`revoke all on table public\\.${table} from anon`));
    assert.doesNotMatch(migration, new RegExp(`grant .*public\\.${table}.* anon`));
  }
});

test('authenticated role retains read only while service mutations remain backend-owned', () => {
  for (const table of tables) {
    assert.match(migration, new RegExp(`grant select on table public\\.${table} to authenticated`));
  }
  assert.match(migration, /revoke insert, update, delete, truncate, references, trigger[\s\S]*pandora_project_versions from authenticated/);
  assert.match(migration, /revoke insert, update, delete, truncate, references, trigger[\s\S]*pandora_project_deployments from authenticated/);
  assert.match(migration, /revoke insert, update, delete, truncate, references, trigger[\s\S]*pandora_project_domains from authenticated/);
});
