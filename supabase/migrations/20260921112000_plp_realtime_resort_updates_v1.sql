-- Safe Realtime invalidation transport for the PLP enterprise workspace.
-- Clients receive only organization/property/topic signals and then refetch
-- existing protected RPC projections. Guest PII, provider secrets, prompts,
-- model/provider routing, and raw audit payloads are never replicated.

create table if not exists public.enterprise_realtime_signals (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid references public.enterprise_properties(id) on delete cascade,
  topic text not null check (
    topic in (
      'bookings',
      'guests',
      'staff_tasks',
      'hospitality',
      'business_activity',
      'source_health',
      'pandora_activity'
    )
  ),
  occurred_at timestamptz not null default clock_timestamp()
);

create index if not exists enterprise_realtime_signals_org_id_idx
  on public.enterprise_realtime_signals(organization_id, id desc);
create index if not exists enterprise_realtime_signals_property_id_idx
  on public.enterprise_realtime_signals(property_id, id desc);

alter table public.enterprise_realtime_signals enable row level security;

drop policy if exists enterprise_realtime_signals_member_read
  on public.enterprise_realtime_signals;
create policy enterprise_realtime_signals_member_read
on public.enterprise_realtime_signals
for select
to authenticated
using (
  exists (
    select 1
    from public.memberships m
    where m.organization_id = enterprise_realtime_signals.organization_id
      and m.user_id = auth.uid()
      and m.status::text = 'active'
  )
);

revoke all on table public.enterprise_realtime_signals
  from public, anon, authenticated;
grant select on table public.enterprise_realtime_signals to authenticated;
grant all on table public.enterprise_realtime_signals to service_role;

create or replace function private.emit_enterprise_realtime_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  org_id uuid;
  prop_id uuid;
begin
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  org_id := nullif(row_data->>'organization_id', '')::uuid;
  prop_id := nullif(row_data->>'property_id', '')::uuid;

  if tg_table_name = 'enterprise_properties' then
    prop_id := nullif(row_data->>'id', '')::uuid;
  end if;

  if org_id is not null then
    insert into public.enterprise_realtime_signals(
      organization_id,
      property_id,
      topic
    )
    values (
      org_id,
      prop_id,
      tg_argv[0]
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.emit_enterprise_realtime_signal() from public;
grant execute on function private.emit_enterprise_realtime_signal() to service_role;

create or replace function private.emit_plp_runtime_realtime_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prop public.enterprise_properties%rowtype;
begin
  select *
  into prop
  from public.enterprise_properties p
  where p.slug = 'plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if prop.id is not null then
    insert into public.enterprise_realtime_signals(
      organization_id,
      property_id,
      topic
    )
    values (
      prop.organization_id,
      prop.id,
      tg_argv[0]
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.emit_plp_runtime_realtime_signal() from public;
grant execute on function private.emit_plp_runtime_realtime_signal() to service_role;

drop trigger if exists plp_realtime_bookings_signal on plp_runtime.plp_bookings;
create trigger plp_realtime_bookings_signal
after insert or update or delete on plp_runtime.plp_bookings
for each row execute function private.emit_plp_runtime_realtime_signal('bookings');

drop trigger if exists plp_realtime_guests_signal on plp_runtime.plp_guests;
create trigger plp_realtime_guests_signal
after insert or update or delete on plp_runtime.plp_guests
for each row execute function private.emit_plp_runtime_realtime_signal('guests');

drop trigger if exists plp_realtime_staff_tasks_signal on plp_runtime.plp_staff_tasks;
create trigger plp_realtime_staff_tasks_signal
after insert or update or delete on plp_runtime.plp_staff_tasks
for each row execute function private.emit_plp_runtime_realtime_signal('staff_tasks');

drop trigger if exists enterprise_realtime_hospitality_signal
  on public.enterprise_hospitality_snapshots;
create trigger enterprise_realtime_hospitality_signal
after insert or update or delete on public.enterprise_hospitality_snapshots
for each row execute function private.emit_enterprise_realtime_signal('hospitality');

drop trigger if exists enterprise_realtime_business_activity_signal
  on public.enterprise_business_activity;
create trigger enterprise_realtime_business_activity_signal
after insert or update or delete on public.enterprise_business_activity
for each row execute function private.emit_enterprise_realtime_signal('business_activity');

drop trigger if exists enterprise_realtime_source_health_signal
  on public.enterprise_properties;
create trigger enterprise_realtime_source_health_signal
after insert or update or delete on public.enterprise_properties
for each row execute function private.emit_enterprise_realtime_signal('source_health');

drop trigger if exists enterprise_realtime_pandora_activity_signal
  on public.pandora_activity_events;
create trigger enterprise_realtime_pandora_activity_signal
after insert or update or delete on public.pandora_activity_events
for each row execute function private.emit_enterprise_realtime_signal('pandora_activity');

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'enterprise_realtime_signals'
  ) then
    alter publication supabase_realtime
      add table public.enterprise_realtime_signals;
  end if;
end;
$$;
