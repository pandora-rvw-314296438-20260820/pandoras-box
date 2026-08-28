-- Pandora Worker A: canonical customer intent and ProjectSpec contracts.
-- Supabase is the durable control plane/system of record; model/provider execution stays outside this schema.

create or replace function private.pandora_control_plane_project_org_matches(
  p_organization_id uuid,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.projectos_projects p
    where p.id = p_project_id
      and p.organization_id = p_organization_id
  );
$$;

revoke all on function private.pandora_control_plane_project_org_matches(uuid, uuid) from public;
grant execute on function private.pandora_control_plane_project_org_matches(uuid, uuid) to authenticated, service_role;

create table if not exists public.pandora_project_intents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  requester_id uuid null references auth.users(id) on delete set null,
  intent_kind text not null default 'build',
  intent_text text not null,
  normalized_summary text null,
  source text not null default 'customer',
  source_reference text null,
  idempotency_key text not null,
  provenance jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint pandora_project_intents_kind_check
    check (intent_kind in ('create', 'build', 'change', 'repair', 'verify', 'preview', 'publish', 'rollback', 'other')),
  constraint pandora_project_intents_source_check
    check (source in ('customer', 'pandora', 'import', 'api')),
  constraint pandora_project_intents_text_check
    check (length(trim(intent_text)) between 1 and 50000),
  constraint pandora_project_intents_idempotency_check
    check (length(trim(idempotency_key)) between 8 and 200),
  constraint pandora_project_intents_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);

create unique index if not exists pandora_project_intents_idempotency_uidx
  on public.pandora_project_intents(organization_id, project_id, idempotency_key);
create index if not exists pandora_project_intents_project_received_idx
  on public.pandora_project_intents(project_id, received_at desc);

create table if not exists public.pandora_project_specs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  version integer not null,
  status text not null default 'active',
  source_intent_id uuid not null references public.pandora_project_intents(id) on delete restrict,
  previous_spec_id uuid null references public.pandora_project_specs(id) on delete restrict,
  schema_version text not null default '1.0.0',
  project_type text not null,
  target_user_summary text null,
  business_summary text null,
  product_scope jsonb not null default '{}'::jsonb,
  data_scope jsonb not null default '{}'::jsonb,
  integration_scope jsonb not null default '{}'::jsonb,
  experience_scope jsonb not null default '{}'::jsonb,
  deployment_scope jsonb not null default '{}'::jsonb,
  acceptance_scope jsonb not null default '{}'::jsonb,
  compiler_provider text null,
  compiler_model text null,
  compiler_version text null,
  compiler_provenance jsonb not null default '{}'::jsonb,
  content_sha256 text not null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  superseded_at timestamptz null,
  constraint pandora_project_specs_version_check check (version > 0),
  constraint pandora_project_specs_status_check
    check (status in ('draft', 'active', 'superseded', 'rejected')),
  constraint pandora_project_specs_schema_version_check
    check (schema_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint pandora_project_specs_project_type_check
    check (length(trim(project_type)) between 1 and 100),
  constraint pandora_project_specs_sha_check
    check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_project_specs_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  constraint pandora_project_specs_superseded_time_check
    check ((status = 'superseded') = (superseded_at is not null))
);

create unique index if not exists pandora_project_specs_project_version_uidx
  on public.pandora_project_specs(project_id, version);
create unique index if not exists pandora_project_specs_one_active_uidx
  on public.pandora_project_specs(project_id)
  where status = 'active';
create index if not exists pandora_project_specs_project_created_idx
  on public.pandora_project_specs(project_id, created_at desc);
create index if not exists pandora_project_specs_source_intent_idx
  on public.pandora_project_specs(source_intent_id);

create or replace function private.pandora_validate_project_spec_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_intent_org uuid;
  v_intent_project uuid;
  v_previous_org uuid;
  v_previous_project uuid;
  v_previous_version integer;
begin
  select i.organization_id, i.project_id
    into v_intent_org, v_intent_project
  from public.pandora_project_intents i
  where i.id = new.source_intent_id;

  if v_intent_project is null
     or v_intent_org <> new.organization_id
     or v_intent_project <> new.project_id then
    raise exception 'ProjectSpec source intent must belong to the same organization/project'
      using errcode = '23514';
  end if;

  if new.version = 1 then
    if new.previous_spec_id is not null then
      raise exception 'ProjectSpec version 1 cannot have a previous spec'
        using errcode = '23514';
    end if;
  else
    if new.previous_spec_id is null then
      raise exception 'ProjectSpec version > 1 requires previous_spec_id'
        using errcode = '23514';
    end if;

    select s.organization_id, s.project_id, s.version
      into v_previous_org, v_previous_project, v_previous_version
    from public.pandora_project_specs s
    where s.id = new.previous_spec_id;

    if v_previous_project is null
       or v_previous_org <> new.organization_id
       or v_previous_project <> new.project_id
       or v_previous_version <> new.version - 1 then
      raise exception 'ProjectSpec previous_spec_id must be the immediately preceding version in the same project'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.pandora_validate_project_spec_lineage() from public;

