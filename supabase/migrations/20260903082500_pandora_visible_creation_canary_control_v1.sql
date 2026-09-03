
-- Task 132: fail-closed Visible Creation canary rollout control.
-- Runtime defaults OFF. Only service-role code may evaluate or mutate the control.

create table if not exists public.pandora_visible_creation_canary_control (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null
);

insert into public.pandora_visible_creation_canary_control(singleton, enabled)
values (true, false)
on conflict (singleton) do nothing;

create table if not exists public.pandora_visible_creation_canary_allowlist (
  target_kind text not null check (target_kind in ('user','project')),
  target_id uuid not null,
  enabled boolean not null default true,
  note text null check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (target_kind, target_id)
);

alter table public.pandora_visible_creation_canary_control enable row level security;
alter table public.pandora_visible_creation_canary_allowlist enable row level security;

revoke all on table public.pandora_visible_creation_canary_control from public, anon, authenticated;
revoke all on table public.pandora_visible_creation_canary_allowlist from public, anon, authenticated;
grant select, insert, update, delete on table public.pandora_visible_creation_canary_control to service_role;
grant select, insert, update, delete on table public.pandora_visible_creation_canary_allowlist to service_role;

create or replace function public.pandora_visible_creation_canary_allowed_v1(
  p_user_id uuid,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    coalesce((
      select c.enabled
      from public.pandora_visible_creation_canary_control c
      where c.singleton = true
    ), false)
    and exists (
      select 1
      from public.pandora_visible_creation_canary_allowlist a
      where a.enabled = true
        and (
          (a.target_kind = 'user' and a.target_id = p_user_id)
          or (a.target_kind = 'project' and a.target_id = p_project_id)
        )
    );
$$;

revoke all on function public.pandora_visible_creation_canary_allowed_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pandora_visible_creation_canary_allowed_v1(uuid, uuid) to service_role;

comment on table public.pandora_visible_creation_canary_control is
  'Task 132 runtime kill switch. enabled=false blocks every new Visible Creation build without a redeploy.';
comment on table public.pandora_visible_creation_canary_allowlist is
  'Task 132 bounded user/project allowlist. No client role can read or mutate it.';
comment on function public.pandora_visible_creation_canary_allowed_v1(uuid, uuid) is
  'Service-only fail-closed Visible Creation canary decision. Requires global enabled plus an enabled user or project allowlist row.';
