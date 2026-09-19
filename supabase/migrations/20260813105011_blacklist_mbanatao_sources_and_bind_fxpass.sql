-- Owner directive: every mbanatao GitHub repository is historical evidence only.
-- Preserve provider and rollback evidence while removing operational source authority.

create table if not exists private.repository_source_policies (
  source_type text not null
    check (source_type in ('github_owner', 'github_repository')),
  source_value text not null,
  wildcard text,
  operational_status text not null
    check (operational_status in ('active', 'historical_only')),
  reason text not null,
  effective_at timestamptz not null,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (source_type, source_value),
  check (source_value = lower(source_value)),
  check (source_value ~ '^[a-z0-9_.-]+(?:/[a-z0-9_.-]+)?$')
);

comment on table private.repository_source_policies is
  'Fail-closed operational source policy. historical_only entries remain readable only for explicit provenance, recovery, and rollback evidence.';

alter table private.repository_source_policies enable row level security;
revoke all on table private.repository_source_policies from public, anon, authenticated;
grant select, insert, update, delete on table private.repository_source_policies to service_role;

insert into private.repository_source_policies (
  source_type,
  source_value,
  wildcard,
  operational_status,
  reason,
  effective_at,
  updated_at
) values (
  'github_owner',
  'mbanatao',
  'mbanatao/*',
  'historical_only',
  'Owner directive: blacklist every mbanatao repository from new work, routing, builds, releases, and current-state authority.',
  '2026-08-13T00:00:00+08:00'::timestamptz,
  timezone('utc', now())
)
on conflict (source_type, source_value) do update set
  wildcard = excluded.wildcard,
  operational_status = excluded.operational_status,
  reason = excluded.reason,
  effective_at = excluded.effective_at,
  updated_at = timezone('utc', now());

create or replace function private.enforce_repository_source_authority()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text;
begin
  if new.repository is null then
    return new;
  end if;

  v_owner := lower(split_part(new.repository, '/', 1));
  if exists (
    select 1
    from private.repository_source_policies policy
    where policy.operational_status = 'historical_only'
      and (
        (policy.source_type = 'github_owner' and policy.source_value = v_owner)
        or (
          policy.source_type = 'github_repository'
          and policy.source_value = lower(new.repository)
        )
      )
  ) then
    raise exception using
      errcode = '42501',
      message = 'repository source is historical-only and cannot be selected operationally';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_repository_source_authority() from public, anon, authenticated;
grant execute on function private.enforce_repository_source_authority() to service_role;

update public.projectos_projects
set config = config || jsonb_build_object(
      'sourceAuthority', jsonb_build_object(
        'status', 'historical_only',
        'repository', repository,
        'owner', 'mbanatao',
        'policyEffectiveDate', '2026-08-13'
      )
    ),
    repository = null,
    updated_at = timezone('utc', now())
where repository is not null
  and lower(split_part(repository, '/', 1)) = 'mbanatao';

update public.projectos_project_resources
set binding_state = 'quarantined',
    configuration = configuration || jsonb_build_object(
      'sourceAuthority', 'historical_only',
      'policyEffectiveDate', '2026-08-13'
    ),
    updated_at = timezone('utc', now())
where provider = 'github'
  and (
    lower(external_id) like 'mbanatao/%'
    or lower(coalesce(canonical_url, '')) like 'https://github.com/mbanatao/%'
  );

do $$
declare
  v_fxpass_id uuid;
  v_fong_id uuid;
