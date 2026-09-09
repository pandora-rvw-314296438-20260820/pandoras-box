-- Pandora × Base44 Phase 0.8: fail-closed publish rollout gate.
-- Base44 projects are explicitly enrolled. Non-enrolled legacy Pandora projects preserve existing publish behavior.
-- The isolated Base44 acceptance project is enrolled with publish disabled by default.

create table if not exists public.pandora_base44_rollout_projects (
  project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  enabled boolean not null default true,
  note text null check (note is null or char_length(note) <= 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pandora_base44_action_control (
  action text primary key check (action in ('publish')),
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null
);

insert into public.pandora_base44_action_control(action, enabled)
values ('publish', false)
on conflict (action) do nothing;

insert into public.pandora_base44_rollout_projects(project_id, enabled, note)
select
  p.id,
  true,
  'Pandora Base44 isolated acceptance project; publish remains fail-closed until explicitly enabled.'
from public.projectos_projects p
where p.id = 'db007811-fe55-42b4-b0be-3a11324dcfff'::uuid
  and p.organization_id = '076a9306-5c4e-4d9d-98d3-e3a6fea968fb'::uuid
  and p.project_key = 'base44-acceptance'
on conflict (project_id) do nothing;

alter table public.pandora_base44_rollout_projects enable row level security;
alter table public.pandora_base44_action_control enable row level security;

revoke all on table public.pandora_base44_rollout_projects from public, anon, authenticated;
revoke all on table public.pandora_base44_action_control from public, anon, authenticated;
grant select, insert, update, delete on table public.pandora_base44_rollout_projects to service_role;
grant select, insert, update, delete on table public.pandora_base44_action_control to service_role;

create or replace function public.pandora_base44_action_allowed_v1(
  p_project_id uuid,
  p_action text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when p_project_id is null or nullif(btrim(p_action), '') is null then false
    when not exists (
      select 1
      from public.pandora_base44_rollout_projects p
      where p.project_id = p_project_id
        and p.enabled = true
    ) then true
    when btrim(p_action) <> 'publish' then false
    else coalesce((
      select c.enabled
      from public.pandora_base44_action_control c
      where c.action = btrim(p_action)
    ), false)
  end;
$$;

revoke all on function public.pandora_base44_action_allowed_v1(uuid, text) from public, anon, authenticated;
grant execute on function public.pandora_base44_action_allowed_v1(uuid, text) to service_role;

comment on table public.pandora_base44_rollout_projects is
  'Explicit server-side enrollment for Pandora Base44 experience projects. Non-enrolled projects retain legacy behavior.';
comment on table public.pandora_base44_action_control is
  'Fail-closed Base44 privileged-action rollout control. Publish defaults disabled and can be changed without redeploying Pandora.';
comment on function public.pandora_base44_action_allowed_v1(uuid, text) is
  'Service-only rollout decision. Non-enrolled projects pass through; enrolled Base44 projects require an explicitly enabled known action.';
