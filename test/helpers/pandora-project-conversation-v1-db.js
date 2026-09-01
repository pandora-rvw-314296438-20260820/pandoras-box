const { readFile } = require('node:fs/promises');
const { join } = require('node:path');

const migrationPaths = [
  '20260901134500_pandora_build_approval_receipts_v1.sql',
  '20260901134600_pandora_project_conversation_projection_v1.sql',
].map((name) => join(process.cwd(), 'supabase', 'migrations', name));

const UUID = {
  org: '10000000-0000-4000-8000-000000000001',
  otherOrg: '10000000-0000-4000-8000-000000000002',
  user: '20000000-0000-4000-8000-000000000001',
  otherUser: '20000000-0000-4000-8000-000000000002',
  project: '30000000-0000-4000-8000-000000000001',
  otherProject: '30000000-0000-4000-8000-000000000002',
  intent: '40000000-0000-4000-8000-000000000001',
  otherIntent: '40000000-0000-4000-8000-000000000002',
  spec: '50000000-0000-4000-8000-000000000001',
  otherSpec: '50000000-0000-4000-8000-000000000002',
  job: '60000000-0000-4000-8000-000000000001',
  version: '70000000-0000-4000-8000-000000000001',
  version2: '70000000-0000-4000-8000-000000000002',
  verification: '80000000-0000-4000-8000-000000000001',
  check: '81000000-0000-4000-8000-000000000001',
  evidence: '82000000-0000-4000-8000-000000000001',
  preview: '90000000-0000-4000-8000-000000000001',
  production: '90000000-0000-4000-8000-000000000002',
  publish: '91000000-0000-4000-8000-000000000001',
  rollbackDeployment: '90000000-0000-4000-8000-000000000003',
  rollbackPublish: '91000000-0000-4000-8000-000000000002',
  toolCall: 'a0000000-0000-4000-8000-000000000001',
};

const RAW_INTENT = `Build me a complete restaurant platform for Porknyeta, Cardiac Delights and 80/20 where customers can order directly, book tables, use Lalamove, see promotions, and I want to control menus, availability, branches.\nKeep this exact request as evidence.`;

async function makeDb() {
  const { PGlite } = await import('@electric-sql/pglite');
  const { pgcrypto } = await import('@electric-sql/pglite/contrib/pgcrypto');
  const db = new PGlite({ extensions: { pgcrypto } });

  await db.exec(`
    create schema if not exists extensions;
    create extension if not exists pgcrypto with schema extensions;

    do $bootstrap$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
    end
    $bootstrap$;

    create schema if not exists auth;
    create schema if not exists private;
    grant usage on schema auth, public to authenticated, service_role;

    create table auth.users (id uuid primary key);
    create or replace function auth.jwt() returns jsonb
    language sql stable
    as $$
      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
    $$;
    create or replace function auth.uid() returns uuid
    language sql stable
    as $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;

    create table public.organizations (id uuid primary key, name text not null);
    create table public.memberships (
      organization_id uuid not null,
      user_id uuid not null,
      status text not null,
      primary key (organization_id, user_id)
    );
    create table public.projectos_projects (
      id uuid primary key,
      organization_id uuid not null,
      name text not null
    );

    create or replace function private.pandora_control_plane_project_org_matches(
      p_organization_id uuid,
      p_project_id uuid
    ) returns boolean
    language sql stable
    as $$
      select exists (
        select 1 from public.projectos_projects p
        where p.id = p_project_id and p.organization_id = p_organization_id
      )
    $$;

    create table public.pandora_project_intents (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      requester_id uuid,
      intent_kind text not null default 'build',
      intent_text text not null,
      normalized_summary text,
      source text not null default 'customer',
      source_reference text,
      idempotency_key text not null,
      provenance jsonb not null default '{}'::jsonb,
      received_at timestamptz not null default now(),
      created_at timestamptz not null default now()
    );

    create table public.pandora_project_specs (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      version integer not null,
      status text not null default 'active',
      source_intent_id uuid not null,
      previous_spec_id uuid,
      schema_version text not null default '1.0.0',
      project_type text not null,
      target_user_summary text,
      business_summary text,
      product_scope jsonb not null default '{}'::jsonb,
      data_scope jsonb not null default '{}'::jsonb,
      integration_scope jsonb not null default '{}'::jsonb,
      experience_scope jsonb not null default '{}'::jsonb,
      deployment_scope jsonb not null default '{}'::jsonb,
      acceptance_scope jsonb not null default '{}'::jsonb,
      compiler_provider text,
      compiler_model text,
      compiler_version text,
      compiler_provenance jsonb not null default '{}'::jsonb,
      content_sha256 text not null,
      created_by uuid,
      created_at timestamptz not null default now(),
      superseded_at timestamptz
    );

    create table public.pandora_build_jobs (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      project_spec_id uuid not null,
      source_intent_id uuid,
      target_project_version_id uuid,
      requested_by uuid,
      job_kind text not null,
      status text not null default 'queued',
      current_stage text not null default 'received',
      idempotency_key text not null,
      public_error_summary text,
      completed_at timestamptz,
      created_at timestamptz not null default now()
    );

    create table public.pandora_project_versions (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      sequence_no bigint not null,
      project_spec_id uuid,
      build_job_id uuid,
      source_sha256 text not null,
      verification_run_id uuid,
      lifecycle_status text not null default 'draft',
      created_at timestamptz not null default now()
    );

    create table public.pandora_verification_runs (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      project_spec_id uuid not null,
      project_version_id uuid not null,
      build_job_id uuid,
      source_digest text not null,
      artifact_digest text not null,
      target_environment text not null,
      status text not null,
      created_at timestamptz not null default now()
    );

    create table public.pandora_verification_checks (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      verification_run_id uuid not null,
      check_key text not null,
      status text not null,
      created_at timestamptz not null default now()
    );

    create table public.pandora_verification_evidence (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      verification_run_id uuid not null,
      content_sha256 text not null,
      evidence_type text not null,
      media_type text not null,
      created_at timestamptz not null default now()
    );

    create table public.pandora_project_deployments (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      version_id uuid not null,
      provider text not null,
      environment text not null,
      provider_project_id text not null,
      provider_deployment_id text,
      status text not null,
      source_sha256 text not null,
      authorization_ref text,
      verification_ref text,
      verification_state text not null default 'unverified',
      ready_at timestamptz,
      created_at timestamptz not null default now()
    );

    create table public.pandora_publish_receipts (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      version_id uuid not null,
      production_deployment_id uuid not null,
      source_sha256 text,
      previous_production_version_id uuid,
      status text not null,
      published_at timestamptz,
      created_at timestamptz not null default now()
    );

    create table public.pandora_runtime_environments (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      environment text not null,
      current_version_id uuid,
      current_deployment_id uuid,
      verification_state text not null default 'unverified'
    );

    create table public.pandora_tool_calls (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid not null,
      project_spec_id uuid not null,
      build_job_id uuid,
      project_version_id uuid,
      tool_name text not null,
      tool_version text not null,
      action_hash text not null,
      decision text not null,
      environment text not null,
      status text not null,
      requested_at timestamptz not null default now()
    );

    grant select on all tables in schema public to authenticated;
  `);

  for (const migrationPath of migrationPaths) {
    await db.exec(await readFile(migrationPath, 'utf8'));
  }
  return db;
}

