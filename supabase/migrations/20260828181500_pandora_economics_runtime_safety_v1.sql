
-- Pandora Worker A: cost/budget, project knowledge, runtime isolation, secret-reference metadata, and database-change safety.
-- Supabase persists control-plane truth only. Provider execution and secret values remain outside these contracts.

create or replace function private.pandora_control_plane_json_has_secret_keys(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_child jsonb;
begin
  if p_value is null then return false; end if;
  if jsonb_typeof(p_value) = 'object' then
    for v_key, v_child in select key, value from jsonb_each(p_value) loop
      if lower(v_key) ~ '(password|secret|token|api[_-]?key|authorization|credential|private[_-]?key)' then return true; end if;
      if private.pandora_control_plane_json_has_secret_keys(v_child) then return true; end if;
    end loop;
  elsif jsonb_typeof(p_value) = 'array' then
    for v_child in select value from jsonb_array_elements(p_value) loop
      if private.pandora_control_plane_json_has_secret_keys(v_child) then return true; end if;
    end loop;
  end if;
  return false;
end;
$$;
revoke all on function private.pandora_control_plane_json_has_secret_keys(jsonb) from public, anon, authenticated;
grant execute on function private.pandora_control_plane_json_has_secret_keys(jsonb) to service_role;

create or replace function private.pandora_control_plane_prevent_history_mutation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin raise exception 'control-plane history is append-only' using errcode = '55000'; end; $$;
revoke all on function private.pandora_control_plane_prevent_history_mutation() from public, anon, authenticated;
grant execute on function private.pandora_control_plane_prevent_history_mutation() to service_role;

create table if not exists public.pandora_budget_limits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid null references public.pandora_project_specs(id) on delete cascade,
  build_job_id uuid null references public.pandora_build_jobs(id) on delete cascade,
  budget_kind text not null,
  scope_key text not null,
  currency text not null default 'USD',
  warning_limit_micros bigint not null default 0,
  hard_limit_micros bigint not null,
  reserved_micros bigint not null default 0,
  spent_micros bigint not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_budget_limits_kind_check check (budget_kind in ('project','build','model','verification','deployment','runtime','provider')),
  constraint pandora_budget_limits_scope_key_check check (length(trim(scope_key)) between 1 and 160),
  constraint pandora_budget_limits_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint pandora_budget_limits_amount_check check (warning_limit_micros >= 0 and hard_limit_micros >= 0 and warning_limit_micros <= hard_limit_micros and reserved_micros >= 0 and spent_micros >= 0 and reserved_micros + spent_micros <= hard_limit_micros),
  constraint pandora_budget_limits_status_check check (status in ('active','exhausted','closed')),
  constraint pandora_budget_limits_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_budget_limits_scope_uidx on public.pandora_budget_limits(organization_id, project_id, budget_kind, scope_key);
create index if not exists pandora_budget_limits_project_idx on public.pandora_budget_limits(project_id, status, budget_kind);
create index if not exists pandora_budget_limits_active_idx on public.pandora_budget_limits(organization_id, status, updated_at) where status = 'active';

create or replace function private.pandora_validate_budget_limit_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  if new.project_spec_id is not null then
    select organization_id, project_id into v_org, v_project from public.pandora_project_specs where id = new.project_spec_id;
    if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'budget ProjectSpec scope mismatch' using errcode = '23514'; end if;
  end if;
  if new.build_job_id is not null then
    select organization_id, project_id into v_org, v_project from public.pandora_build_jobs where id = new.build_job_id;
    if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'budget build job scope mismatch' using errcode = '23514'; end if;
  end if;
  if tg_op = 'UPDATE' and (new.organization_id <> old.organization_id or new.project_id <> old.project_id or new.project_spec_id is distinct from old.project_spec_id or new.build_job_id is distinct from old.build_job_id or new.budget_kind <> old.budget_kind or new.scope_key <> old.scope_key or new.currency <> old.currency or new.hard_limit_micros < old.spent_micros + old.reserved_micros) then
    raise exception 'budget scope is immutable or cannot shrink below committed usage' using errcode = '23514';
  end if;
  new.updated_at := now();
  if new.spent_micros + new.reserved_micros >= new.hard_limit_micros and new.status = 'active' then new.status := 'exhausted'; end if;
  return new;
end; $$;
drop trigger if exists pandora_budget_limits_scope_guard on public.pandora_budget_limits;
create trigger pandora_budget_limits_scope_guard before insert or update on public.pandora_budget_limits for each row execute function private.pandora_validate_budget_limit_scope();

create or replace function private.pandora_reserve_budget(p_budget_id uuid, p_amount_micros bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_amount_micros <= 0 then raise exception 'reservation amount must be positive' using errcode = '22023'; end if;
  update public.pandora_budget_limits b set reserved_micros = b.reserved_micros + p_amount_micros
   where b.id = p_budget_id and b.status = 'active' and b.reserved_micros + b.spent_micros + p_amount_micros <= b.hard_limit_micros;
  return found;
end; $$;
create or replace function private.pandora_release_budget(p_budget_id uuid, p_amount_micros bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_amount_micros <= 0 then raise exception 'release amount must be positive' using errcode = '22023'; end if;
  update public.pandora_budget_limits b
     set reserved_micros = b.reserved_micros - p_amount_micros,
         status = case when b.status = 'exhausted' and b.spent_micros + b.reserved_micros - p_amount_micros < b.hard_limit_micros then 'active' else b.status end
   where b.id = p_budget_id and b.reserved_micros >= p_amount_micros and b.status <> 'closed';
  return found;
end; $$;
create or replace function private.pandora_commit_budget(p_budget_id uuid, p_amount_micros bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_amount_micros <= 0 then raise exception 'commit amount must be positive' using errcode = '22023'; end if;
  update public.pandora_budget_limits b set reserved_micros = b.reserved_micros - p_amount_micros, spent_micros = b.spent_micros + p_amount_micros
   where b.id = p_budget_id and b.reserved_micros >= p_amount_micros and b.status <> 'closed';
  return found;
end; $$;
revoke all on function private.pandora_reserve_budget(uuid,bigint) from public, anon, authenticated;
revoke all on function private.pandora_release_budget(uuid,bigint) from public, anon, authenticated;
revoke all on function private.pandora_commit_budget(uuid,bigint) from public, anon, authenticated;
grant execute on function private.pandora_reserve_budget(uuid,bigint) to service_role;
grant execute on function private.pandora_release_budget(uuid,bigint) to service_role;
grant execute on function private.pandora_commit_budget(uuid,bigint) to service_role;

create table if not exists public.pandora_cost_entries (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid null references public.pandora_project_specs(id) on delete set null, build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,
  model_run_id uuid null references public.pandora_model_runs(id) on delete set null, tool_call_id uuid null references public.pandora_tool_calls(id) on delete set null,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null, budget_limit_id uuid null references public.pandora_budget_limits(id) on delete set null,
  cost_category text not null, provider text null, environment text null, quantity numeric(20,6) not null default 0, unit text not null default 'unit',
  estimated_cost_micros bigint not null default 0, billed_cost_micros bigint not null default 0, charged_cost_micros bigint not null default 0, credit_micros bigint not null default 0,
  currency text not null default 'USD', idempotency_key text not null, metadata_redacted jsonb not null default '{}'::jsonb, occurred_at timestamptz not null default now(), created_at timestamptz not null default now(),
  constraint pandora_cost_entries_category_check check (cost_category in ('model','build_compute','verification','deployment','runtime','storage','network','provider_api','other')),
  constraint pandora_cost_entries_environment_check check (environment is null or environment in ('development','sandbox','test','preview','production')),
  constraint pandora_cost_entries_quantity_check check (quantity >= 0),
  constraint pandora_cost_entries_amount_check check (estimated_cost_micros >= 0 and billed_cost_micros >= 0 and charged_cost_micros >= 0 and credit_micros >= 0),
  constraint pandora_cost_entries_currency_check check (currency ~ '^[A-Z]{3}$'), constraint pandora_cost_entries_idempotency_check check (length(trim(idempotency_key)) between 8 and 200),
  constraint pandora_cost_entries_metadata_check check (not private.pandora_control_plane_json_has_secret_keys(metadata_redacted)),
  constraint pandora_cost_entries_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_cost_entries_idempotency_uidx on public.pandora_cost_entries(organization_id, idempotency_key);
create index if not exists pandora_cost_entries_project_time_idx on public.pandora_cost_entries(project_id, occurred_at desc);
create index if not exists pandora_cost_entries_job_idx on public.pandora_cost_entries(build_job_id, occurred_at desc) where build_job_id is not null;
create index if not exists pandora_cost_entries_category_idx on public.pandora_cost_entries(organization_id, cost_category, occurred_at desc);

create or replace function private.pandora_validate_cost_entry_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  if new.project_spec_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_specs where id=new.project_spec_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost ProjectSpec scope mismatch' using errcode='23514'; end if; end if;
  if new.build_job_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_build_jobs where id=new.build_job_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost build job scope mismatch' using errcode='23514'; end if; end if;
  if new.model_run_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_model_runs where id=new.model_run_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost model run scope mismatch' using errcode='23514'; end if; end if;
  if new.tool_call_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_tool_calls where id=new.tool_call_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost tool call scope mismatch' using errcode='23514'; end if; end if;
  if new.project_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=new.project_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost project version scope mismatch' using errcode='23514'; end if; end if;
  if new.budget_limit_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_budget_limits where id=new.budget_limit_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'cost budget scope mismatch' using errcode='23514'; end if; end if;
  return new;
end; $$;
drop trigger if exists pandora_cost_entries_scope_guard on public.pandora_cost_entries;
create trigger pandora_cost_entries_scope_guard before insert on public.pandora_cost_entries for each row execute function private.pandora_validate_cost_entry_scope();
drop trigger if exists pandora_cost_entries_append_only on public.pandora_cost_entries;
create trigger pandora_cost_entries_append_only before update or delete on public.pandora_cost_entries for each row execute function private.pandora_control_plane_prevent_history_mutation();

create table if not exists public.pandora_project_nodes (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete cascade, node_key text not null, node_type text not null, label text not null, summary text null,
  requirement_id uuid null references public.pandora_project_requirements(id) on delete set null, artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete set null,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null, status text not null default 'active', provenance_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pandora_project_nodes_key_check check (length(trim(node_key)) between 1 and 160),
  constraint pandora_project_nodes_type_check check (node_type in ('feature','workflow','page','entity','integration','runtime_component','acceptance','business_objective','other')),
  constraint pandora_project_nodes_status_check check (status in ('active','superseded','removed')),
  constraint pandora_project_nodes_provenance_check check (not private.pandora_control_plane_json_has_secret_keys(provenance_redacted)),
  constraint pandora_project_nodes_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_project_nodes_key_uidx on public.pandora_project_nodes(project_spec_id, node_key);
create index if not exists pandora_project_nodes_project_type_idx on public.pandora_project_nodes(project_id, node_type, status);
create index if not exists pandora_project_nodes_requirement_idx on public.pandora_project_nodes(requirement_id) where requirement_id is not null;

create or replace function private.pandora_validate_project_node_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  select organization_id,project_id into v_org,v_project from public.pandora_project_specs where id=new.project_spec_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project node ProjectSpec scope mismatch' using errcode='23514'; end if;
  if new.requirement_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_requirements where id=new.requirement_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project node requirement scope mismatch' using errcode='23514'; end if; end if;
  if new.artifact_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifact_versions where id=new.artifact_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project node artifact scope mismatch' using errcode='23514'; end if; end if;
  if new.project_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=new.project_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project node version scope mismatch' using errcode='23514'; end if; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id or new.node_key<>old.node_key or new.node_type<>old.node_type) then raise exception 'project node identity is immutable' using errcode='23514'; end if;
  new.updated_at:=now(); return new;
end; $$;
drop trigger if exists pandora_project_nodes_scope_guard on public.pandora_project_nodes;
create trigger pandora_project_nodes_scope_guard before insert or update on public.pandora_project_nodes for each row execute function private.pandora_validate_project_node_scope();

create table if not exists public.pandora_project_relationships (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete cascade, from_node_id uuid not null references public.pandora_project_nodes(id) on delete cascade,
  to_node_id uuid not null references public.pandora_project_nodes(id) on delete cascade, relationship_type text not null,
  requirement_id uuid null references public.pandora_project_requirements(id) on delete set null, artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete set null,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null, status text not null default 'active', metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pandora_project_relationships_type_check check (relationship_type in ('depends_on','implements','uses','reads','writes','navigates_to','integrates_with','verified_by','produces','consumes','supersedes','other')),
  constraint pandora_project_relationships_nodes_check check (from_node_id <> to_node_id), constraint pandora_project_relationships_status_check check (status in ('active','superseded','removed')),
  constraint pandora_project_relationships_metadata_check check (not private.pandora_control_plane_json_has_secret_keys(metadata_redacted)),
  constraint pandora_project_relationships_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_project_relationships_edge_uidx on public.pandora_project_relationships(project_spec_id, from_node_id, to_node_id, relationship_type);
create index if not exists pandora_project_relationships_from_idx on public.pandora_project_relationships(from_node_id, relationship_type, status);
create index if not exists pandora_project_relationships_to_idx on public.pandora_project_relationships(to_node_id, relationship_type, status);

create or replace function private.pandora_validate_project_relationship_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid; v_spec uuid;
begin
  select organization_id,project_id,project_spec_id into v_org,v_project,v_spec from public.pandora_project_nodes where id=new.from_node_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id or v_spec<>new.project_spec_id then raise exception 'relationship source node scope mismatch' using errcode='23514'; end if;
  select organization_id,project_id,project_spec_id into v_org,v_project,v_spec from public.pandora_project_nodes where id=new.to_node_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id or v_spec<>new.project_spec_id then raise exception 'relationship target node scope mismatch' using errcode='23514'; end if;
  if new.requirement_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_requirements where id=new.requirement_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'relationship requirement scope mismatch' using errcode='23514'; end if; end if;
  if new.artifact_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifact_versions where id=new.artifact_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'relationship artifact scope mismatch' using errcode='23514'; end if; end if;
  if new.project_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=new.project_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'relationship version scope mismatch' using errcode='23514'; end if; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id or new.from_node_id<>old.from_node_id or new.to_node_id<>old.to_node_id or new.relationship_type<>old.relationship_type) then raise exception 'project relationship identity is immutable' using errcode='23514'; end if;
  new.updated_at:=now(); return new;
end; $$;
drop trigger if exists pandora_project_relationships_scope_guard on public.pandora_project_relationships;
create trigger pandora_project_relationships_scope_guard before insert or update on public.pandora_project_relationships for each row execute function private.pandora_validate_project_relationship_scope();

create table if not exists public.pandora_runtime_resources (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null, project_resource_id uuid null references public.projectos_project_resources(id) on delete set null,
  resource_type text not null, provider text not null, environment text not null, isolation_mode text not null, external_ref text not null, region text null, status text not null default 'planned',
  configuration_redacted jsonb not null default '{}'::jsonb, provisioned_at timestamptz null, verified_at timestamptz null, retired_at timestamptz null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pandora_runtime_resources_type_check check (resource_type in ('database','storage','auth','edge_function','web_runtime','mobile_backend','cache','queue','search','analytics','domain','other')),
  constraint pandora_runtime_resources_environment_check check (environment in ('development','sandbox','test','preview','production')),
  constraint pandora_runtime_resources_isolation_check check (isolation_mode in ('dedicated','shared_isolated','logical')),
  constraint pandora_runtime_resources_ref_check check (length(trim(external_ref)) between 1 and 500),
  constraint pandora_runtime_resources_status_check check (status in ('planned','provisioning','ready','degraded','failed','retiring','retired')),
  constraint pandora_runtime_resources_config_check check (not private.pandora_control_plane_json_has_secret_keys(configuration_redacted)),
  constraint pandora_runtime_resources_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_runtime_resources_external_uidx on public.pandora_runtime_resources(organization_id, provider, environment, resource_type, external_ref);
create index if not exists pandora_runtime_resources_project_idx on public.pandora_runtime_resources(project_id, environment, resource_type, status);
create index if not exists pandora_runtime_resources_version_idx on public.pandora_runtime_resources(project_version_id, environment) where project_version_id is not null;

create or replace function private.pandora_validate_runtime_resource_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid; v_provider text; v_external text;
begin
  if new.project_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=new.project_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'runtime resource version scope mismatch' using errcode='23514'; end if; end if;
  if new.project_resource_id is not null then
    select organization_id,project_id,provider,external_id into v_org,v_project,v_provider,v_external from public.projectos_project_resources where id=new.project_resource_id;
    if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'runtime resource ProjectOS binding scope mismatch' using errcode='23514'; end if;
    if lower(v_provider)<>lower(new.provider) or v_external<>new.external_ref then raise exception 'runtime resource ProjectOS binding identity mismatch' using errcode='23514'; end if;
  end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.provider<>old.provider or new.environment<>old.environment or new.resource_type<>old.resource_type or new.external_ref<>old.external_ref or new.isolation_mode<>old.isolation_mode) then raise exception 'runtime resource identity/isolation is immutable' using errcode='23514'; end if;
  new.updated_at:=now(); if new.status='ready' and new.verified_at is null then new.verified_at:=now(); end if; if new.status='retired' and new.retired_at is null then new.retired_at:=now(); end if; return new;
end; $$;
drop trigger if exists pandora_runtime_resources_scope_guard on public.pandora_runtime_resources;
create trigger pandora_runtime_resources_scope_guard before insert or update on public.pandora_runtime_resources for each row execute function private.pandora_validate_runtime_resource_scope();

create table if not exists public.pandora_secret_references (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  runtime_resource_id uuid null references public.pandora_runtime_resources(id) on delete set null, provider text not null, environment text not null, secret_name text not null, purpose text not null,
  scope_labels text[] not null default '{}'::text[], reference_kind text not null, reference_locator text not null, version_label text null, rotation_status text not null default 'current',
  last_rotated_at timestamptz null, last_used_at timestamptz null, revoked_at timestamptz null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pandora_secret_references_environment_check check (environment in ('development','sandbox','test','preview','production')),
  constraint pandora_secret_references_name_check check (secret_name ~ '^[A-Za-z][A-Za-z0-9_.-]{0,159}$'),
  constraint pandora_secret_references_kind_check check (reference_kind in ('supabase_vault','provider_secret','environment_binding','external_vault')),
  constraint pandora_secret_references_locator_check check (reference_locator ~ '^(vault|provider|env|external):[A-Za-z0-9._:/-]{1,480}$'),
  constraint pandora_secret_references_rotation_check check (rotation_status in ('current','rotation_due','rotating','revoked')),
  constraint pandora_secret_references_revoked_check check ((rotation_status = 'revoked') = (revoked_at is not null)),
  constraint pandora_secret_references_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_secret_references_name_uidx on public.pandora_secret_references(project_id, provider, environment, secret_name);
create index if not exists pandora_secret_references_rotation_idx on public.pandora_secret_references(organization_id, rotation_status, updated_at);

create or replace function private.pandora_validate_secret_reference_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  if new.runtime_resource_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_runtime_resources where id=new.runtime_resource_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'secret reference runtime scope mismatch' using errcode='23514'; end if; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.provider<>old.provider or new.environment<>old.environment or new.secret_name<>old.secret_name or new.reference_kind<>old.reference_kind or new.reference_locator<>old.reference_locator) then raise exception 'secret reference identity is immutable' using errcode='23514'; end if;
  new.updated_at:=now(); return new;
end; $$;
drop trigger if exists pandora_secret_references_scope_guard on public.pandora_secret_references;
create trigger pandora_secret_references_scope_guard before insert or update on public.pandora_secret_references for each row execute function private.pandora_validate_secret_reference_scope();

create table if not exists public.pandora_database_change_plans (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict, project_version_id uuid null references public.pandora_project_versions(id) on delete set null,
  build_job_id uuid null references public.pandora_build_jobs(id) on delete set null, target_runtime_resource_id uuid not null references public.pandora_runtime_resources(id) on delete restrict,
  environment text not null, status text not null default 'planned', migration_set_sha256 text not null, schema_before_sha256 text not null, schema_after_sha256 text not null,
  schema_diff_sha256 text not null, action_hash text not null, destructive_change boolean not null default false, backward_compatible boolean not null default true,
  lock_risk text not null default 'low', approval_required boolean not null default false, approval_id uuid null references public.approvals(id) on delete restrict,
  migration_artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete restrict, backup_artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete restrict,
  rollback_plan_sha256 text null, execution_tool_call_id uuid null references public.pandora_tool_calls(id) on delete set null, verification_run_id uuid null references public.pandora_verification_runs(id) on delete set null,
  idempotency_key text not null, public_summary text null, created_at timestamptz not null default now(), approved_at timestamptz null, started_at timestamptz null, applied_at timestamptz null,
  verified_at timestamptz null, rolled_back_at timestamptz null, updated_at timestamptz not null default now(),
  constraint pandora_database_change_plans_environment_check check (environment in ('development','sandbox','test','preview','production')),
  constraint pandora_database_change_plans_status_check check (status in ('planned','reviewed','approved','executing','applied','verified','failed','rolled_back','cancelled')),
  constraint pandora_database_change_plans_digest_check check (migration_set_sha256 ~ '^[0-9a-f]{64}$' and schema_before_sha256 ~ '^[0-9a-f]{64}$' and schema_after_sha256 ~ '^[0-9a-f]{64}$' and schema_diff_sha256 ~ '^[0-9a-f]{64}$' and action_hash ~ '^[0-9a-f]{64}$' and (rollback_plan_sha256 is null or rollback_plan_sha256 ~ '^[0-9a-f]{64}$')),
  constraint pandora_database_change_plans_lock_risk_check check (lock_risk in ('none','low','medium','high')),
  constraint pandora_database_change_plans_destructive_approval_check check (not destructive_change or approval_required),
  constraint pandora_database_change_plans_production_approval_check check (environment <> 'production' or approval_required),
  constraint pandora_database_change_plans_idempotency_check check (length(trim(idempotency_key)) between 8 and 200),
  constraint pandora_database_change_plans_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_database_change_plans_idempotency_uidx on public.pandora_database_change_plans(organization_id, project_id, idempotency_key);
create index if not exists pandora_database_change_plans_project_idx on public.pandora_database_change_plans(project_id, created_at desc);
create index if not exists pandora_database_change_plans_pending_idx on public.pandora_database_change_plans(organization_id, status, created_at) where status in ('planned','reviewed','approved','executing','applied');

create or replace function private.pandora_validate_database_change_plan()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid; v_kind text; v_environment text; v_hash text; v_decision text; v_expires timestamptz; v_status text; v_action_hash text; v_verify_status text;
begin
  select organization_id,project_id into v_org,v_project from public.pandora_project_specs where id=new.project_spec_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan ProjectSpec scope mismatch' using errcode='23514'; end if;
  select organization_id,project_id,resource_type,environment into v_org,v_project,v_kind,v_environment from public.pandora_runtime_resources where id=new.target_runtime_resource_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id or v_kind<>'database' or v_environment<>new.environment then raise exception 'database plan target runtime mismatch' using errcode='23514'; end if;
  if new.project_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=new.project_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan version scope mismatch' using errcode='23514'; end if; end if;
  if new.build_job_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_build_jobs where id=new.build_job_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan build job scope mismatch' using errcode='23514'; end if; end if;
  if new.migration_artifact_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifact_versions where id=new.migration_artifact_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan migration artifact scope mismatch' using errcode='23514'; end if; end if;
  if new.backup_artifact_version_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifact_versions where id=new.backup_artifact_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan backup artifact scope mismatch' using errcode='23514'; end if; end if;
  if new.approval_id is not null then select organization_id,action_hash,decision::text,expires_at into v_org,v_hash,v_decision,v_expires from public.approvals where id=new.approval_id; if v_org is null or v_org<>new.organization_id or v_hash<>new.action_hash then raise exception 'database plan approval action hash mismatch' using errcode='23514'; end if; end if;
  if new.execution_tool_call_id is not null then select organization_id,project_id,action_hash,status into v_org,v_project,v_action_hash,v_status from public.pandora_tool_calls where id=new.execution_tool_call_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id or v_action_hash<>new.action_hash then raise exception 'database plan execution tool binding mismatch' using errcode='23514'; end if; end if;
  if new.verification_run_id is not null then select organization_id,project_id,status into v_org,v_project,v_verify_status from public.pandora_verification_runs where id=new.verification_run_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database plan verification scope mismatch' using errcode='23514'; end if; if new.status='verified' and v_verify_status<>'PASS' then raise exception 'verified database plan requires PASS verification' using errcode='23514'; end if; elsif new.status='verified' then raise exception 'verified database plan requires verification_run_id' using errcode='23514'; end if;
  if new.status in ('approved','executing','applied','verified') and new.approval_required then if new.approval_id is null or v_decision<>'approved' or v_expires<=now() then raise exception 'database plan requires live approved action-bound approval' using errcode='23514'; end if; end if;
  if new.status in ('executing','applied','verified') and (new.destructive_change or new.environment='production') then if new.backup_artifact_version_id is null or new.rollback_plan_sha256 is null then raise exception 'destructive or production database execution requires backup and rollback plan' using errcode='23514'; end if; end if;
  if new.status in ('executing','applied','verified') and new.execution_tool_call_id is null then raise exception 'database execution requires bound tool-call lineage' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id or new.target_runtime_resource_id<>old.target_runtime_resource_id or new.environment<>old.environment or new.migration_set_sha256<>old.migration_set_sha256 or new.schema_before_sha256<>old.schema_before_sha256 or new.schema_after_sha256<>old.schema_after_sha256 or new.schema_diff_sha256<>old.schema_diff_sha256 or new.action_hash<>old.action_hash or new.idempotency_key<>old.idempotency_key then raise exception 'database change plan identity is immutable' using errcode='23514'; end if;
    if new.status is distinct from old.status then
      v_status:=old.status||'>'||new.status;
      if v_status not in ('planned>reviewed','planned>cancelled','reviewed>approved','reviewed>cancelled','approved>executing','approved>cancelled','executing>applied','executing>failed','applied>verified','applied>failed','applied>rolled_back','failed>rolled_back','verified>rolled_back') then raise exception 'invalid database change state transition %',v_status using errcode='23514'; end if;
    end if;
  end if;
  if new.status='approved' and new.approved_at is null then new.approved_at:=now(); end if; if new.status='executing' and new.started_at is null then new.started_at:=now(); end if; if new.status='applied' and new.applied_at is null then new.applied_at:=now(); end if; if new.status='verified' and new.verified_at is null then new.verified_at:=now(); end if; if new.status='rolled_back' and new.rolled_back_at is null then new.rolled_back_at:=now(); end if;
  new.updated_at:=now(); return new;
end; $$;
drop trigger if exists pandora_database_change_plans_guard on public.pandora_database_change_plans;
create trigger pandora_database_change_plans_guard before insert or update on public.pandora_database_change_plans for each row execute function private.pandora_validate_database_change_plan();

create table if not exists public.pandora_database_change_items (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade,
  database_change_plan_id uuid not null references public.pandora_database_change_plans(id) on delete cascade, sequence integer not null, change_kind text not null, object_type text not null,
  object_name_sha256 text not null, destructive boolean not null default false, backward_compatible boolean not null default true, risk text not null default 'low', public_summary text null, created_at timestamptz not null default now(),
  constraint pandora_database_change_items_sequence_check check (sequence >= 0), constraint pandora_database_change_items_kind_check check (change_kind in ('create','alter','drop','rename','data_backfill','index','policy','function','trigger','other')),
  constraint pandora_database_change_items_name_hash_check check (object_name_sha256 ~ '^[0-9a-f]{64}$'), constraint pandora_database_change_items_risk_check check (risk in ('none','low','medium','high','critical'))
);
create unique index if not exists pandora_database_change_items_sequence_uidx on public.pandora_database_change_items(database_change_plan_id, sequence);
create index if not exists pandora_database_change_items_risk_idx on public.pandora_database_change_items(database_change_plan_id, destructive, risk);
create or replace function private.pandora_validate_database_change_item_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin select organization_id,project_id into v_org,v_project from public.pandora_database_change_plans where id=new.database_change_plan_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'database change item plan scope mismatch' using errcode='23514'; end if; return new; end; $$;
drop trigger if exists pandora_database_change_items_scope_guard on public.pandora_database_change_items;
create trigger pandora_database_change_items_scope_guard before insert on public.pandora_database_change_items for each row execute function private.pandora_validate_database_change_item_scope();
drop trigger if exists pandora_database_change_items_append_only on public.pandora_database_change_items;
create trigger pandora_database_change_items_append_only before update or delete on public.pandora_database_change_items for each row execute function private.pandora_control_plane_prevent_history_mutation();

do $worker_a_rls$
declare v_table text;
begin
  foreach v_table in array array['pandora_budget_limits','pandora_cost_entries','pandora_project_nodes','pandora_project_relationships','pandora_runtime_resources','pandora_database_change_plans','pandora_database_change_items'] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('drop policy if exists %I on public.%I',v_table||'_member_read',v_table);
    execute format('create policy %I on public.%I for select to authenticated using (private.is_org_member(organization_id))',v_table||'_member_read',v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated',v_table);
    execute format('grant select on table public.%I to authenticated',v_table);
    execute format('grant select, insert, update on table public.%I to service_role',v_table);
  end loop;
end; $worker_a_rls$;
alter table public.pandora_secret_references enable row level security;
revoke all on table public.pandora_secret_references from public, anon, authenticated;
grant select, insert, update, delete on table public.pandora_secret_references to service_role;

comment on table public.pandora_cost_entries is 'Append-only canonical Worker A project cost ledger; no provider execution.';
comment on table public.pandora_budget_limits is 'Service-owned bounded project/job/model/runtime spending limits with atomic reservation.';
comment on table public.pandora_project_nodes is 'Queryable project knowledge graph nodes bound to one immutable ProjectSpec.';
comment on table public.pandora_runtime_resources is 'Generated-application runtime isolation metadata only; no runtime execution.';
comment on table public.pandora_secret_references is 'Secret reference metadata only. Never stores plaintext credential values.';
comment on table public.pandora_database_change_plans is 'Durable database change safety state; execution remains in governed Tool Gateway/runtime workers.';
