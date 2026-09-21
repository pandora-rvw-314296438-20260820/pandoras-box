create table if not exists public.pandora_tracking_tenants (
  id uuid primary key default gen_random_uuid(),
  workspace_key text not null unique
    check (workspace_key ~ '^[a-z0-9][a-z0-9._-]{1,127}$'),
  display_name text not null check (char_length(display_name) between 1 and 160),
  status text not null default 'active'
    check (status in ('active','paused','archived')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pandora_tracking_campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  slug text not null unique
    check (slug ~ '^[a-z0-9][a-z0-9-]{2,95}$'),
  name text not null check (char_length(name) between 1 and 200),
  destination_url text not null
    check (destination_url ~ '^https://'),
  source text,
  medium text,
  campaign text,
  content text,
  term text,
  provider text,
  provider_campaign_id text,
  provider_adset_id text,
  provider_ad_id text,
  status text not null default 'active'
    check (status in ('active','paused','archived')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table if not exists public.pandora_tracking_clicks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  campaign_id uuid not null references public.pandora_tracking_campaigns(id) on delete cascade,
  click_id text not null unique
    check (click_id ~ '^pdc_[0-9a-f]{32}$'),
  occurred_at timestamptz not null default now(),
  landing_url text,
  referrer text,
  user_agent text,
  ip_hash text check (ip_hash is null or ip_hash ~ '^[0-9a-f]{64}$'),
  visitor_hash text check (visitor_hash is null or visitor_hash ~ '^[0-9a-f]{64}$'),
  platform_click_ids jsonb not null default '{}'::jsonb
    check (jsonb_typeof(platform_click_ids) = 'object'),
  query_params jsonb not null default '{}'::jsonb
    check (jsonb_typeof(query_params) = 'object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  unique (tenant_id, click_id)
);

create table if not exists public.pandora_tracking_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  campaign_id uuid references public.pandora_tracking_campaigns(id) on delete set null,
  click_id text,
  event_type text not null
    check (event_type in ('event','lead','qualified_lead','booking','sale','refund')),
  event_name text not null
    check (event_name ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  source text not null default 'server'
    check (source in ('browser','server','import','provider')),
  external_event_id text,
  value numeric(18,4),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  constraint pandora_tracking_events_click_fk
    foreign key (tenant_id, click_id)
    references public.pandora_tracking_clicks(tenant_id, click_id)
    on delete set null
);

create unique index if not exists pandora_tracking_event_dedupe_uq
  on public.pandora_tracking_events (tenant_id, event_name, external_event_id)
  where external_event_id is not null;

create table if not exists public.pandora_tracking_costs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  campaign_id uuid references public.pandora_tracking_campaigns(id) on delete set null,
  provider text not null check (provider ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  external_record_id text not null,
  bucket_date date not null,
  spend numeric(18,4) not null default 0 check (spend >= 0),
  impressions bigint not null default 0 check (impressions >= 0),
  provider_clicks bigint not null default 0 check (provider_clicks >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, provider, external_record_id)
);

create table if not exists public.pandora_tracking_api_keys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  key_prefix text not null,
  key_hash text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  scopes text[] not null default array['conversion:write','cost:write','report:read']::text[],
  status text not null default 'active'
    check (status in ('active','revoked','expired')),
  last_used_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.pandora_tracking_releases (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  source_base_sha text not null,
  provider_state text not null,
  source_state text not null,
  notes text,
  deployed_at timestamptz not null default now()
);

create index if not exists pandora_tracking_clicks_campaign_time_idx
  on public.pandora_tracking_clicks (tenant_id, campaign_id, occurred_at desc);
create index if not exists pandora_tracking_events_campaign_time_idx
  on public.pandora_tracking_events (tenant_id, campaign_id, occurred_at desc);
create index if not exists pandora_tracking_events_click_idx
  on public.pandora_tracking_events (tenant_id, click_id);
create index if not exists pandora_tracking_costs_campaign_day_idx
  on public.pandora_tracking_costs (tenant_id, campaign_id, bucket_date desc);

create or replace function public.pandora_tracking_touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists pandora_tracking_tenants_touch on public.pandora_tracking_tenants;
create trigger pandora_tracking_tenants_touch
before update on public.pandora_tracking_tenants
for each row execute function public.pandora_tracking_touch_updated_at();

drop trigger if exists pandora_tracking_campaigns_touch on public.pandora_tracking_campaigns;
create trigger pandora_tracking_campaigns_touch
before update on public.pandora_tracking_campaigns
for each row execute function public.pandora_tracking_touch_updated_at();

drop trigger if exists pandora_tracking_costs_touch on public.pandora_tracking_costs;
create trigger pandora_tracking_costs_touch
before update on public.pandora_tracking_costs
for each row execute function public.pandora_tracking_touch_updated_at();

create or replace function public.pandora_tracking_issue_api_key_v1(
  p_tenant_id uuid,
  p_scopes text[] default array['conversion:write','cost:write','report:read']::text[],
  p_expires_at timestamptz default null
)
returns table(api_key text, key_prefix text)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_raw text;
  v_prefix text;
  v_hash text;
begin
  if current_user not in ('postgres','service_role')
     and coalesce(auth.jwt() ->> 'role','') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.pandora_tracking_tenants
    where id = p_tenant_id and status <> 'archived'
  ) then
    raise exception 'tracking tenant not found' using errcode='P0002';
  end if;

  v_raw := 'ptk_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_prefix := left(v_raw, 12);
  v_hash := encode(extensions.digest(v_raw, 'sha256'), 'hex');

  insert into public.pandora_tracking_api_keys(
    tenant_id, key_prefix, key_hash, scopes, expires_at
  ) values (
    p_tenant_id, v_prefix, v_hash, coalesce(p_scopes, '{}'::text[]), p_expires_at
  );

  api_key := v_raw;
  key_prefix := v_prefix;
  return next;
end;
$$;

revoke all on function public.pandora_tracking_issue_api_key_v1(uuid,text[],timestamptz)
  from public, anon, authenticated;
grant execute on function public.pandora_tracking_issue_api_key_v1(uuid,text[],timestamptz)
  to service_role;

create or replace view public.pandora_tracking_campaign_daily_v1 as
with click_agg as (
  select tenant_id, campaign_id, occurred_at::date as day,
         count(*)::bigint as clicks
  from public.pandora_tracking_clicks
  group by tenant_id, campaign_id, occurred_at::date
),
event_agg as (
  select tenant_id, campaign_id, occurred_at::date as day,
         count(*) filter (where event_type='lead')::bigint as leads,
         count(*) filter (where event_type='qualified_lead')::bigint as qualified_leads,
         count(*) filter (where event_type='booking')::bigint as bookings,
         count(*) filter (where event_type='sale')::bigint as sales,
         count(*) filter (where event_type='refund')::bigint as refunds,
         coalesce(sum(value) filter (where event_type='sale'),0)::numeric(18,4) as gross_revenue,
         coalesce(sum(value) filter (where event_type='refund'),0)::numeric(18,4) as refund_value
  from public.pandora_tracking_events
  where campaign_id is not null
  group by tenant_id, campaign_id, occurred_at::date
),
cost_agg as (
  select tenant_id, campaign_id, bucket_date as day,
         coalesce(sum(spend),0)::numeric(18,4) as spend,
         coalesce(sum(impressions),0)::bigint as impressions,
         coalesce(sum(provider_clicks),0)::bigint as provider_clicks
  from public.pandora_tracking_costs
  where campaign_id is not null
  group by tenant_id, campaign_id, bucket_date
),
keys as (
  select tenant_id, campaign_id, day from click_agg
  union
  select tenant_id, campaign_id, day from event_agg
  union
  select tenant_id, campaign_id, day from cost_agg
)
select
  k.tenant_id,
  k.campaign_id,
  c.slug,
  c.name as campaign_name,
  c.provider,
  c.provider_campaign_id,
  k.day,
  coalesce(ca.clicks,0)::bigint as clicks,
  coalesce(co.impressions,0)::bigint as impressions,
  coalesce(co.provider_clicks,0)::bigint as provider_clicks,
  coalesce(ea.leads,0)::bigint as leads,
  coalesce(ea.qualified_leads,0)::bigint as qualified_leads,
  coalesce(ea.bookings,0)::bigint as bookings,
  coalesce(ea.sales,0)::bigint as sales,
  coalesce(ea.refunds,0)::bigint as refunds,
  coalesce(co.spend,0)::numeric(18,4) as spend,
  (coalesce(ea.gross_revenue,0) - coalesce(ea.refund_value,0))::numeric(18,4) as net_revenue,
  case when coalesce(ea.sales,0) > 0
       then round(coalesce(co.spend,0) / ea.sales, 4)
       else null end as cac,
  case when coalesce(co.spend,0) > 0
       then round((coalesce(ea.gross_revenue,0)-coalesce(ea.refund_value,0)) / co.spend, 4)
       else null end as roas
from keys k
join public.pandora_tracking_campaigns c on c.id=k.campaign_id
left join click_agg ca on ca.tenant_id=k.tenant_id and ca.campaign_id=k.campaign_id and ca.day=k.day
left join event_agg ea on ea.tenant_id=k.tenant_id and ea.campaign_id=k.campaign_id and ea.day=k.day
left join cost_agg co on co.tenant_id=k.tenant_id and co.campaign_id=k.campaign_id and co.day=k.day;

alter table public.pandora_tracking_tenants enable row level security;
alter table public.pandora_tracking_campaigns enable row level security;
alter table public.pandora_tracking_clicks enable row level security;
alter table public.pandora_tracking_events enable row level security;
alter table public.pandora_tracking_costs enable row level security;
alter table public.pandora_tracking_api_keys enable row level security;
alter table public.pandora_tracking_releases enable row level security;

revoke all on public.pandora_tracking_tenants from anon, authenticated;
revoke all on public.pandora_tracking_campaigns from anon, authenticated;
revoke all on public.pandora_tracking_clicks from anon, authenticated;
revoke all on public.pandora_tracking_events from anon, authenticated;
revoke all on public.pandora_tracking_costs from anon, authenticated;
revoke all on public.pandora_tracking_api_keys from anon, authenticated;
revoke all on public.pandora_tracking_releases from anon, authenticated;
revoke all on public.pandora_tracking_campaign_daily_v1 from anon, authenticated;

grant select, insert, update, delete on public.pandora_tracking_tenants to service_role;
grant select, insert, update, delete on public.pandora_tracking_campaigns to service_role;
grant select, insert, update, delete on public.pandora_tracking_clicks to service_role;
grant select, insert, update, delete on public.pandora_tracking_events to service_role;
grant select, insert, update, delete on public.pandora_tracking_costs to service_role;
grant select, insert, update, delete on public.pandora_tracking_api_keys to service_role;
grant select, insert, update, delete on public.pandora_tracking_releases to service_role;
grant select on public.pandora_tracking_campaign_daily_v1 to service_role;

insert into public.pandora_tracking_releases(
  version, source_base_sha, provider_state, source_state, notes
) values (
  '1.0.0-provider',
  '464c851de4eee01ac8da02aefba227f62c7d2a0a',
  'supabase_schema_deployed',
  'github_write_blocked',
  'First-party attribution backend. GitHub App denied branch/source writes with HTTP 403; source parity remains pending.'
)
on conflict (version) do update set
  source_base_sha=excluded.source_base_sha,
  provider_state=excluded.provider_state,
  source_state=excluded.source_state,
  notes=excluded.notes,
  deployed_at=now();
