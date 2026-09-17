create table if not exists public.enterprise_properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete set null,
  slug text not null,
  display_name text not null,
  timezone text not null default 'Asia/Manila',
  currency text not null default 'PHP',
  source_status text not null default 'not_connected'
    check (source_status in ('not_connected','connecting','healthy','stale','error')),
  source_observed_at timestamptz,
  source_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, slug)
);

create table if not exists public.enterprise_hospitality_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null references public.enterprise_properties(id) on delete cascade,
  business_date date not null,
  as_of timestamptz not null,
  occupancy_percent numeric(5,2) check (occupancy_percent between 0 and 100),
  rooms_total integer check (rooms_total is null or rooms_total >= 0),
  rooms_available integer check (rooms_available is null or rooms_available >= 0),
  arrivals_today integer check (arrivals_today is null or arrivals_today >= 0),
  departures_today integer check (departures_today is null or departures_today >= 0),
  revenue_today numeric(14,2) check (revenue_today is null or revenue_today >= 0),
  adr numeric(14,2) check (adr is null or adr >= 0),
  revpar numeric(14,2) check (revpar is null or revpar >= 0),
  rooms_ready integer check (rooms_ready is null or rooms_ready >= 0),
  rooms_not_ready integer check (rooms_not_ready is null or rooms_not_ready >= 0),
  data_quality_state text not null default 'verified'
    check (data_quality_state in ('verified','partial','stale','error')),
  source_label text,
  created_at timestamptz not null default now(),
  unique (property_id, as_of)
);

create table if not exists public.enterprise_attention_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null references public.enterprise_properties(id) on delete cascade,
  source_key text not null,
  priority text not null default 'medium'
    check (priority in ('critical','high','medium','low')),
  category text not null default 'operations',
  title text not null,
  summary text,
  action_prompt text,
  status text not null default 'open'
    check (status in ('open','acknowledged','resolved','dismissed')),
  occurred_at timestamptz not null default now(),
  due_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, source_key)
);

create table if not exists public.enterprise_business_activity (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null references public.enterprise_properties(id) on delete cascade,
  activity_key text not null,
  category text not null default 'operations',
  title text not null,
  summary text,
  occurred_at timestamptz not null,
  source_label text,
  created_at timestamptz not null default now(),
  unique (property_id, activity_key)
);

create table if not exists public.enterprise_source_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null references public.enterprise_properties(id) on delete cascade,
  source_type text not null,
  display_name text not null,
  status text not null default 'not_connected'
    check (status in ('not_connected','connecting','healthy','stale','error')),
  last_success_at timestamptz,
  last_attempt_at timestamptz,
  customer_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, source_type)
);

create index if not exists enterprise_properties_org_idx
  on public.enterprise_properties(organization_id);
create index if not exists enterprise_properties_project_idx
  on public.enterprise_properties(project_id);
create index if not exists enterprise_hospitality_snapshots_property_asof_idx
  on public.enterprise_hospitality_snapshots(property_id, as_of desc);
create index if not exists enterprise_hospitality_snapshots_org_idx
  on public.enterprise_hospitality_snapshots(organization_id);
create index if not exists enterprise_attention_items_property_status_time_idx
  on public.enterprise_attention_items(property_id, status, occurred_at desc);
create index if not exists enterprise_attention_items_org_idx
  on public.enterprise_attention_items(organization_id);
create index if not exists enterprise_business_activity_property_time_idx
  on public.enterprise_business_activity(property_id, occurred_at desc);
create index if not exists enterprise_business_activity_org_idx
  on public.enterprise_business_activity(organization_id);
create index if not exists enterprise_source_connections_property_idx
  on public.enterprise_source_connections(property_id);
create index if not exists enterprise_source_connections_org_idx
  on public.enterprise_source_connections(organization_id);

alter table public.enterprise_properties enable row level security;
alter table public.enterprise_hospitality_snapshots enable row level security;
alter table public.enterprise_attention_items enable row level security;
alter table public.enterprise_business_activity enable row level security;
alter table public.enterprise_source_connections enable row level security;

create policy enterprise_properties_member_read on public.enterprise_properties
  for select to authenticated using (private.is_org_member(organization_id));
create policy enterprise_hospitality_snapshots_member_read on public.enterprise_hospitality_snapshots
  for select to authenticated using (private.is_org_member(organization_id));
create policy enterprise_attention_items_member_read on public.enterprise_attention_items
  for select to authenticated using (private.is_org_member(organization_id));
create policy enterprise_business_activity_member_read on public.enterprise_business_activity
  for select to authenticated using (private.is_org_member(organization_id));
create policy enterprise_source_connections_member_read on public.enterprise_source_connections
  for select to authenticated using (private.is_org_member(organization_id));

revoke all on table public.enterprise_properties from anon;
revoke all on table public.enterprise_hospitality_snapshots from anon;
revoke all on table public.enterprise_attention_items from anon;
revoke all on table public.enterprise_business_activity from anon;
revoke all on table public.enterprise_source_connections from anon;

grant select on table public.enterprise_properties to authenticated;
grant select on table public.enterprise_hospitality_snapshots to authenticated;
grant select on table public.enterprise_attention_items to authenticated;
grant select on table public.enterprise_business_activity to authenticated;
grant select on table public.enterprise_source_connections to authenticated;

create or replace view public.enterprise_property_overview_v1
with (security_invoker = true)
as
select
  p.id as property_id,
  p.organization_id,
  p.project_id,
  p.slug,
  p.display_name,
  p.timezone,
  p.currency,
  p.source_status,
  p.source_observed_at,
  p.source_message,
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
  s.data_quality_state
from public.enterprise_properties p
left join lateral (
  select hs.*
  from public.enterprise_hospitality_snapshots hs
  where hs.property_id = p.id
  order by hs.as_of desc
  limit 1
) s on true;

grant select on public.enterprise_property_overview_v1 to authenticated;
revoke all on public.enterprise_property_overview_v1 from anon;

insert into public.enterprise_properties (
  organization_id, project_id, slug, display_name, timezone, currency,
  source_status, source_message
)
select
  organization_id,
  id,
  'plp-boracay',
  'PLP Boracay',
  'Asia/Manila',
  'PHP',
  'not_connected',
  'Live reservations, sales and room operations are not connected to this dashboard yet.'
from public.projectos_projects
where project_key = 'plp-boracay'
on conflict (organization_id, slug) do update set
  project_id = excluded.project_id,
  display_name = excluded.display_name,
  timezone = excluded.timezone,
  currency = excluded.currency,
  source_status = excluded.source_status,
  source_message = excluded.source_message,
  updated_at = now();

insert into public.enterprise_source_connections (
  organization_id, property_id, source_type, display_name, status, customer_message
)
select p.organization_id, p.id, v.source_type, v.display_name, 'not_connected', v.customer_message
from public.enterprise_properties p
cross join (values
  ('reservations','Reservations','Connect live reservations to unlock occupancy, arrivals and departures.'),
  ('payments','Payments','Connect live payments to unlock today’s sales and revenue metrics.'),
  ('housekeeping','Housekeeping','Connect room operations to show ready and not-ready rooms.'),
  ('guest_requests','Guest requests','Connect guest service activity to surface requests needing attention.')
) as v(source_type, display_name, customer_message)
where p.slug='plp-boracay'
on conflict (property_id, source_type) do update set
  display_name = excluded.display_name,
  status = excluded.status,
  customer_message = excluded.customer_message,
  updated_at = now();
