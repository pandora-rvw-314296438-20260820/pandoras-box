'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const registry = JSON.parse(
  fs.readFileSync(
    path.join(root, 'ops/supabase/hardening/edge-function-lifecycle-registry.json'),
    'utf8',
  ),
);
const migration = fs.readFileSync(
  path.join(
    root,
    'supabase/migrations/20260907122000_pandora_edge_capacity_retirement_broker_v1.sql',
  ),
  'utf8',
);

const classificationSha = 'ec9c02fe13095d34c3c7433d1db743ac5a57e14e';

test('Edge retirement broker is exactly bound to source-classified self-retired functions', () => {
  const expected = registry.functions
    .filter((entry) => entry.decision === 'RETIRE_CANDIDATE_SELF_RETIRED')
    .map((entry) => ({
      key: entry.projectRef + ':' + entry.slug,
      version: entry.version,
    }))
    .sort((a, b) => a.key.localeCompare(b.key));

  const actual = [];
  const pattern = /when '([^']+)' then v_expected_version := (\d+);/g;
  for (const match of migration.matchAll(pattern)) {
    actual.push({ key: match[1], version: Number(match[2]) });
  }
  actual.sort((a, b) => a.key.localeCompare(b.key));

  assert.equal(expected.length, 30);
  assert.deepEqual(actual, expected);
  assert.match(migration, new RegExp(classificationSha));
});

test('Edge retirement broker excludes retained and unresolved candidates', () => {
  const protectedEntries = registry.functions.filter((entry) =>
    [
      'RETAIN_EVIDENCE_PENDING_OWNER_RECONCILIATION',
      'REVIEW_REQUIRED_CALLER_PROOF',
    ].includes(entry.decision),
  );

  assert.equal(protectedEntries.length, 6);
  for (const entry of protectedEntries) {
    assert.equal(
      migration.includes("'" + entry.projectRef + ':' + entry.slug + "'"),
      false,
      entry.slug + ' must not enter the retirement allowlist',
    );
  }
});

test('Edge retirement broker uses provider identity CAS and verifies deletion', () => {
  assert.match(migration, /v_metadata->>'version'/);
  assert.match(migration, /v_metadata->>'slug'/);
  assert.match(migration, /v_metadata->>'status'/);
  assert.match(migration, /'DELETE'::extensions\.http_method/);
  assert.match(
    migration,
    /api\.supabase\.com\/v1\/projects\/'.*'\/functions\/'/s,
  );
  assert.match(migration, /if v_verify\.status <> 404 then/);
  assert.match(migration, /retirement candidate changed after classification/);
});

test('Edge retirement authority stays server-only and emits durable receipts', () => {
  assert.match(
    migration,
    /revoke all on function private\.pandora_retire_self_retired_edge_function_20260907\(text,text\)[\s\S]*from public, anon, authenticated;/i,
  );
  assert.match(
    migration,
    /grant execute on function private\.pandora_retire_self_retired_edge_function_20260907\(text,text\)[\s\S]*to service_role;/i,
  );
  assert.match(migration, /pandora_edge_function_retirement_receipts/);
  assert.match(migration, /classification_source_sha/);
  assert.doesNotMatch(migration, /grant execute[\s\S]*to authenticated;/i);
});
