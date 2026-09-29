"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migrationRoot = join(__dirname, "..", "supabase", "migrations");
const oauthMigration = readFileSync(
  join(migrationRoot, "20260925061000_pandora_meta_oauth_marketing_read_v1.sql"),
  "utf8",
);
const prepareCorrection = readFileSync(
  join(migrationRoot, "20260926121500_pandora_meta_business_login_config_id_v1.sql"),
  "utf8",
);

const ORG_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ORG_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const OWNER_A = "11111111-1111-4111-8111-111111111111";
const OWNER_B = "22222222-2222-4222-8222-222222222222";
const PAGE_ID = "123450000000001";
const REQUIRED_SCOPES = [
  "public_profile",
  "pages_show_list",
  "pages_read_engagement",
  "ads_read",
  "ads_management",
  "business_management",
];

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

async function expectDatabaseError(promise, message, code) {
  await assert.rejects(promise, (error) => {
    assert.match(error.message, new RegExp(message));
    if (code) assert.equal(error.code, code);
    return true;
  });
}

async function setUser(db, userId) {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [userId]);
}

async function asRole(db, role, operation) {
  await db.exec("set role " + role);
  try {
    return await operation();
  } finally {
    await db.exec("reset role");
  }
}

async function fixture() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec([
    "create role anon nologin;",
    "create role authenticated nologin;",
    "create role service_role nologin;",
    "create schema auth;",
    "create schema private;",
    "create schema vault;",
    "create schema extensions;",
    "create extension pgcrypto with schema extensions;",
    "create type public.connector_status as enum ('pending','active','degraded','revoked');",
    "create type public.rotation_status as enum ('current','rotating','expired','revoked');",
    "create table auth.users(id uuid primary key);",
    "create table public.organizations(id uuid primary key, status text not null default 'active');",
    "create table public.memberships(organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),status text not null,role text not null,primary key(organization_id,user_id));",
    "create table public.connector_installations(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),provider text not null,external_account_id text not null,display_name text,status public.connector_status not null,scopes text[] not null default '{}',configuration jsonb not null default '{}',installed_by uuid not null references auth.users(id),last_health_check_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(organization_id,provider,external_account_id));",
    "create table public.credential_refs(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),installation_id uuid not null references public.connector_installations(id),secret_ref text not null,key_version integer not null,expires_at timestamptz,rotation_state public.rotation_status not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(installation_id));",
    "create table vault.decrypted_secrets(id uuid primary key default gen_random_uuid(),name text unique,decrypted_secret text not null);",
    "create function auth.uid() returns uuid language sql stable set search_path=pg_catalog as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;",
    "create function extensions.urlencode(p_value text) returns text language sql immutable strict set search_path=pg_catalog as $$ select p_value $$;",
    "create function private.pandora_is_active_org_admin_v1(p_organization_id uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$ select exists(select 1 from public.organizations o join public.memberships m on m.organization_id=o.id where o.id=p_organization_id and o.status='active' and m.user_id=auth.uid() and m.status='active' and m.role in ('owner','admin')) $$;",
    "create function vault.create_secret(p_secret text,p_name text,p_description text) returns uuid language plpgsql security definer set search_path=pg_catalog,vault as $$ declare v_id uuid:=gen_random_uuid(); begin insert into vault.decrypted_secrets(id,name,decrypted_secret) values(v_id,p_name,p_secret); return v_id; end $$;",
    "create function vault.update_secret(p_id uuid,p_secret text,p_name text,p_description text) returns void language plpgsql security definer set search_path=pg_catalog,vault as $$ begin update vault.decrypted_secrets set name=p_name,decrypted_secret=p_secret where id=p_id; if not found then raise exception 'fixture_secret_missing'; end if; end $$;",
  ].join("\n"));

  await db.query(
    "insert into auth.users(id) values($1),($2)",
    [OWNER_A, OWNER_B],
  );
  await db.query(
    "insert into public.organizations(id) values($1),($2)",
    [ORG_A, ORG_B],
  );
  await db.query(
    "insert into public.memberships(organization_id,user_id,status,role) values($1,$2,'active','owner')",
    [ORG_A, OWNER_A],
  );
  await db.exec([
    "insert into vault.decrypted_secrets(name,decrypted_secret) values",
    "('pandora_meta_oauth_app_id','123456789012345'),",
    "('pandora_meta_oauth_app_secret','synthetic-app-secret-never-logged'),",
    "('pandora_meta_oauth_config_id','987654321098765');",
  ].join("\n"));
  await db.exec(oauthMigration);
  await db.exec(prepareCorrection);
  return db;
}

