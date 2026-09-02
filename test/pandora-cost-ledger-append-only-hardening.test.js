
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(
    root,
    'supabase/migrations/20260903100000_pandora_cost_ledger_append_only_hardening_v1.sql',
  ),
  'utf8',
);

test('cost ledger destructive privileges are revoked from application roles', () => {
  assert.match(
    migration,
    /revoke\s+update,\s*delete,\s*truncate,\s*references,\s*trigger[\s\S]+public\.pandora_cost_entries[\s\S]+from\s+public,\s*anon,\s*authenticated,\s*service_role/i,
  );
  assert.match(
    migration,
    /grant\s+select,\s*insert[\s\S]+public\.pandora_cost_entries[\s\S]+to\s+service_role/i,
  );
});

test('cost ledger blocks TRUNCATE at the trigger boundary', () => {
  assert.match(
    migration,
    /create\s+trigger\s+pandora_cost_entries_block_truncate[\s\S]+before\s+truncate\s+on\s+public\.pandora_cost_entries[\s\S]+for\s+each\s+statement[\s\S]+private\.pandora_control_plane_prevent_history_mutation\(\)/i,
  );
});

test('migration fails closed if destructive service-role privileges survive', () => {
  for (const privilege of ['UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) {
    assert.ok(
      migration.includes(
        `has_table_privilege('service_role', 'public.pandora_cost_entries', '${privilege}')`,
      ),
      `missing ${privilege} fail-closed privilege assertion`,
    );
  }
  assert.match(migration, /PANDORA_COST_LEDGER_APPEND_ONLY_PRIVILEGE_DRIFT/);
  assert.match(migration, /PANDORA_COST_LEDGER_TRUNCATE_GUARD_MISSING/);
});
