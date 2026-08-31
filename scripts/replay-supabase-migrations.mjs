import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const repositoryRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const migrationRoot = join(repositoryRoot, 'supabase', 'migrations');
const fixtureRoot = join(
  repositoryRoot,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
  'inactive-source',
  'schema-baseline-candidates',
  'replay-fixtures',
);
const recoveryRoot = join(
  repositoryRoot,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
);
const expectedExtensionStatements = new Map([
  ['20260728150403_enable_http_for_supabase_account_discovery.sql', [
    'create extension if not exists http with schema extensions;',
  ]],
  ['20260807083337_projectos_memory_lifecycle_enforcement.sql', [
    'create extension if not exists pg_net;',
    'create extension if not exists pg_cron;',
  ]],
]);

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function canonicalJson(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(',')}]`;
  }
  if (typeof value === 'object') {
    return `{${Object.keys(value)
      .sort((left, right) => Buffer.compare(
        Buffer.from(left, 'utf8'),
        Buffer.from(right, 'utf8'),
      ))
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  if (typeof value === 'string' || typeof value === 'boolean') {
    return JSON.stringify(value);
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  throw new TypeError('Canonical JSON input contains a non-JSON value');
}

function portableSql(filename, source) {
  let transformed = source;
  for (const statement of expectedExtensionStatements.get(filename) || []) {
    const occurrences = transformed.split(statement).length - 1;
    assert.equal(occurrences, 1, `${filename}: extension substitution drift`);
    transformed = transformed.replace(statement, `-- PGLITE PROVIDER STUB: ${statement}`);
  }
  // PGlite does not fully emulate PostgreSQL pg_get_functiondef() rewrites.
  // Normalize authority literals only inside replayed function definitions so
  // active behavior matches production while historical rows and source bytes
  // remain untouched for recovery/hash assertions.
  transformed = transformed.replace(
    /create\s+(?:or\s+replace\s+)?function\b[\s\S]*?\bas\s+(\$[A-Za-z0-9_]*\$)[\s\S]*?\1\s*;/gi,
    (statement) => statement
      .replaceAll(
        'banataosystems/Pandoras-box',
        'pandora-rvw-314296438-20260820/pandoras-box',
      )
      .replaceAll(
        'banataosystems/pandoras-box-memory',
        'pandora-rvw-314296438-20260820/pandoras-box-memory',
      )
      .replaceAll(
        'team_IcdJUnzLi5wUN1GD8ALHyjF7',
        'team_3yw1CN59ce4pj5SwyQGCAqN3',
      )
      .replaceAll('mbanatao-dc676069', 'mbanatao'),
  );
  return transformed;
}

async function bootstrap(db) {
  await db.exec(`
    create schema if not exists extensions;
    create extension if not exists pgcrypto with schema extensions;

    do $bootstrap$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator nologin noinherit; end if;
    end
    $bootstrap$;

    create schema if not exists auth;
    create type auth.aal_level as enum ('aal1', 'aal2');
    create table auth.users (
      id uuid primary key,
      raw_user_meta_data jsonb not null default '{}'::jsonb,
      is_anonymous boolean not null default false,
      email_confirmed_at timestamptz
    );
    create table auth.sessions (
      id uuid primary key,
      user_id uuid not null references auth.users(id) on delete cascade,
      aal auth.aal_level not null default 'aal1',
      not_after timestamptz
    );
    create or replace function auth.jwt() returns jsonb
    language sql stable
    as $$
      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
    $$;
    create or replace function auth.uid() returns uuid
    language sql stable
    as $$
      select nullif(auth.jwt() ->> 'sub', '')::uuid
    $$;
    create or replace function auth.role() returns text
    language sql stable
    as $$
      select coalesce(nullif(auth.jwt() ->> 'role', ''), current_user)
    $$;
    select set_config('request.jwt.claims', '{"role":"service_role"}', false);

    create schema if not exists vault;
    create table vault.decrypted_secrets (
      id uuid primary key,
      decrypted_secret text
    );

    create type extensions.http_method as enum ('GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD');
    create type extensions.http_header as (field varchar, value varchar);
    create type extensions.http_request as (
      method extensions.http_method,
      uri varchar,
      headers extensions.http_header[],
      content_type varchar,
      content varchar
    );
    create type extensions.http_response as (
      status integer,
      content_type varchar,
      headers extensions.http_header[],
      content varchar
    );
    create or replace function extensions.http(extensions.http_request)
    returns extensions.http_response
    language sql immutable
    as $$
      select row(599, 'application/json', array[]::extensions.http_header[],
        '{"error":"provider HTTP disabled in replay"}')::extensions.http_response
    $$;

    create schema if not exists net;
    create table net._http_response (
      id bigint primary key,
      status_code integer,
      content text,
      headers jsonb,
      error_msg text,
      timed_out boolean not null default false,
      created timestamptz not null default now()
    );
    create sequence net.http_request_id_seq;
    create or replace function net.http_post(
      url text,
      body jsonb default '{}'::jsonb,
      params jsonb default '{}'::jsonb,
      headers jsonb default '{}'::jsonb,
      timeout_milliseconds integer default 1000
    ) returns bigint
    language sql volatile
    as $$ select nextval('net.http_request_id_seq') $$;

    create schema if not exists cron;
    create table cron.job (
      jobid bigint generated always as identity primary key,
      jobname text unique,
      schedule text not null,
      command text not null
    );
    create or replace function cron.schedule(job_name text, schedule text, command text)
    returns bigint
    language plpgsql
    as $$
    declare resolved_id bigint;
    begin
      insert into cron.job(jobname, schedule, command)
      values (job_name, schedule, command)
      on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
      returning jobid into resolved_id;
      return resolved_id;
    end;
    $$;
  `);
}

async function authorizationSmoke(db) {
  const organizationId = '2270b266-59da-4c39-bfd9-9f8d08352af0';
  const users = {
    owner: '11111111-1111-4111-8111-111111111111',
    operator: '22222222-2222-4222-8222-222222222222',
    requester: '33333333-3333-4333-8333-333333333333',
    anonymousOwner: '44444444-4444-4444-8444-444444444444',
  };
  const approvals = {
    ownerSuccess: '30000000-0000-4000-8000-000000000001',
    operatorDenied: '30000000-0000-4000-8000-000000000002',
    anonymousDenied: '30000000-0000-4000-8000-000000000003',
    separationDenied: '30000000-0000-4000-8000-000000000004',
  };

  await db.exec(`
    insert into auth.users(id, raw_user_meta_data, is_anonymous) values
      ('${users.owner}', '{}'::jsonb, false),
      ('${users.operator}', '{}'::jsonb, false),
      ('${users.requester}', '{}'::jsonb, false),
      ('${users.anonymousOwner}', '{}'::jsonb, true);

    insert into public.memberships(organization_id, user_id, role, status, joined_at) values
      ('${organizationId}', '${users.owner}', 'owner', 'active', now()),
      ('${organizationId}', '${users.operator}', 'operator', 'active', now()),
      ('${organizationId}', '${users.requester}', 'member', 'active', now()),
      ('${organizationId}', '${users.anonymousOwner}', 'owner', 'active', now());

    insert into public.workflow_runs(
      id, organization_id, workflow_key, workflow_version, status, requester_id,
      risk_ceiling, idempotency_key, started_at
    ) values
      ('10000000-0000-4000-8000-000000000001', '${organizationId}', 'replay-owner', '1', 'waiting_approval', '${users.requester}', 'R3', 'replay-owner', now()),
      ('10000000-0000-4000-8000-000000000002', '${organizationId}', 'replay-operator', '1', 'waiting_approval', '${users.requester}', 'R1', 'replay-operator', now()),
      ('10000000-0000-4000-8000-000000000003', '${organizationId}', 'replay-anonymous', '1', 'waiting_approval', '${users.requester}', 'R1', 'replay-anonymous', now()),
      ('10000000-0000-4000-8000-000000000004', '${organizationId}', 'replay-sod', '1', 'waiting_approval', '${users.owner}', 'R4', 'replay-sod', now());

    insert into public.workflow_steps(
      id, organization_id, run_id, step_key, sequence, status, risk, approval_required
    ) values
      ('20000000-0000-4000-8000-000000000001', '${organizationId}', '10000000-0000-4000-8000-000000000001', 'approve', 0, 'waiting_approval', 'R3', true),
      ('20000000-0000-4000-8000-000000000002', '${organizationId}', '10000000-0000-4000-8000-000000000002', 'approve', 0, 'waiting_approval', 'R1', true),
      ('20000000-0000-4000-8000-000000000003', '${organizationId}', '10000000-0000-4000-8000-000000000003', 'approve', 0, 'waiting_approval', 'R1', true),
      ('20000000-0000-4000-8000-000000000004', '${organizationId}', '10000000-0000-4000-8000-000000000004', 'approve', 0, 'waiting_approval', 'R4', true);

    insert into public.approvals(
      id, organization_id, run_id, step_id, requested_by, action_hash,
      preview_redacted, expires_at
    ) values
      ('${approvals.ownerSuccess}', '${organizationId}', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '${users.requester}', repeat('a', 64), '{}'::jsonb, now() + interval '1 hour'),
      ('${approvals.operatorDenied}', '${organizationId}', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '${users.requester}', repeat('b', 64), '{}'::jsonb, now() + interval '1 hour'),
      ('${approvals.anonymousDenied}', '${organizationId}', '10000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003', '${users.requester}', repeat('c', 64), '{}'::jsonb, now() + interval '1 hour'),
      ('${approvals.separationDenied}', '${organizationId}', '10000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000004', '${users.owner}', repeat('d', 64), '{}'::jsonb, now() + interval '1 hour');
  `);

  const setClaims = async (userId, isAnonymous = false) => {
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify({ sub: userId, role: 'authenticated', is_anonymous: String(isAnonymous) }),
    ]);
  };
  const decide = (approvalId) => db.query(
    `select (public.decide_approval($1, 'approved'::public.approval_decision, 'replay')).decision::text as decision`,
    [approvalId],
  );
  const mustDeny = async (userId, approvalId, isAnonymous = false) => {
    await setClaims(userId, isAnonymous);
    await assert.rejects(decide(approvalId));
    const state = await db.query(`select decision::text as decision from public.approvals where id = $1`, [approvalId]);
    assert.equal(state.rows[0].decision, 'pending');
  };

  await setClaims(users.owner);
  assert.equal((await db.query(`select count(*)::integer as count from auth.sessions where user_id = $1`, [users.owner])).rows[0].count, 0);
  assert.equal((await decide(approvals.ownerSuccess)).rows[0].decision, 'approved');
  assert.equal(
    (await db.query(`select count(*)::integer as count from public.audit_events where event_type = 'approval.approved' and actor_user_id = $1`, [users.owner])).rows[0].count,
    1,
  );

  await mustDeny(users.operator, approvals.operatorDenied);
  await mustDeny(users.anonymousOwner, approvals.anonymousDenied, true);
  await mustDeny(users.owner, approvals.separationDenied);
  return {
    aal1_owner_without_session: 'approved',
    operator: 'denied',
    anonymous_owner: 'denied',
    high_risk_requester_as_approver: 'denied',
    audit_event_appended: true,
  };
}

