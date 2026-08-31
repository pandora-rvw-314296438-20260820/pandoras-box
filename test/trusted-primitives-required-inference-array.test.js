const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migration = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260831083000_pandora_worker_i_required_primitives_array_append_v1.sql'),
  'utf8',
);

test('Worker I primitive inference appends scalar names as one-element text arrays', () => {
  assert.match(migration, /create or replace function private\.pandora_worker_i_required_primitives_20260831/);
  assert.doesNotMatch(migration, /v_names:=v_names\|\|'pandora-/);
  for (const name of [
    'pandora-auth',
    'pandora-admin',
    'pandora-audit',
    'pandora-notifications',
    'pandora-analytics',
    'pandora-booking',
    'pandora-commerce',
    'pandora-billing',
    'pandora-crm',
    'pandora-forms',
    'pandora-files',
    'pandora-search',
    'pandora-content',
    'pandora-scheduling',
    'pandora-customer-profile',
    'pandora-settings',
    'pandora-feature-flags',
  ]) {
    assert.match(migration, new RegExp(`v_names:=v_names\\|\\|array\\['${name}'\\]`));
  }
});

test('Worker I inference still expands the exact multi-primitive dependency pairs', () => {
  assert.match(migration, /array\['pandora-auth','pandora-rbac'\]/);
  assert.match(migration, /array\['pandora-commerce','pandora-billing'\]/);
  assert.match(migration, /array_agg\(distinct x order by x\)/);
});
