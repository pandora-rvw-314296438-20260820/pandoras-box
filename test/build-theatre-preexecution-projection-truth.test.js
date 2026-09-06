const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  'supabase/migrations/20260906034034_pandora_build_theatre_preexecution_truth_v1.sql',
  'utf8',
);
const backfill = fs.readFileSync(
  'supabase/migrations/20260906034111_pandora_build_theatre_preexecution_truth_backfill_v1.sql',
  'utf8',
);

test('pre-execution terminal builds do not look like active repair work', () => {
  assert.match(migration, /new\.status in \('failed','cancelled'\)/);
  assert.match(migration, /coalesce\(new\.attempt_count, 0\) = 0/);
  assert.match(migration, /new\.started_at is null/);
  assert.match(migration, /when v_preexecution_terminal then 0/);
  assert.match(migration, /when v_preexecution_terminal then 'understanding'/);
  assert.match(migration, /Pandora could not start this build before its execution window ended\./);
  assert.match(migration, /Pandora did not start this build because its build budget was unavailable\./);
  assert.doesNotMatch(
    migration.match(/v_message := case[\s\S]*?end;/)?.[0] ?? '',
    /found something to fix and is working on it/,
  );
});

test('backfill only rewrites the latest matching projection and never reopens a build', () => {
  assert.match(backfill, /distinct on \(j\.project_id\)/);
  assert.match(backfill, /p\.build_job_id=l\.id/);
  assert.match(backfill, /owner_stage='understanding'/);
  assert.match(backfill, /progress_percent=0/);
  assert.match(backfill, /retry_available=true/);
  assert.doesNotMatch(backfill, /update public\.pandora_build_jobs/);
  assert.doesNotMatch(backfill, /status\s*=\s*'queued'/);
});
