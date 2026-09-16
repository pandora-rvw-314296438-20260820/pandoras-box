const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { PGlite } = require('@electric-sql/pglite');
const { pgcrypto } = require('@electric-sql/pglite/contrib/pgcrypto');

const originalMigration = readFileSync(join(__dirname, '../supabase/migrations/20260912031000_pandora_consequential_action_evidence_v1.sql'), 'utf8');
const migration = readFileSync(join(__dirname, '../supabase/migrations/20260912041454_pandora_consequential_action_evidence_v2.sql'), 'utf8');
const org = '10000000-0000-4000-8000-000000000001';
const otherOrg = '10000000-0000-4000-8000-000000000002';
const owner = '20000000-0000-4000-8000-000000000001';
const stranger = '20000000-0000-4000-8000-000000000002';
const project = '30000000-0000-4000-8000-000000000001';
const intake = '40000000-0000-4000-8000-000000000001';

async function makeDb(t, upgraded = true) {
  const db = new PGlite({ extensions: { pgcrypto } });
  t.after(() => db.close());
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema private;
    create schema auth;
    create schema extensions;
    create extension pgcrypto with schema extensions;
    grant usage on schema public, auth to anon, authenticated, service_role;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create type public.audit_actor_type as enum ('system','user');
    create table public.memberships (organization_id uuid, user_id uuid, role text, status text);
    create table public.projectos_projects (id uuid primary key, organization_id uuid, name text, project_key text, repository text);
    create table public.projectos_intake_requests (id uuid primary key, organization_id uuid, project_id uuid);
    create table private.execution_plans (
      id uuid primary key default gen_random_uuid(), organization_id uuid,
      request_id uuid default gen_random_uuid(), intake_id uuid, tool text, risk text,
      status text, result_summary jsonb, error text, duration_ms integer,
      payload_hash text, completed_at timestamptz, updated_at timestamptz default now(),
      created_at timestamptz default now()
    );
    create table public.projectos_evidence (
      id uuid primary key default gen_random_uuid(), organization_id uuid, project_id uuid,
      evidence_type text, provider text, external_id text, source_url text, repository text,
      head_sha text, status text check (status in ('observed','passing','failing','complete','blocked','superseded','invalidated')),
      verdict text, payload_redacted jsonb, observed_at timestamptz, invalidated_at timestamptz, invalidation_reason text
    );
    create unique index evidence_identity on public.projectos_evidence
      (organization_id,provider,evidence_type,external_id) where external_id is not null;
    create table public.audit_events (id bigserial primary key, organization_id uuid, event_type text, payload jsonb);
    create function private.append_audit_event(uuid,uuid,uuid,public.audit_actor_type,uuid,text,jsonb)
      returns bigint language sql as $$
      insert into public.audit_events(organization_id,event_type,payload) values ($1,$6,$7) returning id
    $$;
    insert into public.memberships values ('${org}','${owner}','owner','active');
    insert into public.projectos_projects values ('${project}','${org}','Pandora','pandora','example/pandora');
    insert into public.projectos_intake_requests values ('${intake}','${org}','${project}');
  `);
  await db.exec(originalMigration);
  if (upgraded) await db.exec(migration);
  return db;
}

async function record(db, status, summary = {}, error = null, planOrg = org, tool = 'github.write-repository-api') {
  const { rows } = await db.query(`insert into private.execution_plans
    (organization_id,intake_id,tool,risk,status,result_summary,error,payload_hash,completed_at)
    values ($1,$2,$3,'write',$4,$5,$6,$7,now()) returning id`,
  [planOrg, intake, tool, status, JSON.stringify(summary), error, 'a'.repeat(64)]);
  const evidence = await db.query('select * from public.projectos_evidence where external_id=$1', [rows[0].id]);
  return { id: rows[0].id, evidence: evidence.rows[0] };
}

async function actAs(db, user, role = 'authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
  await db.exec(`set role ${role}`);
}

test('completed execution without explicit provider verification stays observed', async (t) => {
  const db = await makeDb(t);
  for (const summary of [{}, { verified: true }, { providerReadback: { verified: 'true' } }, { providerReadback: { verified: false } }]) {
    const { evidence } = await record(db, 'completed', summary);
    assert.equal(evidence.status, 'observed');
    assert.equal(evidence.verdict, 'unverified');
    assert.equal(evidence.payload_redacted.providerReadback.verified, false);
    assert.doesNotMatch(evidence.payload_redacted.summary, /verified completion/);
  }
  const verified = await record(db, 'completed', { providerReadback: { verified: true, status: 'READY' } });
  assert.equal(verified.evidence.status, 'passing');
  assert.equal(verified.evidence.payload_redacted.providerReadback.verified, true);
});

test('uncertain failures require reconciliation and never become a safe retry', async (t) => {
  const db = await makeDb(t);
  for (const error of [null, 'raw provider failure', JSON.stringify({ terminalClassification: 'reconciliation_required', reconciliationRequired: true })]) {
    const { evidence } = await record(db, 'failed', { providerReadback: { verified: true } }, error);
    assert.equal(evidence.status, 'blocked');
    assert.equal(evidence.payload_redacted.reconciliationRequired, true);
    assert.equal(evidence.payload_redacted.automaticRetryAllowed, false);
  }
  const safeFailure = await record(db, 'failed', {}, JSON.stringify({
    terminalClassification: 'failed_without_side_effect', providerOutcome: 'failed_before_side_effects', reconciliationRequired: false,
  }));
  assert.equal(safeFailure.evidence.status, 'failing');
  assert.equal(safeFailure.evidence.payload_redacted.reconciliationRequired, false);
});

test('owner evidence rejects missing, cross-organization, inactive and insufficient memberships', async (t) => {
  const db = await makeDb(t);
  await record(db, 'completed');
  await actAs(db, null);
  await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [org]), /sign_in_required/);
  await actAs(db, stranger);
  await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [org]), /owner_required/);
  await actAs(db, owner);
  await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [otherOrg]), /owner_required/);
  assert.equal((await db.query('select public.pandora_action_evidence_v1($1) as result', [org])).rows[0].result.length, 1);
  for (const [role, status] of [['viewer','active'], ['admin','suspended'], ['owner','removed']]) {
    await db.exec('reset role');
    await db.query('update public.memberships set role=$1,status=$2', [role, status]);
    await actAs(db, owner);
    await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [org]), /owner_required/);
  }
  await actAs(db, null, 'anon');
  await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [org]), /permission denied/);
});

test('only typed safe identifiers leave the execution ledger; payloads and credential URLs never do', async (t) => {
  const db = await makeDb(t);
  const sourceSha = 'b'.repeat(40);
  const { evidence } = await record(db, 'completed', {
    sourceSha, sourceUrl: 'https://user:secret@example.test/private?token=secret',
    sourceVersion: 'Bearer secret', externalId: 'owner@example.test',
    providerReadback: { verified: false, status: 'request failed with secret' },
    raw: { token: 'private-payload-canary' },
  });
  assert.equal(evidence.head_sha, sourceSha);
  assert.equal(evidence.source_url, `https://github.com/example/pandora/commit/${sourceSha}`);
  const encoded = JSON.stringify(evidence);
  for (const forbidden of ['secret', 'owner@example.test', 'private-payload-canary', 'Bearer']) assert.ok(!encoded.includes(forbidden));
  assert.match(evidence.payload_redacted.resultSummarySha256, /^[a-f0-9]{64}$/);
  const valid = await record(db, 'completed', { sourceVersion: '0.4.0-rc.4+10', deploymentId: 'dpl_abcdefgh12345678', providerReadback: { verified: true, status: 'READY' } }, null, org, 'vercel.deploy');
  assert.equal(valid.evidence.payload_redacted.sourceVersion, '0.4.0-rc.4+10');
  assert.equal(valid.evidence.payload_redacted.providerReadback.externalId, 'dpl_abcdefgh12345678');
});

