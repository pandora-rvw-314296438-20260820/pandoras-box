-- TEST-ONLY, INACTIVE REPLAY FIXTURE.
-- Apply only after 20260731122011_pandora_product_intelligence_schema.
-- This supplies inert rows and provider-extension shapes assumed by later
-- historical migrations. It is not a production seed and must never be placed
-- under supabase/migrations.

-- The later FXPass growth-contract migration assumes this registry row exists.
insert into private.pandora_product_registry (
  organization_id,
  product_key,
  title,
  repo_full_name,
  data_classification
)
values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'fxpass',
  'FXPass',
  'banataosystems/fxpass',
  'pseudonymous_product'
);

-- Supabase Vault is provider-managed in the hosted project. PGlite does not
-- ship that extension, so replay supplies only the non-secret table shape and
-- one deliberately unusable credential reference required by the already-
-- applied Vercel adapter migration.
create table if not exists vault.secrets (
  id uuid primary key default gen_random_uuid(),
  name text unique,
  description text not null default '',
  secret text not null,
  key_id uuid,
  nonce bytea,
  created_at timestamptz not null default current_timestamp,
  updated_at timestamptz not null default current_timestamp
);

insert into vault.secrets (
  id,
  name,
  description,
  secret
)
values (
  '55555555-5555-4555-8555-555555555555'::uuid,
  'vercel',
  'Replay-only inert Vercel credential placeholder',
  'replay-only-not-a-credential'
)
on conflict (name) do update set
  description = excluded.description,
  secret = excluded.secret,
  updated_at = current_timestamp;

insert into vault.decrypted_secrets (id, decrypted_secret)
values (
  '55555555-5555-4555-8555-555555555555'::uuid,
  'replay-only-not-a-credential'
)
on conflict (id) do update set
  decrypted_secret = excluded.decrypted_secret;

-- The hosted project already has the canonical GitHub installation. Replay
-- records a minimal inert equivalent so the Vercel adapter can recover the
-- organization and installer identities without importing provider payloads.
insert into public.connector_installations (
  id,
  organization_id,
  provider,
  external_account_id,
  display_name,
  status,
  scopes,
  configuration,
  installed_by
)
values (
  '66666666-6666-4666-8666-666666666666'::uuid,
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'github',
  'github-primary',
  'Replay GitHub installation',
  'active'::public.connector_status,
  array['repo:read', 'repo:write'],
  jsonb_build_object(
    'account_id', 'github-primary',
    'auth_mode', 'replay_only',
    'credential_state', 'inert_fixture'
  ),
  '76a3bf0a-5bfa-4ce2-b92a-3646824e5754'::uuid
)
on conflict (organization_id, provider, external_account_id) do update set
  display_name = excluded.display_name,
  status = excluded.status,
  scopes = excluded.scopes,
  configuration = excluded.configuration,
  installed_by = excluded.installed_by,
  updated_at = timezone('utc'::text, now());

-- pg_net exposes this exact hosted signature. The replay stub never performs
-- network I/O and returns only a local request identifier.
create or replace function net.http_delete(
  url text,
  params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb,
  timeout_milliseconds integer default 1000,
  body jsonb default null
) returns bigint
language sql volatile
as $$ select nextval('net.http_request_id_seq') $$;