async function prepare(db, organizationId) {
  const result = await db.query(
    "select public.pandora_meta_oauth_prepare_v1($1::uuid) as value",
    [organizationId],
  );
  return result.rows[0].value;
}

async function material(db, state) {
  const result = await db.query(
    "select public.pandora_meta_oauth_material_v1($1::text) as value",
    [state],
  );
  return result.rows[0].value;
}

async function commit(db, state) {
  const pages = [{
    id: PAGE_ID,
    name: "Synthetic Pandora Page",
    access_token: "synthetic-page-token-000000000000",
    tasks: ["ANALYZE"],
  }];
  const adAccounts = [{
    id: "act_123450000000002",
    account_id: "123450000000002",
    name: "Synthetic Ad Account",
    account_status: 1,
    currency: "PHP",
  }];
  const result = await db.query(
    "select public.pandora_meta_oauth_commit_v1($1,$2,$3,$4,$5,$6::text[],$7::jsonb,$8::jsonb) as value",
    [
      state,
      "456789012345678",
      "Synthetic Meta Owner",
      "synthetic-user-token-000000000000",
      3600,
      REQUIRED_SCOPES,
      JSON.stringify(pages),
      JSON.stringify(adAccounts),
    ],
  );
  return result.rows[0].value;
}

test("Meta OAuth state is one-time, organization-bound, and service-only", async () => {
  const db = await fixture();
  try {
    await setUser(db, OWNER_A);

    const acl = (await db.query([
      "select",
      "has_function_privilege('anon','public.pandora_meta_oauth_prepare_v1(uuid)','execute') as prepare_anon,",
      "has_function_privilege('authenticated','public.pandora_meta_oauth_prepare_v1(uuid)','execute') as prepare_authenticated,",
      "has_function_privilege('anon','public.pandora_meta_oauth_material_v1(text)','execute') as material_anon,",
      "has_function_privilege('authenticated','public.pandora_meta_oauth_material_v1(text)','execute') as material_authenticated,",
      "has_function_privilege('service_role','public.pandora_meta_oauth_material_v1(text)','execute') as material_service,",
      "has_function_privilege('anon','public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb)','execute') as commit_anon,",
      "has_function_privilege('authenticated','public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb)','execute') as commit_authenticated,",
      "has_function_privilege('service_role','public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb)','execute') as commit_service",
    ].join("\n"))).rows[0];
    assert.deepEqual(acl, {
      prepare_anon: false,
      prepare_authenticated: true,
      material_anon: false,
      material_authenticated: false,
      material_service: true,
      commit_anon: false,
      commit_authenticated: false,
      commit_service: true,
    });

    await expectDatabaseError(
      asRole(db, "anon", () => prepare(db, ORG_A)),
      "permission denied for function pandora_meta_oauth_prepare_v1",
      "42501",
    );
    await expectDatabaseError(
      asRole(db, "authenticated", () => prepare(db, ORG_B)),
      "pandora_meta_oauth_owner_required",
      "42501",
    );

    const prepared = await asRole(
      db,
      "authenticated",
      () => prepare(db, ORG_A),
    );
    assert.equal(prepared.ok, true);
    assert.equal(prepared.redirectUri, "https://mcpmaster.vercel.app/oauth/meta/callback");
    assert.deepEqual(prepared.scopes, REQUIRED_SCOPES);
    assert.equal("appSecret" in prepared, false);
    const authorizationUrl = new URL(prepared.authorizationUrl);
    const state = authorizationUrl.searchParams.get("state");
    assert.ok(state);
    assert.equal(authorizationUrl.searchParams.get("config_id"), "987654321098765");

    const stateRow = (await db.query(
      "select organization_id::text,user_id::text,state_hash,claimed_at,consumed_at from private.pandora_meta_oauth_states where state_hash=$1",
      [sha256(state)],
    )).rows[0];
    assert.deepEqual(stateRow, {
      organization_id: ORG_A,
      user_id: OWNER_A,
      state_hash: sha256(state),
      claimed_at: null,
      consumed_at: null,
    });

    await expectDatabaseError(
      asRole(db, "authenticated", () => material(db, "x".repeat(43))),
      "permission denied for function pandora_meta_oauth_material_v1",
      "42501",
    );
    await expectDatabaseError(
      asRole(db, "authenticated", () => commit(db, state)),
      "permission denied for function pandora_meta_oauth_commit_v1",
      "42501",
    );
    await expectDatabaseError(
      asRole(db, "service_role", () => material(db, "x".repeat(43))),
      "pandora_meta_oauth_state_invalid_or_replayed",
      "42501",
    );

    const expiredState = "expired-state-material-0000000000000000";
    await db.query(
      "insert into private.pandora_meta_oauth_states(organization_id,user_id,state_hash,redirect_uri,required_scopes,created_at,expires_at) values($1,$2,$3,'https://example.test/callback',$4::text[],now()-interval '20 minutes',now()-interval '10 minutes')",
      [ORG_A, OWNER_A, sha256(expiredState), REQUIRED_SCOPES],
    );
    await expectDatabaseError(
      asRole(db, "service_role", () => material(db, expiredState)),
      "pandora_meta_oauth_state_invalid_or_replayed",
      "42501",
    );
    const expired = (await db.query(
      "select claimed_at,consumed_at from private.pandora_meta_oauth_states where state_hash=$1",
      [sha256(expiredState)],
    )).rows[0];
    assert.deepEqual(expired, { claimed_at: null, consumed_at: null });

    const claimed = await asRole(
      db,
      "service_role",
      () => material(db, state),
    );
    assert.equal(claimed.organizationId, ORG_A);
    assert.equal(claimed.userId, OWNER_A);
    assert.equal(claimed.redirectUri, prepared.redirectUri);
    assert.deepEqual(claimed.requiredScopes, REQUIRED_SCOPES);
    await expectDatabaseError(
      asRole(db, "service_role", () => material(db, state)),
      "pandora_meta_oauth_state_invalid_or_replayed",
      "42501",
    );

    const sentinelSecret = "33333333-3333-4333-8333-333333333333";
    await db.query(
      "insert into private.pandora_meta_connections(organization_id,connected_by,provider_user_id,display_name,user_token_secret_id,scopes,pages,ad_accounts,status,last_verified_at,last_http_status) values($1,$2,'999','Org B sentinel',$3,$4::text[],'[]'::jsonb,'[]'::jsonb,'connected',now(),200)",
      [ORG_B, OWNER_B, sentinelSecret, REQUIRED_SCOPES],
    );
    const orgBBefore = (await db.query(
      "select provider_user_id,display_name,user_token_secret_id::text,scopes,pages,ad_accounts,status,last_verified_at,updated_at from private.pandora_meta_connections where organization_id=$1",
      [ORG_B],
    )).rows[0];

    const committed = await asRole(
      db,
      "service_role",
      () => commit(db, state),
    );
    assert.equal(committed.ok, true);
    assert.equal(committed.organizationId, ORG_A);
    assert.equal(committed.pageCount, 1);
    assert.equal(committed.adAccountCount, 1);

    const stateAfterCommit = (await db.query(
      "select claimed_at is not null as claimed,consumed_at is not null as consumed from private.pandora_meta_oauth_states where state_hash=$1",
      [sha256(state)],
    )).rows[0];
    assert.deepEqual(stateAfterCommit, { claimed: true, consumed: true });

    const orgA = (await db.query(
      "select organization_id::text,connected_by::text,provider_user_id,scopes,pages,ad_accounts,status,last_http_status from private.pandora_meta_connections where organization_id=$1",
      [ORG_A],
    )).rows[0];
    assert.equal(orgA.organization_id, ORG_A);
    assert.equal(orgA.connected_by, OWNER_A);
    assert.equal(orgA.provider_user_id, "456789012345678");
    assert.equal(orgA.status, "connected");
    assert.equal(orgA.last_http_status, 200);
    assert.deepEqual(orgA.scopes, REQUIRED_SCOPES);
    assert.deepEqual(orgA.pages, [{
      id: PAGE_ID,
      name: "Synthetic Pandora Page",
      tasks: ["ANALYZE"],
    }]);
    assert.deepEqual(orgA.ad_accounts, [{
      id: "act_123450000000002",
      name: "Synthetic Ad Account",
      currency: "PHP",
      account_id: "123450000000002",
      account_status: 1,
    }]);

    const publicRows = (await db.query(
      "select c.organization_id::text,c.external_account_id,c.status::text,cr.organization_id::text as credential_org,cr.key_version,cr.rotation_state::text from public.connector_installations c join public.credential_refs cr on cr.installation_id=c.id",
    )).rows;
    assert.deepEqual(publicRows, [{
      organization_id: ORG_A,
      external_account_id: PAGE_ID,
      status: "active",
      credential_org: ORG_A,
      key_version: 1,
      rotation_state: "current",
    }]);
    const committedSecrets = (await db.query([
      "select",
      "  user_secret.decrypted_secret as user_token,",
      "  page_secret.decrypted_secret as page_token,",
      "  connection.token_expires_at is not null as user_expiry_present,",
      "  credential.expires_at is not null as page_expiry_present,",
      "  credential.secret_ref,",
      "  page_token.token_secret_id::text as page_token_secret_id",
      "from private.pandora_meta_connections connection",
      "join public.connector_installations installation",
      "  on installation.organization_id=connection.organization_id",
      "join public.credential_refs credential",
      "  on credential.installation_id=installation.id",
      "join private.pandora_meta_page_tokens page_token",
      "  on page_token.organization_id=connection.organization_id",
      "join vault.decrypted_secrets user_secret",
      "  on user_secret.id=connection.user_token_secret_id",
      "join vault.decrypted_secrets page_secret",
      "  on page_secret.id=page_token.token_secret_id",
      "where connection.organization_id=$1",
    ].join("\n"), [ORG_A])).rows[0];
    assert.ok(committedSecrets);
    assert.equal(committedSecrets.user_token, "synthetic-user-token-000000000000");
    assert.equal(committedSecrets.page_token, "synthetic-page-token-000000000000");
    assert.equal(committedSecrets.user_expiry_present, true);
    assert.equal(committedSecrets.page_expiry_present, true);
    assert.equal(
      committedSecrets.secret_ref,
      `vault://${committedSecrets.page_token_secret_id}`,
    );

    assert.deepEqual((await db.query(
      "select organization_id::text,page_id,page_name,tasks from private.pandora_meta_page_tokens",
    )).rows, [{
      organization_id: ORG_A,
      page_id: PAGE_ID,
      page_name: "Synthetic Pandora Page",
      tasks: ["ANALYZE"],
    }]);
    assert.deepEqual((await db.query(
      "select provider_user_id,display_name,user_token_secret_id::text,scopes,pages,ad_accounts,status,last_verified_at,updated_at from private.pandora_meta_connections where organization_id=$1",
      [ORG_B],
    )).rows[0], orgBBefore);

    const beforeReplay = (await db.query(
      "select (select count(*)::int from vault.decrypted_secrets) as secrets,(select key_version from public.credential_refs limit 1) as key_version,(select updated_at from private.pandora_meta_connections where organization_id=$1) as updated_at",
      [ORG_A],
    )).rows[0];
    await expectDatabaseError(
      asRole(db, "service_role", () => commit(db, state)),
      "pandora_meta_oauth_state_invalid_or_expired",
      "42501",
    );
    assert.deepEqual((await db.query(
      "select (select count(*)::int from vault.decrypted_secrets) as secrets,(select key_version from public.credential_refs limit 1) as key_version,(select updated_at from private.pandora_meta_connections where organization_id=$1) as updated_at",
      [ORG_A],
    )).rows[0], beforeReplay);

    const secondPrepared = await asRole(
      db,
      "authenticated",
      () => prepare(db, ORG_A),
    );
    const unclaimedState = new URL(secondPrepared.authorizationUrl).searchParams.get("state");
    const beforeUnclaimedCommit = (await db.query(
      "select (select count(*)::int from vault.decrypted_secrets) as secrets,(select updated_at from private.pandora_meta_connections where organization_id=$1) as updated_at",
      [ORG_A],
    )).rows[0];
    await expectDatabaseError(
      asRole(db, "service_role", () => commit(db, unclaimedState)),
      "pandora_meta_oauth_state_invalid_or_expired",
      "42501",
    );
    assert.deepEqual((await db.query(
      "select (select count(*)::int from vault.decrypted_secrets) as secrets,(select updated_at from private.pandora_meta_connections where organization_id=$1) as updated_at",
      [ORG_A],
    )).rows[0], beforeUnclaimedCommit);
    const unclaimed = (await db.query(
      "select claimed_at,consumed_at from private.pandora_meta_oauth_states where state_hash=$1",
      [sha256(unclaimedState)],
    )).rows[0];
    assert.deepEqual(unclaimed, { claimed_at: null, consumed_at: null });
  } finally {
    await db.close();
  }
});
