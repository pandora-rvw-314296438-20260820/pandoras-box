-- Authenticated GraphQL read models for PLP and owner dashboards.
-- GraphQL remains a read optimization. Mutations and sensitive audit logs stay
-- on governed RPC/capability paths.
create extension if not exists pg_graphql;

-- Recover the business-activity relation into repository source. This relation
-- predates its first checked-in consumer and already exists in production.
create table if not exists public.enterprise_business_activity (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  property_id uuid not null
    references public.enterprise_properties(id) on delete cascade,
  activity_key text not null,
  category text not null default 'operations',
  title text not null,
  summary text,
  occurred_at timestamptz not null,
  source_label text,
  created_at timestamptz not null default now(),
  unique (property_id, activity_key)
);
create index if not exists enterprise_business_activity_org_idx
  on public.enterprise_business_activity(organization_id);
create index if not exists enterprise_business_activity_property_time_idx
  on public.enterprise_business_activity(property_id, occurred_at desc);
alter table public.enterprise_business_activity enable row level security;

revoke execute on function graphql.resolve(text,jsonb,text,jsonb)
  from public, anon;
grant usage on schema graphql to authenticated, service_role;
grant execute on function graphql.resolve(text,jsonb,text,jsonb)
  to authenticated, service_role;

create or replace view public.enterprise_graphql_owner_dashboards_v1
with (security_barrier=true) as
select
  p.id as property_id,
  p.organization_id,
  p.slug as property_slug,
  p.display_name as property_name,
  p.timezone,
  p.currency,
  p.source_status,
  p.source_observed_at,
  p.source_message,
  s.id as snapshot_id,
  s.business_date,
  s.as_of,
  s.occupancy_percent,
  s.rooms_total,
  s.rooms_available,
  s.arrivals_today,
  s.departures_today,
  s.revenue_today,
  s.adr,
  s.revpar,
  s.rooms_ready,
  s.rooms_not_ready,
  s.data_quality_state,
  s.source_label
from public.enterprise_properties p
left join lateral (
  select hs.*
  from public.enterprise_hospitality_snapshots hs
  where hs.organization_id=p.organization_id
    and hs.property_id=p.id
  order by hs.as_of desc, hs.created_at desc, hs.id desc
  limit 1
) s on true
where exists (
  select 1
  from public.memberships m
  where m.organization_id=p.organization_id
    and m.user_id=auth.uid()
    and m.status::text='active'
);

comment on view public.enterprise_graphql_owner_dashboards_v1 is
  e'@graphql({"primary_key_columns":["property_id"],"max_rows":50})';
revoke all on public.enterprise_graphql_owner_dashboards_v1 from public, anon;
grant select on public.enterprise_graphql_owner_dashboards_v1
  to authenticated, service_role;

create or replace view public.plp_graphql_overview_v1
with (security_barrier=true) as
select *
from public.enterprise_graphql_owner_dashboards_v1
where property_slug='plp-boracay';

comment on view public.plp_graphql_overview_v1 is
  e'@graphql({"primary_key_columns":["property_id"],"max_rows":10})';
revoke all on public.plp_graphql_overview_v1 from public, anon;
grant select on public.plp_graphql_overview_v1
  to authenticated, service_role;

create or replace view public.plp_graphql_guests_v1
with (security_barrier=true) as
select
  b.id as booking_id,
  g.id as guest_id,
  p.organization_id,
  p.id as property_id,
  d.business_date,
  g.full_name,
  b.booking_reference,
  b.accommodation_name,
  b.check_in,
  b.check_out,
  b.nights,
  b.guest_count,
  b.payment_status,
  b.status,
  b.special_requests,
  b.source,
  case
    when b.check_in=d.business_date then 'Arriving'
    when b.check_out=d.business_date then 'Departing'
    when b.check_in < d.business_date
      and b.check_out > d.business_date
      and upper(coalesce(b.status,'')) not in
        ('CANCELLED','CANCELED','CHECKED_OUT')
      then 'In-house'
    else 'Current'
  end as display_status,
  (
    lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
    or lower(coalesce(b.source,'')) like 'qa_%'
  ) as is_mock,
  b.updated_at
from public.enterprise_properties p
cross join lateral (
  select (
    clock_timestamp()
      at time zone coalesce(nullif(p.timezone,''),'Asia/Manila')
  )::date as business_date
) d
join plp_runtime.plp_bookings b
  on b.check_in <= d.business_date
 and b.check_out >= d.business_date
 and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
left join plp_runtime.plp_guests g on g.id=b.guest_id
where p.slug='plp-boracay'
  and exists (
    select 1
    from public.memberships m
    where m.organization_id=p.organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
  );

comment on view public.plp_graphql_guests_v1 is
  e'@graphql({"primary_key_columns":["booking_id"],"max_rows":250})';
