'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync(
  'supabase/migrations/20260927043500_pandora_meta_readiness_projection_v1.sql',
  'utf8',
);

test('FB-012 Meta readiness fails closed on expiry, permissions and recent health', () => {
  assert.match(sql, /v_row\.status='connected'[\s\S]*v_token_expiry_known[\s\S]*not v_token_expired[\s\S]*v_scopes_verified[\s\S]*v_health_verified/);
  assert.match(sql, /v_row\.token_expires_at is not null/);
  assert.match(sql, /not v_token_expiry_known[\s\S]*or v_row\.token_expires_at<=clock_timestamp\(\)/);
  assert.match(sql, /last_verified_at>=clock_timestamp\(\)-interval '24 hours'/);
  assert.match(sql, /private\.pandora_meta_required_scopes_v1\(\)/);
  assert.match(sql, /last_http_status between 200 and 299/);
  assert.match(sql, /'canUseNow',v_can_use/);
});

test('FB-012 projects accurate reconnect and permission guidance', () => {
  assert.match(sql, /Reconnect Facebook to establish a verifiable token expiry/);
  assert.match(sql, /Reconnect Facebook to refresh the expired access token/);
  assert.match(sql, /Reconnect Facebook and grant all required permissions/);
  assert.match(sql, /Refresh connection health or reconnect Facebook before using Meta/);
  assert.match(sql, /'tokenExpiryKnown',v_token_expiry_known/);
  assert.match(sql, /'tokenExpired',v_token_expired/);
  assert.match(sql, /'scopesVerified',v_scopes_verified/);
  assert.match(sql, /'healthVerified',v_health_verified/);
});

test('FB-012 preserves owner/admin authorization and explicitly rejects missing membership', () => {
  assert.match(sql, /pandora_meta_connection_sign_in_required/);
  assert.match(sql, /v_role is null or v_role not in \('owner','admin'\)/);
  assert.match(sql, /revoke all on function public\.pandora_meta_connection_v1\(uuid\) from public,anon/);
  assert.match(sql, /grant execute on function public\.pandora_meta_connection_v1\(uuid\) to authenticated/);
});

