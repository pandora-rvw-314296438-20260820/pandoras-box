import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';

const root = join(import.meta.dirname, '..');
const migrationPath = join(
  root,
  'supabase',
  'migrations',
  '20260928210000_pandora_meta_existing_grants_health_refresh.sql',
);
const vaultCompatMigrationPath = join(
  root,
  'supabase',
  'migrations',
  '20261002113405_pandora_meta_vault_lock_compat_v1.sql',
);
const ownerApiPath = join(
  root,
  'supabase',
  'functions',
  'pandora-owner-api',
  'index.ts',
);
const migration = await readFile(migrationPath, 'utf8');
const vaultCompatMigration = await readFile(vaultCompatMigrationPath, 'utf8');
const ownerApi = await readFile(ownerApiPath, 'utf8');
const verifierSection = migration.slice(
  migration.indexOf(
    'create or replace function public.pandora_verify_meta_connection_20260906(',
  ),
  migration.indexOf(
    'revoke all on function public.pandora_verify_meta_connection_20260906(',
  ),
);
const finalizerSection = vaultCompatMigration.slice(
  vaultCompatMigration.indexOf(
    'CREATE OR REPLACE FUNCTION private.pandora_meta_health_finalize_v1(',
  ),
  vaultCompatMigration.indexOf(
    'revoke all on function private.pandora_meta_health_finalize_v1(',
  ),
);

const org = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const otherOrg = '66666666-6666-4666-8666-666666666666';
const installation = '2582faeb-5431-427b-93ba-d7e803eba3c1';
const pageSecret = '11111111-1111-4111-8111-111111111111';
const userSecret = '22222222-2222-4222-8222-222222222222';
const otherSecret = '33333333-3333-4333-8333-333333333333';
const user = '44444444-4444-4444-8444-444444444444';
const pageId = '123456789';
const adId = 'act_987654321';
const accountId = '987654321';
const userUrl = 'https://graph.facebook.com/v26.0/me?fields=id';
const permissionsUrl =
  'https://graph.facebook.com/v26.0/me/permissions?limit=100';
const pageUrl =
  `https://graph.facebook.com/v26.0/${pageId}?fields=id,name`;
const adUrl =
  `https://graph.facebook.com/v26.0/${adId}?fields=id,account_id,name,currency`;

