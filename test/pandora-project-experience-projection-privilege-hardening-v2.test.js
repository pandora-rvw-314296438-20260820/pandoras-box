const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const source = readFileSync(
  join(
    __dirname,
    '..',
    'supabase',
    'migrations',
    '20260831090000_pandora_project_experience_projection_privilege_hardening_v2.sql',
  ),
  'utf8',
);

test('experience projection is SELECT-only for authenticated clients', () => {
  assert.match(
    source,
    /revoke all on table public\.pandora_project_experience_projection from authenticated/i,
  );
  assert.match(
    source,
    /grant select on table public\.pandora_project_experience_projection to authenticated/i,
  );
  assert.match(
    source,
    /revoke all on table public\.pandora_project_experience_projection from anon/i,
  );
  assert.doesNotMatch(
    source,
    /grant\s+(insert|update|delete|truncate|trigger|references)\b[\s\S]*authenticated/i,
  );
});