test('FB-012 behavior rejects unauthorized, expired and unverified readiness across projection and dispatch', async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create schema auth;
      create schema private;
      create schema extensions;
      create schema vault;
      create type extensions.http_response as (status integer, content_type text, headers text[], content text);
      create type public.connector_status as enum ('pending','active','degraded','revoked');

      create table public.memberships(
        organization_id uuid not null,
        user_id uuid not null,
        status text not null,
        role text not null
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
        organization_id uuid not null,
        installation_id uuid not null,
        secret_ref text not null,
        rotation_state text not null,
        expires_at timestamptz
      );
      create table public.pandora_intelligence_threads(
        id uuid primary key default gen_random_uuid(), organization_id uuid, project_id uuid,
        created_by uuid, title text, status text, last_message_at timestamptz, updated_at timestamptz
      );
      create table public.pandora_intelligence_messages(
        thread_id uuid, organization_id uuid, project_id uuid, author_role text, content text,
        attachment_manifest jsonb, structured_response jsonb, provider text, model text
      );

      create or replace function auth.uid() returns uuid
      language sql stable
      as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

      create or replace function private.pandora_meta_required_scopes_v1() returns text[]
      language sql immutable
      as $$ select array['ads_read','business_management']::text[] $$;
    `);
    const native = fs.readFileSync(
      'supabase/migrations/20260925063000_pandora_meta_native_capability_v1.sql', 'utf8',
    );
    const dispatchStart = native.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_capability_dispatch_native_v1');
    const dispatchEnd = native.indexOf('do $meta_native_contract$', dispatchStart);
    assert.ok(dispatchStart >= 0 && dispatchEnd > dispatchStart);
    await db.exec(native.slice(dispatchStart, dispatchEnd));
    const definition = async () => (await db.query(
      "select pg_get_functiondef('public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)'::regprocedure) as body"
    )).rows[0].body;
    const beforeDispatch = await definition();
    await db.exec(sql);
    const afterDispatch = await definition();
    await db.exec(sql);
    assert.equal(await definition(), afterDispatch, 'readiness migration is idempotent');
    const stripMeta = (body) => body.slice(0, body.indexOf("elsif v_provider='meta' then"))
      + body.slice(body.indexOf("elsif v_provider='google' then"));
    assert.equal(stripMeta(afterDispatch), stripMeta(beforeDispatch), 'other provider lanes and guards remain intact');

    const org = '2270b266-59da-4c39-bfd9-9f8d08352af0';
    const outsider = '11111111-1111-4111-8111-111111111111';
    await db.query(`select set_config('request.jwt.claim.sub','${outsider}',false)`);
    await assert.rejects(
      db.query(`select public.pandora_meta_connection_v1('${org}'::uuid)`),
      /pandora_meta_connection_owner_required/,
    );

    const owner = '22222222-2222-4222-8222-222222222222';
    await db.exec(`
      insert into public.memberships(organization_id,user_id,status,role)
      values ('${org}','${owner}','active','owner');

      insert into private.pandora_meta_connections(
        organization_id,connected_by,provider_user_id,display_name,user_token_secret_id,
        scopes,pages,ad_accounts,status,token_expires_at,last_verified_at,last_http_status,last_error
      ) values (
        '${org}','${owner}','123','Meta test','33333333-3333-4333-8333-333333333333',
        array['ads_read','business_management'],'[]'::jsonb,'[]'::jsonb,'connected',
        null,clock_timestamp(),200,null
      );
    `);
    await db.query(`select set_config('request.jwt.claim.sub','${owner}',false)`);
    const result = await db.query(`select public.pandora_meta_connection_v1('${org}'::uuid) as connection`);
    const connection = result.rows[0].connection;
    assert.equal(connection.connected, true);
    assert.equal(connection.tokenExpiryKnown, false);
    assert.equal(connection.tokenExpired, true);
    assert.equal(connection.canUseNow, false);
    assert.match(connection.guidance, /verifiable token expiry/);

    const readConnection = async () => (await db.query(
      `select public.pandora_meta_connection_v1('${org}'::uuid) as connection`
    )).rows[0].connection;
    const readDispatch = async (message = 'facebook status') => (await db.query(
      'select public.pandora_chat_capability_dispatch_native_v1($1::uuid,$2::text) as turn', [org, message]
    )).rows[0].turn;
    let turn = await readDispatch();
    assert.equal(turn.providerReadback.connected, true);
    assert.equal(turn.providerReadback.canUseNow, false);
    assert.equal(turn.providerReadback.verified, false);
    assert.match(turn.reply, /verifiable token expiry/);
    assert.doesNotMatch(turn.reply, /Pandora can read/);

    const installation = '44444444-4444-4444-8444-444444444444';
    await db.exec(`
      update private.pandora_meta_connections
      set token_expires_at=clock_timestamp()+interval '1 hour';
      insert into public.connector_installations(
        id,organization_id,provider,external_account_id,display_name,status,scopes,installed_by,last_health_check_at
      ) values (
        '${installation}','${org}','meta','456','Meta Page','active',
        array['ads_read','business_management'],'${owner}',clock_timestamp()
      );
    `);
    let ready = await readConnection();
    assert.equal(ready.canUseNow, true);
    assert.equal(ready.installations[0].credentialUsable, false);
    assert.equal(ready.installations[0].canUseNow, false, 'missing credential is unusable');
    await db.exec(`
      insert into public.credential_refs(organization_id,installation_id,secret_ref,rotation_state,expires_at)
      values ('${org}','${installation}','vault://55555555-5555-4555-8555-555555555555','current',clock_timestamp()+interval '1 hour');
    `);
    ready = await readConnection();
    assert.equal(ready.installations[0].canUseNow, true);
    turn = await readDispatch();
    assert.equal(turn.providerReadback.verified, true);
    assert.equal(turn.providerReadback.canUseNow, true);
    assert.match(turn.reply, /Pandora can read/);

    for (const [mutation, reason] of [
      ["expires_at=clock_timestamp()-interval '1 second'", 'expired'],
      ["expires_at=clock_timestamp()+interval '1 hour',rotation_state='revoked'", 'revoked'],
      ["rotation_state='current',organization_id='66666666-6666-4666-8666-666666666666'", 'other tenant'],
      [`organization_id='${org}',secret_ref='not-a-vault-reference'`, 'invalid reference'],
    ]) {
      await db.exec('update public.credential_refs set '+mutation);
      ready = await readConnection();
      assert.equal(ready.installations[0].credentialUsable, false, reason);
      assert.equal(ready.installations[0].canUseNow, false, reason);
    }
    await db.exec(`
      update public.credential_refs set secret_ref='vault://55555555-5555-4555-8555-555555555555',expires_at=null;
    `);
    assert.equal((await readConnection()).installations[0].canUseNow, true, 'non-expiring page credential keeps existing resolver semantics');

    for (const [mutation, guidance] of [
      ["token_expires_at=clock_timestamp()-interval '1 second'", /expired access token/],
      ["token_expires_at=clock_timestamp()+interval '1 hour',scopes=array['ads_read']", /grant all required permissions/],
      ["scopes=array['ads_read','business_management'],last_verified_at=clock_timestamp()-interval '25 hours'", /Refresh connection health/],
      ["last_verified_at=clock_timestamp(),last_http_status=500", /Refresh connection health/],
    ]) {
      await db.exec('update private.pandora_meta_connections set '+mutation);
      ready = await readConnection();
      assert.equal(ready.canUseNow, false);
      assert.equal(ready.installations[0].canUseNow, false, 'installation inherits unusable account readiness');
      turn = await readDispatch();
      assert.equal(turn.providerReadback.verified, false);
      assert.equal(turn.providerReadback.canUseNow, false);
      assert.match(turn.reply, guidance);
      assert.doesNotMatch(turn.reply, /Pandora can read/);
    }

    await db.exec(`
      create or replace function public.pandora_meta_oauth_prepare_v1(p_organization_id uuid)
      returns jsonb language sql as $$
        select jsonb_build_object('ok',true,'authorizationUrl','https://www.facebook.com/test-only');
      $$;
    `);
    const reconnect = await readDispatch('reconnect facebook');
    assert.equal(reconnect.providerReadback.verified, false);
    assert.equal(reconnect.providerReadback.canUseNow, false);
    assert.equal(reconnect.providerReadback.authorization.ok, true);
    assert.equal(reconnect.providerReadback.authorization.authorizationUrl, 'https://www.facebook.com/test-only');
    assert.match(reconnect.reply, /secure Facebook OAuth handoff/);
  } finally {
    await db.close();
  }
});
