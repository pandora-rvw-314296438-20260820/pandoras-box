const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migrationPath = join(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '20260831143000_pandora_project_experience_drift_telemetry_v1.sql',
);
const source = readFileSync(migrationPath, 'utf8');

test('drift telemetry is a private observation-only contract', () => {
  assert.match(source, /create table if not exists private\.pandora_project_experience_drift_observations/i);
  assert.match(source, /Observation-only lifecycle drift telemetry/i);
  assert.match(source, /unique \(project_id, source, drift_code\)/i);
  assert.match(source, /revoke all on table[\s\S]*from authenticated/i);
  assert.match(source, /grant select on table private\.pandora_project_experience_drift_observations to service_role/i);
  assert.doesNotMatch(source, /grant (?:insert|update|delete)[\s\S]*pandora_project_experience_drift_observations[\s\S]*to service_role/i);
  assert.doesNotMatch(source, /update public\.pandora_project_experience_projection/i);
});

test('capture compares legacy customerJourney and Build Theatre against canonical projection', () => {
  assert.match(source, /p\.config -> 'customerJourney'/);
  assert.match(source, /public\.pandora_build_theatre_projection/);
  assert.match(source, /public\.pandora_project_experience_projection/);
  for (const code of [
    'legacy_live_without_canonical_live',
    'canonical_live_legacy_stage_stale',
    'published_version_mismatch',
    'preview_version_outside_canonical_graph',
    'active_build_job_mismatch',
    'theatre_version_outside_canonical_graph',
    'needs_you_mismatch',
    'retry_available_mismatch',
    'theatre_live_without_canonical_live',
  ]) {
    assert.match(source, new RegExp(code));
  }
});

test('capture is idempotent and resolves stale observations', () => {
  assert.match(source, /set resolved_at = v_now[\s\S]*where project_id = p_project_id[\s\S]*resolved_at is null/i);
  assert.match(source, /on conflict \(project_id, source, drift_code\)/i);
  assert.match(source, /occurrence_count = private\.pandora_project_experience_drift_observations\.occurrence_count \+ 1/i);
  assert.match(source, /resolved_at = null/i);
});

test('canonical LIVE precedence over a background theatre build remains valid', () => {
  assert.match(source, /A LIVE canonical state with a background theatre build is valid/i);
  assert.doesNotMatch(source, /canonical_live_theatre_nonlive/);
  assert.match(source, /l\.theatre_build_job_id = e\.active_build_job_id[\s\S]*theatre_needs_you is distinct from e\.needs_you/i);
});

test('existing touch flow refreshes canonical state before capturing drift', () => {
  assert.match(
    source,
    /perform private\.pandora_refresh_project_experience_projection_v1\(v_project_id\);\s*perform private\.pandora_capture_project_experience_drift_v1\(v_project_id\);/i,
  );
});

test('resolved drift has an explicit bounded retention contract', () => {
  assert.match(source, /p_retention interval default interval '30 days'/i);
  assert.match(source, /drift retention must be at least 1 day/i);
  assert.match(source, /resolved_at < now\(\) - p_retention/i);
  assert.match(source, /grant execute on function private\.pandora_prune_project_experience_drift_v1\(interval\) to service_role/i);
});
