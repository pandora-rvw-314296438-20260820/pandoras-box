create table if not exists public.pandora_connection_verification_observations_v1 (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null check (provider_key ~ '^[a-z0-9][a-z0-9._-]{1,79}$'),
  state text not null check (state in ('verified','partial','not_connected','error')),
  observed_at timestamptz not null,
  stale_after timestamptz,
  source text not null check (length(source) between 3 and 120),
  missing_reason text,
  evidence_redacted jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id, provider_key),
  check (jsonb_typeof(evidence_redacted) = 'object')
);

alter table public.pandora_connection_verification_observations_v1 enable row level security;

revoke all on public.pandora_connection_verification_observations_v1 from anon;
revoke all on public.pandora_connection_verification_observations_v1 from authenticated;
grant select on public.pandora_connection_verification_observations_v1 to authenticated;
grant select, insert, update, delete on public.pandora_connection_verification_observations_v1 to service_role;

drop policy if exists pandora_connection_verification_observations_read_v1
  on public.pandora_connection_verification_observations_v1;
create policy pandora_connection_verification_observations_read_v1
  on public.pandora_connection_verification_observations_v1
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.memberships m
      where m.organization_id = pandora_connection_verification_observations_v1.organization_id
        and m.user_id = auth.uid()
        and m.status = 'active'
    )
  );

create index if not exists pandora_connection_verification_observations_freshness_v1
  on public.pandora_connection_verification_observations_v1
  (organization_id, observed_at desc);

comment on table public.pandora_connection_verification_observations_v1 is
  'Redacted, tenant-scoped provider verification observations for the Connections Center. Never stores credentials or raw provider tokens.';