drop trigger if exists pandora_project_specs_lineage_guard on public.pandora_project_specs;
create trigger pandora_project_specs_lineage_guard
before insert on public.pandora_project_specs
for each row execute function private.pandora_validate_project_spec_lineage();

create or replace function private.pandora_guard_project_spec_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id <> old.id
     or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id
     or new.version <> old.version
     or new.source_intent_id <> old.source_intent_id
     or new.previous_spec_id is distinct from old.previous_spec_id
     or new.schema_version <> old.schema_version
     or new.project_type <> old.project_type
     or new.target_user_summary is distinct from old.target_user_summary
     or new.business_summary is distinct from old.business_summary
     or new.product_scope <> old.product_scope
     or new.data_scope <> old.data_scope
     or new.integration_scope <> old.integration_scope
     or new.experience_scope <> old.experience_scope
     or new.deployment_scope <> old.deployment_scope
     or new.acceptance_scope <> old.acceptance_scope
     or new.compiler_provider is distinct from old.compiler_provider
     or new.compiler_model is distinct from old.compiler_model
     or new.compiler_version is distinct from old.compiler_version
     or new.compiler_provenance <> old.compiler_provenance
     or new.content_sha256 <> old.content_sha256
     or new.created_by is distinct from old.created_by
     or new.created_at <> old.created_at then
    raise exception 'ProjectSpec content is immutable; create a new version'
      using errcode = '55000';
  end if;

  if old.status = 'draft' and new.status in ('active', 'rejected') then
    null;
  elsif old.status = 'active' and new.status = 'superseded' and new.superseded_at is not null then
    null;
  elsif old.status = new.status and old.superseded_at is not distinct from new.superseded_at then
    null;
  else
    raise exception 'invalid ProjectSpec status transition'
      using errcode = '55000';
  end if;

  if new.status <> 'superseded' and new.superseded_at is not null then
    raise exception 'superseded_at is only valid for superseded ProjectSpecs'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.pandora_guard_project_spec_update() from public;

drop trigger if exists pandora_project_specs_update_guard on public.pandora_project_specs;
create trigger pandora_project_specs_update_guard
before update on public.pandora_project_specs
for each row execute function private.pandora_guard_project_spec_update();

create or replace function private.pandora_reject_immutable_control_plane_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'control-plane history is append-only; create a new version/record'
    using errcode = '55000';
end;
$$;

revoke all on function private.pandora_reject_immutable_control_plane_mutation() from public;

drop trigger if exists pandora_project_intents_update_guard on public.pandora_project_intents;
create trigger pandora_project_intents_update_guard
before update or delete on public.pandora_project_intents
for each row execute function private.pandora_reject_immutable_control_plane_mutation();

drop trigger if exists pandora_project_specs_delete_guard on public.pandora_project_specs;
create trigger pandora_project_specs_delete_guard
before delete on public.pandora_project_specs
for each row execute function private.pandora_reject_immutable_control_plane_mutation();

create table if not exists public.pandora_project_business_objectives (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  ordinal integer not null default 1,
  objective text not null,
  desired_outcome text null,
  success_metric text null,
  baseline text null,
  target text null,
  provenance jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint pandora_project_business_objectives_ordinal_check check (ordinal > 0),
  constraint pandora_project_business_objectives_objective_check check (length(trim(objective)) between 1 and 5000),
  constraint pandora_project_business_objectives_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  unique (project_spec_id, ordinal)
);

create table if not exists public.pandora_project_requirements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  source_intent_id uuid null references public.pandora_project_intents(id) on delete restrict,
  requirement_key text not null,
  category text not null,
  priority text not null default 'must',
  statement text not null,
  details jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint pandora_project_requirements_category_check
    check (category in ('business', 'product', 'data', 'integration', 'experience', 'deployment', 'acceptance', 'security', 'operations')),
  constraint pandora_project_requirements_priority_check
    check (priority in ('must', 'should', 'could', 'wont')),
  constraint pandora_project_requirements_key_check check (length(trim(requirement_key)) between 1 and 160),
  constraint pandora_project_requirements_statement_check check (length(trim(statement)) between 1 and 10000),
  constraint pandora_project_requirements_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  unique (project_spec_id, requirement_key)
);

