-- Base44 / external web experience rollout control.
-- External privileged writes are denied by default and can be enabled per exact
-- origin + operation without redeploying Pandora. Browser roles cannot inspect
-- or mutate this control.

create table if not exists public.pandora_external_experience_write_control (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null
);

insert into public.pandora_external_experience_write_control(singleton, enabled)
values (true, false)
on conflict (singleton) do nothing;

create table if not exists public.pandora_external_experience_write_allowlist (
  origin text not null
    check (
      char_length(origin) between 9 and 2048
      and origin ~ '^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?$'
    ),
  operation text not null
    check (
      operation in (
        'project.create',
        'preview.create',
        'project.undo',
        'project.rollback',
        'project.publish',
        'production.verify'
      )
    ),
  enabled boolean not null default false,
  note text null check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid null,
  primary key (origin, operation)
);

alter table public.pandora_external_experience_write_control enable row level security;
alter table public.pandora_external_experience_write_allowlist enable row level security;

revoke all on table public.pandora_external_experience_write_control from public, anon, authenticated;
revoke all on table public.pandora_external_experience_write_allowlist from public, anon, authenticated;

grant select, insert, update, delete
  on table public.pandora_external_experience_write_control
  to service_role;
grant select, insert, update, delete
  on table public.pandora_external_experience_write_allowlist
  to service_role;

create or replace function public.pandora_external_experience_write_allowed_v1(
  p_origin text,
  p_operation text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    coalesce(
      (
        select c.enabled
        from public.pandora_external_experience_write_control c
        where c.singleton = true
      ),
      false
    )
    and exists (
      select 1
      from public.pandora_external_experience_write_allowlist a
      where a.origin = nullif(trim(p_origin), '')
        and a.operation = nullif(trim(p_operation), '')
        and a.enabled = true
    );
$$;

revoke all
  on function public.pandora_external_experience_write_allowed_v1(text, text)
  from public, anon, authenticated;
grant execute
  on function public.pandora_external_experience_write_allowed_v1(text, text)
  to service_role;

comment on table public.pandora_external_experience_write_control is
  'Fail-closed global switch for privileged writes from non-first-party web experience origins.';

comment on table public.pandora_external_experience_write_allowlist is
  'Exact origin + operation allowlist for privileged non-first-party web experience writes. Rows default disabled.';

comment on function public.pandora_external_experience_write_allowed_v1(text, text) is
  'Service-only external web experience write decision. Requires global enable plus an exact enabled origin + operation row.';
