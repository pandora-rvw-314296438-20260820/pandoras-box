create or replace view public.pandora_tracking_campaign_traffic_daily_v2 as
with click_agg as (
  select
    tenant_id,
    campaign_id,
    occurred_at::date as day,
    count(*)::bigint as clicks,
    count(distinct visitor_hash) filter (where visitor_hash is not null)::bigint as unique_visitors
  from public.pandora_tracking_clicks
  group by tenant_id,campaign_id,occurred_at::date
),
event_agg as (
  select
    tenant_id,
    campaign_id,
    occurred_at::date as day,
    count(*) filter (where event_type='lead')::bigint as leads,
    count(*) filter (where event_type='qualified_lead')::bigint as qualified_leads,
    count(*) filter (where event_type='booking')::bigint as bookings,
    count(*) filter (where event_type='sale')::bigint as sales,
    count(*) filter (where event_type='refund')::bigint as refunds
  from public.pandora_tracking_events
  where campaign_id is not null
  group by tenant_id,campaign_id,occurred_at::date
),
keys as (
  select tenant_id,campaign_id,day from click_agg
  union
  select tenant_id,campaign_id,day from event_agg
)
select
  k.tenant_id,
  k.campaign_id,
  p.slug,
  p.name as campaign_name,
  p.provider,
  p.provider_campaign_id,
  k.day,
  coalesce(c.clicks,0)::bigint as clicks,
  coalesce(c.unique_visitors,0)::bigint as unique_visitors,
  coalesce(e.leads,0)::bigint as leads,
  coalesce(e.qualified_leads,0)::bigint as qualified_leads,
  coalesce(e.bookings,0)::bigint as bookings,
  coalesce(e.sales,0)::bigint as sales,
  coalesce(e.refunds,0)::bigint as refunds
from keys k
join public.pandora_tracking_campaigns p
  on p.id=k.campaign_id and p.tenant_id=k.tenant_id
left join click_agg c
  on c.tenant_id=k.tenant_id
 and c.campaign_id=k.campaign_id
 and c.day=k.day
left join event_agg e
  on e.tenant_id=k.tenant_id
 and e.campaign_id=k.campaign_id
 and e.day=k.day;

revoke all on public.pandora_tracking_campaign_traffic_daily_v2
  from anon, authenticated;
grant select on public.pandora_tracking_campaign_traffic_daily_v2
  to service_role;

comment on view public.pandora_tracking_campaign_traffic_daily_v2 is
  'Deduplicated currency-neutral first-party traffic and conversion counts; click totals are independent of event multiplicity.';