create table if not exists public.pandora_project_constraints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  source_intent_id uuid null references public.pandora_project_intents(id) on delete restrict,
  constraint_key text not null,
  constraint_type text not null default 'product',
  severity text not null default 'required',
  statement text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint pandora_project_constraints_type_check
    check (constraint_type in ('business', 'product', 'technical', 'data', 'security', 'legal', 'brand', 'accessibility', 'deployment', 'budget', 'timeline', 'other')),
  constraint pandora_project_constraints_severity_check
    check (severity in ('required', 'preferred', 'advisory')),
  constraint pandora_project_constraints_key_check check (length(trim(constraint_key)) between 1 and 160),
  constraint pandora_project_constraints_statement_check check (length(trim(statement)) between 1 and 10000),
  constraint pandora_project_constraints_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  unique (project_spec_id, constraint_key)
);

create table if not exists public.pandora_project_acceptance_criteria (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  requirement_id uuid null references public.pandora_project_requirements(id) on delete restrict,
  criterion_key text not null,
  criterion text not null,
  test_kind text not null default 'acceptance',
  required boolean not null default true,
  provenance jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint pandora_project_acceptance_key_check check (length(trim(criterion_key)) between 1 and 160),
  constraint pandora_project_acceptance_criterion_check check (length(trim(criterion)) between 1 and 10000),
  constraint pandora_project_acceptance_test_kind_check
    check (test_kind in ('manual', 'unit', 'integration', 'e2e', 'visual', 'accessibility', 'security', 'migration', 'runtime', 'acceptance', 'business')),
  constraint pandora_project_acceptance_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  unique (project_spec_id, criterion_key)
);

create or replace function private.pandora_validate_spec_child_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec_org uuid;
  v_spec_project uuid;
  v_intent_org uuid;
  v_intent_project uuid;
  v_req_org uuid;
  v_req_project uuid;
  v_req_spec uuid;
begin
  select s.organization_id, s.project_id
    into v_spec_org, v_spec_project
  from public.pandora_project_specs s
  where s.id = new.project_spec_id;

  if v_spec_project is null
     or v_spec_org <> new.organization_id
     or v_spec_project <> new.project_id then
    raise exception 'ProjectSpec child must belong to the same organization/project'
      using errcode = '23514';
  end if;

  if tg_table_name in ('pandora_project_requirements', 'pandora_project_constraints')
     and new.source_intent_id is not null then
    select i.organization_id, i.project_id
      into v_intent_org, v_intent_project
    from public.pandora_project_intents i
    where i.id = new.source_intent_id;
    if v_intent_project is null
       or v_intent_org <> new.organization_id
       or v_intent_project <> new.project_id then
      raise exception 'source intent must belong to the same organization/project'
        using errcode = '23514';
    end if;
  end if;

  if tg_table_name = 'pandora_project_acceptance_criteria'
     and new.requirement_id is not null then
    select r.organization_id, r.project_id, r.project_spec_id
      into v_req_org, v_req_project, v_req_spec
    from public.pandora_project_requirements r
    where r.id = new.requirement_id;
    if v_req_project is null
       or v_req_org <> new.organization_id
       or v_req_project <> new.project_id
       or v_req_spec <> new.project_spec_id then
      raise exception 'acceptance criterion requirement must belong to the same ProjectSpec'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.pandora_validate_spec_child_lineage() from public;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pandora_project_business_objectives',
    'pandora_project_requirements',
    'pandora_project_constraints',
    'pandora_project_acceptance_criteria'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', v_table || '_lineage_guard', v_table);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function private.pandora_validate_spec_child_lineage()',
      v_table || '_lineage_guard',
      v_table
    );
    execute format('drop trigger if exists %I on public.%I', v_table || '_immutable_guard', v_table);
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function private.pandora_reject_immutable_control_plane_mutation()',
      v_table || '_immutable_guard',
      v_table
    );
  end loop;
end
$$;

create index if not exists pandora_project_objectives_project_spec_idx
  on public.pandora_project_business_objectives(project_id, project_spec_id, ordinal);
create index if not exists pandora_project_requirements_project_spec_idx
  on public.pandora_project_requirements(project_id, project_spec_id, category, priority);
create index if not exists pandora_project_constraints_project_spec_idx
  on public.pandora_project_constraints(project_id, project_spec_id, constraint_type);
create index if not exists pandora_project_acceptance_project_spec_idx
  on public.pandora_project_acceptance_criteria(project_id, project_spec_id, required);

alter table public.projectos_decisions
  add column if not exists project_spec_id uuid null references public.pandora_project_specs(id) on delete restrict,
  add column if not exists source_intent_id uuid null references public.pandora_project_intents(id) on delete restrict,
  add column if not exists provenance jsonb not null default '{}'::jsonb;

create index if not exists projectos_decisions_project_spec_idx
  on public.projectos_decisions(project_id, project_spec_id)
  where project_spec_id is not null;
