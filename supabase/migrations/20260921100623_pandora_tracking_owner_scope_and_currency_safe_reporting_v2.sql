alter table public.pandora_tracking_tenants
  add column if not exists organization_id uuid,
  add column if not exists project_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='pandora_tracking_tenants_organization_fk'
  ) then
    alter table public.pandora_tracking_tenants
      add constraint pandora_tracking_tenants_organization_fk
      foreign key (organization_id) references public.organizations(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname='pandora_tracking_tenants_project_fk'
  ) then
    alter table public.pandora_tracking_tenants
      add constraint pandora_tracking_tenants_project_fk
      foreign key (project_id) references public.projectos_projects(id) on delete set null;
  end if;
end $$;

create index if not exists pandora_tracking_tenants_organization_idx
  on public.pandora_tracking_tenants (organization_id, status);
create index if not exists pandora_tracking_tenants_project_idx
  on public.pandora_tracking_tenants (project_id)
  where project_id is not null;

create or replace function public.pandora_tracking_validate_tenant_scope_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.project_id is not null then
    if new.organization_id is null then
      raise exception 'tracking project scope requires organization scope'
        using errcode='23514';
    end if;
    if not exists (
      select 1
      from public.projectos_projects p
      where p.id=new.project_id
        and p.organization_id=new.organization_id
    ) then
      raise exception 'tracking project does not belong to tracking organization'
        using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_tracking_tenant_scope_guard
  on public.pandora_tracking_tenants;
create trigger pandora_tracking_tenant_scope_guard
before insert or update of organization_id,project_id
on public.pandora_tracking_tenants
for each row execute function public.pandora_tracking_validate_tenant_scope_v1();

create or replace view public.pandora_tracking_campaign_traffic_daily_v2 as
select
  c.tenant_id,
  c.campaign_id,
  p.slug,
  p.name as campaign_name,
  p.provider,
  p.provider_campaign_id,
  c.occurred_at::date as day,
  count(*)::bigint as clicks,
  count(distinct c.visitor_hash) filter (where c.visitor_hash is not null)::bigint as unique_visitors,
  count(e.id) filter (where e.event_type='lead')::bigint as leads,
  count(e.id) filter (where e.event_type='qualified_lead')::bigint as qualified_leads,
  count(e.id) filter (where e.event_type='booking')::bigint as bookings,
  count(e.id) filter (where e.event_type='sale')::bigint as sales,
  count(e.id) filter (where e.event_type='refund')::bigint as refunds
from public.pandora_tracking_clicks c
join public.pandora_tracking_campaigns p
  on p.id=c.campaign_id and p.tenant_id=c.tenant_id
left join public.pandora_tracking_events e
  on e.tenant_id=c.tenant_id and e.click_id=c.click_id
group by
  c.tenant_id,c.campaign_id,p.slug,p.name,p.provider,p.provider_campaign_id,c.occurred_at::date;

create or replace view public.pandora_tracking_campaign_financial_daily_v2 as
with event_money as (
  select
    tenant_id,
    campaign_id,
    occurred_at::date as day,
    currency,
    count(*) filter (where event_type='sale')::bigint as monetized_sales,
    count(*) filter (where event_type='refund')::bigint as monetized_refunds,
    coalesce(sum(value) filter (where event_type='sale'),0)::numeric(18,4) as gross_revenue,
    coalesce(sum(value) filter (where event_type='refund'),0)::numeric(18,4) as refund_value
  from public.pandora_tracking_events
  where campaign_id is not null
    and currency is not null
    and event_type in ('sale','refund')
  group by tenant_id,campaign_id,occurred_at::date,currency
),
cost_money as (
  select
    tenant_id,
    campaign_id,
    bucket_date as day,
    currency,
    coalesce(sum(spend),0)::numeric(18,4) as spend,
    coalesce(sum(impressions),0)::bigint as impressions,
    coalesce(sum(provider_clicks),0)::bigint as provider_clicks
  from public.pandora_tracking_costs
  where campaign_id is not null
  group by tenant_id,campaign_id,bucket_date,currency
),
money_keys as (
  select tenant_id,campaign_id,day,currency from event_money
  union
  select tenant_id,campaign_id,day,currency from cost_money
),
all_sales as (
  select
    tenant_id,
    campaign_id,
    occurred_at::date as day,
    count(*) filter (where event_type='sale')::bigint as total_sales
  from public.pandora_tracking_events
  where campaign_id is not null
  group by tenant_id,campaign_id,occurred_at::date
)
select
  k.tenant_id,
  k.campaign_id,
  p.slug,
  p.name as campaign_name,
  p.provider,
  p.provider_campaign_id,
  k.day,
  k.currency,
  coalesce(cm.impressions,0)::bigint as impressions,
  coalesce(cm.provider_clicks,0)::bigint as provider_clicks,
  coalesce(em.monetized_sales,0)::bigint as monetized_sales,
  coalesce(em.monetized_refunds,0)::bigint as monetized_refunds,
  coalesce(cm.spend,0)::numeric(18,4) as spend,
  (coalesce(em.gross_revenue,0)-coalesce(em.refund_value,0))::numeric(18,4) as net_revenue,
  case
    when coalesce(s.total_sales,0) > 0
      then round(coalesce(cm.spend,0) / s.total_sales,4)
    else null
  end as cac,
  case
    when coalesce(cm.spend,0) > 0
      then round(
        (coalesce(em.gross_revenue,0)-coalesce(em.refund_value,0)) / cm.spend,
        4
      )
    else null
  end as roas
from money_keys k
join public.pandora_tracking_campaigns p
  on p.id=k.campaign_id and p.tenant_id=k.tenant_id
left join event_money em
  on em.tenant_id=k.tenant_id
 and em.campaign_id=k.campaign_id
 and em.day=k.day
 and em.currency=k.currency
left join cost_money cm
  on cm.tenant_id=k.tenant_id
 and cm.campaign_id=k.campaign_id
 and cm.day=k.day
 and cm.currency=k.currency
left join all_sales s
  on s.tenant_id=k.tenant_id
 and s.campaign_id=k.campaign_id
 and s.day=k.day;

revoke all on public.pandora_tracking_campaign_traffic_daily_v2
  from anon, authenticated;
revoke all on public.pandora_tracking_campaign_financial_daily_v2
  from anon, authenticated;
grant select on public.pandora_tracking_campaign_traffic_daily_v2
  to service_role;
grant select on public.pandora_tracking_campaign_financial_daily_v2
  to service_role;

comment on view public.pandora_tracking_campaign_traffic_daily_v2 is
  'Currency-neutral first-party traffic and conversion counts for Pandora Tracking.';
comment on view public.pandora_tracking_campaign_financial_daily_v2 is
  'Currency-isolated spend, revenue, CAC and ROAS; never aggregates money across currencies.';