test('terminal evidence is scoped, idempotent, replayable and transactional with its audit event', async (t) => {
  const db = await makeDb(t);
  assert.equal((await record(db, 'running')).evidence, undefined);
  assert.equal((await record(db, 'completed', {}, null, otherOrg)).evidence, undefined);
  await db.exec(`insert into private.execution_plans(organization_id,intake_id,tool,risk,status)
    values ('${org}','${intake}','github.read-repository-api','read','completed')`);
  const first = await record(db, 'completed');
  const replay = await db.query('select private.pandora_record_execution_plan_evidence_v1($1) as id', [first.id]);
  assert.equal(replay.rows[0].id, first.evidence.id);
  await db.exec(migration);
  assert.equal((await db.query('select count(*)::int as n from public.projectos_evidence')).rows[0].n, 1);
  assert.equal((await db.query('select count(*)::int as n from public.audit_events')).rows[0].n, 1);
  await db.exec('begin');
  await record(db, 'completed');
  await db.exec('rollback');
  assert.equal((await db.query('select count(*)::int as n from public.projectos_evidence')).rows[0].n, 1);
  assert.equal((await db.query('select count(*)::int as n from public.audit_events')).rows[0].n, 1);
  await actAs(db, owner);
  await assert.rejects(db.query('select private.pandora_record_execution_plan_evidence_v1($1)', [first.id]), /permission denied/);
});

