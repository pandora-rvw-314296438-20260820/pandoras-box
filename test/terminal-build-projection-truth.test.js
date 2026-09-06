const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  'supabase/migrations/20260906185211_pandora_terminal_build_projection_truth_v1.sql',
  'utf8',
);

test('terminal failed builds stop presenting active repair work', () => {
  assert.match(migration, /v_terminal_failure := new\.status = 'failed'/);
  assert.match(migration, /when v_terminal_failure then 'needs_you'/);
  assert.match(migration, /new\.status = 'failed' or new\.status = 'waiting_approval'/);
  assert.match(migration, /This build stopped before it was ready\. You can retry\./);
  assert.match(migration, /owner_state='blocked'/);
  assert.match(migration, /owner_stage='needs_you'/);
  assert.match(migration, /needs_you=true/);
  assert.match(migration, /retry_available=true/);
});

test('terminal failed projects with no current version are not projected as BUILD', () => {
  assert.match(migration, /n\.latest_failure_is_relevant/);
  assert.match(migration, /n\.active_build_job_id is null/);
  assert.match(migration, /then 'UNDERSTAND'/);
  assert.match(migration, /latest_job_public_error_summary/);
  assert.match(migration, /pandora_refresh_project_experience_projection_v1/);
  assert.doesNotMatch(migration, /update public\.pandora_build_jobs\s+set\s+status\s*=\s*'queued'/i);
});