async function seedCore(db) {
  await db.exec(`
    insert into auth.users(id) values ('${UUID.user}'), ('${UUID.otherUser}');
    insert into public.organizations(id, name) values
      ('${UUID.org}', 'BOK Org'),
      ('${UUID.otherOrg}', 'Other Org');
    insert into public.memberships(organization_id, user_id, status) values
      ('${UUID.org}', '${UUID.user}', 'active'),
      ('${UUID.otherOrg}', '${UUID.otherUser}', 'active');
    insert into public.projectos_projects(id, organization_id, name) values
      ('${UUID.project}', '${UUID.org}', 'BOK Direct'),
      ('${UUID.otherProject}', '${UUID.otherOrg}', 'Other Project');

    insert into public.pandora_project_intents(
      id, organization_id, project_id, requester_id, intent_kind, intent_text,
      normalized_summary, source, idempotency_key, received_at, created_at
    ) values (
      '${UUID.intent}', '${UUID.org}', '${UUID.project}', '${UUID.user}', 'create',
      ${quoteLiteral(RAW_INTENT)},
      'Direct ordering, booking, delivery and restaurant controls.',
      'customer', 'intent-bok-0001', now() - interval '20 minutes', now() - interval '20 minutes'
    ), (
      '${UUID.otherIntent}', '${UUID.otherOrg}', '${UUID.otherProject}', '${UUID.otherUser}', 'create',
      'Build another organization project.', 'Other organization request.',
      'customer', 'intent-other-0001', now() - interval '20 minutes', now() - interval '20 minutes'
    );

    insert into public.pandora_project_specs(
      id, organization_id, project_id, version, status, source_intent_id,
      project_type, target_user_summary, business_summary, product_scope,
      content_sha256, created_by, created_at
    ) values (
      '${UUID.spec}', '${UUID.org}', '${UUID.project}', 1, 'active', '${UUID.intent}',
      'web_application', 'Restaurant customers and operators',
      'Own the direct customer relationship across the three restaurants.',
      '{"features":["ordering","reservations","availability"]}'::jsonb,
      '${'a'.repeat(64)}', '${UUID.user}', now() - interval '19 minutes'
    ), (
      '${UUID.otherSpec}', '${UUID.otherOrg}', '${UUID.otherProject}', 1, 'active', '${UUID.otherIntent}',
      'web_application', 'Other audience', 'Other organization proposal.', '{}',
      '${'b'.repeat(64)}', '${UUID.otherUser}', now() - interval '19 minutes'
    );
  `);
}

function quoteLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function signIn(db, userId = UUID.user) {
  await db.exec(`
    select set_config(
      'request.jwt.claims',
      '{"sub":"${userId}","role":"authenticated"}',
      false
    );
    set role authenticated;
  `);
}

async function resetRole(db) {
  await db.exec('reset role;');
}

async function seedLifecycle(db, authorizationId) {
  await db.exec(`
    insert into public.pandora_build_jobs(
      id, organization_id, project_id, project_spec_id, source_intent_id,
      requested_by, job_kind, status, current_stage, idempotency_key, completed_at, created_at
    ) values (
      '${UUID.job}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.intent}',
      '${UUID.user}', 'build', 'succeeded', 'preview_ready', 'build-job-history-0001',
      now() - interval '12 minutes', now() - interval '17 minutes'
    );

    insert into public.pandora_project_versions(
      id, organization_id, project_id, sequence_no, project_spec_id, build_job_id,
      source_sha256, lifecycle_status, created_at
    ) values (
      '${UUID.version}', '${UUID.org}', '${UUID.project}', 1, '${UUID.spec}', '${UUID.job}',
      '${'d'.repeat(64)}', 'preview_ready', now() - interval '16 minutes'
    );
    update public.pandora_build_jobs set target_project_version_id='${UUID.version}' where id='${UUID.job}';

    insert into public.pandora_verification_runs(
      id, organization_id, project_id, project_spec_id, project_version_id, build_job_id,
      source_digest, artifact_digest, target_environment, status, created_at
    ) values (
      '${UUID.verification}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.version}', '${UUID.job}',
      '${'d'.repeat(64)}', '${'e'.repeat(64)}', 'preview', 'PASS', now() - interval '14 minutes'
    );
    update public.pandora_project_versions set verification_run_id='${UUID.verification}' where id='${UUID.version}';

    insert into public.pandora_verification_checks(
      id, organization_id, project_id, verification_run_id, check_key, status, created_at
    ) values ('${UUID.check}', '${UUID.org}', '${UUID.project}', '${UUID.verification}', 'compile', 'PASS', now() - interval '14 minutes');
    insert into public.pandora_verification_evidence(
      id, organization_id, project_id, verification_run_id, content_sha256, evidence_type, media_type, created_at
    ) values ('${UUID.evidence}', '${UUID.org}', '${UUID.project}', '${UUID.verification}', '${'f'.repeat(64)}', 'log', 'text/plain', now() - interval '14 minutes');

    insert into public.pandora_project_deployments(
      id, organization_id, project_id, version_id, provider, environment, provider_project_id,
      provider_deployment_id, status, source_sha256, verification_ref, verification_state, ready_at, created_at
    ) values (
      '${UUID.preview}', '${UUID.org}', '${UUID.project}', '${UUID.version}', 'vercel', 'preview', 'provider-project',
      'preview-1', 'ready', '${'d'.repeat(64)}', '${UUID.verification}', 'live_verified', now() - interval '13 minutes', now() - interval '13 minutes'
    ), (
      '${UUID.production}', '${UUID.org}', '${UUID.project}', '${UUID.version}', 'vercel', 'production', 'provider-project',
      'prod-1', 'ready', '${'d'.repeat(64)}', '${UUID.verification}', 'live_verified', now() - interval '11 minutes', now() - interval '11 minutes'
    );

    insert into public.pandora_publish_receipts(
      id, organization_id, project_id, version_id, production_deployment_id,
      source_sha256, status, published_at, created_at
    ) values (
      '${UUID.publish}', '${UUID.org}', '${UUID.project}', '${UUID.version}', '${UUID.production}',
      '${'d'.repeat(64)}', 'live_verified', now() - interval '10 minutes', now() - interval '11 minutes'
    );

    insert into public.pandora_verification_runs(
      id, organization_id, project_id, project_spec_id, project_version_id, build_job_id,
      source_digest, artifact_digest, target_environment, status, created_at
    ) values (
      '80000000-0000-4000-8000-000000000099', '${UUID.org}', '${UUID.project}', '${UUID.otherSpec}', '${UUID.version}', '${UUID.job}',
      '${'d'.repeat(64)}', '${'e'.repeat(64)}', 'preview', 'PASS', now() - interval '9 minutes'
    );

    insert into public.pandora_project_deployments(
      id, organization_id, project_id, version_id, provider, environment, provider_project_id,
      provider_deployment_id, status, source_sha256, verification_state, created_at
    ) values (
      '90000000-0000-4000-8000-000000000099', '${UUID.org}', '${UUID.project}', '${UUID.version}', 'vercel', 'preview', 'provider-project',
      'orphan-preview', 'ready', '${'0'.repeat(64)}', 'live_verified', now() - interval '8 minutes'
    );
  `);

  await db.exec('set role service_role;');
  await db.query(
    `select public.pandora_bind_build_authorization_service_v1($1, $2)`,
    [authorizationId, UUID.job],
  );
  await db.exec('reset role;');
}

module.exports = { UUID, RAW_INTENT, migrationPaths, makeDb, seedCore, signIn, resetRole, seedLifecycle };