async function fixture() {
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema private;
    create schema vault;
    create schema extensions;
    create schema auth;
    create or replace function auth.jwt()
    returns jsonb
    language sql stable
    set search_path=pg_catalog
    as $fn$
      select '{}'::jsonb
    $fn$;

    create type public.connector_status
      as enum ('pending','active','degraded','revoked');
    create type extensions.http_method
      as enum ('GET','POST','PUT','DELETE','PATCH');
    create type extensions.http_header as (
      field varchar,
      value varchar
    );
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
    create or replace function extensions.http_header(
      p_field text,
      p_value text
    ) returns extensions.http_header
    language sql immutable
    set search_path=pg_catalog,extensions
    as $fn$
      select row(
        p_field::varchar,
        p_value::varchar
      )::extensions.http_header
    $fn$;
    create or replace function extensions.digest(
      p_data bytea,
      p_algorithm text
    ) returns bytea
    language sql immutable
    set search_path=pg_catalog
    as $fn$
      select convert_to(md5(encode(p_data,'hex')),'UTF8')
    $fn$;

    create table public.connector_installations(
      id uuid primary key,
      organization_id uuid not null,
      provider text not null,
      external_account_id text not null,
      display_name text,
      status public.connector_status not null,
      scopes text[] not null,
      configuration jsonb not null default '{}'::jsonb,
      installed_by uuid not null,
      last_health_check_at timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
    create table public.credential_refs(
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      installation_id uuid not null,
      secret_ref text not null,
      key_version integer not null,
      expires_at timestamptz,
      rotation_state text not null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
    create table private.pandora_meta_connections(
      organization_id uuid primary key,
      connected_by uuid not null,
      provider_user_id text not null,
      display_name text,
      user_token_secret_id uuid not null,
      scopes text[] not null,
      pages jsonb not null,
      ad_accounts jsonb not null,
      status text not null,
      token_expires_at timestamptz,
      last_verified_at timestamptz,
      last_http_status integer,
      last_error text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
    create table private.pandora_meta_page_tokens(
      organization_id uuid not null,
      page_id text not null,
      page_name text,
      token_secret_id uuid not null,
      tasks text[] not null default '{}',
      updated_at timestamptz not null default now(),
      primary key(organization_id,page_id)
    );
    create table vault.secrets(
      id uuid primary key
    );
    create table vault.decrypted_secrets(
      id uuid primary key,
      decrypted_secret text
    );
    create table private.fixture_http_responses(
      uri text primary key,
      status integer,
      content text,
      should_raise boolean not null default false,
      drift_target text,
      calls integer not null default 0
    );
    create or replace function private.pandora_meta_required_scopes_v1()
    returns text[]
    language sql immutable
    set search_path=pg_catalog
    as $fn$
      select array[
         'public_profile',
         'pages_show_list',
         'pages_read_engagement',
         'ads_read',
         'ads_management',
         'business_management'
       ]::text[]
    $fn$;

    create or replace function extensions.http(
      p_request extensions.http_request
    ) returns extensions.http_response
    language plpgsql
    set search_path=pg_catalog,private,extensions,pg_temp
    as $fn$
    declare
      v_status integer;
      v_content text;
      v_raise boolean;
      v_drift_target text;
      v_wait_until timestamptz;
    begin
      update private.fixture_http_responses
      set calls=calls+1
      where uri=p_request.uri
      returning status,content,should_raise,drift_target
      into v_status,v_content,v_raise,v_drift_target;
      if not found then
        return row(
          404,
          'application/json'::varchar,
          array[]::extensions.http_header[],
          '{}'::varchar
        )::extensions.http_response;
      end if;
      if v_drift_target = 'wait_for_expiry' then
        select token_expires_at into v_wait_until
        from private.pandora_meta_connections limit 1;
        if v_wait_until > clock_timestamp()+interval '2 seconds' then
          raise exception 'fixture_expiry_wait_out_of_bounds';
        end if;
        -- Bounded synthetic provider latency; do not mutate the health snapshot.
        while clock_timestamp() <= v_wait_until loop
          null;
        end loop;
      elsif v_drift_target = 'installation' then
        update public.connector_installations
        set display_name=display_name||' drift'
        where provider='meta';
      elsif v_drift_target = 'connection' then
        update private.pandora_meta_connections
        set display_name=display_name||' drift';
      elsif v_drift_target = 'credential' then
        update public.credential_refs
        set key_version=key_version+1;
      elsif v_drift_target = 'page_material' then
        update private.pandora_meta_page_tokens
        set page_name=page_name||' drift';
      elsif v_drift_target = 'page_secret' then
        update vault.decrypted_secrets
        set decrypted_secret=decrypted_secret||'-rotated'
        where decrypted_secret='page-token-fixture';
      elsif v_drift_target = 'user_secret' then
        update vault.decrypted_secrets
        set decrypted_secret=decrypted_secret||'-rotated'
        where decrypted_secret='user-token-fixture';
      end if;
      if v_raise then
        raise exception 'fixture_http_transport_failure';
      end if;
      return row(
        v_status,
        'application/json'::varchar,
        array[]::extensions.http_header[],
        v_content::varchar
      )::extensions.http_response;
    end;
    $fn$;
  `);

  await db.query(
    `insert into public.connector_installations(
       id,organization_id,provider,external_account_id,display_name,status,
       scopes,configuration,installed_by,last_health_check_at,updated_at
     ) values (
       $1,$2,'meta',$3,'Fixture Page','active',
       array[
         'public_profile',
         'pages_show_list',
         'pages_read_engagement',
         'ads_read',
         'ads_management',
         'business_management'
       ],
       '{"app_ownership_verified":false}'::jsonb,
       $4,clock_timestamp()-interval '2 days',clock_timestamp()-interval '2 days'
     )`,
    [installation, org, pageId, user],
  );
  await db.query(
    `insert into public.credential_refs(
       organization_id,installation_id,secret_ref,key_version,expires_at,
       rotation_state,updated_at
     ) values (
       $1,$2,$3,1,clock_timestamp()+interval '1 day','current',
       clock_timestamp()
     )`,
    [org, installation, `vault://${pageSecret}`],
  );
  await db.query(
    `insert into private.pandora_meta_connections(
       organization_id,connected_by,provider_user_id,display_name,
       user_token_secret_id,scopes,pages,ad_accounts,status,token_expires_at,
       last_verified_at,last_http_status,last_error,updated_at
     ) values (
       $1,$2,'555555','Fixture Meta',$3,
       array[
         'public_profile',
         'pages_show_list',
         'pages_read_engagement',
         'ads_read',
         'ads_management',
         'business_management'
       ],
       $4::jsonb,$5::jsonb,'connected',clock_timestamp()+interval '1 day',
       clock_timestamp()-interval '2 days',200,null,
       clock_timestamp()-interval '2 days'
     )`,
    [
      org,
      user,
      userSecret,
      JSON.stringify([{ id: pageId, name: 'Fixture Page', tasks: ['ANALYZE'] }]),
      JSON.stringify([{ id: adId, name: 'Fixture Ads', currency: 'PHP' }]),
    ],
  );
  await db.query(
    `insert into private.pandora_meta_page_tokens(
       organization_id,page_id,page_name,token_secret_id,tasks
     ) values ($1,$2,'Fixture Page',$3,array['ANALYZE'])`,
    [org, pageId, pageSecret],
  );
  await db.query(
    'insert into vault.secrets(id) values ($1),($2)',
    [pageSecret, userSecret],
  );
  await db.query(
    'insert into vault.decrypted_secrets(id,decrypted_secret) values ($1,$2),($3,$4)',
    [pageSecret, 'page-token-fixture', userSecret, 'user-token-fixture'],
  );
  await db.query(
    `insert into private.fixture_http_responses(uri,status,content)
     values
       ($1,200,$2),
       ($3,200,$4),
       ($5,200,$6),
       ($7,200,$8)`,
    [
      userUrl,
      JSON.stringify({ id: '555555' }),
      permissionsUrl,
      JSON.stringify({
        data: [
          { permission: 'public_profile', status: 'granted' },
          { permission: 'pages_show_list', status: 'granted' },
          { permission: 'pages_read_engagement', status: 'granted' },
          { permission: 'ads_read', status: 'granted' },
          { permission: 'ads_management', status: 'granted' },
          { permission: 'business_management', status: 'granted' },
        ],
      }),
      pageUrl,
      JSON.stringify({ id: pageId, name: 'Fixture Page' }),
      adUrl,
      JSON.stringify({
        id: adId,
        account_id: accountId,
        name: 'Fixture Ads',
        account_status: 1,
        currency: 'PHP',
      }),
    ],
  );
  await db.exec(migration);
  await db.exec(vaultCompatMigration);

  const invoke = async (organizationId = org, installationId = installation) => (
    await db.query(
      `select public.pandora_verify_meta_connection_20260906(
         $1::uuid,$2::uuid
       ) as result`,
      [organizationId, installationId],
    )
  ).rows[0].result;

  const health = async () => (
    await db.query(
      `select
         c.status as connection_status,
         c.last_verified_at,c.last_http_status,c.last_error,c.updated_at,
         i.status as installation_status,
         i.last_health_check_at,i.updated_at as installation_updated_at,
         i.configuration
       from private.pandora_meta_connections c
       join public.connector_installations i
         on i.organization_id=c.organization_id
       where c.organization_id=$1 and i.id=$2`,
      [org, installation],
    )
  ).rows[0];

  return { db, invoke, health };
}

async function failureCase(f, mutate, expectedReason) {
  await f.db.exec('begin');
  try {
    if (mutate) await mutate(f.db);
    const before = await f.health();
    const result = await f.invoke();
    assert.equal(result.ok, false);
    assert.equal(result.reason, expectedReason);
    const after = await f.health();
    assert.equal(after.connection_status, 'problem');
    assert.equal(after.installation_status, 'degraded');
    assert.equal(after.last_error, expectedReason);
    assert.equal(after.configuration.health_error_code, expectedReason);
    assert.equal(after.configuration.provider_network_enabled, false);
    assert.equal(
      new Date(after.last_verified_at).toISOString(),
      new Date(before.last_verified_at).toISOString(),
      expectedReason,
    );
    assert.equal(
      new Date(after.last_health_check_at).toISOString(),
      new Date(before.last_health_check_at).toISOString(),
      expectedReason,
    );
    assert.doesNotMatch(
      JSON.stringify(result),
      /token-fixture|vault:\/\/|fixture_http_transport_failure|secret_ref/i,
    );
  } finally {
    await f.db.exec('rollback');
  }
}

test('inactive and revoked lifecycle states fail closed without provider I/O or revival', async () => {
  const f = await fixture();
  try {
    const cases = [
      {
        name: 'pending installation',
        mutate: (db) => db.query(
          `update public.connector_installations set status='pending'
           where id=$1`,
          [installation],
        ),
        reason: 'installation_inactive',
        connectionStatus: 'connected',
        installationStatus: 'pending',
      },
      {
        name: 'revoked installation',
        mutate: (db) => db.query(
          `update public.connector_installations set status='revoked'
           where id=$1`,
          [installation],
        ),
        reason: 'installation_inactive',
        connectionStatus: 'connected',
        installationStatus: 'revoked',
      },
      {
        name: 'revoked connection',
        mutate: (db) => db.query(
          `update private.pandora_meta_connections set status='revoked'
           where organization_id=$1`,
          [org],
        ),
        reason: 'connection_unavailable',
        connectionStatus: 'revoked',
        installationStatus: 'active',
      },
      {
        name: 'revoked credential',
        mutate: (db) => db.query(
          `update public.credential_refs set rotation_state='revoked'
           where installation_id=$1`,
          [installation],
        ),
        reason: 'credential_missing',
        connectionStatus: 'problem',
        installationStatus: 'degraded',
      },
    ];

    for (const lifecycleCase of cases) {
      await f.db.exec('begin');
      try {
        await lifecycleCase.mutate(f.db);
        const before = await f.health();
        const result = await f.invoke();
        const after = await f.health();
        const calls = await f.db.query(
          'select coalesce(sum(calls),0)::int as count from private.fixture_http_responses',
        );

        assert.equal(result.ok, false, lifecycleCase.name);
        assert.equal(result.reason, lifecycleCase.reason, lifecycleCase.name);
        assert.equal(after.connection_status, lifecycleCase.connectionStatus);
        assert.equal(after.installation_status, lifecycleCase.installationStatus);
        assert.equal(calls.rows[0].count, 0, lifecycleCase.name);
        assert.equal(
          new Date(after.last_verified_at).toISOString(),
          new Date(before.last_verified_at).toISOString(),
          lifecycleCase.name,
        );
        assert.equal(
          new Date(after.last_health_check_at).toISOString(),
          new Date(before.last_health_check_at).toISOString(),
          lifecycleCase.name,
        );
        assert.doesNotMatch(
          JSON.stringify(result),
          /token-fixture|vault:\/\/|secret_ref/i,
          lifecycleCase.name,
        );
      } finally {
        await f.db.exec('rollback');
      }
    }
  } finally {
    await f.db.close();
  }
});

test('four exact read-only GETs accept legacy Page null expiry and atomically refresh health', async () => {
  const f = await fixture();
  try {
    await f.db.query(
      `update public.credential_refs
       set expires_at=null where installation_id=$1`,
      [installation],
    );
    const before = await f.health();
    const result = await f.invoke();
    const after = await f.health();

    assert.equal(result.ok, true);
    assert.equal(result.provider, 'meta');
    assert.equal(result.status, 'ACTIVE_HEALTHY');
    assert.equal(result.pageId, pageId);
    assert.equal(result.adAccountId, adId);
    assert.equal(result.currency, 'PHP');
    assert.equal(result.appOwnershipVerified, false);
    assert.ok(
      new Date(after.last_verified_at) > new Date(before.last_verified_at),
    );
    assert.ok(
      new Date(after.last_health_check_at) >
        new Date(before.last_health_check_at),
    );
    assert.equal(after.connection_status, 'connected');
    assert.equal(after.installation_status, 'active');
    assert.equal(after.last_http_status, 200);
    assert.equal(after.last_error, null);
    assert.equal(after.configuration.ad_account_access_verified, true);
    assert.equal(after.configuration.provider_network_enabled, true);

    const calls = await f.db.query(
      'select uri,calls from private.fixture_http_responses order by uri',
    );
    assert.deepEqual(
      calls.rows.map(({ uri, calls: count }) => [uri, count]),
      [
        [pageUrl, 1],
        [adUrl, 1],
        [permissionsUrl, 1],
        [userUrl, 1],
      ],
    );
    assert.doesNotMatch(
      JSON.stringify(result),
      /token-fixture|vault:\/\/|secret_ref/i,
    );
  } finally {
    await f.db.close();
  }
});

for (const timeZone of ['America/Los_Angeles', 'Asia/Manila']) {
  test(`health refresh preserves expiry and timestamps in ${timeZone}`, async () => {
    const f = await fixture();
    try {
      await f.db.query("select set_config('TimeZone',$1,false)", [timeZone]);
      const clock = async () => new Date((
        await f.db.query('select clock_timestamp() as observed_at')
      ).rows[0].observed_at).getTime();
      const assertWithinCall = (value, startedAt, endedAt, label) => {
        const timestamp = new Date(value).getTime();
        assert.ok(
          timestamp >= startedAt && timestamp <= endedAt,
          `${label} must record the current instant in ${timeZone}`,
        );
      };
      await f.db.query(
        `update private.pandora_meta_connections
         set token_expires_at=clock_timestamp()+interval '1 hour'
         where organization_id=$1`,
        [org],
      );
      await f.db.query(
        `update public.credential_refs
         set expires_at=clock_timestamp()+interval '1 hour'
         where installation_id=$1`,
        [installation],
      );
      const startedAt = await clock();
      const result = await f.invoke();
      const endedAt = await clock();
      const healthy = await f.health();
      assert.equal(result.ok, true);
      assert.equal(result.status, 'ACTIVE_HEALTHY');
      assert.equal(healthy.connection_status, 'connected');
      assert.equal(healthy.installation_status, 'active');
      assert.equal(healthy.last_error, null);
      for (const [label, value] of Object.entries({
        checkedAt: result.checkedAt,
        lastVerifiedAt: healthy.last_verified_at,
        lastHealthCheckAt: healthy.last_health_check_at,
        connectionUpdatedAt: healthy.updated_at,
        installationUpdatedAt: healthy.installation_updated_at,
      })) {
        assertWithinCall(value, startedAt, endedAt, label);
        assert.equal(
          new Date(value).getTime(),
          new Date(result.checkedAt).getTime(),
          label,
        );
      }
      const calls = await f.db.query(
        'select calls from private.fixture_http_responses',
      );
      assert.equal(calls.rows.length, 4);
      assert.ok(calls.rows.every((row) => row.calls === 1));

      await f.db.query(
        `update private.pandora_meta_connections
         set token_expires_at=clock_timestamp()-interval '1 hour'
         where organization_id=$1`,
        [org],
      );
      await f.db.query(
        `update public.credential_refs
         set expires_at=clock_timestamp()-interval '1 hour'
         where installation_id=$1`,
        [installation],
      );
      await f.db.exec('update private.fixture_http_responses set calls=0');
      const failureStartedAt = await clock();
      const denied = await f.invoke();
      const failureEndedAt = await clock();
      const failed = await f.health();
      assert.equal(denied.ok, false);
      assert.equal(denied.reason, 'credential_expired');
      assert.equal(failed.connection_status, 'problem');
      assert.equal(failed.installation_status, 'degraded');
      assert.equal(failed.last_error, 'credential_expired');
      assert.equal(failed.configuration.provider_network_enabled, false);
      for (const [label, value] of Object.entries({
        connectionUpdatedAt: failed.updated_at,
        installationUpdatedAt: failed.installation_updated_at,
      })) {
        assertWithinCall(value, failureStartedAt, failureEndedAt, label);
      }
      assert.equal(
        new Date(failed.last_verified_at).getTime(),
        new Date(healthy.last_verified_at).getTime(),
      );
      assert.equal(
        new Date(failed.last_health_check_at).getTime(),
        new Date(healthy.last_health_check_at).getTime(),
      );
      const deniedCalls = await f.db.query(
        'select sum(calls)::integer as count from private.fixture_http_responses',
      );
      assert.equal(deniedCalls.rows[0].count, 0);
    } finally {
      await f.db.close();
    }
  });
}

test('same-snapshot Page and marketing expiry records credential_expired health', async () => {
  const f = await fixture();
  try {
    await failureCase(
      f,
      async (db) => {
        await db.query(
          `update private.pandora_meta_connections
           set token_expires_at=clock_timestamp()-interval '1 second'
           where organization_id=$1`,
          [org],
        );
        await db.query(
          `update public.credential_refs
           set expires_at=clock_timestamp()-interval '1 second'
           where installation_id=$1`,
          [installation],
        );
      },
      'credential_expired',
    );
  } finally {
    await f.db.close();
  }
});

test('provider failure after unchanged grants expire still records degraded health', async () => {
  const f = await fixture();
  try {
    await f.db.exec(`
      create function private.fixture_expiring_provider_rejection(
        p_org uuid,p_installation uuid
      ) returns jsonb language plpgsql as $fn$
      declare v_expiry timestamptz:=clock_timestamp()+interval '1 second';
      begin
        update private.pandora_meta_connections
        set token_expires_at=v_expiry where organization_id=p_org;
        update public.credential_refs
        set expires_at=v_expiry where installation_id=p_installation;
        update private.fixture_http_responses
        set status=500,drift_target='wait_for_expiry';
        return public.pandora_verify_meta_connection_20260906(
          p_org,p_installation
        );
      end;
      $fn$;
    `);
    const before = await f.health();
    const result = (await f.db.query(
      'select private.fixture_expiring_provider_rejection($1,$2) as result',
      [org, installation],
    )).rows[0].result;
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'provider_rejected');
    const after = await f.health();
    assert.equal(after.connection_status, 'problem');
    assert.equal(after.installation_status, 'degraded');
    assert.equal(after.last_error, 'provider_rejected');
    assert.equal(after.configuration.health_error_code, 'provider_rejected');
    assert.equal(after.configuration.provider_network_enabled, false);
    assert.equal(
      new Date(after.last_verified_at).toISOString(),
      new Date(before.last_verified_at).toISOString(),
    );
    assert.equal(
      new Date(after.last_health_check_at).toISOString(),
      new Date(before.last_health_check_at).toISOString(),
    );
    const calls = await f.db.query(
      'select sum(calls)::integer as count from private.fixture_http_responses',
    );
    assert.equal(calls.rows[0].count, 1);
  } finally {
    await f.db.close();
  }
});

test('fresh failure invalidates readiness and exact retry restores health', async () => {
  const f = await fixture();
  try {
    const first = await f.invoke();
    assert.equal(first.ok, true);
    const fresh = await f.health();

    await f.db.query(
      `update private.fixture_http_responses
       set content=$2 where uri=$1`,
      [userUrl, JSON.stringify({ id: '999999' })],
    );
    const failed = await f.invoke();
    const invalidated = await f.health();

    assert.equal(failed.ok, false);
    assert.equal(failed.reason, 'provider_user_identity_mismatch');
    assert.equal(invalidated.connection_status, 'problem');
    assert.equal(invalidated.installation_status, 'degraded');
    assert.equal(
      new Date(invalidated.last_verified_at).toISOString(),
      new Date(fresh.last_verified_at).toISOString(),
    );
    assert.equal(
      new Date(invalidated.last_health_check_at).toISOString(),
      new Date(fresh.last_health_check_at).toISOString(),
    );

    await f.db.query(
      `update private.fixture_http_responses
       set content=$2 where uri=$1`,
      [userUrl, JSON.stringify({ id: '555555' })],
    );
    const recovered = await f.invoke();
    const healthy = await f.health();

    assert.equal(recovered.ok, true);
    assert.equal(healthy.connection_status, 'connected');
    assert.equal(healthy.installation_status, 'active');
    assert.equal(healthy.last_error, null);
    assert.equal(healthy.configuration.health_error_code, undefined);
    assert.equal(healthy.configuration.provider_network_enabled, true);
    assert.ok(
      new Date(healthy.last_verified_at) >
        new Date(invalidated.last_verified_at),
    );
  } finally {
    await f.db.close();
  }
});

test('stored identity, scope, expiry and credential drift cannot advance health', async () => {
  const f = await fixture();
  try {
    const cases = [
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set pages='[]'::jsonb where organization_id=$1`,
          [org],
        ),
        'page_identity_ambiguous',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set pages=$2::jsonb where organization_id=$1`,
          [org, JSON.stringify([{ id: '999' }])],
        ),
        'page_identity_mismatch',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set ad_accounts='[]'::jsonb where organization_id=$1`,
          [org],
        ),
        'ad_account_identity_ambiguous',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set ad_accounts=$2::jsonb where organization_id=$1`,
          [org, JSON.stringify([
            { id: adId, account_id: '111', currency: 'PHP' },
          ])],
        ),
        'ad_account_identity_invalid',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set scopes=array['pages_show_list'] where organization_id=$1`,
          [org],
        ),
        'required_scopes_missing',
      ],
      [
        (db) => db.query(
          `update public.connector_installations
           set scopes=array['pages_show_list'] where id=$1`,
          [installation],
        ),
        'required_scopes_missing',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set token_expires_at=clock_timestamp()-interval '1 second'
           where organization_id=$1`,
          [org],
        ),
        'credential_expired',
      ],
      [
        (db) => db.query(
          `update private.pandora_meta_connections
           set token_expires_at=null where organization_id=$1`,
          [org],
        ),
        'credential_expired',
      ],
      [
        (db) => db.query(
          'delete from public.credential_refs where installation_id=$1',
          [installation],
        ),
        'credential_missing',
      ],
      [
        (db) => db.query(
          `update public.credential_refs
           set expires_at=clock_timestamp()-interval '1 second'
           where installation_id=$1`,
          [installation],
        ),
        'credential_missing',
      ],
      [
        (db) => db.query(
          `update public.credential_refs set secret_ref='not-vault'
           where installation_id=$1`,
          [installation],
        ),
        'credential_reference_invalid',
      ],
      [
        async (db) => {
          await db.query(
            `insert into vault.decrypted_secrets(id,decrypted_secret)
             values ($1,'other-page-token')`,
            [otherSecret],
          );
          await db.query(
            `update private.pandora_meta_page_tokens set token_secret_id=$2
             where organization_id=$1 and page_id=$3`,
            [org, otherSecret, pageId],
          );
        },
        'page_credential_binding_mismatch',
      ],
      [
        (db) => db.query(
          'delete from vault.decrypted_secrets where id=$1',
          [userSecret],
        ),
        'credential_unavailable',
      ],
    ];
    for (const [mutate, reason] of cases) {
      await failureCase(f, mutate, reason);
    }
  } finally {
    await f.db.close();
  }
});

