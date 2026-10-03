'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');
const { PGlite } = require('@electric-sql/pglite');
const { normalizeActivityEvent } = require('../packages/pandora-activity-theatre/src/activity-theatre-event');

const read = (path) => readFileSync(join(__dirname, '..', path), 'utf8');
const signature = 'public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamp with time zone)';
const migration = read('supabase/migrations/20261003170300_pandora_device_activity_cancel_v1.sql');
const previous = read('supabase/migrations/20260916124500_r061_direct_communication_activity_v1.sql')
  .replace('\nbegin\n', '\nbegin\n  perform private.pandora_core_activity_scope_v1(p_organization_id);\n');
const org = randomUUID();
const otherOrg = randomUUID();
const owner = randomUUID();
const colleague = randomUUID();
const stranger = randomUUID();
const operation = 'device-operation.fixture';
let db;

async function actor(user = owner, role = 'authenticated') {
  assert.ok(['authenticated', 'anon'].includes(role));
  await db.exec('reset role');
  // Auth identity is simulated only inside this isolated SQL unit fixture.
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
  await db.exec(`set role ${role}`);
}

async function makeJob({ organization = org, user = owner } = {}) {
  const id = randomUUID();
  await db.exec('reset role');
  await db.query('insert into public.pandora_activity_jobs(id,organization_id,requested_by) values($1,$2,$3)', [id, organization, user]);
  await actor();
  return id;
}

async function fact(job, stage, { capability = 'calendar.events', organization = org, operationId = operation } = {}) {
  return (await db.query(`select ${signature.split('(')[0]}($1,$2,$3,$4,$5,now()) receipt`,
    [organization, job, operationId, capability, stage])).rows[0].receipt;
}

async function rows(job) {
  await db.exec('reset role');
  return (await db.query('select event from public.pandora_activity_events where job_id=$1 order by sequence', [job])).rows.map((row) => row.event);
}

async function rejected(action, pattern) {
  await db.exec('savepoint rejected_fact');
  try {
    await assert.rejects(action, pattern);
  } finally {
    await db.exec('rollback to savepoint rejected_fact;release savepoint rejected_fact');
  }
}

test.before(async () => {
  db = new PGlite();
  await db.exec(`
    set time zone 'UTC';
    create schema auth;
    create schema private;
    create role anon;
    create role authenticated;
    grant usage on schema auth,public to anon,authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
    $$;
    create table public.memberships(organization_id uuid,user_id uuid,status text);
    create table private.fixture_scope_rejections(organization_id uuid primary key);
    create function private.pandora_core_activity_scope_v1(p_org uuid) returns void
      language plpgsql security definer set search_path='' as $$begin
      if exists(select 1 from private.fixture_scope_rejections where organization_id=p_org) then
        raise exception 'CORE_ACTIVITY_SCOPE_REJECTED' using errcode='42501';
      end if;
    end;$$;
    revoke all on function private.pandora_core_activity_scope_v1(uuid) from public,anon,authenticated;
    create table public.pandora_activity_jobs(
      id uuid primary key,organization_id uuid not null,requested_by uuid not null,
      writer_epoch bigint not null default 1,writer_id text not null default 'pandora-android-device-v1',
      last_sequence bigint not null default 0,terminal_state text,updated_at timestamptz not null default now()
    );
    create table public.pandora_activity_events(
      job_id uuid not null,organization_id uuid not null,sequence bigint not null,event_id text not null,
      writer_epoch bigint not null,state text not null,message text not null,event jsonb not null,
      occurred_at timestamptz not null,admitted_at timestamptz not null,
      primary key(job_id,sequence),unique(job_id,event_id)
    );
    revoke all on all tables in schema public from public,anon,authenticated;
  `);
  await db.query("insert into public.memberships values($1,$2,'active'),($1,$3,'active'),($4,$5,'active')", [org, owner, colleague, otherOrg, stranger]);
  await db.exec(previous);
  const baseline = (await db.query('select md5(prosrc) hash from pg_proc where oid=$1::regprocedure', [signature])).rows[0].hash;
  assert.equal(baseline, '74f72bcacd0b3177a930dbfcd7bc2df8', 'fixture is the live scoped function body');
  await db.exec(migration);
});
test.after(async () => { await db?.close(); });
test.beforeEach(async () => { await db.exec('reset role;begin'); });
test.afterEach(async () => { await db.exec('rollback;reset role'); });

