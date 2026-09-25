const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { PGlite } = require('@electric-sql/pglite');

const migrations = join(__dirname, '..', 'supabase', 'migrations');
const original = readFileSync(join(migrations,
  '20260828193000_pandora_realtime_audit_security_v1.sql'), 'utf8');
const previousTrigger = readFileSync(join(migrations,
  '20260910161000_pandora_theatre_mid_generation_truth_v1.sql'), 'utf8');
const correction = readFileSync(join(migrations,
  '20260925101500_pandora_build_theatre_cancelled_truth_v1.sql'), 'utf8');

const ORG = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const PROJECT = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const OLD = '11111111-1111-4111-8111-111111111111';
const NEW = '22222222-2222-4222-8222-222222222222';
const VERSION_PREEXISTING = '33333333-3333-4333-8333-333333333333';
const VERSION_CANDIDATE = '44444444-4444-4444-8444-444444444444';

function extractFunction(source, name, closingDelimiter) {
  const start = source.indexOf(`create or replace function private.${name}(`);
  assert.ok(start >= 0, `missing canonical function ${name}`);
  const end = source.indexOf(`\n${closingDelimiter};`, start);
  assert.ok(end > start, `missing close for ${name}`);
  return source.slice(start, end + closingDelimiter.length + 2);
}

async function setup(db) {
  await db.exec(`
    create schema private;
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create table public.pandora_build_jobs (
      id uuid primary key, organization_id uuid not null, project_id uuid not null,
      job_kind text not null default 'build', created_at timestamptz not null,
      project_spec_id uuid, target_project_version_id uuid,
      status text not null, current_stage text, error_code text,
      public_error_summary text, attempt_count int not null default 0,
      started_at timestamptz
    );
    create table public.pandora_build_stream_events (
      build_job_id uuid not null, event_type text not null
    );
    create table public.pandora_build_theatre_projection (
      project_id uuid primary key, organization_id uuid not null,
      build_job_id uuid, project_spec_id uuid, project_version_id uuid,
      owner_state text not null, owner_stage text not null,
      progress_percent smallint,
      public_message text not null, preview_url text, live_url text,
      needs_you boolean not null, retry_available boolean not null,
      last_event_at timestamptz not null, updated_at timestamptz not null,
      constraint pandora_build_theatre_projection_stage_check check (
        owner_stage in (
          'understanding','designing','building','connecting','checking','fixing',
          'preparing_preview','preview_ready','needs_you','publishing','live'
        )
      ),
      constraint pandora_build_theatre_projection_progress_check check (
        progress_percent is null or progress_percent between 0 and 100
      )
    );
    create function private.pandora_trusted_primitive_unavailable_message_20260910(uuid,text)
      returns text language sql as $$select 'Trusted primitive unavailable.'::text$$;
  `);
  for (const name of [
    'pandora_build_theatre_owner_stage',
    'pandora_build_theatre_owner_state',
    'pandora_build_theatre_progress',
    'pandora_build_theatre_message',
  ]) await db.exec(extractFunction(original, name, '$$'));
  await db.exec(extractFunction(previousTrigger,
    'pandora_sync_build_theatre_from_job', '$function$'));
  await db.exec(`
    create trigger build_theatre_project_job after insert or update
    on public.pandora_build_jobs for each row
    execute function private.pandora_sync_build_theatre_from_job();
    revoke all on function private.pandora_build_theatre_owner_stage(text,text)
      from public,anon,authenticated;
    revoke all on function private.pandora_build_theatre_owner_state(text,text)
      from public,anon,authenticated;
    revoke all on function private.pandora_build_theatre_progress(text,text)
      from public,anon,authenticated;
    revoke all on function private.pandora_build_theatre_message(text,text)
      from public,anon,authenticated;
    grant execute on function private.pandora_build_theatre_owner_state(text,text)
      to service_role;
  `);
}

async function state(db, stage, status) {
  const { rows } = await db.query(`
    select private.pandora_build_theatre_owner_state($1,$2) as owner_state,
      private.pandora_build_theatre_owner_stage($1,$2) as owner_stage,
      private.pandora_build_theatre_progress($1,$2) as progress_percent,
      private.pandora_build_theatre_message($1,$2) as public_message
  `, [stage, status]);
  return rows[0];
}

async function projection(db) {
  const { rows } = await db.query(`select build_job_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,preview_url,live_url,
    needs_you,retry_available from public.pandora_build_theatre_projection
    where project_id=$1`, [PROJECT]);
  return rows[0];
}

async function insertJob(db, id, timestamp, status = 'running', stage = 'building') {
  await db.query(`insert into public.pandora_build_jobs
    (id,organization_id,project_id,created_at,status,current_stage,
     target_project_version_id,attempt_count,started_at)
    values ($1,$2,$3,$4,$5,$6,$7,1,'2026-09-25T08:00:00Z')`,
  [id, ORG, PROJECT, timestamp, status, stage, VERSION_CANDIDATE]);
}

