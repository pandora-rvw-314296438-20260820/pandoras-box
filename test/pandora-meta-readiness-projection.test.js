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

test('FB-012 behavior rejects a signed-in non-member and unknown token expiry', async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create schema auth;
      create schema private;
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

      create or replace function auth.uid() returns uuid
      language sql stable
      as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

      create or replace function private.pandora_meta_required_scopes_v1() returns text[]
      language sql immutable
      as $$ select array['ads_read','business_management']::text[] $$;
    `);
    await db.exec(sql);

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
  } finally {
    await db.close();
  }
});
