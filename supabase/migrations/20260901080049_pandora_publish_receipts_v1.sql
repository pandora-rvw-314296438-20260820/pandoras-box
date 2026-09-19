-- Evo Task 42: durable exact publish receipts and rollback provenance.
-- Captures the previous production pointer at production-deployment insertion,
-- before the runtime environment CAS switches to the new exact version.

create table if not exists public.pandora_publish_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  version_id uuid not null references public.pandora_project_versions(id) on delete restrict,
  production_deployment_id uuid not null references public.pandora_project_deployments(id) on delete restrict,
  provider text not null,
  provider_resource_id text,
  source_sha256 text,
  artifact_digest text,
  preview_verification_run_id text not null,
  production_verification_run_id text,
  previous_production_version_id uuid references public.pandora_project_versions(id) on delete restrict,
  previous_production_deployment_id uuid references public.pandora_project_deployments(id) on delete set null,
  production_result_url text,
  live_url text,
  status text not null default 'awaiting_production_verification',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_publish_receipts_status_check
    check (status in ('awaiting_production_verification','live_verified','failed','superseded')),
  constraint pandora_publish_receipts_source_check
    check (source_sha256 is null or source_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_publish_receipts_artifact_check
    check (artifact_digest is null or artifact_digest ~ '^[0-9a-f]{64}$'),
  unique (production_deployment_id)
);

create index if not exists pandora_publish_receipts_project_created_idx
  on public.pandora_publish_receipts(project_id, created_at desc);

alter table public.pandora_publish_receipts enable row level security;
revoke all on public.pandora_publish_receipts from anon, authenticated;
grant select, insert, update, delete on public.pandora_publish_receipts to service_role;

create or replace function private.pandora_capture_publish_receipt_20260901()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_previous_version_id uuid;
  v_previous_deployment_id uuid;
begin
  if new.environment <> 'production' then
    return new;
  end if;

  -- The production deployment row is written before the environment CAS update.
  -- Therefore this read is the authoritative previous-production rollback pointer.
  select e.current_version_id, e.current_deployment_id
    into v_previous_version_id, v_previous_deployment_id
  from public.pandora_runtime_environments e
  where e.organization_id = new.organization_id
    and e.project_id = new.project_id
    and e.environment = 'production'
  limit 1;

  if v_previous_version_id is null then
    select d.version_id, d.id
      into v_previous_version_id, v_previous_deployment_id
    from public.pandora_project_deployments d
    where d.organization_id = new.organization_id
      and d.project_id = new.project_id
      and d.environment = 'production'
      and d.id <> new.id
    order by d.created_at desc
    limit 1;
  end if;

  if nullif(new.verification_ref, '') is null then
    raise exception 'PUBLISH_RECEIPT_VERIFICATION_REQUIRED' using errcode = '23514';
  end if;

  insert into public.pandora_publish_receipts (
    organization_id,
    project_id,
    version_id,
    production_deployment_id,
    provider,
    provider_resource_id,
    source_sha256,
    artifact_digest,
    preview_verification_run_id,
    previous_production_version_id,
    previous_production_deployment_id,
    production_result_url,
    status
  ) values (
    new.organization_id,
    new.project_id,
    new.version_id,
    new.id,
    new.provider,
    new.provider_deployment_id,
    new.source_sha256,
    new.artifact_digest,
    new.verification_ref,
    v_previous_version_id,
    v_previous_deployment_id,
    coalesce(new.immutable_url, new.url),
    case when new.verification_state = 'live_verified'
      then 'live_verified'
      else 'awaiting_production_verification'
    end
  )
  on conflict (production_deployment_id) do nothing;

  return new;
end;
$$;

drop trigger if exists pandora_capture_publish_receipt on public.pandora_project_deployments;
create trigger pandora_capture_publish_receipt
after insert on public.pandora_project_deployments
for each row
when (new.environment = 'production')
execute function private.pandora_capture_publish_receipt_20260901();

create or replace function private.pandora_finalize_publish_receipt_20260901()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_live_url text;
begin
  if new.environment <> 'production'
     or new.verification_state <> 'live_verified'
     or old.verification_state = 'live_verified' then
    return new;
  end if;

  select nullif(p.config #>> '{customerJourney,liveUrl}', '')
    into v_live_url
  from public.projectos_projects p
  where p.id = new.project_id
    and p.organization_id = new.organization_id;

  update public.pandora_publish_receipts r
  set production_verification_run_id = new.verification_ref,
      production_result_url = coalesce(new.immutable_url, new.url, r.production_result_url),
      live_url = coalesce(v_live_url, new.url, r.production_result_url),
      status = 'live_verified',
      published_at = now(),
      updated_at = now()
  where r.organization_id = new.organization_id
    and r.project_id = new.project_id
    and r.production_deployment_id = new.id
    and r.version_id = new.version_id;

  if not found then
    raise exception 'PUBLISH_RECEIPT_MISSING' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists pandora_finalize_publish_receipt on public.pandora_project_deployments;
create trigger pandora_finalize_publish_receipt
after update of verification_state, verification_ref, url, immutable_url
on public.pandora_project_deployments
for each row
when (new.environment = 'production' and new.verification_state = 'live_verified')
execute function private.pandora_finalize_publish_receipt_20260901();

create or replace function public.pandora_get_publish_receipts(
  p_project_id uuid,
  p_limit integer default 20
)
returns table (
  receipt_id uuid,
  project_id uuid,
  version_id uuid,
  production_deployment_id uuid,
  provider text,
  provider_resource_id text,
  source_sha256 text,
  artifact_digest text,
  preview_verification_run_id text,
  production_verification_run_id text,
  previous_production_version_id uuid,
  previous_production_deployment_id uuid,
  production_result_url text,
  live_url text,
  status text,
  published_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode = '42501';
  end if;

  select p.organization_id into v_organization_id
  from public.projectos_projects p
  where p.id = p_project_id;

  if v_organization_id is null then
    raise exception 'PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = v_organization_id
      and m.user_id = v_user_id
      and m.status = 'active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  return query
  select
    r.id,
    r.project_id,
    r.version_id,
    r.production_deployment_id,
    r.provider,
    r.provider_resource_id,
    r.source_sha256,
    r.artifact_digest,
    r.preview_verification_run_id,
    r.production_verification_run_id,
    r.previous_production_version_id,
    r.previous_production_deployment_id,
    r.production_result_url,
    r.live_url,
    r.status,
    r.published_at,
    r.created_at
  from public.pandora_publish_receipts r
  where r.organization_id = v_organization_id
    and r.project_id = p_project_id
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 20), 100));
end;
$$;

revoke all on function public.pandora_get_publish_receipts(uuid, integer) from public, anon;
grant execute on function public.pandora_get_publish_receipts(uuid, integer) to authenticated, service_role;

comment on table public.pandora_publish_receipts is
  'Durable exact publish provenance: reviewed version, verification identity, production result, and previous-production rollback pointer.';