test('provider failures and exact readback mismatches leave both health rows stale', async () => {
  const f = await fixture();
  try {
    const cases = [
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [userUrl, JSON.stringify({ id: '999999' })],
        ),
        'provider_user_identity_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [permissionsUrl, JSON.stringify({
            data: [
              { permission: 'public_profile', status: 'granted' },
              { permission: 'pages_show_list', status: 'granted' },
              { permission: 'pages_read_engagement', status: 'granted' },
              { permission: 'ads_read', status: 'granted' },
              { permission: 'ads_management', status: 'granted' },
            ],
          })],
        ),
        'provider_scope_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [permissionsUrl, JSON.stringify({
            data: [
              { permission: 'public_profile', status: 'granted' },
              { permission: 'pages_show_list', status: 'granted' },
              { permission: 'pages_read_engagement', status: 'granted' },
              { permission: 'ads_read', status: 'granted' },
              { permission: 'ads_management', status: 'granted' },
              { permission: 'business_management', status: 'declined' },
            ],
          })],
        ),
        'provider_scope_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [permissionsUrl, JSON.stringify({
            data: [
              { permission: 'public_profile', status: 'granted' },
              { permission: 'pages_show_list', status: 'granted' },
              { permission: 'pages_read_engagement', status: 'granted' },
              { permission: 'ads_read', status: 'granted' },
              { permission: 'ads_management', status: 'granted' },
              { permission: 'business_management', status: 'granted' },
              { permission: 'business_management', status: 'declined' },
            ],
          })],
        ),
        'provider_scope_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [permissionsUrl, JSON.stringify({
            data: [
              { permission: 'public_profile', status: 'granted' },
              { permission: 'pages_show_list', status: 'granted' },
              { permission: 'pages_read_engagement', status: 'granted' },
              { permission: 'ads_read', status: 'granted' },
              { permission: 'ads_management', status: 'granted' },
              { permission: 'business_management', status: 'granted' },
            ],
            paging: { next: 'https://untrusted.invalid/cursor' },
          })],
        ),
        'provider_scope_readback_incomplete',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [permissionsUrl, JSON.stringify({ data: ['malformed'] })],
        ),
        'provider_scope_readback_invalid',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [pageUrl, JSON.stringify({ id: '999', name: 'Wrong Page' })],
        ),
        'page_identity_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content=$2 where uri=$1`,
          [adUrl, JSON.stringify({
            id: 'act_111',
            account_id: '111',
            currency: 'PHP',
          })],
        ),
        'ad_account_identity_mismatch',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses set status=500
           where uri=$1`,
          [pageUrl],
        ),
        'provider_rejected',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses set status=null
           where uri=$1`,
          [userUrl],
        ),
        'provider_rejected',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses set content='not-json'
           where uri=$1`,
          [pageUrl],
        ),
        'provider_rejected',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses
           set content='{"error":{"message":"redacted-fixture"}}'
           where uri=$1`,
          [adUrl],
        ),
        'provider_rejected',
      ],
      [
        (db) => db.query(
          `update private.fixture_http_responses set should_raise=true
           where uri=$1`,
          [adUrl],
        ),
        'provider_unavailable',
      ],
    ];
    for (const [mutate, reason] of cases) {
      await failureCase(f, mutate, reason);
    }
  } finally {
    await f.db.close();
  }
});