revoke all on public.plp_graphql_guests_v1 from public, anon;
grant select on public.plp_graphql_guests_v1 to authenticated, service_role;

create or replace view public.plp_graphql_operations_v1
with (security_barrier=true) as
select
  t.id as task_id,
  p.organization_id,
  p.id as property_id,
  t.booking_reference,
  t.kind,
  t.category,
  t.priority,
  t.status,
  t.title,
  t.note,
  t.source,
  t.actor,
  t.created_at,
  t.updated_at,
  t.completed_at,
  g.full_name,
  b.accommodation_name,
  (
    lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
    or lower(coalesce(t.source,'')) like 'qa_%'
    or lower(coalesce(b.source,'')) like 'qa_%'
  ) as is_mock
from public.enterprise_properties p
join plp_runtime.plp_staff_tasks t on true
left join plp_runtime.plp_bookings b
  on b.booking_reference=t.booking_reference
left join plp_runtime.plp_guests g on g.id=b.guest_id
where p.slug='plp-boracay'
  and lower(coalesce(t.status,'')) not in
    ('done','completed','complete','cancelled','canceled','closed')
  and exists (
    select 1
    from public.memberships m
    where m.organization_id=p.organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
  );

comment on view public.plp_graphql_operations_v1 is
  e'@graphql({"primary_key_columns":["task_id"],"max_rows":200})';
revoke all on public.plp_graphql_operations_v1 from public, anon;
grant select on public.plp_graphql_operations_v1
  to authenticated, service_role;

create or replace view public.plp_graphql_activity_v1
with (security_barrier=true) as
with authorized as (
  select p.id as property_id, p.organization_id
  from public.enterprise_properties p
  where p.slug='plp-boracay'
    and exists (
      select 1
      from public.memberships m
      where m.organization_id=p.organization_id
        and m.user_id=auth.uid()
        and m.status::text='active'
    )
)
select
  'business:' || e.id::text as activity_id,
  a.organization_id,
  a.property_id,
  case
    when lower(coalesce(e.category,'')) in
      ('guest','guests','booking','bookings','arrival','arrivals',
       'departure','departures','concierge','hospitality')
      then 'guests'
    when lower(coalesce(e.category,'')) in
      ('operations','team','staff','maintenance','housekeeping')
      then 'team'
    else 'all'
  end as audience,
  coalesce(nullif(trim(e.category),''),'activity') as category,
  e.title,
  e.summary,
  coalesce(nullif(trim(e.source_label),''),'PLP runtime') as source_label,
  e.occurred_at,
  (
    lower(coalesce(e.source_label,'')) like '%mock%'
    or lower(coalesce(e.source_label,'')) like '%qa%'
  ) as is_mock
from authorized a
join public.enterprise_business_activity e
  on e.organization_id=a.organization_id
 and e.property_id=a.property_id

union all

select
  'task:' || t.id::text,
  a.organization_id,
  a.property_id,
  'team'::text,
  coalesce(nullif(trim(t.category),''), nullif(trim(t.kind),''), 'team'),
  t.title,
  coalesce(nullif(trim(t.note),''), 'PLP staff task updated.'),
  coalesce(nullif(trim(t.source),''),'PLP runtime'),
  coalesce(t.completed_at,t.updated_at,t.created_at),
  (
    lower(coalesce(t.source,'')) like 'qa_%'
    or lower(coalesce(t.actor,'')) like '%qa%'
  )
from authorized a
join plp_runtime.plp_staff_tasks t on true

union all

select
  'booking:' || b.id::text,
  a.organization_id,
  a.property_id,
  'guests'::text,
  'booking'::text,
  case upper(coalesce(b.status,''))
    when 'CONFIRMED' then 'Booking confirmed'
    when 'CHECKED_IN' then 'Guest checked in'
    when 'IN_HOUSE' then 'Guest in house'
    when 'CHECKED_OUT' then 'Guest checked out'
    when 'CANCELLED' then 'Booking cancelled'
    when 'CANCELED' then 'Booking cancelled'
    else 'Booking updated'
  end,
  concat_ws(
    ' · ',
    nullif(trim(g.full_name),''),
    nullif(trim(b.accommodation_name),''),
    nullif(trim(b.booking_reference),'')
  ),
  coalesce(nullif(trim(b.source),''),'PLP runtime'),
  coalesce(b.confirmed_at,b.cancelled_at,b.updated_at,b.created_at),
  (
    lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
    or lower(coalesce(b.source,'')) like 'qa_%'
  )
from authorized a
join plp_runtime.plp_bookings b on true
left join plp_runtime.plp_guests g on g.id=b.guest_id;

comment on view public.plp_graphql_activity_v1 is
  e'@graphql({"primary_key_columns":["activity_id"],"max_rows":100})';
revoke all on public.plp_graphql_activity_v1 from public, anon;
grant select on public.plp_graphql_activity_v1
  to authenticated, service_role;
