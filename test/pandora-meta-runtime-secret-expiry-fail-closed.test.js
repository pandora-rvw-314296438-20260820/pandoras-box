"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const root = join(__dirname, "..");
const baseMigration = readFileSync(
  join(root, "supabase/migrations/20260925061000_pandora_meta_oauth_marketing_read_v1.sql"),
  "utf8",
);
const repairMigration = readFileSync(
  join(root, "supabase/migrations/20260929023000_pandora_meta_runtime_secret_expiry_fail_closed_v1.sql"),
  "utf8",
);
const ORG_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ORG_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const OWNER = "11111111-1111-4111-8111-111111111111";
const INSTALLATION = "22222222-2222-4222-8222-222222222222";
const PAGE_SECRET = "33333333-3333-4333-8333-333333333333";
const USER_SECRET = "44444444-4444-4444-8444-444444444444";
const PAGE_TOKEN = "synthetic-page-token-never-live";
const USER_TOKEN = "synthetic-user-token-never-live";
function runtimeFunction(sql) {
  const marker =
    "create or replace function public.pandora_meta_runtime_secret_v1";
  const start = sql.indexOf(marker);
  const end = sql.indexOf(
    "revoke all on function public.pandora_meta_runtime_secret_v1",
    start,
  );
  assert.ok(start >= 0 && end > start);
  return sql.slice(start, end).replace(/\s+/g, " ").trim();
}

async function asRole(db, role, operation) {
  await db.exec("set role " + role);
  try {
    return await operation();
  } finally {
    await db.exec("reset role");
  }
}

async function resolveSecret(
  db,
  purpose,
  organizationId = ORG_A,
  installationId = INSTALLATION,
) {
  const result = await db.query(
    "select public.pandora_meta_runtime_secret_v1($1::uuid,$2::uuid,$3) as value",
    [organizationId, installationId, purpose],
  );
  return result.rows[0].value;
}
async function expectDenied(
  db,
  purpose,
  expectedMessage,
  expectedCode,
  organizationId = ORG_A,
  installationId = INSTALLATION,
) {
  await assert.rejects(
    asRole(
      db,
      "service_role",
      () => resolveSecret(db, purpose, organizationId, installationId),
    ),
    (error) => {
      assert.match(error.message, new RegExp(expectedMessage));
      assert.equal(error.code, expectedCode);
      assert.doesNotMatch(error.message, /synthetic-(?:page|user)-token/i);
      return true;
    },
  );
}

async function fixture() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema auth;
    create schema private;
    create schema vault;
    create schema extensions;
    create extension pgcrypto with schema extensions;
    create type public.connector_status
      as enum ('pending','active','degraded','revoked');
    create type public.rotation_status
      as enum ('current','rotating','expired','revoked');
    create table auth.users(id uuid primary key);
    create table public.organizations(
      id uuid primary key,
      status text not null default 'active'
    );
    create table public.memberships(
      organization_id uuid not null references public.organizations(id),
      user_id uuid not null references auth.users(id),
      status text not null,
      role text not null,
      primary key(organization_id,user_id)
    );
    create table public.connector_installations(
      id uuid primary key,
      organization_id uuid not null references public.organizations(id),
      provider text not null,
      external_account_id text not null,
      display_name text,
      status public.connector_status not null,
      scopes text[] not null default '{}',
      configuration jsonb not null default '{}',
      installed_by uuid not null references auth.users(id),
      last_health_check_at timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique(organization_id,provider,external_account_id)
    );
    create table public.credential_refs(
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null references public.organizations(id),
      installation_id uuid not null references public.connector_installations(id),
      secret_ref text not null,
      key_version integer not null,
      expires_at timestamptz,
      rotation_state public.rotation_status not null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique(installation_id)
    );
    create table vault.decrypted_secrets(
      id uuid primary key default gen_random_uuid(),
      name text unique,
      decrypted_secret text not null
    );
    create function auth.uid()
    returns uuid language sql stable set search_path=pg_catalog
    as $$ select nullif(
      current_setting('request.jwt.claim.sub',true),''
    )::uuid $$;
    create function extensions.urlencode(p_value text)
    returns text language sql immutable strict set search_path=pg_catalog
    as $$ select p_value $$;
    create function vault.create_secret(
      p_secret text,
      p_name text,
      p_description text
    ) returns uuid language plpgsql security definer
    set search_path=pg_catalog,vault
    as $$
    declare v_id uuid:=gen_random_uuid();
    begin
      insert into vault.decrypted_secrets(id,name,decrypted_secret)
      values(v_id,p_name,p_secret);
      return v_id;
    end $$;
    create function vault.update_secret(
      p_id uuid,
      p_secret text,
      p_name text,
      p_description text
    ) returns void language plpgsql security definer
    set search_path=pg_catalog,vault
    as $$
    begin
      update vault.decrypted_secrets
      set name=p_name,decrypted_secret=p_secret
      where id=p_id;
    end $$;
  `);
  await db.exec(baseMigration);
  await db.exec(repairMigration);
  await db.query(
    "insert into auth.users(id) values($1)",
    [OWNER],
  );
  await db.query(
    "insert into public.organizations(id) values($1),($2)",
    [ORG_A, ORG_B],
  );
  await db.query(
    `insert into public.connector_installations(
       id,organization_id,provider,external_account_id,display_name,status,
       scopes,installed_by,last_health_check_at
     ) values (
       $1,$2,'meta','123456789','Fixture Meta Page','active',
       array['ads_read'],$3,clock_timestamp()
     )`,
    [INSTALLATION, ORG_A, OWNER],
  );
  await db.query(
    `insert into vault.decrypted_secrets(id,name,decrypted_secret)
     values ($1,'fixture-page',$2),($3,'fixture-user',$4)`,
    [PAGE_SECRET, PAGE_TOKEN, USER_SECRET, USER_TOKEN],
  );
  await db.query(
    `insert into public.credential_refs(
       organization_id,installation_id,secret_ref,key_version,
       expires_at,rotation_state
     ) values ($1,$2,$3,1,null,'current')`,
    [ORG_A, INSTALLATION, `vault://${PAGE_SECRET}`],
  );
  await db.query(
    `insert into private.pandora_meta_connections(
       organization_id,connected_by,provider_user_id,display_name,
       user_token_secret_id,scopes,pages,ad_accounts,status,
       token_expires_at,last_verified_at,last_http_status
     ) values (
       $1,$2,'987654321','Fixture Meta',$3,array['ads_read'],
       '[]'::jsonb,'[]'::jsonb,'connected',null,clock_timestamp(),200
     )`,
    [ORG_A, OWNER, USER_SECRET],
  );
  await db.query(
    `insert into private.pandora_meta_page_tokens(
       organization_id,page_id,page_name,token_secret_id,tasks
     ) values ($1,'123456789','Fixture Meta Page',$2,array['ANALYZE'])`,
    [ORG_A, PAGE_SECRET],
  );
  return db;
}
test("repair changes only the marketing NULL-expiry predicate and preserves ACLs", async () => {
  const before = runtimeFunction(baseMigration);
  const after = runtimeFunction(repairMigration);
  const expected = before
    .replace(
      "if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_meta_runtime_service_role_required' using errcode='42501'; end if;",
      "if session_user not in ('postgres','service_role','supabase_admin') and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role' then raise exception 'pandora_meta_runtime_service_role_required' using errcode='42501'; end if;",
    )
    .replace(
      "and (c.token_expires_at is null or c.token_expires_at>now())",
      "and c.token_expires_at is not null and c.token_expires_at>now()",
    );
  assert.notEqual(expected, before);
  assert.equal(after, expected);
  assert.match(after, /session_user not in/);
  assert.match(after, /request\.jwt\.claims/);
  assert.match(
    after,
    /cr\.expires_at is null or cr\.expires_at>now\(\)/,
  );

  const db = await fixture();
  try {
    const acl = (await db.query(`
      select
        has_function_privilege(
          'anon',
          'public.pandora_meta_runtime_secret_v1(uuid,uuid,text)',
          'EXECUTE'
        ) as anon_execute,
        has_function_privilege(
          'authenticated',
          'public.pandora_meta_runtime_secret_v1(uuid,uuid,text)',
          'EXECUTE'
        ) as authenticated_execute,
        has_function_privilege(
          'service_role',
          'public.pandora_meta_runtime_secret_v1(uuid,uuid,text)',
          'EXECUTE'
        ) as service_execute
    `)).rows[0];
    assert.deepEqual(acl, {
      anon_execute: false,
      authenticated_execute: false,
      service_execute: true,
    });
  } finally {
    await db.close();
  }
});