test('state drift during provider reads yields no verifier mutation', async () => {
  const f = await fixture();
  try {
    for (const driftTarget of [
      'installation',
      'connection',
      'credential',
      'page_material',
      'page_secret',
      'user_secret',
    ]) {
      await f.db.exec('begin');
      try {
        await f.db.query(
          `update private.fixture_http_responses
           set drift_target=$2 where uri=$1`,
          [adUrl, driftTarget],
        );
        const before = await f.health();
        const result = await f.invoke();
        const after = await f.health();

        assert.equal(result.ok, false);
        assert.equal(result.reason, 'health_state_changed');
        assert.doesNotMatch(
          JSON.stringify(result),
          /[0-9a-f]{64}|tokenDigest|secret_ref|vault:\/\//i,
        );
        assert.equal(after.connection_status, 'connected');
        assert.equal(after.installation_status, 'active');
        assert.equal(after.last_error, null);
        assert.equal(
          new Date(after.last_verified_at).toISOString(),
          new Date(before.last_verified_at).toISOString(),
        );
        assert.equal(
          new Date(after.last_health_check_at).toISOString(),
          new Date(before.last_health_check_at).toISOString(),
        );
      } finally {
        await f.db.exec('rollback');
      }
    }
  } finally {
    await f.db.close();
  }
});

