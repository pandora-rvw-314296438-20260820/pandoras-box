const test = require('node:test');
const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const { join } = require('node:path');

const migrationPath = join(
  process.cwd(),
  'supabase',
  'migrations',
  '20260828153500_pandora_project_spec_control_plane_v1.sql',
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

    create schema if not exists private;
    create type public.member_role as enum ('owner', 'admin', 'operator', 'member', 'viewer');
    create type public.membership_status as enum ('invited', 'active', 'suspended', 'removed');

    create table public.organizations (
      id uuid primary key,
      name text not null
    );
    create table public.memberships (
      organization_id uuid not null references public.organizations(id),
      user_id uuid not null references auth.users(id),
      role public.member_role not null,
      status public.membership_status not null default 'invited',
      primary key (organization_id, user_id)
    );
    create table public.projectos_projects (
      id uuid primary key,
      org_id uuid not null references public.organizations(id),
      created_by uuid not null references auth.users(id),
      name text not null
    );
    create table public.projectos_decisions (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null references public.organizations(id),
      project_id uuid not null references public.projectos_projects(id),
      decision_type text not null,
      statement text not null,
      rationale text not null default '',
      confidence numeric not null default 1,
      source text not null default 'operator',
      supersedes_id uuid null,
      created_by uuid null references auth.users(id),
      created_at timestamptz not null default now()
    );

    create or replace function private.is_org_member(target_organization_id uuid)
    returns boolean
    language sql stable security definer
    set search_path = ''
    as $$
      select (select auth.uid()) is not null
        and exists (
          select 1
          from public.memberships m
          where m.organization_id = target_organization_id
            and m.user_id = (select auth.uid())
            and m.status = 'active'::public.membership_status
        )
    $$;
  `);

  await db.exec(await readFile(migrationPath, 'utf8'));
  return db;
}

test('ProjectSpec migration is replayable and enforces immutable version lineage', async () => {
  const db = await makeDb();
  const org = '10000000-0000-4000-8000-000000000001';
  const user = '20000000-0000-4000-8000-000000000001';
  const project = '30000000-0000-4000-8000-000000000001';

  await db.exec(`
    insert into auth.users(id) values ('${user}');
    insert into public.organizations(id, name) values ('${org}', 'Replay Org');
    insert into public.memberships(organization_id, user_id, role, status)
      values ('${org}', '${user}', 'owner', 'active');
    insert into public.projectos_projects(id, org_id, created_by, name)
      values ('${project}', '${org}', '${user}', 'Replay Project');
  `);

  const intent = await db.query(`
    insert into public.pandora_project_intents(
      organization_id, project_id, requester_id, intent_kind, intent_text,
      source, idempotency_key, provenance
    ) values (
      $1, $2, $3, 'build', 'Build a booking system', 'customer',
      'replay-intent-0001', '{"source":"test"}'::jsonb
    )
    returning id
  `, [org, project, user]);

  const intentId = intent.rows[0].id;
  const spec1 = await db.query(`
    insert into public.pandora_project_specs(
      organization_id, project_id, version, status, source_intent_id,
      project_type, product_scope, content_sha256, created_by
    ) values (
      $1, $2, 1, 'active', $3, 'web_app',
      '{"capabilities":["booking"]}'::jsonb, $4, $5
    )
    returning id
  `, [org, project, intentId, 'a'.repeat(64), user]);
  const spec1Id = spec1.rows[0].id;

  await assert.rejects(
    db.query(
      `update public.pandora_project_specs set project_type = 'mobile_app' where id = $1`,
      [spec1Id],
    ),
    /immutable/i,
  );

  await assert.rejects(
    db.query(`
      insert into public.pandora_project_specs(
        organization_id, project_id, version, status, source_intent_id,
        project_type, content_sha256, created_by
      ) values ($1, $2, 2, 'draft', $3, 'web_app', $4, $5)
    `, [org, project, intentId, 'b'.repeat(64), user]),
    /previous_spec_id/i,
  );

  await db.query(
    `update public.pandora_project_specs
       set status = 'superseded', superseded_at = now()
     where id = $1`,
    [spec1Id],
  );

  const spec2 = await db.query(`
    insert into public.pandora_project_specs(
      organization_id, project_id, version, status, source_intent_id, previous_spec_id,
      project_type, data_scope, content_sha256, created_by
    ) values (
      $1, $2, 2, 'active', $3, $4, 'web_app',
      '{"entities":["booking"]}'::jsonb, $5, $6
    )
    returning id
  `, [org, project, intentId, spec1Id, 'b'.repeat(64), user]);

  assert.ok(spec2.rows[0].id);

  await db.query(`
    insert into public.pandora_project_requirements(
      organization_id, project_id, project_spec_id, source_intent_id,
      requirement_key, category, priority, statement, provenance
    ) values (
      $1, $2, $3, $4, 'REQ-BOOK-001', 'product', 'must',
      'Customers can create a booking', '{"source":"compiler"}'::jsonb
    )
  `, [org, project, spec2.rows[0].id, intentId]);

  const requirementCount = await db.query(
    `select count(*)::integer as count
       from public.pandora_project_requirements
      where project_spec_id = $1`,
    [spec2.rows[0].id],
  );
  assert.equal(requirementCount.rows[0].count, 1);

  await db.close();
});

test('ProjectSpec RLS allows member intent intake but blocks identity spoofing and spec writes', async () => {
  const db = await makeDb();
  const org = '10000000-0000-4000-8000-000000000002';
  const user = '20000000-0000-4000-8000-000000000002';
  const other = '20000000-0000-4000-8000-000000000003';
  const project = '30000000-0000-4000-8000-000000000002';

  await db.exec(`
    insert into auth.users(id) values ('${user}'), ('${other}');
    insert into public.organizations(id, name) values ('${org}', 'RLS Org');
    insert into public.memberships(organization_id, user_id, role, status)
      values ('${org}', '${user}', 'member', 'active');
    insert into public.projectos_projects(id, org_id, created_by, name)
      values ('${project}', '${org}', '${user}', 'RLS Project');
    select set_config(
      'request.jwt.claims',
      '{"sub":"${user}","role":"authenticated"}',
      false
    );
    set role authenticated;
  `);

  const accepted = await db.query(`
    insert into public.pandora_project_intents(
      organization_id, project_id, requester_id, intent_text, idempotency_key
    ) values ($1, $2, $3, 'Make checkout simpler', 'rls-intent-0001')
    returning id
  `, [org, project, user]);
  assert.ok(accepted.rows[0].id);

  await assert.rejects(
    db.query(`
      insert into public.pandora_project_intents(
        organization_id, project_id, requester_id, intent_text, idempotency_key
      ) values ($1, $2, $3, 'Spoofed', 'rls-intent-0002')
    `, [org, project, other]),
    /row-level security|policy/i,
  );

  await assert.rejects(
    db.query(`
      insert into public.pandora_project_specs(
        organization_id, project_id, version, source_intent_id,
        project_type, content_sha256
      ) values ($1, $2, 1, $3, 'web_app', $4)
    `, [org, project, accepted.rows[0].id, 'c'.repeat(64)]),
    /permission denied|row-level security/i,
  );

  await db.exec('reset role;');
  await db.close();
});
