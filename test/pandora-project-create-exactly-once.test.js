const test = require('node:test');
const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const { join } = require('node:path');

const migrationPath = join(
  process.cwd(),
  'supabase',
  'migrations',
  '20260906073500_pandora_exactly_once_project_creation_v1.sql',
);
const runtimePath = join(
  process.cwd(),
  'supabase',
  'functions',
  'pandora-project-runtime',
  'index.ts',
);
const createPath = join(
  process.cwd(),
  'supabase',
  'functions',
  'pandora-project-runtime',
  'project-create.ts',
);

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
    create table auth.users (id uuid primary key);

    create type public.member_role as enum ('owner','admin','operator','member','viewer');
    create type public.membership_status as enum ('invited','active','suspended','removed');

    create table public.organizations (
      id uuid primary key,
      name text not null
    );
    create table public.memberships (
      organization_id uuid not null references public.organizations(id),
      user_id uuid not null references auth.users(id),
      role public.member_role not null,
      status public.membership_status not null,
      primary key (organization_id,user_id)
    );
    create table public.projectos_projects (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null references public.organizations(id),
      project_key text not null,
      name text not null,
      repository text,
      workspace_path text not null,
      status text not null default 'active',
      objective text not null default '',
      roadmap_version text not null default '1.0.0',
      current_phase_key text,
      current_task_key text,
      progress_percent numeric(5,2) not null default 0,
      config jsonb not null default '{}'::jsonb,
      created_by uuid references auth.users(id),
      last_reconciled_at timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique (organization_id, project_key)
    );
  `);

  await db.exec(await readFile(migrationPath, 'utf8'));
  return db;
}

test('same create idempotency key replays exactly one project', async () => {
  const db = await makeDb();
  const org = '10000000-0000-4000-8000-000000000101';
  const user = '20000000-0000-4000-8000-000000000101';
  const hash = 'a'.repeat(64);

  await db.exec(`
    insert into auth.users(id) values ('${user}');
    insert into public.organizations(id,name) values ('${org}','Create Org');
    insert into public.memberships(organization_id,user_id,role,status)
      values ('${org}','${user}','owner','active');
  `);

  const first = await db.query(
    `select public.pandora_create_customer_project_v1($1,$2,$3,$4,$5,$6,$7) as result`,
    [org,user,'create-key-0001',hash,'Realtime Status Page','Build one realtime status page','help_me_decide'],
  );
  const second = await db.query(
    `select public.pandora_create_customer_project_v1($1,$2,$3,$4,$5,$6,$7) as result`,
    [org,user,'create-key-0001',hash,'Realtime Status Page','Build one realtime status page','help_me_decide'],
  );

  assert.equal(first.rows[0].result.project.id, second.rows[0].result.project.id);
  assert.equal(first.rows[0].result.replayed, false);
  assert.equal(second.rows[0].result.replayed, true);

  const count = await db.query(
    'select count(*)::integer as count from public.projectos_projects where organization_id=$1',
    [org],
  );
  assert.equal(count.rows[0].count, 1);

  const requestCount = await db.query(
    'select count(*)::integer as count from public.pandora_project_creation_requests where organization_id=$1',
    [org],
  );
  assert.equal(requestCount.rows[0].count, 1);
  await db.close();
});

test('same create key with different request hash fails closed', async () => {
  const db = await makeDb();
  const org = '10000000-0000-4000-8000-000000000102';
  const user = '20000000-0000-4000-8000-000000000102';

  await db.exec(`
    insert into auth.users(id) values ('${user}');
    insert into public.organizations(id,name) values ('${org}','Collision Org');
    insert into public.memberships(organization_id,user_id,role,status)
      values ('${org}','${user}','admin','active');
  `);

  await db.query(
    `select public.pandora_create_customer_project_v1($1,$2,$3,$4,$5,$6,$7)`,
    [org,user,'create-key-0002','b'.repeat(64),'One Project','Build the first project','web_app'],
  );

  await assert.rejects(
    db.query(
      `select public.pandora_create_customer_project_v1($1,$2,$3,$4,$5,$6,$7)`,
      [org,user,'create-key-0002','c'.repeat(64),'Different Project','Build a different project','web_app'],
    ),
    /PROJECT_CREATE_IDEMPOTENCY_COLLISION/,
  );

  const count = await db.query(
    'select count(*)::integer as count from public.projectos_projects where organization_id=$1',
    [org],
  );
  assert.equal(count.rows[0].count, 1);
  await db.close();
});

test('project runtime consumes the idempotency header and does not provision Vercel during create', async () => {
  const [runtime, createSource] = await Promise.all([
    readFile(runtimePath, 'utf8'),
    readFile(createPath, 'utf8'),
  ]);

  assert.match(createSource, /pandora_create_customer_project_v1/);
  assert.match(createSource, /p_idempotency_key: idempotencyKey/);
  assert.doesNotMatch(createSource, /ensureVercelProject/);
  assert.match(runtime, /req\.headers\.get\("idempotency-key"\)/);
  assert.match(runtime, /createCustomerProject/);
});