test('wrong organization, installation and provider cannot update another row', async () => {
  const f = await fixture();
  try {
    const before = await f.health();
    await assert.rejects(
      f.invoke(otherOrg),
      (error) => error.code === '22023',
    );
    await assert.rejects(
      f.invoke(org, '99999999-9999-4999-8999-999999999999'),
      (error) => error.code === '22023',
    );

    await f.db.exec('begin');
    try {
      await f.db.query(
        `update public.connector_installations set provider='github'
         where id=$1`,
        [installation],
      );
      await assert.rejects(f.invoke(), (error) => error.code === '22023');
    } finally {
      await f.db.exec('rollback');
    }

    const after = await f.health();
    assert.equal(
      new Date(after.last_verified_at).toISOString(),
      new Date(before.last_verified_at).toISOString(),
    );
    assert.equal(
      new Date(after.last_health_check_at).toISOString(),
      new Date(before.last_health_check_at).toISOString(),
    );
  } finally {
    await f.db.close();
  }
});
test('service-only ACL, owner API compatibility and no-grant source boundary remain exact', async () => {
  const f = await fixture();
  try {
    const privileges = await f.db.query(`
      select
        has_function_privilege(
          'anon',
          'public.pandora_verify_meta_connection_20260906(uuid,uuid)',
          'EXECUTE'
        ) as anon_execute,
        has_function_privilege(
          'authenticated',
          'public.pandora_verify_meta_connection_20260906(uuid,uuid)',
          'EXECUTE'
        ) as authenticated_execute,
        has_function_privilege(
          'service_role',
          'public.pandora_verify_meta_connection_20260906(uuid,uuid)',
          'EXECUTE'
        ) as service_execute
    `);
    assert.equal(privileges.rows[0].anon_execute, false);
    assert.equal(privileges.rows[0].authenticated_execute, false);
    assert.equal(privileges.rows[0].service_execute, true);
  } finally {
    await f.db.close();
  }

  assert.match(
    ownerApi,
    /pandora_verify_meta_connection_20260906[\s\S]{0,260}p_organization_id[\s\S]{0,120}p_installation_id/,
  );
  assert.match(
    ownerApi,
    /result\.ok !== true[\s\S]*result\.provider[\s\S]*ACTIVE_HEALTHY/,
  );
  assert.match(
    verifierSection,
    /session_user not in \('postgres', 'service_role', 'supabase_admin'\)[\s\S]*auth\.jwt\(\)->>'role'/,
  );
  assert.doesNotMatch(verifierSection, /for update/i);
  assert.match(
    vaultCompatMigration,
    /lock table vault\.secrets in share mode;[\s\S]*for share[\s\S]*for update/i,
  );
  assert.doesNotMatch(
    finalizerSection,
    /from vault\.secrets[\s\S]{0,120}for share/i,
  );
  assert.doesNotMatch(
    vaultCompatMigration,
    /grant\s+update[\s\S]{0,200}vault\.secrets/i,
  );
  assert.doesNotMatch(finalizerSection, /extensions\.http\s*\(/);
  const lockOrder = [
    finalizerSection.indexOf(
      'lock table vault.secrets in share mode',
    ),
    finalizerSection.indexOf(
      'from private.pandora_meta_page_tokens',
    ),
    finalizerSection.indexOf(
      'from public.connector_installations',
    ),
    finalizerSection.indexOf(
      'from public.credential_refs',
    ),
    finalizerSection.indexOf(
      'from private.pandora_meta_connections',
    ),
  ];
  assert.ok(lockOrder.every((position) => position >= 0));
  assert.deepEqual(lockOrder, [...lockOrder].sort((a, b) => a - b));
  assert.match(
    migration,
    /'https:\/\/graph\.facebook\.com\/v26\.0\/me\?fields=id'/,
  );
  assert.match(
    migration,
    /'https:\/\/graph\.facebook\.com\/v26\.0\/me\/permissions\?limit=100'/,
  );
  assert.match(
    migration,
    /'GET'::extensions\.http_method[\s\S]*v26\.0[\s\S]*fields=id,name/,
  );
  assert.match(
    migration,
    /'GET'::extensions\.http_method[\s\S]*fields=id,account_id,name,currency/,
  );
  assert.match(
    migration,
    /extensions\.http_header\('authorization', 'Bearer ' \|\| v_user_token\)/,
  );
  assert.match(
    migration,
    /extensions\.http_header\('authorization', 'Bearer ' \|\| v_page_token\)/,
  );
  assert.doesNotMatch(
    migration,
    /pandora_meta_oauth_(?:prepare|material|commit)_v1|create_secret|update_secret|POST'::extensions\.http_method|access_token=/,
  );
  assert.doesNotMatch(
    migration.slice(migration.lastIndexOf('return jsonb_build_object(')),
    /v_page_token|v_user_token|secret_ref|decrypted_secret|v_user_body|v_permissions_body|v_ad_body/,
  );
});
