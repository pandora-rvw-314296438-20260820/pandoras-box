const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { PGlite } = require('@electric-sql/pglite');

const migration = readFileSync(
  join(__dirname, '../supabase/migrations/20260915104500_pandora_activity_history_v1.sql'),
  'utf8',
);

const orgA = '10000000-0000-4000-8000-000000000001';
const orgB = '10000000-0000-4000-8000-000000000002';
const ownerA = '20000000-0000-4000-8000-000000000001';
const adminA = '20000000-0000-4000-8000-000000000002';
const memberA = '20000000-0000-4000-8000-000000000003';
const inactiveA = '20000000-0000-4000-8000-000000000004';
const revokedA = '20000000-0000-4000-8000-000000000005';
const ownerB = '20000000-0000-4000-8000-000000000006';
const jobOwner = '30000000-0000-4000-8000-000000000001';
const jobAdmin = '30000000-0000-4000-8000-000000000002';
const jobMember = '30000000-0000-4000-8000-000000000003';
const jobOtherOrg = '30000000-0000-4000-8000-000000000004';
const threadOwner = '40000000-0000-4000-8000-000000000001';
const projectOwner = '50000000-0000-4000-8000-000000000001';

function event({
  eventId,
  jobId,
  sequence,
  state,
  occurredAt,
  message,
  domain = 'chat',
  sourceType = 'runtime',
  sourceId = 'pandora-runtime',
  outcome,
  blocker,
  evidenceRefs = [],
}) {
  return {
    schemaVersion: 1,
    eventId,
    jobId,
    sequence,
    writerEpoch: 1,
    state,
    occurredAt,
    message,
    domain,
    capability: domain === 'device' ? 'device.communication' : 'intelligence.chat',
    executionId: `execution-${sequence}`,
    provenance: {
      sourceType,
      sourceId,
      sourceEventId: `source-${eventId}`,
      observedAt: occurredAt,
    },
    evidenceRefs,
    ...(outcome ? { outcome } : {}),
    ...(blocker ? { blocker } : {}),
  };
}