test('upgrade path fixes cancelled projection while retaining preexisting version and URLs', async () => {
  const db = new PGlite();
  try {
    await setup(db);
    assert.equal((await state(db, 'live', 'cancelled')).owner_state, 'live');
    await insertJob(db, OLD, '2026-09-25T09:00:00Z');
    await db.query(`update public.pandora_build_theatre_projection
      set project_version_id=$1, preview_url='https://preview.example.test',
      live_url='https://example.test' where project_id=$2`,
    [VERSION_PREEXISTING, PROJECT]);

    await db.exec(correction);
    await db.query(`update public.pandora_build_jobs
      set status='cancelled',current_stage='live'
      where id=$1`, [OLD]);
    assert.deepEqual(await projection(db), {
      build_job_id: OLD,
      project_version_id: VERSION_PREEXISTING,
      owner_state: 'blocked',
      owner_stage: 'cancelled',
      progress_percent: null,
      public_message: 'This build was cancelled. You can retry.',
      preview_url: 'https://preview.example.test',
      live_url: 'https://example.test',
      needs_you: false,
      retry_available: true,
    });
    const { rows } = await db.query(`select
      has_function_privilege('anon','private.pandora_build_theatre_owner_state(text,text)','EXECUTE') as anon,
      has_function_privilege('authenticated','private.pandora_build_theatre_owner_state(text,text)','EXECUTE') as authenticated,
      has_function_privilege('service_role','private.pandora_build_theatre_owner_state(text,text)','EXECUTE') as service`);
    assert.deepEqual(rows[0], { anon: false, authenticated: false, service: true });
  } finally {
    await db.close();
  }
});

test('clean isolated fixture makes cancellation terminal across stale stages and retains controls', async () => {
  const db = new PGlite();
  try {
    await setup(db);
    await db.exec(correction);
    for (const stage of [
      'live','preview_ready','publishing','verifying','building',
      'awaiting_approval','needs_you',
    ]) {
      assert.deepEqual(await state(db, stage, 'cancelled'), {
        owner_state: 'blocked', owner_stage: 'cancelled', progress_percent: null,
        public_message: 'This build was cancelled. You can retry.',
      }, stage);
    }
    for (const [stage, status, expected] of [
      ['live','failed','blocked'],
      ['building','waiting_approval','needs_you'],
      ['building','waiting_verification','checking'],
      ['live','succeeded','live'],
      ['building','running','building'],
    ]) assert.equal((await state(db, stage, status)).owner_state, expected);

    await insertJob(db, OLD, '2026-09-25T09:00:00Z');
    await insertJob(db, NEW, '2026-09-25T09:01:00Z');
    const latest = await projection(db);
    await db.query(`update public.pandora_build_jobs
      set status='cancelled',current_stage='live'
      where id=$1`, [OLD]);
    assert.deepEqual(await projection(db), latest, 'late older job cannot overwrite latest');

    await db.query(`update public.pandora_build_jobs
      set status='cancelled',current_stage='awaiting_approval'
      where id=$1`, [NEW]);
    const cancelled = await projection(db);
    assert.equal(cancelled.owner_state, 'blocked',
      'a preexisting candidate version cannot make a cancelled job live');
    assert.equal(cancelled.owner_stage, 'cancelled');
    assert.equal(cancelled.progress_percent, null);
    assert.equal(cancelled.needs_you, false);
    assert.equal(cancelled.retry_available, true);
    assert.equal(cancelled.project_version_id, VERSION_CANDIDATE,
      'preexisting projection version remains; its verification is not established here');

    await db.query(`update public.pandora_build_jobs set status='failed',
      current_stage='failed',error_code='INVALID_GENERATED_SOURCE_X'
      where id=$1`, [NEW]);
    const failed = await projection(db);
    assert.equal(failed.owner_state, 'blocked');
    assert.equal(failed.owner_stage, 'needs_you');
    assert.equal(failed.public_message,
      'Pandora could not finish generating this project. You can try again.');
  } finally {
    await db.close();
  }
});

test('preexecution cancellation keeps did-not-start copy and no fabricated progress', async () => {
  const db = new PGlite();
  try {
    await setup(db);
    await db.exec(correction);
    await db.query(`insert into public.pandora_build_jobs
      (id,organization_id,project_id,created_at,status,current_stage,attempt_count)
      values ($1,$2,$3,'2026-09-25T09:00:00Z','cancelled','live',0)`,
    [OLD, ORG, PROJECT]);
    const cancelled = await projection(db);
    assert.equal(cancelled.owner_state, 'blocked');
    assert.equal(cancelled.owner_stage, 'cancelled');
    assert.equal(cancelled.progress_percent, null);
    assert.equal(cancelled.public_message,
      'Pandora did not start this build. You can try again.');
    assert.equal(cancelled.project_version_id, null);
    assert.equal(cancelled.needs_you, false);
  } finally {
    await db.close();
  }
});