async function governedWorkerSmoke(db) {
  const organizationId = '2270b266-59da-4c39-bfd9-9f8d08352af0';
  const requesterId = '11111111-1111-4111-8111-111111111111';
  const repository = 'pandora-rvw-314296438-20260820/pandoras-box';
  const exactSha = 'c'.repeat(40);
  const workerId = 'worker-01-replay';
  const publicKeyB64 = `${'A'.repeat(43)}=`;
  const keyFingerprint = sha256(Buffer.alloc(32));
  const reviewerId = 'worker-reviewer-replay';
  const reviewerPublicKey = Buffer.alloc(32, 1);
  const reviewerPublicKeyB64 = reviewerPublicKey.toString('base64');
  const reviewerKeyFingerprint = sha256(reviewerPublicKey);
  const reviewerRequestId = '737bd079-03fc-478b-894a-7e8c98d70ddb';
  const reviewerSignatureB64 = Buffer.alloc(64, 2).toString('base64');
  const reviewArtifactSha256 = sha256('governed-worker-review-artifact');
  const registrationIdempotency = sha256('worker-registration-replay');
  const ownerIdempotency = sha256('governed-owner-worker-replay');
  const ownerFingerprint = sha256('verify exact replay source');
  const runnerPolicyHash = 'c'.repeat(64);
  const runnerImageDigest = `sha256:${'d'.repeat(64)}`;
  const acquisitionImageDigest = `sha256:${'e'.repeat(64)}`;

  const scalar = async (sql, params = []) => {
    const result = await db.query(sql, params);
    assert.equal(result.rows.length, 1);
    return Object.values(result.rows[0])[0];
  };
  let workerAuthorityCounter = 0;
  const setWorkerAuthority = async ({
    purpose,
    requestId,
    requestSha256,
    workerKeyFingerprint = keyFingerprint,
    dispatchId = null,
    planId = null,
  }) => {
    workerAuthorityCounter += 1;
    const issuedAt = Math.floor(Date.now() / 1000);
    const authorityClaims = {
      role: 'projectos_worker_ingest',
      iss: 'pandora-independent-worker-authority',
      aud: 'projectos_worker_ingest',
      purpose,
      sub: requestId,
      organization_id: organizationId,
      worker_id: workerId,
      worker_key_fingerprint: workerKeyFingerprint,
      request_id: requestId,
      ...(dispatchId ? { dispatch_id: dispatchId } : {}),
      ...(planId ? { plan_id: planId } : {}),
      request_sha256: requestSha256,
      jti: `worker-replay-authority-${String(workerAuthorityCounter).padStart(4, '0')}`,
      iat: issuedAt,
      nbf: issuedAt,
      exp: issuedAt + 90,
    };
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify(authorityClaims),
    ]);
    return authorityClaims;
  };
  const memoryEnvelope = (tool) => ({
    schemaVersion: '1.0.0',
    source: 'pandora-memory',
    status: 'available',
    namespace: 'real_life',
    queryHash: sha256(`worker-replay:${tool}`),
    queryBasis: { tool, identifiers: {} },
    counts: {
      projectContext: 1,
      riskWarnings: 0,
      openLoops: 0,
      recentEvents: 1,
      semanticMatches: 1,
    },
    highlights: {
      project: ['Governed replay fixture'],
      risks: [],
      openLoops: [],
      recent: [],
      semantic: [],
    },
    warnings: [],
    retrievedAt: new Date().toISOString(),
  });
  const attachContext = async (planId, requestId, tool) => {
    const envelope = memoryEnvelope(tool);
    const contextHash = sha256(canonicalJson(envelope));
    const result = await scalar(
      `select public.attach_execution_plan_context($1, $2, $3, $4, $5::jsonb) as result`,
      [organizationId, planId, requestId, contextHash, JSON.stringify(envelope)],
    );
    return { contextHash, envelope, result };
  };

  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);

  const privateTableAccess = await db.query(`
    select
      has_table_privilege(
        'service_role', 'private.execution_dispatch_outbox', 'SELECT'
      ) as dispatch_select,
      has_table_privilege(
        'service_role', 'private.owner_command_bindings', 'SELECT'
      ) as command_binding_select,
      has_table_privilege(
        'service_role', 'private.compute_worker_identities', 'SELECT'
      ) as worker_identity_select,
      has_table_privilege(
        'service_role', 'private.compute_worker_nonces', 'SELECT'
      ) as nonce_select
  `);
  assert.deepEqual(privateTableAccess.rows, [{
    dispatch_select: false,
    command_binding_select: false,
    worker_identity_select: false,
    nonce_select: false,
  }], 'service_role regained direct governed-worker table access');

  const workerRpcAccess = await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.consume_compute_worker_nonce(uuid,text,text)',
        'EXECUTE'
      ) as legacy_nonce,
      has_function_privilege(
        'service_role',
        'public.consume_compute_worker_nonce(uuid,text,text,text)',
        'EXECUTE'
      ) as key_bound_nonce,
      has_function_privilege(
        'service_role',
        'public.claim_governed_worker_dispatch(uuid,text)',
        'EXECUTE'
      ) as legacy_claim,
      has_function_privilege(
        'service_role',
        'public.claim_governed_worker_dispatch(uuid,text,text)',
        'EXECUTE'
      ) as key_bound_claim,
      has_function_privilege(
        'service_role',
        'public.finish_governed_worker_dispatch(uuid,uuid,uuid,text,text,integer,text,text,jsonb)',
        'EXECUTE'
      ) as legacy_finish,
      has_function_privilege(
        'service_role',
        'public.finish_governed_worker_dispatch(uuid,uuid,uuid,text,text,text,integer,text,text,jsonb)',
        'EXECUTE'
      ) as key_bound_finish,
      has_function_privilege(
        'service_role',
        'public.record_governed_worker_job_envelope(uuid,uuid,uuid,text,text,jsonb,text)',
        'EXECUTE'
      ) as legacy_job,
      has_function_privilege(
        'service_role',
        'public.claim_governed_worker_dispatch_authorized(uuid,text,text,uuid,text,text,text)',
        'EXECUTE'
      ) as service_authorized_claim,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.claim_governed_worker_dispatch_authorized(uuid,text,text,uuid,text,text,text)',
        'EXECUTE'
      ) as worker_authorized_claim,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.record_governed_worker_job_envelope_authorized(uuid,uuid,uuid,text,text,text,jsonb,text)',
        'EXECUTE'
      ) as worker_authorized_job,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.finish_governed_worker_dispatch_authorized(uuid,uuid,uuid,text,text,text,integer,text,text,jsonb,uuid,text,text,text)',
        'EXECUTE'
      ) as worker_authorized_finish
  `);
  assert.deepEqual(workerRpcAccess.rows, [{
    legacy_nonce: false,
    key_bound_nonce: false,
    legacy_claim: false,
    key_bound_claim: false,
    legacy_finish: false,
    key_bound_finish: false,
    legacy_job: false,
    service_authorized_claim: false,
    worker_authorized_claim: true,
    worker_authorized_job: true,
    worker_authorized_finish: true,
  }], 'candidate service role retained a governed worker mutation');

  const registrationIntake = await scalar(
    `select public.projectos_accept_intake($1, $2, $3, $4, $5, $6, $7, $8, $9) as result`,
    [
      organizationId,
      requesterId,
      'Enroll the replay-only governed worker identity.',
      'pandoras-box',
      'Pandoras Box',
      repository,
      'maintenance',
      'system',
      registrationIdempotency,
    ],
  );
  const projectId = registrationIntake.project.id;
  const registrationIntakeId = registrationIntake.intake.id;
  const registrationArgs = {
    schemaVersion: 1,
    operation: 'enroll',
    workerId,
    keyFingerprint,
    allowedRepositories: [repository],
    allowedJobClasses: ['node_regression'],
  };
  const registrationHash = await scalar(
    `select private.projectos_worker_identity_plan_payload_hash($1::jsonb) as hash`,
    [JSON.stringify(registrationArgs)],
  );
  const registrationPlan = await scalar(
    `select public.create_execution_plan($1, $2, $3, $4, $5, $6::jsonb, $7, now() + interval '20 minutes') as result`,
    [
      organizationId,
      registrationIntakeId,
      registrationIntakeId,
      'projectos.worker.identity.register',
      'write',
      JSON.stringify(registrationArgs),
      registrationHash,
    ],
  );
  const registrationContext = await attachContext(
    registrationPlan.planId,
    registrationIntakeId,
    'projectos.worker.identity.register',
  );
  await scalar(
    `select public.approve_execution_plan($1, $2, 'replay-owner') as result`,
    [organizationId, registrationPlan.planId],
  );
  const contextAuditCount = async (planId) => scalar(
    `select count(*)::integer as count
       from private.execution_audit_events
      where plan_id = $1 and event_type = 'plan_context_attached'`,
    [planId],
  );
  const auditCountBeforeReplay = await contextAuditCount(registrationPlan.planId);
  const exactContextReplay = await scalar(
    `select public.attach_execution_plan_context($1, $2, $3, $4, $5::jsonb) as result`,
    [
      organizationId,
      registrationPlan.planId,
      registrationIntakeId,
      registrationContext.contextHash,
      JSON.stringify(registrationContext.envelope),
    ],
  );
  assert.equal(exactContextReplay.recordedAt, registrationContext.result.recordedAt);
  assert.equal(await contextAuditCount(registrationPlan.planId), auditCountBeforeReplay);

  await assert.rejects(
    scalar(
      `select public.attach_execution_plan_context($1, $2, $3, $4, $5::jsonb) as result`,
      [
        organizationId,
        registrationPlan.planId,
        registrationIntakeId,
        registrationContext.contextHash,
        JSON.stringify({ ...registrationContext.envelope, warnings: ['changed'] }),
      ],
    ),
    (error) => error?.code === '55000',
    'same-hash changed context bypassed immutable replay validation',
  );
  const changedContextEnvelope = {
    ...registrationContext.envelope,
    warnings: ['changed'],
  };
  await assert.rejects(
    scalar(
      `select public.attach_execution_plan_context($1, $2, $3, $4, $5::jsonb) as result`,
      [
        organizationId,
        registrationPlan.planId,
        registrationIntakeId,
        sha256(canonicalJson(changedContextEnvelope)),
        JSON.stringify(changedContextEnvelope),
      ],
    ),
    (error) => error?.code === '55000',
    'canonically hashed context replacement was not rejected as immutable',
  );
  await assert.rejects(
    scalar(
      `select public.attach_execution_plan_context($1, $2, $3, $4, $5::jsonb) as result`,
      [
        organizationId,
        registrationPlan.planId,
        registrationIntakeId,
        sha256('different-context'),
        JSON.stringify(registrationContext.envelope),
      ],
    ),
    (error) => error?.code === '55000',
    'different-hash context bypassed immutable replay validation',
  );

  const approvedWithoutContextRequestId = '11111111-1111-4111-8111-111111111112';
  const approvedWithoutContext = await scalar(
    `select public.create_execution_plan($1, $2, $3, $4, 'read', '{}'::jsonb, $5, now() + interval '20 minutes') as result`,
    [
      organizationId,
      approvedWithoutContextRequestId,
      registrationIntakeId,
      'projectos.context.closed.approved',
      sha256('approved-without-context'),
    ],
  );
  await assert.rejects(
    attachContext(
      approvedWithoutContext.planId,
      approvedWithoutContextRequestId,
      'projectos.context.closed.approved',
    ),
    (error) => error?.code === '55000',
    'first context attachment after approval was not rejected',
  );

  const expiredPendingRequestId = '11111111-1111-4111-8111-111111111113';
  const expiredPending = await scalar(
    `select public.create_execution_plan($1, $2, $3, $4, 'write', '{}'::jsonb, $5, now() + interval '20 minutes') as result`,
    [
      organizationId,
      expiredPendingRequestId,
      registrationIntakeId,
      'projectos.context.closed.expired',
      sha256('expired-pending-without-context'),
    ],
  );
  await db.query(
    `update private.execution_plans set expires_at = now() - interval '1 minute' where id = $1`,
    [expiredPending.planId],
  );
  await assert.rejects(
    attachContext(
      expiredPending.planId,
      expiredPendingRequestId,
      'projectos.context.closed.expired',
    ),
    (error) => error?.code === '55000',
    'first context attachment on an expired pending plan was not rejected',
  );
  const enrolled = await scalar(
    `select public.register_compute_worker_identity($1, $2, $3, $4, $5::text[], $6::text[]) as result`,
    [
      organizationId,
      registrationPlan.planId,
      workerId,
      publicKeyB64,
      [repository],
      ['node_regression'],
    ],
  );
  assert.equal(enrolled.workerId, workerId);
  assert.equal(enrolled.keyFingerprint, keyFingerprint);
  assert.equal(enrolled.idempotentReplay, false);

  await assert.rejects(
    scalar(
      `select public.consume_compute_worker_nonce($1, $2, $3, $4) as result`,
      [organizationId, workerId, '0'.repeat(64), 'replay-nonce-wrong-key-0001'],
    ),
    (error) => error?.code === '42501',
    'nonce acceptance was not bound to the resolved worker key',
  );
  assert.deepEqual(
    await scalar(
      `select public.consume_compute_worker_nonce($1, $2, $3, $4) as result`,
      [organizationId, workerId, keyFingerprint, 'replay-nonce-correct-key-01'],
    ),
    { accepted: true },
  );

  const runtimeProofIds = await db.query(`
    insert into public.projectos_agent_runtime_proofs (
      organization_id, project_id, agent_key, vendor, role,
      repository_scopes, proven_capabilities, phone_only_compatible,
      credential_state, quota_state, health_state, active_leases,
      max_concurrent_leases, cost_class, verified_by, evidence_refs,
      verified_at, context_updated_at, expires_at, is_active
    ) values
      (
        $1, $2, $3, 'openai', 'builder', array[$4]::text[],
        array['projectos.worker.verify:node_regression']::text[], true,
        'ready', 'available', 'healthy', 0, 1, 'subscription-included',
        'replay', '[]'::jsonb, now(), now(), now() + interval '30 minutes', true
      ),
      (
        $1, $2, $5, 'google', 'reviewer', array[$4]::text[],
        array['projectos.worker.verify.review:node_regression']::text[], true,
        'ready', 'available', 'healthy', 0, 1, 'subscription-included',
        'replay', '[]'::jsonb, now(), now(), now() + interval '30 minutes', true
      )
    returning id, role
  `, [organizationId, projectId, workerId, repository, reviewerId]);
  const builderProofId = runtimeProofIds.rows.find((row) => row.role === 'builder').id;
  const reviewerProofId = runtimeProofIds.rows.find((row) => row.role === 'reviewer').id;
  const reviewerRpcAccess = await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.register_compute_reviewer_identity(uuid,uuid,text,text,text[])',
        'EXECUTE'
      ) as service_can_enroll,
      has_function_privilege(
        'service_role',
        'public.record_governed_worker_review_attestation(uuid,uuid,text,text,uuid,uuid,uuid,text,text,text,text,text,text,text,text,text)',
        'EXECUTE'
      ) as service_can_attest,
      has_function_privilege(
        'projectos_reviewer_ingest',
        'public.record_governed_worker_review_attestation(uuid,uuid,text,text,uuid,uuid,uuid,text,text,text,text,text,text,text,text,text)',
        'EXECUTE'
      ) as reviewer_can_attest,
      pg_has_role(
        'authenticator', 'projectos_reviewer_ingest', 'MEMBER'
      ) as authenticator_can_assume_reviewer
  `);
  assert.deepEqual(reviewerRpcAccess.rows, [{
    service_can_enroll: false,
    service_can_attest: false,
    reviewer_can_attest: true,
    authenticator_can_assume_reviewer: true,
  }], 'owner service-role authority crossed the reviewer boundary');
  const reviewerIdentity = await scalar(
    `select public.register_compute_reviewer_identity($1, $2, $3, $4, $5::text[]) as result`,
    [
      organizationId,
      reviewerProofId,
      reviewerId,
      reviewerPublicKeyB64,
      [repository],
    ],
  );
  assert.equal(reviewerIdentity.reviewerId, reviewerId);
  assert.equal(reviewerIdentity.keyFingerprint, reviewerKeyFingerprint);
  assert.equal(reviewerIdentity.idempotentReplay, false);

  const accepted = await scalar(
    `select public.projectos_accept_governed_worker_intake($1, $2, $3, $4, $5, $6) as result`,
    [
      organizationId,
      requesterId,
      'Verify one exact replay source without production mutation.',
      'pandoras-box',
      ownerIdempotency,
      ownerFingerprint,
    ],
  );
  assert.equal(accepted.idempotentReplay, false);
  const acceptedReplay = await scalar(
    `select public.projectos_accept_governed_worker_intake($1, $2, $3, $4, $5, $6) as result`,
    [
      organizationId,
      requesterId,
      'Verify one exact replay source without production mutation.',
      'pandoras-box',
      ownerIdempotency,
      ownerFingerprint,
    ],
  );
  assert.equal(acceptedReplay.idempotentReplay, true);
  await assert.rejects(
    scalar(
      `select public.projectos_accept_governed_worker_intake($1, $2, $3, $4, $5, $6) as result`,
      [
        organizationId,
        requesterId,
        'Conflicting replay request.',
        'pandoras-box',
        ownerIdempotency,
        sha256('conflicting replay request'),
      ],
    ),
    (error) => error?.code === '23505',
  );

  const intakeId = accepted.intake.id;
  const planArgs = {
    exactSha,
    jobClass: 'node_regression',
    maxRuntimeSeconds: 60,
    productionMutationAllowed: false,
    repository,
    schemaVersion: 1,
  };
  const planPayload = `{"tool":"projectos.worker.verify","args":{"exactSha":"${exactSha}","jobClass":"node_regression","maxRuntimeSeconds":60,"productionMutationAllowed":false,"repository":"${repository}","schemaVersion":1}}`;
  const planHash = sha256(planPayload);
  const plan = await scalar(
    `select public.projectos_create_or_get_worker_plan($1, $2, $3::jsonb, $4, now() + interval '20 minutes') as result`,
    [organizationId, intakeId, JSON.stringify(planArgs), planHash],
  );
  assert.equal(plan.status, 'pending_approval');
  await attachContext(plan.planId, intakeId, 'projectos.worker.verify');
  const ownerPlanSessionId = '4c652e30-6229-4f99-b9e7-97e7538e4d75';
  await db.query(`
    insert into auth.sessions (id, user_id, aal, not_after)
    values ($1, $2, 'aal1'::auth.aal_level, now() + interval '30 minutes')
  `, [ownerPlanSessionId, requesterId]);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({
      role: 'authenticated',
      sub: requesterId,
      aal: 'aal1',
      is_anonymous: false,
      session_id: ownerPlanSessionId,
    }),
  ]);
  assert.deepEqual((await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.decide_governed_worker_execution_plan(uuid,uuid,text,text)',
        'EXECUTE'
      ) as service_can_supply_actor,
      has_function_privilege(
        'service_role',
        'public.decide_governed_worker_execution_plan(uuid,uuid,text)',
        'EXECUTE'
      ) as service_can_decide,
      has_function_privilege(
        'authenticated',
        'public.decide_governed_worker_execution_plan(uuid,uuid,text)',
        'EXECUTE'
      ) as owner_session_can_decide
  `)).rows, [{
    service_can_supply_actor: false,
    service_can_decide: false,
    owner_session_can_decide: true,
  }]);
  await db.exec(`set role service_role`);
  try {
    await assert.rejects(
      scalar(
        `select public.decide_governed_worker_execution_plan($1, $2, 'approve', 'caller-supplied') as result`,
        [organizationId, plan.planId],
      ),
      (error) => error?.code === '42501',
      'service_role could still decide with caller-supplied decided_by',
    );
    await assert.rejects(
      scalar(
        `select public.decide_governed_worker_execution_plan($1, $2, 'approve') as result`,
        [organizationId, plan.planId],
      ),
      (error) => error?.code === '42501',
      'service_role could call the live-owner plan-decision wrapper',
    );
  } finally {
    await db.exec(`reset role`);
  }
  const decision = await scalar(
    `select public.decide_governed_worker_execution_plan($1, $2, 'approve') as result`,
    [organizationId, plan.planId],
  );
  assert.equal(decision.status, 'executing');
  assert.equal(decision.dispatchStatus, 'queued');
  await db.query(`delete from auth.sessions where id = $1`, [ownerPlanSessionId]);
  await assert.rejects(
    scalar(
      `select public.decide_governed_worker_execution_plan($1, $2, 'approve') as result`,
      [organizationId, plan.planId],
    ),
    (error) => error?.code === '42501',
    'a revoked owner session remained plan-decision capable',
  );
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);

  const claimRequestId = '8bef5599-e24f-4c45-9ac1-11c568919bef';
  const claimNonce = 'worker-claim-replay-nonce-0001';
  const claimTimestamp = new Date().toISOString();
  const claimSignatureB64 = Buffer.alloc(64, 3).toString('base64');
  const claimBasis = [
    'pandora-worker-request-v1', 'claim', organizationId, workerId,
    claimRequestId, claimNonce, claimTimestamp,
  ].join('|');
  const claimRequestSha256 = sha256([
    'pandora-worker-authority-v1', 'worker_claim', sha256(claimBasis),
    keyFingerprint, sha256(Buffer.from(claimSignatureB64, 'base64')),
  ].join('|'));
  const wrongClaimRequestSha256 = sha256([
    'pandora-worker-authority-v1', 'worker_claim', sha256(claimBasis),
    '0'.repeat(64), sha256(Buffer.from(claimSignatureB64, 'base64')),
  ].join('|'));
  await setWorkerAuthority({
    purpose: 'worker_claim',
    requestId: claimRequestId,
    requestSha256: wrongClaimRequestSha256,
    workerKeyFingerprint: '0'.repeat(64),
  });
  await assert.rejects(
    scalar(
      `select public.claim_governed_worker_dispatch_authorized($1, $2, $3, $4, $5, $6, $7) as result`,
      [
        organizationId, workerId, '0'.repeat(64), claimRequestId,
        claimNonce, claimTimestamp, claimSignatureB64,
      ],
    ),
    (error) => error?.code === '42501',
    'dispatch claim was not bound to the resolved worker key',
  );
  const claimAuthorityClaims = await setWorkerAuthority({
    purpose: 'worker_claim',
    requestId: claimRequestId,
    requestSha256: claimRequestSha256,
  });
  const claimed = await scalar(
    `select public.claim_governed_worker_dispatch_authorized($1, $2, $3, $4, $5, $6, $7) as result`,
    [
      organizationId, workerId, keyFingerprint, claimRequestId,
      claimNonce, claimTimestamp, claimSignatureB64,
    ],
  );
  assert.equal(claimed.status, 'claimed');
  assert.equal(claimed.exactSha, exactSha);
  assert.equal(claimed.jobClass, 'node_regression');
  const activeLease = await scalar(
    `select active_leases as count from public.projectos_agent_runtime_proofs where id = $1`,
    [builderProofId],
  );
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);
  assert.equal(activeLease, 1);
  const runtimeRefreshObservedAt = new Date();
  const refreshedRuntimeProof = await scalar(
    `select public.projectos_upsert_agent_runtime_proof($1, 'pandoras-box', $2::jsonb) as result`,
    [organizationId, JSON.stringify({
      agent_key: workerId,
      vendor: 'openai',
      role: 'builder',
      repository_scopes: [repository],
      proven_capabilities: ['projectos.worker.verify:node_regression'],
      phone_only_compatible: true,
      credential_state: 'ready',
      quota_state: 'available',
      health_state: 'healthy',
      active_leases: 0,
      max_concurrent_leases: 1,
      cost_class: 'subscription-included',
      verified_by: 'replay',
      evidence_refs: [],
      verified_at: runtimeRefreshObservedAt.toISOString(),
      context_updated_at: runtimeRefreshObservedAt.toISOString(),
      expires_at: new Date(
        runtimeRefreshObservedAt.getTime() + 30 * 60 * 1000,
      ).toISOString(),
    })],
  );
  assert.equal(refreshedRuntimeProof.activeLeases, 1);
  assert.equal(
    await scalar(
      `select active_leases from public.projectos_agent_runtime_proofs where id = $1`,
      [builderProofId],
    ),
    1,
    'caller-controlled runtime-proof refresh changed the durable lease count',
  );
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify(claimAuthorityClaims),
  ]);

  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + 60_000);
  const jobPayload = {
    schemaVersion: 1,
    audience: `pandora-worker:${workerId}`,
    organizationId,
    dispatchId: claimed.dispatchId,
    planId: plan.planId,
    repository,
    exactSha,
    jobClass: 'node_regression',
    maxRuntimeSeconds: 60,
    issuedAt: issuedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
    runnerPolicyHash,
    runnerImageDigest,
    acquisitionImageDigest,
    networkPolicy: 'none',
    isolation: 'hyperv_container',
    productionMutationAllowed: false,
  };
  const jobDigest = await scalar(
    `select private.projectos_worker_job_digest($1::jsonb) as digest`,
    [JSON.stringify(jobPayload)],
  );
  const envelope = await scalar(
    `select public.record_governed_worker_job_envelope_authorized($1, $2, $3, $4, $5, $6, $7::jsonb, $8) as result`,
    [
      organizationId,
      claimed.dispatchId,
      plan.planId,
      workerId,
      keyFingerprint,
      jobDigest,
      JSON.stringify(jobPayload),
      `${'A'.repeat(86)}==`,
    ],
  );
  assert.equal(envelope.status, 'envelope_ready');

  const completedAt = new Date();
  const startedAt = new Date(completedAt.getTime() - 1000);
  const resultSummary = {
    schemaVersion: 1,
    organizationId,
    dispatchId: claimed.dispatchId,
    planId: plan.planId,
    workerId,
    jobDigest,
    repository,
    exactSha,
    jobClass: 'node_regression',
    outcome: 'completed',
    exitCode: 0,
    isolation: 'hyperv_container',
    networkPolicy: 'none',
    productionMutationAllowed: false,
    runnerPolicyHash,
    runnerImageDigest,
    acquisitionImageDigest,
    sourceTreeSha: 'd'.repeat(40),
    testsDiscovered: 190,
    startedAt: startedAt.toISOString(),
    completedAt: completedAt.toISOString(),
    stdoutSha256: 'f'.repeat(64),
    stderrSha256: '0'.repeat(64),
  };
  const workerEvidenceHash = await scalar(
    `select private.projectos_worker_evidence_hash($1::jsonb) as hash`,
    [JSON.stringify(resultSummary)],
  );
  const completionRequestId = '7f752610-9668-4111-8cc7-f65a0865f4b0';
  const completionNonce = 'worker-complete-replay-nonce-01';
  const completionTimestamp = new Date().toISOString();
  const completionSignatureB64 = Buffer.alloc(64, 4).toString('base64');
  const completionBasis = [
    'pandora-worker-request-v1', 'complete', organizationId, workerId,
    completionRequestId, completionNonce, completionTimestamp,
    claimed.dispatchId, plan.planId, jobDigest, 'completed', '1500',
    workerEvidenceHash,
  ].join('|');
  const completionRequestSha256For = (fingerprint) => sha256([
    'pandora-worker-authority-v1', 'worker_complete', sha256(completionBasis),
    fingerprint, sha256(Buffer.from(completionSignatureB64, 'base64')),
  ].join('|'));
  await setWorkerAuthority({
    purpose: 'worker_complete',
    requestId: completionRequestId,
    requestSha256: completionRequestSha256For('0'.repeat(64)),
    workerKeyFingerprint: '0'.repeat(64),
    dispatchId: claimed.dispatchId,
    planId: plan.planId,
  });
  await assert.rejects(
    scalar(
      `select public.finish_governed_worker_dispatch_authorized($1, $2, $3, $4, $5, 'completed', 1500, $6, $7, $8::jsonb, $9, $10, $11, $12) as result`,
      [
        organizationId,
        claimed.dispatchId,
        plan.planId,
        workerId,
        '0'.repeat(64),
        jobDigest,
        workerEvidenceHash,
        JSON.stringify(resultSummary),
        completionRequestId,
        completionNonce,
        completionTimestamp,
        completionSignatureB64,
      ],
    ),
    (error) => error?.code === '42501',
    'worker completion was not bound to the key that claimed the dispatch',
  );
  await setWorkerAuthority({
    purpose: 'worker_complete',
    requestId: completionRequestId,
    requestSha256: completionRequestSha256For(keyFingerprint),
    dispatchId: claimed.dispatchId,
    planId: plan.planId,
  });
  const reported = await scalar(
    `select public.finish_governed_worker_dispatch_authorized($1, $2, $3, $4, $5, 'completed', 1500, $6, $7, $8::jsonb, $9, $10, $11, $12) as result`,
    [
      organizationId,
      claimed.dispatchId,
      plan.planId,
      workerId,
      keyFingerprint,
      jobDigest,
      workerEvidenceHash,
      JSON.stringify(resultSummary),
      completionRequestId,
      completionNonce,
      completionTimestamp,
      completionSignatureB64,
    ],
  );
  assert.equal(reported.status, 'result_reported');
  assert.equal(reported.reviewRequired, true);
  const exactCompletionSql =
    `select public.finish_governed_worker_dispatch_authorized($1, $2, $3, $4, $5, 'completed', 1500, $6, $7, $8::jsonb, $9, $10, $11, $12) as result`;
  const exactCompletionArgs = [
    organizationId, claimed.dispatchId, plan.planId, workerId, keyFingerprint,
    jobDigest, workerEvidenceHash, JSON.stringify(resultSummary),
    completionRequestId, completionNonce, completionTimestamp,
    completionSignatureB64,
  ];
  await assert.rejects(
    scalar(exactCompletionSql, exactCompletionArgs),
    (error) => error?.code === '23505',
    'a consumed worker completion authority JTI was reusable',
  );
  await setWorkerAuthority({
    purpose: 'worker_complete',
    requestId: completionRequestId,
    requestSha256: completionRequestSha256For(keyFingerprint),
    dispatchId: claimed.dispatchId,
    planId: plan.planId,
  });
  const replayedCompletion = await scalar(exactCompletionSql, exactCompletionArgs);
  assert.equal(replayedCompletion.idempotentReplay, true);
  assert.equal(
    await scalar(`select status from private.execution_plans where id = $1`, [plan.planId]),
    'executing',
  );
  await assert.rejects(
    scalar(
      `select public.finish_execution_plan($1, $2, 'completed', 1500, null, '{}'::jsonb) as result`,
      [organizationId, plan.planId],
    ),
    (error) => error?.code === '55000',
    'worker self-report bypassed reviewer-gated plan finalization',
  );

  const unsignedVerificationEvidenceId = await scalar(`
    insert into public.projectos_evidence (
      organization_id, project_id, evidence_type, provider, external_id,
      repository, head_sha, status, verdict, payload_redacted, observed_at
    ) values (
      $1, $2, 'worker_dispatch_review', 'google', $3, $4, $5,
      'passing', 'pass', $6::jsonb, now()
    ) returning id
  `, [
    organizationId,
    projectId,
    `unsigned-worker-replay-${claimed.dispatchId}`,
    repository,
    exactSha,
    JSON.stringify({
      dispatchId: claimed.dispatchId,
      workerEvidenceSha256: workerEvidenceHash,
      reviewerAgent: reviewerId,
      reviewerVendor: 'google',
      decision: 'completed',
    }),
  ]);
  await assert.rejects(
    scalar(
      `select public.verify_governed_worker_dispatch($1, $2, $3, $4, $5, 'completed') as result`,
      [
        organizationId,
        claimed.dispatchId,
        plan.planId,
        reviewerProofId,
        unsignedVerificationEvidenceId,
      ],
    ),
    (error) => error?.code === '55000' &&
      /signed reviewer and worker completion attestations required/.test(error.message),
    'unsigned generic evidence bypassed reviewer-attestation finalization',
  );

  const reviewNonce = 'reviewer-replay-nonce-0001';
  const reviewTimestamp = new Date().toISOString();
  const reviewerSignatureBasis = [
    'pandora-reviewer-request-v1',
    'attest',
    organizationId,
    reviewerId,
    reviewerRequestId,
    reviewNonce,
    reviewTimestamp,
    claimed.dispatchId,
    plan.planId,
    reviewerProofId,
    workerEvidenceHash,
    repository,
    exactSha,
    resultSummary.sourceTreeSha,
    'pass',
    reviewArtifactSha256,
  ].join('|');
  const reviewAttestationArgs = [
    organizationId,
    reviewerRequestId,
    reviewerId,
    reviewerKeyFingerprint,
    claimed.dispatchId,
    plan.planId,
    reviewerProofId,
    workerEvidenceHash,
    repository,
    exactSha,
    resultSummary.sourceTreeSha,
    'pass',
    reviewArtifactSha256,
    reviewNonce,
    reviewTimestamp,
    reviewerSignatureB64,
  ];
  const workerAuthorityRequestSha = (args) => {
    const signatureBasis = [
      'pandora-reviewer-request-v1',
      'attest',
      args[0],
      args[2],
      args[1],
      args[13],
      args[14],
      args[4],
      args[5],
      args[6],
      args[7],
      args[8],
      args[9],
      args[10],
      args[11],
      args[12],
    ].join('|');
    return sha256([
      'pandora-reviewer-authority-v1',
      sha256(signatureBasis),
      args[3],
      sha256(Buffer.from(args[15], 'base64')),
    ].join('|'));
  };
  let workerAuthoritySequence = 0;
  const setWorkerReviewAuthority = async (args, reuseJti = null) => {
    const issuedAt = Math.floor(Date.now() / 1000);
    const jti = reuseJti || `worker-review-authority-${++workerAuthoritySequence}-20260823`;
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify({
        role: 'projectos_reviewer_ingest',
        iss: 'pandora-independent-review-authority',
        pandora_audience: 'projectos-reviewer-ingest',
        pandora_purpose: 'worker_review',
        pandora_organization_id: args[0],
        pandora_reviewer_id: args[2],
        pandora_request_sha256: workerAuthorityRequestSha(args),
        jti,
        iat: issuedAt,
        nbf: issuedAt,
        exp: issuedAt + 90,
      }),
    ]);
    return jti;
  };
  const firstWorkerAuthorityJti = await setWorkerReviewAuthority(reviewAttestationArgs);
  const reviewAttestation = await scalar(
    `select public.record_governed_worker_review_attestation(
      $1, $2, $3, $4, $5, $6, $7, $8,
      $9, $10, $11, $12, $13, $14, $15, $16
    ) as result`,
    reviewAttestationArgs,
  );
  assert.equal(reviewAttestation.status, 'attested');
  assert.equal(reviewAttestation.decision, 'completed');
  assert.equal(reviewAttestation.signatureBasisSha256, sha256(reviewerSignatureBasis));
  assert.equal(reviewAttestation.idempotentReplay, false);
  await assert.rejects(
    scalar(
      `select public.record_governed_worker_review_attestation(
        $1, $2, $3, $4, $5, $6, $7, $8,
        $9, $10, $11, $12, $13, $14, $15, $16
      ) as result`,
      reviewAttestationArgs,
    ),
    (error) => error?.code === '23505',
    'a consumed external reviewer authority token was reusable',
  );
  await setWorkerReviewAuthority(reviewAttestationArgs);
  const replayedReviewAttestation = await scalar(
    `select public.record_governed_worker_review_attestation(
      $1, $2, $3, $4, $5, $6, $7, $8,
      $9, $10, $11, $12, $13, $14, $15, $16
    ) as result`,
    reviewAttestationArgs,
  );
  assert.equal(replayedReviewAttestation.idempotentReplay, true);
  const changedReviewArgs = reviewAttestationArgs.map((value, index) =>
    index === 12 ? sha256('different-review-artifact') : value);
  await setWorkerReviewAuthority(changedReviewArgs);
  await assert.rejects(
    scalar(
      `select public.record_governed_worker_review_attestation(
        $1, $2, $3, $4, $5, $6, $7, $8,
        $9, $10, $11, $12, $13, $14, $15, $16
      ) as result`,
      changedReviewArgs,
    ),
    (error) => error?.code === '55000',
    'a signed request identity accepted different terminal review content',
  );
  const verificationEvidenceId = reviewAttestation.verificationEvidenceId;
  const reviewBinding = await db.query(`
    select
      evidence.organization_id = dispatch.organization_id as organization_matches,
      evidence.project_id = intake.project_id as project_matches,
      evidence.repository = plan.args ->> 'repository' as repository_matches,
      evidence.head_sha = plan.args ->> 'exactSha' as source_matches,
      evidence.invalidated_at is null as remains_valid,
      evidence.evidence_type in ('independent_review_pass', 'worker_dispatch_review') as type_matches,
      evidence.observed_at >= dispatch.worker_reported_at - interval '2 minutes' as time_matches,
      evidence.payload_redacted ->> 'dispatchId' = dispatch.id::text as dispatch_matches,
      evidence.payload_redacted ->> 'workerEvidenceSha256' = dispatch.evidence_sha256 as worker_evidence_matches
    from public.projectos_evidence evidence
    join private.execution_dispatch_outbox dispatch on dispatch.id = $2
    join private.execution_plans plan on plan.id = dispatch.plan_id
    join public.projectos_intake_requests intake on intake.id = plan.intake_id
    where evidence.id = $1
  `, [verificationEvidenceId, claimed.dispatchId]);
  assert.deepEqual(reviewBinding.rows, [{
    organization_matches: true,
    project_matches: true,
    repository_matches: true,
    source_matches: true,
    remains_valid: true,
    type_matches: true,
    time_matches: true,
    dispatch_matches: true,
    worker_evidence_matches: true,
  }], 'worker review evidence binding drifted');
  const durableAttestation = await db.query(`
    select
      request_id,
      reviewer_id,
      reviewer_runtime_proof_id,
      reviewer_key_fingerprint,
      reviewer_nonce_sha256,
      signed_timestamp,
      signature_b64,
      signature_basis_sha256,
      worker_evidence_sha256,
      review_artifact_sha256,
      repository,
      exact_sha,
      source_tree_sha
    from private.governed_worker_review_attestations
    where organization_id = $1 and dispatch_id = $2
  `, [organizationId, claimed.dispatchId]);
  assert.deepEqual(durableAttestation.rows, [{
    request_id: reviewerRequestId,
    reviewer_id: reviewerId,
    reviewer_runtime_proof_id: reviewerProofId,
    reviewer_key_fingerprint: reviewerKeyFingerprint,
    reviewer_nonce_sha256: sha256(reviewNonce),
    signed_timestamp: reviewTimestamp,
    signature_b64: reviewerSignatureB64,
    signature_basis_sha256: sha256(reviewerSignatureBasis),
    worker_evidence_sha256: workerEvidenceHash,
    review_artifact_sha256: reviewArtifactSha256,
    repository,
    exact_sha: exactSha,
    source_tree_sha: resultSummary.sourceTreeSha,
  }], 'durable signed reviewer attestation binding drifted');
  await assert.rejects(
    db.query(`
      update private.governed_worker_review_attestations
      set review_artifact_sha256 = repeat('0', 64)
      where organization_id = $1 and dispatch_id = $2
    `, [organizationId, claimed.dispatchId]),
    (error) => error?.code === '55000',
    'durable reviewer attestation accepted an update',
  );
  await assert.rejects(
    db.query(`
      delete from private.governed_worker_review_attestations
      where organization_id = $1 and dispatch_id = $2
    `, [organizationId, claimed.dispatchId]),
    (error) => error?.code === '55000',
    'durable reviewer attestation accepted a delete',
  );
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);
  const verified = await scalar(
    `select public.verify_governed_worker_dispatch($1, $2, $3, $4, $5, 'completed') as result`,
    [
      organizationId,
      claimed.dispatchId,
      plan.planId,
      reviewerProofId,
      verificationEvidenceId,
    ],
  );
  assert.equal(verified.status, 'completed');
  assert.equal(
    await scalar(`select status from private.execution_plans where id = $1`, [plan.planId]),
    'completed',
  );
  assert.equal(
    await scalar(
      `select active_leases from public.projectos_agent_runtime_proofs where id = $1`,
      [builderProofId],
    ),
    0,
  );
  assert.equal(
    await scalar(
      `select count(*)::integer from private.execution_audit_events where plan_id = $1 and event_type = 'worker_dispatch_reviewer_finalized'`,
      [plan.planId],
    ),
    1,
  );

  return {
    owner_intake_idempotency: 'pass',
    conflicting_idempotency_rejected: true,
    governed_worker_enrollment: 'pass',
    execution_plan_context_immutable: true,
    memory_gated_atomic_dispatch: 'pass',
    signed_envelope_exact_binding: 'pass',
    worker_self_report_terminal: false,
    direct_private_table_access: false,
    direct_finish_bypass_rejected: true,
    unsigned_reviewer_evidence_rejected: true,
    signed_reviewer_attestation: 'pass',
    reviewer_attestation_immutable: true,
    owner_can_self_attest: false,
    independent_reviewer_finalization: 'pass',
    active_lease_released: true,
  };
}

async function canonicalReleaseAttestationSmoke(db) {
  const organizationId = '2270b266-59da-4c39-bfd9-9f8d08352af0';
  const repository = 'pandora-rvw-314296438-20260820/pandoras-box';
  // Reuse the exact source/tree already proven by governedWorkerSmoke so the
  // physical journey can bind a real owner plan, Worker-01 result, and review.
  const sourceSha = 'c'.repeat(40);
  const sourceTreeSha = 'd'.repeat(40);
  const sourceChainSha256 = 'e'.repeat(64);
  const sourceArtifactSha256 = 'f'.repeat(64);
  const versionChainSha256 = '1'.repeat(64);
  const apkSha256 = '2'.repeat(64);
  const mobileArtifactDigest = '3'.repeat(64);
  const deviceIdHash = '4'.repeat(64);
  const productionDeploymentId = 'dpl_releaseCandidate123';
  const rollbackDeploymentId = 'dpl_releaseRollback456';
  const rollbackSourceSha = 'b'.repeat(40);
  const reviewRequestId = 'b0c689b5-ad71-422c-9c4b-dd74ac4e37fb';
  const ownerRequestId = 'owner-release-auth-0001';
  const reviewNonce = 'canonical-release-review-nonce-0001';
  const reviewExternalId = 'independent-release-review-0001';
  const reviewSourceUrl = 'https://github.com/pandora-rvw-314296438-20260820/pandoras-box/issues/1';
  const reviewDigest = sha256('independent canonical release review');
  const reviewSignatureB64 = Buffer.alloc(64, 3).toString('base64');
  const reviewSignatureSha256 = sha256(Buffer.from(reviewSignatureB64, 'base64'));
  const completedSteps = [
    'owner_authenticate',
    'submit_owner_command',
    'observe_durable_dispatch',
    'observe_worker_01_claim',
    'observe_exact_provider_result',
    'observe_proof_in_owner_read',
  ];
  const scalar = async (sql, params = []) => {
    const result = await db.query(sql, params);
    assert.equal(result.rows.length, 1);
    return Object.values(result.rows[0])[0];
  };

  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);
  const reviewer = (await db.query(`
    select identity.reviewer_id,
           identity.runtime_proof_id,
           identity.key_fingerprint,
           proof.project_id
    from private.compute_reviewer_identities identity
    join public.projectos_agent_runtime_proofs proof
      on proof.id = identity.runtime_proof_id
    where identity.organization_id = $1
      and identity.status = 'active'
    order by identity.created_at
    limit 1
  `, [organizationId])).rows[0];
  assert.ok(reviewer, 'release reviewer fixture unavailable');
  await db.query(`
    update public.projectos_agent_runtime_proofs
    set proven_capabilities = (
          select array_agg(distinct capability order by capability)
          from unnest(proven_capabilities || array['projectos.release.review']) capability
        ),
        verified_at = now(),
        context_updated_at = now(),
        expires_at = now() + interval '30 minutes',
        is_active = true
    where id = $1
  `, [reviewer.runtime_proof_id]);
  const ownerUserId = await scalar(`
    select user_id
    from public.memberships
    where organization_id = $1
      and role = 'owner'::public.member_role
      and status = 'active'::public.membership_status
    order by created_at
    limit 1
  `, [organizationId]);

  await db.query(`
    insert into public.projectos_evidence (
      organization_id, project_id, evidence_type, provider, external_id,
      source_url, repository, head_sha, status, verdict, payload_redacted,
      observed_at
    ) values (
      $1, $2, 'canonical_vercel_production', 'vercel', $3,
      'https://api.vercel.com/v13/deployments/' || $3 || '?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3',
      $4, $5, 'passing', 'pass', $6::jsonb,
      clock_timestamp() - interval '12 minutes'
    )
  `, [
    organizationId,
    reviewer.project_id,
    productionDeploymentId,
    repository,
    sourceSha,
    JSON.stringify({
      gitRepository: repository,
      sourceSha,
      deploymentId: productionDeploymentId,
      productionVerifiedDeploymentId: productionDeploymentId,
      routeProbesPassed: true,
    }),
  ]);
  await db.query(`
    insert into private.canonical_vercel_rehearsal_receipts (
      organization_id, repository, project_id, team_id, phase,
      candidate_deployment_id, candidate_source_sha,
      rollback_deployment_id, rollback_source_sha,
      transition_from_deployment_id, transition_to_deployment_id,
      external_id, vercel_api_source_url, alias_api_source_url,
      alias_pre_response_sha256, alias_pre_observed_at,
      alias_post_response_sha256, alias_post_observed_at,
      route_probe_contract, route_probe_sha256, route_probe_observed_at,
      observed_at
    ) values
    (
      $1, $2, 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
      'team_3yw1CN59ce4pj5SwyQGCAqN3', 'rollback_transition',
      $3, $4, $5, $6, $3, $5, $5,
      'https://api.vercel.com/v13/deployments/' || $5 || '?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3',
      'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3',
      repeat('5', 64), clock_timestamp() - interval '11 minutes',
      repeat('6', 64), clock_timestamp() - interval '9 minutes',
      'canonical_routes_v1', repeat('7', 64), clock_timestamp() - interval '10 minutes',
      clock_timestamp() - interval '8 minutes 50 seconds'
    ),
    (
      $1, $2, 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
      'team_3yw1CN59ce4pj5SwyQGCAqN3', 'rollback_restoration',
      $3, $4, $5, $6, $5, $3, $3,
      'https://api.vercel.com/v13/deployments/' || $3 || '?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3',
      'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3',
      repeat('8', 64), clock_timestamp() - interval '8 minutes',
      repeat('9', 64), clock_timestamp() - interval '6 minutes',
      'canonical_routes_v1', repeat('a', 64), clock_timestamp() - interval '7 minutes',
      clock_timestamp() - interval '5 minutes 50 seconds'
    )
  `, [
    organizationId,
    repository,
    productionDeploymentId,
    sourceSha,
    rollbackDeploymentId,
    rollbackSourceSha,
  ]);
  await db.query(`
    insert into private.canonical_supabase_release_receipts (
      organization_id, repository, project_ref, source_sha, source_tree_sha,
      source_chain_sha256, source_artifact_sha256,
      source_artifact_external_id, source_artifact_url,
      expected_version_chain_sha256, captured_applied_versions,
      captured_version_chain_sha256
    ) values (
      $1, $2, 'jcyqixttuebxqqfkjonq', $3, $4, $5, $6,
      '123456789',
      'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/123456789',
      $7, array['20260823160000']::text[], $7
    )
  `, [
    organizationId,
    repository,
    sourceSha,
    sourceTreeSha,
    sourceChainSha256,
    sourceArtifactSha256,
    versionChainSha256,
  ]);

  const ciArtifact = {
    externalId: '987654321',
    sourceUrl: 'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/987654321',
    name: `pandora-mobile-android-validation-${sourceSha}`,
    digestSha256: mobileArtifactDigest,
    apkSha256,
    sourceSha,
    sourceTreeSha,
  };
  for (const [network, evidenceType, minutes] of [
    ['wifi', 'canonical_physical_android_wifi', 5],
    ['mobile_data', 'canonical_physical_android_mobile_data', 4],
  ]) {
    await db.query(`
      insert into public.projectos_evidence (
        organization_id, project_id, evidence_type, provider, external_id,
        repository, head_sha, status, verdict, payload_redacted, observed_at
      ) values (
        $1, $2, $3, 'physical_android_observer', $4, $5, $6,
        'passing', 'verified', $7::jsonb,
        clock_timestamp() - make_interval(mins => $8)
      )
    `, [
      organizationId,
      reviewer.project_id,
      evidenceType,
      `physical-${network}-${sourceSha}`,
      repository,
      sourceSha,
      JSON.stringify({
        network,
        sourceSha,
        sourceTreeSha,
        productionOrigin: 'https://mcpmaster.vercel.app',
        deploymentId: productionDeploymentId,
        artifactSha256: apkSha256,
        ciArtifact,
        deviceIdHash,
        packageName: 'com.banataosystems.pandora_mobile',
        completedSteps,
        verified: true,
      }),
      minutes,
    ]);
  }

  const workerBinding = (await db.query(`
    select
      plan.id as plan_id,
      dispatch.id as dispatch_id,
      dispatch.evidence_sha256,
      dispatch.verification_evidence_id,
      dispatch.verifier_runtime_proof_id
    from private.execution_plans plan
    join private.execution_dispatch_outbox dispatch on dispatch.plan_id = plan.id
    where plan.organization_id = $1
      and plan.tool = 'projectos.worker.verify'
      and plan.status = 'completed'
      and plan.args ->> 'repository' = $2
      and plan.args ->> 'exactSha' = $3
      and dispatch.status = 'completed'
      and dispatch.result_summary ->> 'sourceTreeSha' = $4
    order by dispatch.completed_at desc
    limit 1
  `, [organizationId, repository, sourceSha, sourceTreeSha])).rows[0];
  assert.ok(workerBinding, 'canonical physical journey worker binding unavailable');

  const observerId = 'physical-android-replay';
  const observerPublicKey = Buffer.alloc(32, 9);
  const observerPublicKeyB64 = observerPublicKey.toString('base64');
  const observerKeyFingerprint = sha256(observerPublicKey);
  const physicalSignatureB64 = Buffer.alloc(64, 7).toString('base64');
  const registeredObserver = await scalar(`
    select public.register_physical_android_observer_identity(
      $1, $2, $3, $4::text[]
    ) as result
  `, [organizationId, observerId, observerPublicKeyB64, [repository]]);
  assert.equal(registeredObserver.keyFingerprint, observerKeyFingerprint);

  let physicalAuthoritySequence = 0;
  const physicalArgs = (network, observedAt) => {
    const observationIndex = network === 'wifi' ? 1 : 2;
    const requestId = network === 'wifi'
      ? '8a4c4ad2-79ec-4e7e-9d84-f17252fd62a1'
      : 'f164d9f8-0ca1-4270-8628-084ae81cc0c5';
    const nonce = `physical-android-${network}-nonce-20260823`;
    const basis = [
      'pandora-physical-android-request-v1',
      'capture',
      organizationId,
      observerId,
      observerKeyFingerprint,
      requestId,
      nonce,
      observedAt,
      repository,
      sourceSha,
      sourceTreeSha,
      productionDeploymentId,
      'https://mcpmaster.vercel.app',
      ciArtifact.externalId,
      ciArtifact.sourceUrl,
      ciArtifact.name,
      ciArtifact.digestSha256,
      apkSha256,
      deviceIdHash,
      'com.banataosystems.pandora_mobile',
      network,
      String(observationIndex),
      completedSteps.join(','),
      workerBinding.plan_id,
      workerBinding.dispatch_id,
      workerBinding.evidence_sha256,
      workerBinding.verification_evidence_id,
      workerBinding.verifier_runtime_proof_id,
    ].join('|');
    return {
      observationIndex,
      basis,
      values: [
        organizationId,
        requestId,
        observerId,
        observerKeyFingerprint,
        repository,
        sourceSha,
        sourceTreeSha,
        productionDeploymentId,
        'https://mcpmaster.vercel.app',
        ciArtifact.externalId,
        ciArtifact.sourceUrl,
        ciArtifact.name,
        ciArtifact.digestSha256,
        apkSha256,
        deviceIdHash,
        'com.banataosystems.pandora_mobile',
        network,
        completedSteps,
        workerBinding.plan_id,
        workerBinding.dispatch_id,
        workerBinding.evidence_sha256,
        workerBinding.verification_evidence_id,
        workerBinding.verifier_runtime_proof_id,
        nonce,
        observedAt,
        physicalSignatureB64,
        sha256(basis),
      ],
    };
  };
  const setPhysicalAuthority = async (request, reuseJti = null) => {
    const issuedAt = Math.floor(Date.now() / 1000);
    const jti = reuseJti ||
      `physical-android-authority-${++physicalAuthoritySequence}-20260823`;
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify({
        role: 'projectos_physical_android_ingest',
        iss: 'pandora-physical-android-authority-v1',
        aud: 'projectos_physical_android_ingest',
        purpose: 'canonical_physical_android_capture',
        sub: observerId,
        jti,
        iat: issuedAt,
        nbf: issuedAt,
        exp: issuedAt + 90,
        organization_id: organizationId,
        observer_id: observerId,
        observer_key_fingerprint: observerKeyFingerprint,
        request_id: request.values[1],
        request_sha256: sha256(`${request.basis}|${physicalSignatureB64}`),
        network: request.values[16],
        provider_observation_index: request.observationIndex,
        device_id_hash: deviceIdHash,
      }),
    ]);
    return jti;
  };
  const capturePhysical = (request) => scalar(`
    select public.capture_canonical_physical_android_receipt(
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
      $15, $16, $17, $18::text[], $19, $20, $21, $22, $23, $24, $25,
      $26, $27
    ) as result
  `, request.values);

  const wifiRequest = physicalArgs(
    'wifi',
    new Date(Date.now() - 2000).toISOString(),
  );
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);
  await assert.rejects(
    capturePhysical(wifiRequest),
    (error) => error?.code === '42501',
    'service role could directly assert canonical physical Android evidence',
  );
  const wifiAuthorityJti = await setPhysicalAuthority(wifiRequest);
  assert.equal(
    (await scalar(
      `select public.consume_physical_android_authority_rate_limit($1) as result`,
      [organizationId],
    )).allowed,
    true,
  );
  const wifiReceipt = await capturePhysical(wifiRequest);
  assert.equal(wifiReceipt.storageAuthority, 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT');
  assert.equal(wifiReceipt.providerObservationIndex, 1);
  await assert.rejects(
    capturePhysical(wifiRequest),
    (error) => error?.code === '23505',
    'external physical authority issuer/JTI was reusable',
  );
  assert.ok(wifiAuthorityJti);

  await setPhysicalAuthority(wifiRequest);
  const replayedWifi = await capturePhysical(wifiRequest);
  assert.equal(replayedWifi.receiptId, wifiReceipt.receiptId);
  assert.equal(replayedWifi.idempotentReplay, true);

  const mobileRequest = physicalArgs(
    'mobile_data',
    new Date(Date.now() - 500).toISOString(),
  );
  await setPhysicalAuthority(mobileRequest);
  assert.equal(
    (await scalar(
      `select public.consume_physical_android_authority_rate_limit($1) as result`,
      [organizationId],
    )).allowed,
    true,
  );
  const mobileReceipt = await capturePhysical(mobileRequest);
  assert.equal(mobileReceipt.providerObservationIndex, 2);
  assert.notEqual(mobileReceipt.receiptId, wifiReceipt.receiptId);

  await assert.rejects(
    db.query(`
      update private.canonical_physical_android_receipts
      set apk_sha256 = repeat('0', 64)
      where id = $1
    `, [mobileReceipt.receiptId]),
    (error) => error?.code === '55000',
    'canonical physical Android receipt was mutable',
  );

  const reviewedAt = new Date();
  const reviewArgs = [
    organizationId,
    reviewRequestId,
    repository,
    sourceSha,
    sourceTreeSha,
    productionDeploymentId,
    rollbackDeploymentId,
    sourceChainSha256,
    reviewer.reviewer_id,
    reviewer.runtime_proof_id,
    reviewer.key_fingerprint,
    reviewExternalId,
    reviewSourceUrl,
    reviewDigest,
    reviewSignatureB64,
    reviewSignatureSha256,
    reviewNonce,
    reviewedAt.toISOString(),
  ];
  const releaseAuthorityRequestSha = sha256([
    'pandora-release-review-authority-v1',
    organizationId,
    reviewRequestId,
    reviewer.reviewer_id,
    reviewer.runtime_proof_id,
    reviewer.key_fingerprint,
    reviewNonce,
    reviewedAt.toISOString(),
    repository,
    sourceSha,
    sourceTreeSha,
    productionDeploymentId,
    rollbackDeploymentId,
    sourceChainSha256,
    reviewExternalId,
    reviewSourceUrl,
    reviewDigest,
    reviewSignatureSha256,
    'approved',
  ].join('|'));
  let releaseAuthoritySequence = 0;
  const setReleaseAuthority = async () => {
    const issuedAt = Math.floor(Date.now() / 1000);
    const jti = `release-review-authority-${++releaseAuthoritySequence}-20260823`;
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify({
        role: 'projectos_reviewer_ingest',
        iss: 'pandora-independent-review-authority',
        pandora_audience: 'projectos-reviewer-ingest',
        pandora_purpose: 'release_review',
        pandora_organization_id: organizationId,
        pandora_reviewer_id: reviewer.reviewer_id,
        pandora_request_sha256: releaseAuthorityRequestSha,
        jti,
        iat: issuedAt,
        nbf: issuedAt,
        exp: issuedAt + 90,
      }),
    ]);
    return jti;
  };
  await setReleaseAuthority();
  const reviewReceipt = await scalar(`
    select public.capture_canonical_release_review_receipt(
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      $10, $11, $12, $13, $14, $15, $16, $17, $18
    ) as result
  `, reviewArgs);
  assert.equal(reviewReceipt.verified, true);
  assert.equal(reviewReceipt.authority, 'INDEPENDENT_REVIEWER');
  assert.equal(reviewReceipt.idempotentReplay, undefined);
  await assert.rejects(
    scalar(`
      select public.capture_canonical_release_review_receipt(
        $1, $2, $3, $4, $5, $6, $7, $8, $9,
        $10, $11, $12, $13, $14, $15, $16, $17, $18
      ) as result
    `, reviewArgs),
    (error) => error?.code === '23505',
    'a consumed external release-review authority token was reusable',
  );
  await setReleaseAuthority();
  const replayedReview = await scalar(`
    select public.capture_canonical_release_review_receipt(
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      $10, $11, $12, $13, $14, $15, $16, $17, $18
    ) as result
  `, reviewArgs);
  assert.equal(replayedReview.receiptId, reviewReceipt.receiptId);
  assert.equal(replayedReview.idempotentReplay, true);
  assert.equal(
    await scalar(`
      select count(*)::integer
      from private.compute_reviewer_nonces
      where organization_id = $1
        and reviewer_id = $2
        and nonce_sha256 = $3
    `, [organizationId, reviewer.reviewer_id, sha256(reviewNonce)]),
    1,
  );

  const ownerSessionId = 'fd150e20-4fc2-4d5e-b1fb-b18107964677';
  const mfaVerifiedEpoch = Math.floor(Date.now() / 1000);
  await db.query(`
    insert into auth.sessions (id, user_id, aal, not_after)
    values ($1, $2, 'aal2'::auth.aal_level, now() + interval '30 minutes')
  `, [ownerSessionId, ownerUserId]);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({
      role: 'authenticated',
      sub: ownerUserId,
      aal: 'aal2',
      is_anonymous: false,
      session_id: ownerSessionId,
      amr: [
        { method: 'totp', timestamp: mfaVerifiedEpoch },
        { method: 'password', timestamp: mfaVerifiedEpoch - 60 },
      ],
    }),
  ]);
  const authorizedAt = new Date();
  const ownerArgs = [
    organizationId,
    repository,
    ownerUserId,
    sourceSha,
    productionDeploymentId,
    reviewReceipt.receiptId,
    reviewReceipt.receiptSha256,
    'aal2',
    ownerRequestId,
    authorizedAt.toISOString(),
  ];
  const ownerReceipt = await scalar(`
    select public.capture_canonical_release_owner_authorization(
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
    ) as result
  `, ownerArgs);
  assert.equal(ownerReceipt.verified, true);
  assert.equal(ownerReceipt.authority, 'OWNER_AUTHORIZATION');
  assert.equal(ownerReceipt.sessionId, ownerSessionId);
  assert.equal(
    Math.abs(Date.parse(ownerReceipt.mfaVerifiedAt) - mfaVerifiedEpoch * 1000) <= 1000,
    true,
  );
  const replayedOwner = await scalar(`
    select public.capture_canonical_release_owner_authorization(
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
    ) as result
  `, ownerArgs);
  assert.equal(replayedOwner.receiptId, ownerReceipt.receiptId);
  assert.equal(replayedOwner.idempotentReplay, true);

  await db.query(`delete from auth.sessions where id = $1`, [ownerSessionId]);
  await assert.rejects(
    scalar(`
      select public.capture_canonical_release_owner_authorization(
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
      ) as result
    `, ownerArgs),
    (error) => error?.code === '42501',
    'a revoked owner session remained authorization-capable',
  );

  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ role: 'service_role' }),
  ]);
  const access = (await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.capture_canonical_release_review_receipt(uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      ) as service_can_review,
      has_function_privilege(
        'projectos_reviewer_ingest',
        'public.capture_canonical_release_review_receipt(uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      ) as reviewer_can_review,
      has_function_privilege(
        'service_role',
        'public.capture_canonical_release_owner_authorization(uuid,text,uuid,text,text,uuid,text,text,text,timestamptz)',
        'EXECUTE'
      ) as service_can_authorize,
      has_function_privilege(
        'authenticated',
        'public.capture_canonical_release_owner_authorization(uuid,text,uuid,text,text,uuid,text,text,text,timestamptz)',
        'EXECUTE'
      ) as owner_session_can_authorize
  `)).rows[0];
  assert.deepEqual(access, {
    service_can_review: false,
    reviewer_can_review: true,
    service_can_authorize: false,
    owner_session_can_authorize: true,
  });
  await assert.rejects(
    db.query(`
      update private.canonical_release_review_receipts
      set review_digest = repeat('0', 64)
      where id = $1
    `, [reviewReceipt.receiptId]),
    (error) => error?.code === '55000',
    'canonical release review receipt was mutable',
  );
  await assert.rejects(
    db.query(`
      update private.canonical_release_owner_authorizations
      set request_id = 'owner-release-auth-9999'
      where id = $1
    `, [ownerReceipt.receiptId]),
    (error) => error?.code === '55000',
    'canonical owner authorization receipt was mutable',
  );

  await db.query(`
    update public.memberships
    set status = 'suspended'::public.membership_status
    where organization_id = $1 and user_id = $2
  `, [organizationId, ownerUserId]);
  const statusAfterOffboarding = await scalar(
    `select public.get_canonical_release_status($1, $2, $3) as result`,
    [organizationId, repository, sourceSha],
  );
  assert.equal(
    statusAfterOffboarding.ownerAuthorization?.receiptId,
    ownerReceipt.receiptId,
    `offboarding rewrote authorization-at-capture evidence: ${JSON.stringify(statusAfterOffboarding)}`,
  );
  await db.query(`
    update public.memberships
    set status = 'active'::public.membership_status
    where organization_id = $1 and user_id = $2
  `, [organizationId, ownerUserId]);

  return {
    physical_android_external_authority: true,
    service_role_physical_assertion: false,
    physical_android_ordered_network_receipts: true,
    physical_android_owner_worker_reviewer_binding: true,
    independent_review_actor_separated: true,
    release_review_atomic_nonce: true,
    release_review_idempotent: true,
    aal2_owner_exact_review_binding: true,
    live_recent_aal2_session_binding: true,
    revoked_session_rejected: true,
    offboarding_preserves_capture_evidence: true,
    owner_authorization_idempotent: true,
    receipts_immutable: true,
  };
}

