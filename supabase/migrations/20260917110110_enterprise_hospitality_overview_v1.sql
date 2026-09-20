-- Source reconstruction of durable enterprise hospitality objects from
-- provider migration 20260917110110. The retired ProjectOS foreign-key link is
-- intentionally not recreated; project_id remains nullable historical metadata.

create table if not exists public.enterprise_properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid,
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
  unique (organization_id,slug)
);
create index if not exists enterprise_properties_org_idx
  on public.enterprise_properties(organization_id);
create index if not exists enterprise_properties_project_idx
  on public.enterprise_properties(project_id);

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
  unique (property_id,as_of)
);
create index if not exists enterprise_hospitality_snapshots_org_idx
  on public.enterprise_hospitality_snapshots(organization_id);
create index if not exists enterprise_hospitality_snapshots_property_asof_idx
  on public.enterprise_hospitality_snapshots(property_id,as_of desc);

alter table public.enterprise_properties enable row level security;
alter table public.enterprise_hospitality_snapshots enable row level security;

revoke all on table public.enterprise_properties from public, anon, authenticated;
revoke all on table public.enterprise_hospitality_snapshots from public, anon, authenticated;
grant all on table public.enterprise_properties to service_role;
grant all on table public.enterprise_hospitality_snapshots to service_role;