test("marketing requires a known future expiry while Page NULL expiry remains usable", async () => {
  const db = await fixture();
  try {
    await expectDenied(
      db,
      "marketing",
      "pandora_meta_runtime_credential_unavailable",
      "55000",
    );
    const page = await asRole(
      db,
      "service_role",
      () => resolveSecret(db, "page"),
    );
    assert.deepEqual(page, { token: PAGE_TOKEN, purpose: "page" });

    await db.query(
      `update private.pandora_meta_connections
       set token_expires_at=clock_timestamp()+interval '1 hour'
       where organization_id=$1`,
      [ORG_A],
    );
    const marketing = await asRole(
      db,
      "service_role",
      () => resolveSecret(db, "marketing"),
    );
    assert.deepEqual(
      marketing,
      { token: USER_TOKEN, purpose: "marketing" },
    );

    await db.query(
      `update private.pandora_meta_connections
       set token_expires_at=clock_timestamp()-interval '1 second'
       where organization_id=$1`,
      [ORG_A],
    );
    await expectDenied(
      db,
      "marketing",
      "pandora_meta_runtime_credential_unavailable",
      "55000",
    );
  } finally {
    await db.close();
  }
});

test("revoked, inactive and cross-tenant states cannot resolve either credential", async () => {
  const db = await fixture();
  try {
    await db.query(
      `update private.pandora_meta_connections
       set token_expires_at=clock_timestamp()+interval '1 hour',
           status='revoked'
       where organization_id=$1`,
      [ORG_A],
    );
    await expectDenied(
      db,
      "marketing",
      "pandora_meta_runtime_credential_unavailable",
      "55000",
    );

    await db.query(
      "update private.pandora_meta_connections set status='connected' where organization_id=$1",
      [ORG_A],
    );
    await db.query(
      "update public.connector_installations set status='revoked' where id=$1",
      [INSTALLATION],
    );
    await expectDenied(
      db,
      "marketing",
      "pandora_meta_runtime_installation_unavailable",
      "42501",
    );
    await expectDenied(
      db,
      "page",
      "pandora_meta_runtime_installation_unavailable",
      "42501",
    );

    await db.query(
      "update public.connector_installations set status='active' where id=$1",
      [INSTALLATION],
    );
    await expectDenied(
      db,
      "marketing",
      "pandora_meta_runtime_installation_unavailable",
      "42501",
      ORG_B,
      INSTALLATION,
    );

    await db.query(
      `update public.credential_refs
       set rotation_state='revoked'
       where installation_id=$1`,
      [INSTALLATION],
    );
    await expectDenied(
      db,
      "page",
      "pandora_meta_runtime_credential_unavailable",
      "55000",
    );
  } finally {
    await db.close();
  }
});