begin
  select id into v_fong_id
  from public.projectos_projects
  where project_key = 'fong'
  limit 1;

  select id into v_fxpass_id
  from public.projectos_projects
  where lower(repository) = 'banataosystems/fxpass'
     or project_key = 'fxpass'
  order by case when lower(repository) = 'banataosystems/fxpass' then 0 else 1 end
  limit 1;

  if v_fxpass_id is null and v_fong_id is not null then
    insert into public.projectos_projects (
      organization_id,
      project_key,
      name,
      repository,
      workspace_path,
      status,
      objective,
      config,
      last_reconciled_at,
      created_at,
      updated_at
    )
    select
      organization_id,
      'fxpass',
      'FXPass',
      'banataosystems/fxpass',
      'projectos/projects/fxpass',
      'active',
      objective,
      jsonb_build_object(
        'sourceAuthority', jsonb_build_object(
          'status', 'active',
          'repository', 'banataosystems/fxpass',
          'replaces', 'mbanatao/fong',
          'policyEffectiveDate', '2026-08-13'
        )
      ),
      timezone('utc', now()),
      timezone('utc', now()),
      timezone('utc', now())
    from public.projectos_projects
    where id = v_fong_id
    on conflict (organization_id, project_key) do update set
      name = excluded.name,
      repository = excluded.repository,
      workspace_path = excluded.workspace_path,
      status = excluded.status,
      config = public.projectos_projects.config || excluded.config,
      last_reconciled_at = excluded.last_reconciled_at,
      updated_at = excluded.updated_at
    returning id into v_fxpass_id;
  end if;

  insert into public.projectos_project_resources (
    organization_id,
    project_id,
    provider,
    resource_type,
    external_id,
    external_name,
    environment,
    canonical_url,
    binding_state,
    configuration,
    verified_at,
    created_at,
    updated_at
  )
  select
    resource.organization_id,
    v_fxpass_id,
    resource.provider,
    resource.resource_type,
    resource.external_id,
    resource.external_name,
    resource.environment,
    resource.canonical_url,
    'verified',
    resource.configuration || jsonb_build_object(
      'sourceRepository', 'banataosystems/fxpass',
      'migratedFromProjectKey', 'fong',
      'policyEffectiveDate', '2026-08-13'
    ),
    timezone('utc', now()),
    timezone('utc', now()),
    timezone('utc', now())
  from public.projectos_project_resources resource
  where resource.project_id = v_fong_id
    and (
      (resource.provider = 'supabase' and resource.external_id = 'jhygppdcfrmejbzyozud')
      or (resource.provider = 'vercel' and resource.external_id = 'prj_t9cl0GiY9APSTw2NUNJLtRg6auwZ')
    )
  on conflict (project_id, provider, resource_type, external_id) do update set
    external_name = excluded.external_name,
    environment = excluded.environment,
    canonical_url = excluded.canonical_url,
    binding_state = excluded.binding_state,
    configuration = excluded.configuration,
    verified_at = excluded.verified_at,
    updated_at = excluded.updated_at;

  update public.projectos_project_resources
  set binding_state = 'quarantined',
      configuration = configuration || jsonb_build_object(
        'sourceAuthority', 'historical_only',
        'canonicalReplacement', 'banataosystems/fxpass',
        'policyEffectiveDate', '2026-08-13'
      ),
      updated_at = timezone('utc', now())
  where project_id = v_fong_id;

  update public.projectos_projects
  set status = 'archived',
      config = config || jsonb_build_object(
        'sourceAuthority', jsonb_build_object(
          'status', 'historical_only',
          'repository', 'mbanatao/fong',
          'canonicalReplacement', 'banataosystems/fxpass',
          'policyEffectiveDate', '2026-08-13'
        )
      ),
      updated_at = timezone('utc', now())
  where id = v_fong_id;

  if v_fxpass_id is not null then
    update public.projectos_projects
    set name = 'FXPass',
        repository = 'banataosystems/fxpass',
        status = 'active',
        config = config || jsonb_build_object(
          'sourceAuthority', jsonb_build_object(
            'status', 'active',
            'repository', 'banataosystems/fxpass',
            'replaces', 'mbanatao/fong',
            'policyEffectiveDate', '2026-08-13'
          )
        ),
        last_reconciled_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
    where id = v_fxpass_id;
  end if;
end;
$$;

alter table private.project_resource_bindings
  add column if not exists source_status text not null default 'active'
    check (source_status in ('active', 'historical_only'));

update private.project_resource_bindings
set github_access = 'read_only',
    source_status = 'historical_only',
    notes = notes || case
      when notes like '%Owner-wide source blacklist effective 2026-08-13.%' then ''
      else ' Owner-wide source blacklist effective 2026-08-13; retained for historical evidence only.'
    end,
    updated_at = timezone('utc', now())
where lower(split_part(repo_full_name, '/', 1)) = 'mbanatao';

insert into private.project_resource_bindings (
  repo_full_name,
  github_access,
  supabase_project_ref,
  supabase_project_name,
  database_binding_state,
  vercel_team_id,
  vercel_project_id,
  vercel_project_name,
  vercel_binding_state,
  canonical_domain,
  notes,
  verified_at,
  updated_at,
  source_status
)
select
  'banataosystems/fxpass',
  'read_write',
  supabase_project_ref,
  supabase_project_name,
  database_binding_state,
  vercel_team_id,
  vercel_project_id,
  vercel_project_name,
  vercel_binding_state,
  canonical_domain,
  'Canonical FXPass source and resource binding; replaces historical-only mbanatao/fong.',
  timezone('utc', now()),
  timezone('utc', now()),
  'active'
from private.project_resource_bindings
where lower(repo_full_name) = 'mbanatao/fong'
on conflict (repo_full_name) do update set
  github_access = excluded.github_access,
  supabase_project_ref = excluded.supabase_project_ref,
  supabase_project_name = excluded.supabase_project_name,
  database_binding_state = excluded.database_binding_state,
  vercel_team_id = excluded.vercel_team_id,
  vercel_project_id = excluded.vercel_project_id,
  vercel_project_name = excluded.vercel_project_name,
  vercel_binding_state = excluded.vercel_binding_state,
  canonical_domain = excluded.canonical_domain,
  notes = excluded.notes,
  verified_at = excluded.verified_at,
  updated_at = excluded.updated_at,
  source_status = excluded.source_status;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.projectos_accept_fxpass_product_intake(uuid,jsonb)'::regprocedure
  ) into v_definition;
  if v_definition is null then
    raise exception 'FXPass product intake function is missing';
  end if;
  v_definition := replace(v_definition, 'mbanatao/fong', 'banataosystems/fxpass');
  execute v_definition;
end;
$$;

revoke all on function public.projectos_accept_fxpass_product_intake(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.projectos_accept_fxpass_product_intake(uuid, jsonb) to service_role;

drop trigger if exists enforce_repository_source_authority on public.projectos_projects;
create trigger enforce_repository_source_authority
before insert or update of repository on public.projectos_projects
for each row execute function private.enforce_repository_source_authority();

