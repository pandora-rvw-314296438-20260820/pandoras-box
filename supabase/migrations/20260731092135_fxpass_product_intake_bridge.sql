-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- SEMANTIC REDACTION: live HMAC seed omitted; coordinated production rotation required.

create schema if not exists private;

create table if not exists private.integration_secrets (
  secret_name text primary key,
  secret_value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

revoke all on private.integration_secrets from public, anon, authenticated;
grant select, insert, update on private.integration_secrets to service_role;

-- Production FXPass HMAC seed intentionally replaced.
-- Fresh replays receive a database-generated, environment-scoped value.
-- Preserve any pre-existing credential instead of overwriting it.
insert into private.integration_secrets(secret_name, secret_value)
values ('projectos_fxpass_intake_hmac', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (secret_name) do nothing;

create or replace function public.projectos_service_secret(p_secret_name text)
returns text
language sql
security definer
set search_path = private, public
as $$
  select secret_value from private.integration_secrets where secret_name = p_secret_name;
$$;
revoke all on function public.projectos_service_secret(text) from public, anon, authenticated;
grant execute on function public.projectos_service_secret(text) to service_role;

create table if not exists private.product_intake_payloads (
  id uuid primary key default gen_random_uuid(),
  source_system text not null,
  source_submission_id uuid not null,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  requester_id uuid not null,
  workflow_run_id uuid references public.workflow_runs(id) on delete set null,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  received_at timestamptz not null default now(),
  unique (source_system, source_submission_id)
);

revoke all on private.product_intake_payloads from public, anon, authenticated;
grant select, insert, update on private.product_intake_payloads to service_role;
create index if not exists product_intake_payloads_received_at_idx on private.product_intake_payloads(received_at desc);

comment on table private.product_intake_payloads is 'Service-role-only product discovery payloads accepted into ProjectOS and linked to durable workflow runs.';
