-- Pandora execution-provider allowlist and ProjectOS retirement enforcement.
-- Active execution authority is limited to GitHub, Supabase, and Vercel.
-- Model, payment, analytics, and customer integrations are not execution authorities.

create table if not exists public.pandora_execution_provider_policy (
  provider text primary key,
  active boolean not null default true,
  purpose text not null,
  updated_at timestamptz not null default now(),
  constraint pandora_execution_provider_policy_provider_ck
    check (provider in ('github','supabase','vercel'))
);

alter table public.pandora_execution_provider_policy enable row level security;
revoke all on table public.pandora_execution_provider_policy
  from public, anon, authenticated;

insert into public.pandora_execution_provider_policy(provider,active,purpose)
values
  ('github',true,'canonical source, pull requests, and provider readback'),
  ('supabase',true,'database, Edge runtime, Vault, and governed provider transport'),
  ('vercel',true,'web runtime, deployments, and sandbox execution when capacity is available')
on conflict(provider) do update
set active=excluded.active,
    purpose=excluded.purpose,
    updated_at=now();

create or replace function private.pandora_assert_execution_provider_v1(p_provider text)
returns text
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_provider text := lower(trim(coalesce(p_provider,'')));
begin
  if not exists (
    select 1
    from public.pandora_execution_provider_policy
    where provider=v_provider and active=true
  ) then
    raise exception 'PANDORA_EXECUTION_PROVIDER_NOT_ALLOWED: %', v_provider
      using errcode='42501',
            hint='Allowed execution providers are GitHub, Supabase, and Vercel.';
  end if;
  return v_provider;
end;
$$;

revoke all on function private.pandora_assert_execution_provider_v1(text)
  from public, anon, authenticated;

-- ProjectOS remains only as historical schema/audit material. It has no
-- client-callable execution authority.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (
        p.proname like 'projectos_%'
        or p.proname like 'pandora_memory_release_deploy_projectos_%'
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      r.sig
    );
  end loop;
end $$;

-- Remove recurring work for retired ProjectOS and Bitbucket execution paths.
do $$
declare
  r record;
begin
  for r in
    select jobid
    from cron.job
    where lower(coalesce(jobname,'')) like '%projectos%'
       or lower(command) like '%projectos%'
       or lower(coalesce(jobname,'')) like '%bitbucket%'
       or lower(command) like '%bitbucket%'
  loop
    perform cron.unschedule(r.jobid);
  end loop;
end $$;

comment on table public.pandora_execution_provider_policy is
  'Canonical Pandora execution authority allowlist. Exactly GitHub, Supabase, and Vercel may be active execution providers.';
