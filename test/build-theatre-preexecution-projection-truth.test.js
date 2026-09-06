const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const source = fs.readFileSync(
  'supabase/migrations/20260906031500_pandora_build_theatre_preexecution_truth_v1.sql',
  'utf8',
);

test('pre-execution terminal builds do not look like active repair work', () => {
  assert.match(source, /new\.status in \('failed','cancelled'\)/);
  assert.match(source, /coalesce\(new\.attempt_count, 0\) = 0/);
  assert.match(source, /new\.started_at is null/);
  assert.match(source, /when v_preexecution_terminal then 0/);
  assert.match(
    source,
    /Pandora could not start this build before its execution window ended\./,
  );
  assert.match(
    source,
    /Pandora did not start this build because its build budget was unavailable\./,
  );
  assert.doesNotMatch(
    source.match(/v_message := case[\s\S]*?end;/)?.[0] ?? '',
    /found something to fix and is working on it/,
  );
});