test('before-effect cancellation is terminal, replayable and valid Activity evidence for every native capability', async () => {
  for (const capability of ['calendar.events', 'reminder.local', 'communication.sms', 'communication.call']) {
    const job = await makeJob();
    await fact(job, 'acting', { capability });
    const cancelled = await fact(job, 'cancelled', { capability });
    assert.equal(cancelled.state, 'cancelled');
    assert.equal(cancelled.sequence, 2);
    assert.equal(cancelled.duplicate, false);
    const again = await fact(job, 'cancelled', { capability });
    assert.equal(again.duplicate, true);
    assert.equal(again.eventId, cancelled.eventId);
    assert.equal(again.sequence, cancelled.sequence);
    const events = await rows(job);
    assert.equal(events.length, 2);
    const event = normalizeActivityEvent(events[1]);
    assert.equal(event.state, 'cancelled');
    assert.equal(event.outcome, null);
    assert.deepEqual(event.evidence.map(({ type, relation }) => ({ type, relation })), [
      { type: 'device_event', relation: 'authoritative_cancellation' },
    ]);
    const saved = (await db.query('select terminal_state,last_sequence from public.pandora_activity_jobs where id=$1', [job])).rows[0];
    assert.equal(saved.terminal_state, 'cancelled');
    assert.equal(Number(saved.last_sequence), 2);
  }
});

test('a cancelled operation rejects late progress or completion instead of resurrecting the job', async () => {
  const job = await makeJob();
  await fact(job, 'cancelled');
  for (const stage of ['acting', 'verifying', 'result']) {
    await rejected(() => fact(job, stage), /pandora_activity_job_terminal/);
  }
  assert.deepEqual((await rows(job)).map((event) => event.state), ['cancelled']);
});

test('a committed native result cannot be replaced by late cancellation', async () => {
  const job = await makeJob();
  await fact(job, 'acting');
  await fact(job, 'verifying');
  const committed = await fact(job, 'result');
  await rejected(() => fact(job, 'cancelled'), /pandora_activity_job_terminal/);
  const duplicate = await fact(job, 'result');
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.eventId, committed.eventId);
  const events = await rows(job);
  assert.deepEqual(events.map((event) => event.state), ['acting', 'verifying', 'result']);
  assert.equal(normalizeActivityEvent(events[2]).state, 'result');
  assert.equal(events[2].outcome.physicalDevice, false);
});

test('another active member cannot cancel the requesting user job', async () => {
  const job = await makeJob();
  await actor(colleague);
  await rejected(() => fact(job, 'cancelled'), /pandora_activity_job_not_available/);
  assert.equal((await rows(job)).length, 0);
});

test('cross-organization and inactive membership cancellation remain denied', async () => {
  const job = await makeJob();
  await actor(stranger);
  await rejected(() => fact(job, 'cancelled'), /pandora_activity_membership_required/);
  await rejected(() => fact(job, 'cancelled', { organization: otherOrg }), /pandora_activity_job_not_available/);
  await db.exec('reset role');
  await db.query("update public.memberships set status='inactive' where user_id=$1", [owner]);
  await actor();
  await rejected(() => fact(job, 'cancelled'), /pandora_activity_membership_required/);
  assert.equal((await rows(job)).length, 0);
});

test('current Core scope rejection still runs before device fact admission', async () => {
  const job = await makeJob();
  await db.exec('reset role');
  await db.query('insert into private.fixture_scope_rejections values($1)', [org]);
  await actor();
  await rejected(() => fact(job, 'cancelled'), /CORE_ACTIVITY_SCOPE_REJECTED/);
  assert.equal((await rows(job)).length, 0);
});

test('anonymous callers and arbitrary stages or capabilities cannot mint cancellation evidence', async () => {
  const job = await makeJob();
  await actor(null, 'anon');
  await rejected(() => fact(job, 'cancelled'), /permission denied/);
  await actor();
  await rejected(() => fact(job, 'cancelled', { capability: 'unbounded.operator.action' }), /pandora_device_capability_invalid/);
  await rejected(() => fact(job, 'invented'), /pandora_device_stage_invalid/);
  await rejected(() => fact(job, 'cancelled', { operationId: 'short' }), /pandora_device_operation_id_invalid/);
  assert.equal((await rows(job)).length, 0);
});

test('the forward patch is repeatable and refuses a drifted function body', async () => {
  await db.exec(migration);
  const patched = (await db.query('select md5(prosrc) hash,pg_get_functiondef(oid) definition from pg_proc where oid=$1::regprocedure', [signature])).rows[0];
  assert.equal(patched.hash, 'bcd54210c01e418d17071a77cbef4347');
  assert.match(patched.definition, /perform private\.pandora_core_activity_scope_v1\(p_organization_id\)/);
  const drifted = patched.definition.replace('declare\n', 'declare\n  -- Unreviewed fixture drift.\n');
  assert.notEqual(drifted, patched.definition);
  await db.exec(drifted);
  await rejected(() => db.exec(migration), /PANDORA_DEVICE_CANCEL_BASELINE_CHANGED/);
});

test('the mobile bounded stage allowlist admits the same cancellation fact', () => {
  const mobile = read('apps/pandora-mobile/lib/core/data/pandora_activity_stream_api.dart');
  const stages = mobile.slice(mobile.indexOf("'acting'"), mobile.indexOf('}.contains(safeStage)'));
  assert.match(stages, /'cancelled'/);
  assert.match(mobile, /'p_stage': safeStage/);
});