async function makeDb(t) {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema auth;
    grant usage on schema public, auth to anon, authenticated, service_role;

    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;

    create table public.organizations (
      id uuid primary key,
      name text not null
    );
    create table public.profiles (
      id uuid primary key,
      display_name text
    );
    create table public.memberships (
      organization_id uuid not null,
      user_id uuid not null,
      role text not null,
      status text not null
    );
    create table public.pandora_activity_jobs (
      id uuid primary key,
      organization_id uuid not null,
      requested_by uuid not null,
      thread_id uuid,
      project_id uuid,
      created_at timestamptz not null default now()
    );
    create table public.pandora_activity_events (
      job_id uuid not null,
      organization_id uuid not null,
      sequence bigint not null,
      admitted_at timestamptz not null,
      expires_at timestamptz not null,
      event jsonb not null,
      state text not null,
      message text not null,
      event_id text not null,
      primary key (job_id, sequence)
    );

    insert into public.organizations(id,name) values
      ('${orgA}','Pandora A'),
      ('${orgB}','Pandora B');
    insert into public.profiles(id,display_name) values
      ('${ownerA}','Owner A'),
      ('${adminA}','Admin A'),
      ('${memberA}','Member A'),
      ('${inactiveA}','Inactive A'),
      ('${revokedA}','Revoked A'),
      ('${ownerB}','Owner B');
    insert into public.memberships(organization_id,user_id,role,status) values
      ('${orgA}','${ownerA}','owner','active'),
      ('${orgA}','${adminA}','admin','active'),
      ('${orgA}','${memberA}','member','active'),
      ('${orgA}','${inactiveA}','admin','inactive'),
      ('${orgA}','${revokedA}','owner','revoked'),
      ('${orgB}','${ownerB}','owner','active');
    insert into public.pandora_activity_jobs(id,organization_id,requested_by,thread_id,project_id,created_at) values
      ('${jobOwner}','${orgA}','${ownerA}','${threadOwner}','${projectOwner}','2026-09-15T10:00:00Z'),
      ('${jobAdmin}','${orgA}','${adminA}',null,null,'2026-09-15T10:01:00Z'),
      ('${jobMember}','${orgA}','${memberA}',null,null,'2026-09-15T10:02:00Z'),
      ('${jobOtherOrg}','${orgB}','${ownerB}',null,null,'2026-09-15T10:03:00Z');
  `);

  const ownerEvents = [
    {
      sequence: 1,
      admittedAt: '2026-09-15T10:10:00Z',
      payload: event({
        eventId: 'event-owner-understanding', jobId: jobOwner, sequence: 1,
        state: 'understanding', occurredAt: '2026-09-15T10:09:59Z',
        message: 'Understanding the requested task.',
      }),
    },
    {
      sequence: 2,
      admittedAt: '2026-09-15T10:20:00Z',
      payload: event({
        eventId: 'event-owner-device', jobId: jobOwner, sequence: 2,
        state: 'checking', occurredAt: '2026-09-15T10:19:59Z',
        message: 'Checked device communication readiness.', domain: 'device',
        sourceType: 'device', sourceId: 'android-device-agent',
        evidenceRefs: [{ type: 'device_event', relation: 'source', ref: 'device:readiness:001' }],
      }),
    },
    {
      sequence: 3,
      admittedAt: '2026-09-15T10:30:00Z',
      payload: event({
        eventId: 'event-owner-result', jobId: jobOwner, sequence: 3,
        state: 'result', occurredAt: '2026-09-15T10:29:59Z',
        message: 'Verified the requested result.',
        evidenceRefs: [{ type: 'verification_receipt', relation: 'verification', ref: 'verification:owner:001' }],
        outcome: { summary: 'Result verified from canonical runtime evidence.', physicalDevice: false },
      }),
    },
  ];

  for (const item of ownerEvents) {
    await db.query(
      `insert into public.pandora_activity_events
        (job_id,organization_id,sequence,admitted_at,expires_at,event,state,message,event_id)
       values ($1,$2,$3,$4,now()+interval '30 days',$5,$6,$7,$8)`,
      [jobOwner, orgA, item.sequence, item.admittedAt, JSON.stringify(item.payload), item.payload.state, item.payload.message, item.payload.eventId],
    );
  }

  const adminPayload = event({
    eventId: 'event-admin-result', jobId: jobAdmin, sequence: 1, state: 'result',
    occurredAt: '2026-09-15T10:39:59Z', message: 'Admin requested result.',
    evidenceRefs: [{ type: 'verification_receipt', relation: 'verification', ref: 'verification:admin:001' }],
    outcome: { summary: 'Admin-owned result.', physicalDevice: false },
  });
  const memberPayload = event({
    eventId: 'event-member-result', jobId: jobMember, sequence: 1, state: 'result',
    occurredAt: '2026-09-15T10:49:59Z', message: 'Member requested result.',
    evidenceRefs: [{ type: 'verification_receipt', relation: 'verification', ref: 'verification:member:001' }],
    outcome: { summary: 'Member-owned result.', physicalDevice: false },
  });
  const otherOrgPayload = event({
    eventId: 'event-other-org-result', jobId: jobOtherOrg, sequence: 1, state: 'result',
    occurredAt: '2026-09-15T10:59:59Z', message: 'Other tenant result.',
    evidenceRefs: [{ type: 'verification_receipt', relation: 'verification', ref: 'verification:other:001' }],
    outcome: { summary: 'Other tenant result.', physicalDevice: false },
  });

  for (const [jobId, organizationId, admittedAt, payload] of [
    [jobAdmin, orgA, '2026-09-15T10:40:00Z', adminPayload],
    [jobMember, orgA, '2026-09-15T10:50:00Z', memberPayload],
    [jobOtherOrg, orgB, '2026-09-15T11:00:00Z', otherOrgPayload],
  ]) {
    await db.query(
      `insert into public.pandora_activity_events
        (job_id,organization_id,sequence,admitted_at,expires_at,event,state,message,event_id)
       values ($1,$2,1,$3,now()+interval '30 days',$4,$5,$6,$7)`,
      [jobId, organizationId, admittedAt, JSON.stringify(payload), payload.state, payload.message, payload.eventId],
    );
  }

  const expired = event({
    eventId: 'event-owner-expired', jobId: jobOwner, sequence: 4, state: 'failed',
    occurredAt: '2026-08-01T10:00:00Z', message: 'Expired canonical event.',
  });
  await db.query(
    `insert into public.pandora_activity_events
      (job_id,organization_id,sequence,admitted_at,expires_at,event,state,message,event_id)
     values ($1,$2,4,'2026-08-01T10:00:01Z',now()-interval '1 second',$3,$4,$5,$6)`,
    [jobOwner, orgA, JSON.stringify(expired), expired.state, expired.message, expired.eventId],
  );

  await db.exec(migration);
  return db;
}

async function actAs(db, user, role = 'authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
  await db.exec(`set role ${role}`);
}

async function history(db, organizationId = orgA, args = {}) {
  const params = [organizationId];
  const clauses = [];
  const mapping = [
    ['query', 'p_query', 'text'],
    ['states', 'p_states', 'text[]'],
    ['domains', 'p_domains', 'text[]'],
    ['sourceTypes', 'p_source_types', 'text[]'],
    ['requestedBy', 'p_requested_by', 'uuid'],
    ['jobId', 'p_job_id', 'uuid'],
    ['from', 'p_from', 'timestamptz'],
    ['to', 'p_to', 'timestamptz'],
    ['beforeAdmittedAt', 'p_before_admitted_at', 'timestamptz'],
    ['beforeJobId', 'p_before_job_id', 'uuid'],
    ['beforeSequence', 'p_before_sequence', 'bigint'],
    ['limit', 'p_limit', 'integer'],
  ];
  for (const [key, sqlName, type] of mapping) {
    if (Object.prototype.hasOwnProperty.call(args, key)) {
      params.push(args[key]);
      clauses.push(`${sqlName} => $${params.length}::${type}`);
    }
  }
  const suffix = clauses.length ? `, ${clauses.join(', ')}` : '';
  const { rows } = await db.query(
    `select public.pandora_activity_history_search_v1($1::uuid${suffix}) as result`,
    params,
  );
  return rows[0].result;
}

function ids(result) {
  return result.items.map((item) => item.event.eventId);
}

test('History enforces requester identity, active membership, tenant isolation, and no owner/admin widening', async (t) => {
  const db = await makeDb(t);

  await actAs(db, ownerA);
  let result = await history(db);
  assert.deepEqual(ids(result), [
    'event-owner-result',
    'event-owner-device',
    'event-owner-understanding',
  ]);
  assert.ok(result.items.every((item) => item.requestedBy === ownerA));
  await assert.rejects(history(db, orgA, { requestedBy: adminA }), /pandora_activity_history_person_forbidden/);
  await assert.rejects(history(db, orgB), /pandora_activity_membership_required/);

  await actAs(db, adminA);
  result = await history(db);
  assert.deepEqual(ids(result), ['event-admin-result']);
  assert.ok(!ids(result).includes('event-owner-result'));
  await assert.rejects(history(db, orgA, { requestedBy: ownerA }), /pandora_activity_history_person_forbidden/);

  await actAs(db, memberA);
  result = await history(db);
  assert.deepEqual(ids(result), ['event-member-result']);

  await actAs(db, inactiveA);
  await assert.rejects(history(db), /pandora_activity_membership_required/);
  await actAs(db, revokedA);
  await assert.rejects(history(db), /pandora_activity_membership_required/);

  await actAs(db, null);
  await assert.rejects(history(db), /pandora_activity_sign_in_required/);

  await actAs(db, ownerA, 'anon');
  await assert.rejects(history(db), /permission denied/i);

  await db.exec('reset role');
  const servicePrivilege = await db.query(
    "select has_function_privilege('service_role','public.pandora_activity_history_search_v1(uuid,text,text[],text[],text[],uuid,uuid,timestamptz,timestamptz,timestamptz,uuid,bigint,integer)','EXECUTE') as allowed",
  );
  assert.equal(servicePrivilege.rows[0].allowed, false);
});

test('History rejects NULL and out-of-range limits while honoring bounded values', async (t) => {
  const db = await makeDb(t);
  await actAs(db, ownerA);

  await assert.rejects(history(db, orgA, { limit: null }), /pandora_activity_history_limit_invalid/);
  await assert.rejects(history(db, orgA, { limit: 0 }), /pandora_activity_history_limit_invalid/);
  await assert.rejects(history(db, orgA, { limit: 201 }), /pandora_activity_history_limit_invalid/);

  const one = await history(db, orgA, { limit: 1 });
  assert.equal(one.items.length, 1);
  assert.equal(one.hasMore, true);
  assert.equal(one.items[0].event.eventId, 'event-owner-result');
  assert.ok(one.nextCursor);

  const normal = await history(db, orgA, { limit: 2 });
  assert.equal(normal.items.length, 2);
  assert.equal(normal.hasMore, true);

  const max = await history(db, orgA, { limit: 200 });
  assert.equal(max.items.length, 3);
  assert.equal(max.hasMore, false);
  assert.equal(max.nextCursor, null);
});

test('History cursor replay is stable, gap-free, duplicate-free, and preserves exact canonical identity', async (t) => {
  const db = await makeDb(t);
  await actAs(db, ownerA);

  const first = await history(db, orgA, { limit: 2 });
  assert.deepEqual(ids(first), ['event-owner-result', 'event-owner-device']);
  assert.equal(first.hasMore, true);
  assert.deepEqual(first.nextCursor, {
    admittedAt: '2026-09-15T10:20:00+00:00',
    jobId: jobOwner,
    sequence: 2,
  });

  const second = await history(db, orgA, {
    limit: 2,
    beforeAdmittedAt: first.nextCursor.admittedAt,
    beforeJobId: first.nextCursor.jobId,
    beforeSequence: first.nextCursor.sequence,
  });
  assert.deepEqual(ids(second), ['event-owner-understanding']);
  assert.equal(second.hasMore, false);
  assert.equal(second.nextCursor, null);
  assert.deepEqual(new Set([...ids(first), ...ids(second)]).size, 3);

  const result = first.items[0].event;
  assert.equal(result.eventId, 'event-owner-result');
  assert.equal(result.jobId, jobOwner);
  assert.equal(result.sequence, 3);
  assert.equal(result.occurredAt, '2026-09-15T10:29:59Z');
  assert.equal(result.provenance.sourceType, 'runtime');
  assert.equal(result.provenance.sourceId, 'pandora-runtime');
  assert.deepEqual(result.evidenceRefs, [
    { type: 'verification_receipt', relation: 'verification', ref: 'verification:owner:001' },
  ]);
  assert.equal(result.state, 'result');
  assert.equal(result.outcome.summary, 'Result verified from canonical runtime evidence.');

  await assert.rejects(
    history(db, orgA, { beforeAdmittedAt: first.nextCursor.admittedAt, limit: 2 }),
    /pandora_activity_history_cursor_invalid/,
  );
});

test('History search/filtering reads only canonical retained events and never reconstructs expired history', async (t) => {
  const db = await makeDb(t);
  await actAs(db, ownerA);

  assert.deepEqual(ids(await history(db, orgA, { query: 'runtime evidence' })), ['event-owner-result']);
  assert.deepEqual(ids(await history(db, orgA, { sourceTypes: ['device'] })), ['event-owner-device']);
  assert.deepEqual(ids(await history(db, orgA, { domains: ['device'] })), ['event-owner-device']);
  assert.deepEqual(ids(await history(db, orgA, { states: ['result'] })), ['event-owner-result']);
  assert.deepEqual(ids(await history(db, orgA, { jobId: jobOwner })), [
    'event-owner-result', 'event-owner-device', 'event-owner-understanding',
  ]);

  const retained = await history(db, orgA, { limit: 200 });
  assert.equal(retained.retentionBoundary, 'canonical_event_retention');
  assert.ok(!ids(retained).includes('event-owner-expired'));
  assert.equal(retained.items.length, 3);
});