async function rollbackSmoke(db) {
  const rollback = await readFile(
    join(recoveryRoot, 'rollback', '20260812034825_restore_projectos_approval_aal2.sql'),
    'utf8',
  );
  const aal1 = await readFile(
    join(migrationRoot, '20260813014555_remove_projectos_approval_aal2.sql'),
    'utf8',
  );
  const definition = async () => (await db.query(`
    select pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'decide_approval'
      and pg_get_function_identity_arguments(p.oid) = 'approval_id uuid, requested_decision approval_decision, reason text'
  `)).rows[0].definition;

  await db.exec(rollback);
  const restored = await definition();
  assert.match(restored, /auth\.sessions/i, 'database rollback did not restore session assurance');
  assert.match(restored, /current_session_id/i, 'database rollback did not restore session identity');
  assert.match(restored, /'aal2'/i, 'database rollback did not restore AAL2');

  await db.exec(aal1);
  const reapplied = await definition();
  assert.doesNotMatch(
    reapplied,
    /auth\.sessions|auth\.aal_level|current_session_id/i,
    'AAL1 migration could not be reapplied after rollback',
  );
  return {
    restore_previous_aal2_definition: 'pass',
    reapply_aal1_definition: 'pass',
  };
}

async function physicalAndroidRollbackSmoke(db) {
  const rollback = await readFile(
    join(
      recoveryRoot,
      'rollback',
      '20260823170000_remove_immutable_physical_android_receipts.sql',
    ),
    'utf8',
  );
  const before = (await db.query(`
    select
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_physical_android_receipts receipt
      ), '[]')
        as physical_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(jti) order by jti.issuer, jti.jti)::text
        from private.physical_android_authority_jtis jti
      ), '[]')
        as authority_jtis,
      coalesce((
        select jsonb_agg(to_jsonb(rate_limit)
          order by rate_limit.organization_id, rate_limit.purpose_sha256,
            rate_limit.window_started_at)::text
        from private.physical_android_authority_rate_limits rate_limit
      ), '[]')
        as authority_rate_limits,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id', identity.organization_id,
          'observer_id', identity.observer_id,
          'public_key_b64', identity.public_key_b64,
          'key_fingerprint', identity.key_fingerprint,
          'allowed_repositories', identity.allowed_repositories,
          'created_at', identity.created_at
        ) order by identity.organization_id, identity.observer_id)::text
        from private.physical_android_observer_identities identity
      ), '[]')
        as observer_identities,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_review_receipts receipt
      ), '[]')
        as release_review_receipts
  `)).rows[0];
  await db.exec(rollback);

  const after = (await db.query(`
    select
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_physical_android_receipts receipt
      ), '[]')
        as physical_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(jti) order by jti.issuer, jti.jti)::text
        from private.physical_android_authority_jtis jti
      ), '[]')
        as authority_jtis,
      coalesce((
        select jsonb_agg(to_jsonb(rate_limit)
          order by rate_limit.organization_id, rate_limit.purpose_sha256,
            rate_limit.window_started_at)::text
        from private.physical_android_authority_rate_limits rate_limit
      ), '[]')
        as authority_rate_limits,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id', identity.organization_id,
          'observer_id', identity.observer_id,
          'public_key_b64', identity.public_key_b64,
          'key_fingerprint', identity.key_fingerprint,
          'allowed_repositories', identity.allowed_repositories,
          'created_at', identity.created_at
        ) order by identity.organization_id, identity.observer_id)::text
        from private.physical_android_observer_identities identity
      ), '[]')
        as observer_identities,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_review_receipts receipt
      ), '[]')
        as release_review_receipts
  `)).rows[0];
  assert.deepEqual(after, before, 'physical Android rollback changed historical evidence');

  const access = (await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.resolve_physical_android_observer_identity(uuid,text)',
        'EXECUTE'
      ) as service_can_resolve_observer,
      has_function_privilege(
        'projectos_physical_android_ingest',
        'public.capture_canonical_physical_android_receipt(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text[],uuid,uuid,text,uuid,uuid,text,text,text,text)',
        'EXECUTE'
      ) as ingest_can_capture,
      has_function_privilege(
        'projectos_physical_android_ingest',
        'public.consume_physical_android_authority_rate_limit(uuid)',
        'EXECUTE'
      ) as ingest_can_consume_rate_limit,
      has_function_privilege(
        'service_role',
        'public.get_canonical_physical_android_release_status(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_physical_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_weaker_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_final_attestations(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_pre_attestation_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_release_status,
      pg_has_role(
        'authenticator',
        'projectos_physical_android_ingest',
        'MEMBER'
      ) as authenticator_can_assume_ingest
  `)).rows[0];
  assert.deepEqual(access, {
    service_can_resolve_observer: false,
    ingest_can_capture: false,
    ingest_can_consume_rate_limit: false,
    service_can_read_physical_status: false,
    service_can_read_weaker_status: false,
    service_can_read_pre_attestation_status: false,
    service_can_read_release_status: false,
    authenticator_can_assume_ingest: false,
  }, 'physical Android rollback left an authority capability enabled');

  const preserved = (await db.query(`
    select
      not exists (
        select 1
        from private.physical_android_observer_identities
        where status = 'active'
      ) as active_observers_drained,
      exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'canonical_physical_android_receipts'
          and trigger.tgname = 'canonical_physical_android_receipts_immutable'
          and not trigger.tgisinternal
      ) as receipt_immutability_guard,
      exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'canonical_release_review_receipts'
          and trigger.tgname = 'bind_release_review_to_physical_android_receipts'
          and not trigger.tgisinternal
      ) as review_binding_guard,
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'private'
          and table_name = 'canonical_release_review_receipts'
          and column_name in (
            'physical_wifi_receipt_id',
            'physical_mobile_data_receipt_id',
            'physical_receipt_binding_sha256'
          )
        group by table_schema, table_name
        having count(*) = 3
      ) as review_binding_columns
      , exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'canonical_physical_android_receipts'
          and trigger.tgname = 'guard_physical_android_worker_completion'
          and not trigger.tgisinternal
      ) as worker_completion_binding_guard
  `)).rows[0];
  assert.deepEqual(preserved, {
    active_observers_drained: true,
    receipt_immutability_guard: true,
    review_binding_guard: true,
    review_binding_columns: true,
    worker_completion_binding_guard: true,
  }, 'physical Android rollback weakened immutable evidence bindings');

  return {
    physical_capture: 'disabled',
    physical_status_readers: 'disabled',
    authenticator_ingest_membership: 'revoked',
    active_observers: 'draining',
    receipts_jtis_and_bindings: 'preserved',
  };
}

async function canonicalReleaseRollbackSmoke(db) {
  const finalAttestationRollback = await readFile(
    join(
      recoveryRoot,
      'rollback',
      '20260823160000_remove_canonical_release_attestations.sql',
    ),
    'utf8',
  );
  const providerReceiptRollback = await readFile(
    join(
      recoveryRoot,
      'rollback',
      '20260823153552_remove_canonical_release_status_readback.sql',
    ),
    'utf8',
  );
  const before = (await db.query(`
    select
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_supabase_release_receipts receipt
      ), '[]')
        as supabase_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_vercel_rehearsal_receipts receipt
      ), '[]')
        as vercel_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_review_receipts receipt
      ), '[]')
        as review_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_owner_authorizations receipt
      ), '[]')
        as owner_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(nonce)
          order by nonce.organization_id, nonce.reviewer_id, nonce.nonce_sha256)::text
        from private.compute_reviewer_nonces nonce
      ), '[]')
        as reviewer_nonces,
      coalesce((
        select jsonb_agg(to_jsonb(nonce)
          order by nonce.issuer, nonce.jti_sha256)::text
        from private.reviewer_ingest_token_nonces nonce
      ), '[]')
        as reviewer_authority_jtis
  `)).rows[0];

  // Simulate each rollback independently against a fully enabled current head.
  // These grants exist only inside the disposable replay database.
  await db.exec(`
    grant execute on function public.capture_canonical_release_review_receipt(
      uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz
    ) to projectos_reviewer_ingest;
    grant execute on function public.capture_canonical_release_owner_authorization(
      uuid,text,uuid,text,text,uuid,text,text,text,timestamptz
    ) to authenticated;
    grant execute on function public.get_canonical_release_status(uuid,text,text)
      to service_role;
    grant execute on function public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)
      to service_role;
    grant execute on function public.get_canonical_release_status_without_final_attestations(uuid,text,text)
      to service_role;
  `);
  await db.exec(finalAttestationRollback);

  const finalAttestationAccess = (await db.query(`
    select
      has_function_privilege(
        'projectos_reviewer_ingest',
        'public.capture_canonical_release_review_receipt(uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      ) as reviewer_can_capture,
      has_function_privilege(
        'authenticated',
        'public.capture_canonical_release_owner_authorization(uuid,text,uuid,text,text,uuid,text,text,text,timestamptz)',
        'EXECUTE'
      ) as owner_can_authorize,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_pre_physical_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_release_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_final_attestations(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_pre_attestation_status
  `)).rows[0];
  assert.deepEqual(finalAttestationAccess, {
    reviewer_can_capture: false,
    owner_can_authorize: false,
    service_can_read_release_status: false,
    service_can_read_pre_physical_status: false,
    service_can_read_pre_attestation_status: false,
  }, 'standalone final-attestation rollback left a capability enabled');

  await db.exec(`
    grant execute on function public.capture_canonical_supabase_release_receipt(
      uuid,text,text,text,text,text,text,text,text
    ) to service_role;
    grant execute on function public.capture_canonical_vercel_rehearsal_receipt(
      uuid,text,text,text,text,text,text
    ) to service_role;
    grant execute on function public.get_canonical_release_status(uuid,text,text)
      to service_role;
    grant execute on function public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)
      to service_role;
    grant execute on function public.get_canonical_release_status_without_final_attestations(uuid,text,text)
      to service_role;
  `);
  await db.exec(providerReceiptRollback);

  const after = (await db.query(`
    select
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_supabase_release_receipts receipt
      ), '[]')
        as supabase_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_vercel_rehearsal_receipts receipt
      ), '[]')
        as vercel_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_review_receipts receipt
      ), '[]')
        as review_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(receipt) order by receipt.id)::text
        from private.canonical_release_owner_authorizations receipt
      ), '[]')
        as owner_receipts,
      coalesce((
        select jsonb_agg(to_jsonb(nonce)
          order by nonce.organization_id, nonce.reviewer_id, nonce.nonce_sha256)::text
        from private.compute_reviewer_nonces nonce
      ), '[]')
        as reviewer_nonces,
      coalesce((
        select jsonb_agg(to_jsonb(nonce)
          order by nonce.issuer, nonce.jti_sha256)::text
        from private.reviewer_ingest_token_nonces nonce
      ), '[]')
        as reviewer_authority_jtis
  `)).rows[0];
  assert.deepEqual(after, before, 'canonical release rollback changed historical evidence');

  const access = (await db.query(`
    select
      has_function_privilege(
        'service_role',
        'public.capture_canonical_supabase_release_receipt(uuid,text,text,text,text,text,text,text,text)',
        'EXECUTE'
      ) as service_can_capture_supabase,
      has_function_privilege(
        'service_role',
        'public.capture_canonical_vercel_rehearsal_receipt(uuid,text,text,text,text,text,text)',
        'EXECUTE'
      ) as service_can_capture_vercel,
      has_function_privilege(
        'projectos_reviewer_ingest',
        'public.capture_canonical_release_review_receipt(uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      ) as reviewer_can_capture,
      has_function_privilege(
        'authenticated',
        'public.capture_canonical_release_owner_authorization(uuid,text,uuid,text,text,uuid,text,text,text,timestamptz)',
        'EXECUTE'
      ) as owner_can_authorize,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_pre_physical_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status_without_final_attestations(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_pre_attestation_status,
      has_function_privilege(
        'service_role',
        'public.get_canonical_release_status(uuid,text,text)',
        'EXECUTE'
      ) as service_can_read_release_status
  `)).rows[0];
  assert.deepEqual(access, {
    service_can_capture_supabase: false,
    service_can_capture_vercel: false,
    reviewer_can_capture: false,
    owner_can_authorize: false,
    service_can_read_pre_physical_status: false,
    service_can_read_pre_attestation_status: false,
    service_can_read_release_status: false,
  }, 'canonical release rollback left an authority capability enabled');

  const guards = (await db.query(`
    select count(*)::integer as immutable_guard_count
    from pg_trigger trigger
    join pg_class relation on relation.oid = trigger.tgrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and trigger.tgname in (
        'canonical_supabase_release_receipts_immutable',
        'canonical_vercel_rehearsal_receipts_immutable',
        'canonical_release_review_receipts_immutable',
        'canonical_release_owner_authorizations_immutable',
        'canonical_physical_android_receipts_immutable',
        'bind_release_review_to_physical_android_receipts',
        'guard_physical_android_worker_completion'
      )
      and not trigger.tgisinternal
  `)).rows[0];
  assert.deepEqual(guards, {
    immutable_guard_count: 7,
  }, 'canonical release rollback removed an immutability guard');

  return {
    provider_capture: 'disabled',
    final_attestation_capture: 'disabled',
    canonical_status_readers: 'disabled',
    provider_review_owner_evidence: 'preserved',
    immutable_guards: 'preserved',
  };
}

async function workerAuthorityRollbackSmoke(db) {
  const rollback = await readFile(
    join(
      recoveryRoot,
      'rollback',
      '20260823171000_restore_candidate_worker_gateway_authority.sql',
    ),
    'utf8',
  );
  await db.exec(rollback);

  const access = (await db.query(`
    select
      has_function_privilege(
        'authenticated',
        'public.decide_governed_worker_execution_plan(uuid,uuid,text)',
        'EXECUTE'
      ) as authenticated_can_decide,
      has_function_privilege(
        'service_role',
        'public.decide_governed_worker_execution_plan(uuid,uuid,text,text)',
        'EXECUTE'
      ) as service_can_supply_decider,
      has_function_privilege(
        'service_role',
        'public.claim_governed_worker_dispatch(uuid,text,text)',
        'EXECUTE'
      ) as service_can_claim_legacy,
      has_function_privilege(
        'service_role',
        'public.record_governed_worker_job_envelope(uuid,uuid,uuid,text,text,jsonb,text)',
        'EXECUTE'
      ) as service_can_record_job_legacy,
      has_function_privilege(
        'service_role',
        'public.finish_governed_worker_dispatch(uuid,uuid,uuid,text,text,text,integer,text,text,jsonb)',
        'EXECUTE'
      ) as service_can_finish_legacy,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.claim_governed_worker_dispatch_authorized(uuid,text,text,uuid,text,text,text)',
        'EXECUTE'
      ) as ingest_can_claim_authorized,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.record_governed_worker_job_envelope_authorized(uuid,uuid,uuid,text,text,text,jsonb,text)',
        'EXECUTE'
      ) as ingest_can_record_job_authorized,
      has_function_privilege(
        'projectos_worker_ingest',
        'public.finish_governed_worker_dispatch_authorized(uuid,uuid,uuid,text,text,text,integer,text,text,jsonb,uuid,text,text,text)',
        'EXECUTE'
      ) as ingest_can_finish_authorized,
      pg_has_role(
        'authenticator',
        'projectos_worker_ingest',
        'MEMBER'
      ) as authenticator_can_assume_ingest
  `)).rows[0];
  assert.deepEqual(access, {
    authenticated_can_decide: false,
    service_can_supply_decider: false,
    service_can_claim_legacy: false,
    service_can_record_job_legacy: false,
    service_can_finish_legacy: false,
    ingest_can_claim_authorized: false,
    ingest_can_record_job_authorized: false,
    ingest_can_finish_authorized: false,
    authenticator_can_assume_ingest: false,
  }, 'worker authority rollback restored a mutation capability');

  const preserved = (await db.query(`
    select
      to_regclass('private.worker_authority_jtis') is not null as authority_jtis,
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'private'
          and table_name = 'execution_dispatch_outbox'
          and column_name = 'worker_completion_signature_b64'
      ) as dispatch_completion_signature,
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'private'
          and table_name = 'governed_worker_review_attestations'
          and column_name = 'worker_completion_signature_b64'
      ) as reviewer_completion_signature,
      exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'execution_dispatch_outbox'
          and trigger.tgname = 'guard_worker_authority_receipts'
          and not trigger.tgisinternal
      ) as dispatch_immutability_guard,
      exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'governed_worker_review_attestations'
          and trigger.tgname = 'bind_worker_completion_to_review'
          and not trigger.tgisinternal
      ) as reviewer_binding_guard,
      exists (
        select 1
        from pg_trigger trigger
        join pg_class relation on relation.oid = trigger.tgrelid
        join pg_namespace namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'private'
          and relation.relname = 'canonical_physical_android_receipts'
          and trigger.tgname = 'guard_physical_android_worker_completion'
          and not trigger.tgisinternal
      ) as physical_binding_guard,
      not exists (
        select 1
        from private.compute_worker_identities
        where status = 'active'
      ) as active_workers_drained
  `)).rows[0];
  assert.deepEqual(preserved, {
    authority_jtis: true,
    dispatch_completion_signature: true,
    reviewer_completion_signature: true,
    dispatch_immutability_guard: true,
    reviewer_binding_guard: true,
    physical_binding_guard: true,
    active_workers_drained: true,
  }, 'worker authority rollback deleted evidence or left a worker active');

  return {
    owner_decision_entrypoints: 'disabled',
    legacy_service_role_mutation: 'disabled',
    external_worker_mutation: 'disabled',
    authenticator_ingest_membership: 'revoked',
    active_workers: 'draining',
    authority_and_completion_evidence: 'preserved',
    immutable_reviewer_and_physical_bindings: 'preserved',
  };
}

async function terminalOutcomeSmoke(db) {
  const secret = 'private-provider-payload-must-not-surface';
  const durableFailure = JSON.stringify({
    schemaVersion: '1.0.0',
    terminalClassification: 'reconciliation_required',
    providerOutcome: 'succeeded',
    mutationState: 'PROVIDER_SUCCEEDED_LOCAL_FINALIZATION_FAILED',
    downstreamProcessingOutcome: 'local_processing_failed',
    safeErrorCode: 'provider_result_contract_error',
    retryable: false,
    automaticRetryAllowed: false,
    retryContract: 'do_not_repeat_provider_mutation',
    reconciliationRequired: true,
    providerIdempotencySupported: false,
    payloadHash: 'c'.repeat(64),
    evidencePolicy: 'privacy_safe_summary_only_v1',
    rawProviderPayload: secret,
  });
  const reconciliation = (await db.query(`
    select private.execution_terminal_outcome('failed', $1::text, null) as outcome
  `, [durableFailure])).rows[0].outcome;
  assert.equal(reconciliation.terminalClassification, 'reconciliation_required');
  assert.equal(reconciliation.providerOutcome, 'succeeded');
  assert.equal(reconciliation.retryable, false);
  assert.equal(reconciliation.automaticRetryAllowed, false);
  assert.equal(reconciliation.retryContract, 'do_not_repeat_provider_mutation');
  assert.equal(reconciliation.reconciliationRequired, true);
  assert.equal(reconciliation.payloadHash, 'c'.repeat(64));
  assert.equal(Object.hasOwn(reconciliation, 'rawProviderPayload'), false);
  assert.doesNotMatch(JSON.stringify(reconciliation), new RegExp(secret));

  const unknown = (await db.query(`
    select private.execution_terminal_outcome(
      'failed',
      'unstructured private provider failure',
      null
    ) as outcome
  `)).rows[0].outcome;
  assert.deepEqual({
    terminalClassification: unknown.terminalClassification,
    providerOutcome: unknown.providerOutcome,
    retryable: unknown.retryable,
    automaticRetryAllowed: unknown.automaticRetryAllowed,
    retryContract: unknown.retryContract,
    reconciliationRequired: unknown.reconciliationRequired,
  }, {
    terminalClassification: 'failed_unknown',
    providerOutcome: 'ambiguous',
    retryable: false,
    automaticRetryAllowed: false,
    retryContract: 'reconcile_before_retry',
    reconciliationRequired: true,
  });

  return {
    reconciliation_terminal_status: 'failed',
    classification: reconciliation.terminalClassification,
    automatic_retry_allowed: reconciliation.automaticRetryAllowed,
    raw_provider_payload_exposed: false,
    unknown_failure_requires_reconciliation: unknown.reconciliationRequired,
  };
}

async function catalogAssertions(db, migrationFiles) {
  const server = await db.query('show server_version_num');
  const count = async (sql, params = []) => Number((await db.query(sql, params)).rows[0].count);
  const columns = {};
  for (const table of ['webhook_events', 'meta_drafts', 'meta_webhook_health']) {
    columns[table] = await count(
      `select count(*) from information_schema.columns where table_schema = 'public' and table_name = $1`,
      [table],
    );
  }
  assert.deepEqual(
    columns,
    { webhook_events: 14, meta_drafts: 11, meta_webhook_health: 9 },
    'Meta table column counts drifted',
  );

  const rls = await db.query(`
    select relname, relrowsecurity
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and relname in ('meta_drafts', 'meta_webhook_health')
    order by relname
  `);
  assert.equal(rls.rows.length, 2, 'Meta RLS table set drifted');
  assert.ok(rls.rows.every((row) => row.relrowsecurity === true), 'Meta RLS is not enabled');
  assert.equal(
    await count(`select count(*) from pg_policies where schemaname = 'public' and tablename = 'meta_drafts'`),
    2,
    'Meta draft policy count drifted',
  );

  const approval = await db.query(`
    select pg_get_functiondef(p.oid) as definition,
           p.prosecdef as security_definer,
           p.proconfig as configuration,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
           has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'decide_approval'
      and pg_get_function_identity_arguments(p.oid) = 'approval_id uuid, requested_decision approval_decision, reason text'
  `);
  assert.equal(approval.rows.length, 1, 'decide_approval signature was not found');
  const [row] = approval.rows;
  assert.equal(row.security_definer, true, 'decide_approval is not security-definer');
  assert.equal(row.authenticated_execute, true, 'authenticated cannot execute decide_approval');
  assert.equal(row.service_execute, true, 'service_role cannot execute decide_approval');
  assert.equal(row.anon_execute, false, 'anon can execute decide_approval');
  assert.ok(
    row.configuration?.some((entry) => /^search_path=(?:""|)$/i.test(entry)),
    'decide_approval search path is not pinned empty',
  );
  assert.doesNotMatch(
    row.definition,
    /auth\.sessions|auth\.aal_level|current_session_id/i,
    'decide_approval still depends on an AAL2 session',
  );
  assert.match(row.definition, /'owner'/i, 'decide_approval owner role is missing');
  assert.match(row.definition, /'admin'/i, 'decide_approval admin role is missing');
  assert.doesNotMatch(
    row.definition,
    /ARRAY\[[^\]]*'operator'/i,
    'decide_approval still admits operator',
  );

  const sourcePolicy = await db.query(`
    select source_type, source_value, wildcard, operational_status
    from private.repository_source_policies
    where source_type = 'github_owner'
      and source_value = 'mbanatao'
  `);
  assert.deepEqual(sourcePolicy.rows, [{
    source_type: 'github_owner',
    source_value: 'mbanatao',
    wildcard: 'mbanatao/*',
    operational_status: 'historical_only',
  }], 'owner-wide repository source policy drifted');

  const historicalBindings = await db.query(`
    select repo_full_name, github_access, source_status
    from private.project_resource_bindings
    where lower(split_part(repo_full_name, '/', 1)) = 'mbanatao'
    order by lower(repo_full_name)
  `);
  assert.ok(historicalBindings.rows.length > 0, 'historical repository bindings are missing');
  assert.ok(
    historicalBindings.rows.every((binding) =>
      binding.github_access === 'read_only' && binding.source_status === 'historical_only'),
    'an mbanatao repository binding remains operational',
  );

  const canonicalBinding = await db.query(`
    select github_access, supabase_project_ref, vercel_project_id, source_status
    from private.project_resource_bindings
    where repo_full_name = 'banataosystems/fxpass'
  `);
  assert.deepEqual(canonicalBinding.rows, [{
    github_access: 'read_write',
    supabase_project_ref: 'jhygppdcfrmejbzyozud',
    vercel_project_id: 'prj_t9cl0GiY9APSTw2NUNJLtRg6auwZ',
    source_status: 'active',
  }], 'canonical FXPass binding drifted');

  const sourceTrigger = await db.query(`
    select procedure.prosecdef as security_definer,
           procedure.proconfig as configuration,
           has_function_privilege('anon', procedure.oid, 'EXECUTE') as anon_execute,
           has_function_privilege('authenticated', procedure.oid, 'EXECUTE') as authenticated_execute,
           has_function_privilege('service_role', procedure.oid, 'EXECUTE') as service_execute
    from pg_trigger trigger
    join pg_proc procedure on procedure.oid = trigger.tgfoid
    join pg_class relation on relation.oid = trigger.tgrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'projectos_projects'
      and trigger.tgname = 'enforce_repository_source_authority'
      and not trigger.tgisinternal
  `);
  assert.equal(sourceTrigger.rows.length, 1, 'repository source trigger is missing');
  assert.equal(sourceTrigger.rows[0].security_definer, true, 'repository source trigger is not security-definer');
  assert.equal(sourceTrigger.rows[0].anon_execute, false, 'anon can execute the repository source trigger');
  assert.equal(sourceTrigger.rows[0].authenticated_execute, false, 'authenticated can execute the repository source trigger');
  assert.equal(sourceTrigger.rows[0].service_execute, true, 'service_role cannot execute the repository source trigger');
  assert.ok(
    sourceTrigger.rows[0].configuration?.some((entry) => /^search_path=(?:""|)$/i.test(entry)),
    'repository source trigger search path is not pinned empty',
  );

  const fxpassIntake = await db.query(`
    select pg_get_functiondef(
      'public.projectos_accept_fxpass_product_intake(uuid,jsonb)'::regprocedure
    ) as definition
  `);
  assert.match(fxpassIntake.rows[0].definition, /banataosystems\/fxpass/i, 'FXPass intake lacks canonical repository');
  assert.doesNotMatch(fxpassIntake.rows[0].definition, /mbanatao\/fong/i, 'FXPass intake retains historical repository');

  let mixedCaseSourceDenied = false;
  try {
    await db.exec(`
      insert into public.projectos_projects (
        organization_id, project_key, name, repository, workspace_path
      ) values (
        '2270b266-59da-4c39-bfd9-9f8d08352af0',
        'blocked-source-replay',
        'Blocked source replay',
        'MBANATAO/blocked-source-replay',
        'projectos/projects/blocked-source-replay'
      )
    `);
  } catch (error) {
    mixedCaseSourceDenied = error?.code === '42501';
  }
  assert.equal(mixedCaseSourceDenied, true, 'mixed-case mbanatao repository was not rejected');

  const secrets = await db.query(`
    select secret_name, length(secret_value) as value_length
    from private.integration_secrets
    order by secret_name
  `);
  assert.deepEqual(
    secrets.rows,
    [
      { secret_name: 'projectos_fxpass_intake_hmac', value_length: 64 },
      { secret_name: 'projectos_memory_learning_hmac', value_length: 64 },
    ],
    'database-generated integration secrets are missing',
  );
  const config = await db.query(`
    select length(admin_token_hash) as admin_length,
           length(approval_token_hash) as approval_length
    from private.runtime_security_configs
  `);
  assert.deepEqual(
    config.rows,
    [{ admin_length: 64, approval_length: 64 }],
    'database-generated runtime verifiers are missing',
  );

  const authorization = await authorizationSmoke(db);
  const governedWorker = await governedWorkerSmoke(db);
  const canonicalReleaseAttestation = await canonicalReleaseAttestationSmoke(db);
  // Exercise fail-closed capability rollbacks after the evidence-producing
  // paths have proven their exact bindings. Every rollback must retain the
  // immutable receipts and guards it is shutting down.
  const workerAuthorityRollback = await workerAuthorityRollbackSmoke(db);
  const physicalAndroidRollback = await physicalAndroidRollbackSmoke(db);
  const canonicalReleaseRollback = await canonicalReleaseRollbackSmoke(db);
  const terminalOutcome = await terminalOutcomeSmoke(db);
  const rollback = await rollbackSmoke(db);
  return {
    schema_version: '1.0.0',
    engine: { name: 'pglite', package_version: '0.5.4', postgres_server_version_num: server.rows[0].server_version_num },
    provider_equivalence: false,
    migration_count: migrationFiles.length,
    chain_sha256: sha256(
      migrationFiles.map(({ filename, source }) => `${filename}:${sha256(source)}`).join('\n') + '\n',
    ),
    provider_extension_substitutions: [...expectedExtensionStatements.entries()].flatMap(([filename, statements]) =>
      statements.map((statement) => ({ filename, statement }))),
    fixtures: ['after-foundations.sql', 'after-20260731122011.sql'],
    assertions: {
      meta_table_column_counts: columns,
      meta_rls_enabled: true,
      meta_drafts_policy_count: 2,
      final_decide_approval: 'AAL1 permanent owner/admin; anon/operator/session dependency denied',
      replay_credentials: 'four database-generated 256-bit values; no source literals',
      source_authority: {
        owner_wildcard: 'mbanatao/*',
        historical_binding_count: historicalBindings.rows.length,
        canonical_fxpass_binding: 'active',
        mixed_case_repository_insert: 'denied',
      },
      authorization_smoke: authorization,
      governed_worker_smoke: governedWorker,
      canonical_release_attestation_smoke: canonicalReleaseAttestation,
      physical_android_rollback_smoke: physicalAndroidRollback,
      canonical_release_rollback_smoke: canonicalReleaseRollback,
      terminal_outcome_smoke: terminalOutcome,
      database_rollback_smoke: rollback,
      worker_authority_rollback_smoke: workerAuthorityRollback,
    },
  };
}

async function main() {
  const filenames = (await readdir(migrationRoot))
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
  const minimumHistoricalMigrationCount = 52;
  assert.ok(
    filenames.length >= minimumHistoricalMigrationCount,
    `historical migration chain unexpectedly shrank below ${minimumHistoricalMigrationCount}`,
  );
  assert.equal(
    new Set(filenames.map((filename) => filename.slice(0, 14))).size,
    filenames.length,
    'migration timestamps must remain unique',
  );
  const migrationFiles = await Promise.all(filenames.map(async (filename) => ({
    filename,
    source: await readFile(join(migrationRoot, filename), 'utf8'),
  })));
  const fixtures = new Map([
    ['20260724030000_meta_remote_mcp_persistence.sql', await readFile(join(fixtureRoot, 'after-foundations.sql'), 'utf8')],
    ['20260731122011_projectos_product_intelligence_schema.sql', await readFile(join(fixtureRoot, 'after-20260731122011.sql'), 'utf8')],
  ]);

  const db = new PGlite({ extensions: { pgcrypto } });
  let currentMigration = 'bootstrap';
  let succeeded = false;
  try {
    await bootstrap(db);
    for (const migration of migrationFiles) {
      currentMigration = migration.filename;
      await db.exec(portableSql(migration.filename, migration.source));
      if (fixtures.has(migration.filename)) await db.exec(fixtures.get(migration.filename));
    }
    currentMigration = 'post-migration catalog assertions';
    const result = await catalogAssertions(db, migrationFiles);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    succeeded = true;
  } catch (error) {
    const assertion = error?.name === 'AssertionError' ? ` (${error.message.split('\n')[0]})` : '';
    const detail = error?.name === 'AssertionError'
      ? ''
      : ` (${String(error?.message || 'unknown replay error').split('\n')[0]})`;
    process.stderr.write(
      `Supabase replay failed at ${currentMigration}: ${error?.code || error?.name || 'error'}${assertion}${detail}\n`,
    );
  } finally {
    await db.close();
  }
  return succeeded;
}

if (!await main()) process.exit(1);