test('upgrade preserves historical evidence and audit, then reclassifies in bounded batches', async (t) => {
  const db = await makeDb(t, false);
  const old = [];
  for (let i = 0; i < 3; i++) old.push(await record(db, 'completed'));
  const priorAudit = (await db.query('select * from public.audit_events order by id')).rows;
  const priorPayloads = (await db.query('select id,payload_redacted from public.projectos_evidence order by id')).rows;
  await db.exec(migration);
  const superseded = (await db.query('select id,payload_redacted,status,invalidated_at from public.projectos_evidence order by id')).rows;
  assert.deepEqual(superseded.map(({ id, payload_redacted }) => ({ id, payload_redacted })), priorPayloads);
  assert.ok(superseded.every(e => e.status === 'superseded' && e.invalidated_at));
  assert.deepEqual((await db.query('select * from public.audit_events order by id limit 3')).rows, priorAudit);
  assert.equal((await db.query('select private.pandora_backfill_action_evidence_v2(2) as n')).rows[0].n, 2);
  assert.equal((await db.query('select private.pandora_backfill_action_evidence_v2(2) as n')).rows[0].n, 1);
  assert.equal((await db.query('select private.pandora_backfill_action_evidence_v2(2) as n')).rows[0].n, 0);
  const current = (await db.query("select * from public.projectos_evidence where evidence_type='projectos_execution_outcome_v2' order by id")).rows;
  assert.equal(current.length, 3);
  assert.ok(current.every(e => e.status === 'observed' && e.verdict === 'unverified'));
  assert.deepEqual(new Set(current.map(e => e.payload_redacted.supersedesEvidenceId)), new Set(old.map(e => e.evidence.id)));
  await db.exec(migration);
  assert.equal((await db.query('select count(*)::int as n from public.audit_events')).rows[0].n, 7);
  await actAs(db, owner);
  const projected = (await db.query('select public.pandora_action_evidence_v1($1,2) as evidence', [org])).rows[0].evidence;
  assert.equal(projected.length, 2);
  assert.ok(projected.every(e => e.evidenceType === 'projectos_execution_outcome_v2'));
  await assert.rejects(db.query('select private.pandora_backfill_action_evidence_v2(1)'), /permission denied/);
});

test('containment rollback closes access and new evidence without restoring vulnerable code', async (t) => {
  const db = await makeDb(t);
  await record(db, 'completed');
  await db.exec(readFileSync(join(__dirname, '../docs/supabase/rollback/pandora-action-evidence-v2-containment.sql'), 'utf8'));
  assert.equal((await record(db, 'completed')).evidence, undefined);
  assert.equal((await db.query('select count(*)::int as n from public.projectos_evidence')).rows[0].n, 1);
  await actAs(db, owner);
  await assert.rejects(db.query('select public.pandora_action_evidence_v1($1)', [org]), /permission denied/);
  await db.exec('reset role');
  await db.exec(migration);
  assert.ok((await record(db, 'completed')).evidence);
});
