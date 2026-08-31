const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migrationPath = join(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '20260831085000_pandora_project_experience_projection_v1.sql',
);
const source = readFileSync(migrationPath, 'utf8');

test('experience projection is derived, member-readable, and realtime-enabled', () => {
  assert.match(source, /create table if not exists public\.pandora_project_experience_projection/i);
  assert.match(source, /private\.is_org_member\(organization_id\)/);
  assert.match(source, /alter publication supabase_realtime[\s\S]*pandora_project_experience_projection/i);
  assert.match(source, /revoke insert, update, delete[\s\S]*from authenticated/i);
  assert.match(source, /grant select[\s\S]*to authenticated/i);
});

test('experience projection keeps canonical current, candidate, production, and verification lineage', () => {
  assert.match(source, /current_version_id uuid references public\.pandora_project_versions/);
  assert.match(source, /candidate_version_id uuid references public\.pandora_project_versions/);
  assert.match(source, /production_version_id uuid references public\.pandora_project_versions/);
  assert.match(source, /candidate_version_id <> current_version_id/);
  assert.match(source, /candidate_verification_state = 'passed'/);
  assert.match(source, /current_verified/);
  assert.match(source, /verification_summary jsonb/);
});

test('build theatre remains activity-only and cannot override canonical product state', () => {
  assert.doesNotMatch(source, /\bowner_state\b/);
  assert.doesNotMatch(source, /customerJourney/);
  assert.match(source, /t\.build_job_id as theatre_build_job_id/);
  assert.match(source, /s\.theatre_build_job_id = s\.active_build_job_id/);
  assert.match(source, /when n\.current_version_id is not null or n\.production_version_id is not null[\s\S]*then 'LIVE'/);
});

test('spec compilation state ignores non-product verify intents', () => {
  assert.match(source, /i\.intent_kind in \('create','build','change'\)/);
  assert.doesNotMatch(source, /i\.intent_kind in \('create','build','change','verify'\)/);
});

test('failed candidates preserve a safe current product', () => {
  assert.match(
    source,
    /when n\.current_version_id is not null[\s\S]*normalized_candidate_verification_state in \('failed','blocked'\)[\s\S]*then 'LIVE'/,
  );
  assert.match(source, /Your current version is still safe/);
  assert.match(source, /candidate equals current version/);
});

test('publish stays fail-closed to a verified exact target', () => {
  assert.match(
    source,
    /check \(not can_publish or candidate_verification_state = 'passed' or current_verified\)/,
  );
  assert.match(
    source,
    /candidate_version_id is not null[\s\S]*normalized_candidate_verification_state = 'passed'[\s\S]*candidate_preview_ready/,
  );
  assert.match(
    source,
    /current_version_id is not null[\s\S]*is_current_verified[\s\S]*current_version_id is distinct from s\.production_version_id/,
  );
});

test('visible transitions are monotonic and do not emit no-op updates', () => {
  assert.match(source, /transition_sequence = transition_sequence \+ 1/);
  assert.match(source, /v_current_payload is not distinct from v_next_payload[\s\S]*return;/);
  assert.match(source, /last_transition_at = now\(\)/);
});

test('all canonical lifecycle inputs refresh the projection', () => {
  for (const table of [
    'projectos_projects',
    'pandora_project_intents',
    'pandora_project_specs',
    'pandora_project_versions',
    'pandora_build_jobs',
    'pandora_build_theatre_projection',
    'pandora_project_deployments',
    'pandora_verification_runs',
    'pandora_verification_checks',
    'pandora_runtime_environments',
  ]) {
    assert.match(source, new RegExp(`on public\\.${table.replaceAll('_', '\\_')}`, 'i'));
  }
});


test('realtime publication update is portable when publication is absent', () => {
  assert.match(source, /from pg_publication\s+where pubname = 'supabase_realtime'/);
  assert.match(source, /and not exists \([\s\S]*from pg_publication_tables/);
});