create index if not exists projectos_decisions_source_intent_idx
  on public.projectos_decisions(project_id, source_intent_id)
  where source_intent_id is not null;

create or replace function private.pandora_validate_projectos_decision_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec_org uuid;
  v_spec_project uuid;
  v_intent_org uuid;
  v_intent_project uuid;
begin
  if new.project_spec_id is not null then
    select s.organization_id, s.project_id
      into v_spec_org, v_spec_project
    from public.pandora_project_specs s
    where s.id = new.project_spec_id;
    if v_spec_project is null
       or v_spec_org <> new.organization_id
       or v_spec_project <> new.project_id then
      raise exception 'decision ProjectSpec must belong to the same organization/project'
        using errcode = '23514';
    end if;
  end if;

  if new.source_intent_id is not null then
    select i.organization_id, i.project_id
      into v_intent_org, v_intent_project
    from public.pandora_project_intents i
    where i.id = new.source_intent_id;
    if v_intent_project is null
       or v_intent_org <> new.organization_id
       or v_intent_project <> new.project_id then
      raise exception 'decision source intent must belong to the same organization/project'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.pandora_validate_projectos_decision_lineage() from public;

drop trigger if exists projectos_decisions_pandora_lineage_guard on public.projectos_decisions;
create trigger projectos_decisions_pandora_lineage_guard
before insert or update of project_spec_id, source_intent_id on public.projectos_decisions
for each row execute function private.pandora_validate_projectos_decision_lineage();

alter table public.pandora_project_intents enable row level security;
alter table public.pandora_project_specs enable row level security;
alter table public.pandora_project_business_objectives enable row level security;
alter table public.pandora_project_requirements enable row level security;
alter table public.pandora_project_constraints enable row level security;
alter table public.pandora_project_acceptance_criteria enable row level security;

drop policy if exists pandora_project_intents_member_read on public.pandora_project_intents;
create policy pandora_project_intents_member_read
  on public.pandora_project_intents
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_intents_member_insert on public.pandora_project_intents;
create policy pandora_project_intents_member_insert
  on public.pandora_project_intents
  for insert
  to authenticated
  with check (
    private.is_org_member(organization_id)
    and requester_id = auth.uid()
    and source = 'customer'
  );

drop policy if exists pandora_project_specs_member_read on public.pandora_project_specs;
create policy pandora_project_specs_member_read
  on public.pandora_project_specs
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_objectives_member_read on public.pandora_project_business_objectives;
create policy pandora_project_objectives_member_read
  on public.pandora_project_business_objectives
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_requirements_member_read on public.pandora_project_requirements;
create policy pandora_project_requirements_member_read
  on public.pandora_project_requirements
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_constraints_member_read on public.pandora_project_constraints;
create policy pandora_project_constraints_member_read
  on public.pandora_project_constraints
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_acceptance_member_read on public.pandora_project_acceptance_criteria;
create policy pandora_project_acceptance_member_read
  on public.pandora_project_acceptance_criteria
  for select
  to authenticated
  using (private.is_org_member(organization_id));

revoke all on table public.pandora_project_intents from anon, authenticated;
revoke all on table public.pandora_project_specs from anon, authenticated;
revoke all on table public.pandora_project_business_objectives from anon, authenticated;
revoke all on table public.pandora_project_requirements from anon, authenticated;
revoke all on table public.pandora_project_constraints from anon, authenticated;
revoke all on table public.pandora_project_acceptance_criteria from anon, authenticated;

grant select, insert on table public.pandora_project_intents to authenticated;
grant select on table public.pandora_project_specs to authenticated;
grant select on table public.pandora_project_business_objectives to authenticated;
grant select on table public.pandora_project_requirements to authenticated;
grant select on table public.pandora_project_constraints to authenticated;
grant select on table public.pandora_project_acceptance_criteria to authenticated;

grant select, insert, update, delete on table public.pandora_project_intents to service_role;
grant select, insert, update, delete on table public.pandora_project_specs to service_role;
grant select, insert, update, delete on table public.pandora_project_business_objectives to service_role;
grant select, insert, update, delete on table public.pandora_project_requirements to service_role;
grant select, insert, update, delete on table public.pandora_project_constraints to service_role;
grant select, insert, update, delete on table public.pandora_project_acceptance_criteria to service_role;

comment on table public.pandora_project_intents is
  'Append-only customer/Pandora intent receipts. Raw chat is not authoritative build specification.';
comment on table public.pandora_project_specs is
  'Versioned canonical ProjectSpec records. Content is immutable; material changes create a new version.';
comment on table public.pandora_project_requirements is
  'Queryable requirements bound to one immutable ProjectSpec version.';
