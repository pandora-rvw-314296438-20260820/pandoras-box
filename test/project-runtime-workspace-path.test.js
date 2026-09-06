const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const source = readFileSync(
  resolve(
    process.cwd(),
    'supabase/migrations/20260906073500_pandora_exactly_once_project_creation_v1.sql',
  ),
  'utf8',
);

test('customer project creation writes the canonical ProjectOS workspace path', () => {
  assert.match(
    source,
    /'projectos\/projects\/' \|\| v_project_key/,
  );
  assert.doesNotMatch(
    source,
    /'projects\/' \|\| v_project_key/,
  );
});
