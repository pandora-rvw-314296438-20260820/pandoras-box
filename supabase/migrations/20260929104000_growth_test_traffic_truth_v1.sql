-- Explicitly separate controlled test traffic from business outcomes and KPIs.
-- No provider delivery, privacy authorization, campaign activation or spend is created here.
begin;

alter table public.pandora_growth_outcome_receipts
  add column if not exists is_test boolean not null default false;

alter table public.pandora_tracking_clicks
  add column if not exists is_test boolean not null default false;

create or replace function public.pandora_ingest_growth_outcome_v1(
  p_event jsonb,
  p_claim_sha256 text,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_org uuid;
  v_tenant uuid;
  v_project uuid;
  v_existing public.pandora_growth_outcome_receipts%rowtype;
  v_receipt_id uuid;
  v_campaign_id uuid;
  v_click_id text;
  v_event_type text;
  v_tracking_event_id uuid;
  v_amount bigint;
  v_currency text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_GROWTH_OUTCOME_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if jsonb_typeof(p_event) is distinct from 'object'
    or not (p_event ? 'is_test')
    or jsonb_typeof(p_event->'is_test') is distinct from 'boolean'
    or p_claim_sha256 !~ '^[0-9a-f]{64}$'
    or p_policy_version !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception 'PANDORA_GROWTH_OUTCOME_INPUT_INVALID' using errcode='22023';
  end if;

  begin
    v_org:=(p_event->>'organization_id')::uuid;
    v_tenant:=(p_event->>'tracking_tenant_id')::uuid;
    v_project:=case when p_event->>'project_id' is null then null
      else (p_event->>'project_id')::uuid end;
  exception when others then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_INVALID' using errcode='22023';
  end;

  if v_project is null or not exists(
    select 1 from public.pandora_tracking_tenants t
    where t.id=v_tenant and t.organization_id=v_org and t.project_id=v_project
      and t.status='active'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_DENIED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    v_org,v_project,p_policy_version,'server_outcomes'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_PRIVACY_HOLD' using errcode='42501';
  end if;

  select * into v_existing
  from public.pandora_growth_outcome_receipts
  where organization_id=v_org and tracking_tenant_id=v_tenant
    and event_name=p_event->>'event_name' and outcome_id=p_event->>'outcome_id'
  for update;
  if found then
    if v_existing.claim_sha256 is distinct from p_claim_sha256
      or v_existing.event_id is distinct from p_event->>'event_id' then
      raise exception 'PANDORA_GROWTH_OUTCOME_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'duplicate',true,'receiptId',v_existing.id,
      'trackingEventId',(
        select e.id from public.pandora_tracking_events e
        where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
          and e.external_event_id=p_event->>'event_id' limit 1
      )
    );
  end if;

  if p_event#>>'{attribution,kind}'='observed' then
    v_click_id:=p_event#>>'{attribution,click_id}';
    select c.campaign_id into v_campaign_id
    from public.pandora_tracking_clicks c
    where c.tenant_id=v_tenant and c.click_id=v_click_id;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_CLICK_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}' in ('platform_reported','inferred') then
    select c.id into v_campaign_id
    from public.pandora_tracking_campaigns c
    where c.tenant_id=v_tenant and c.status='active'
      and c.provider='meta'
      and c.provider_campaign_id=p_event#>>'{attribution,campaign_id}'
      and (not ((p_event#>'{attribution}') ? 'adset_id')
        or c.provider_adset_id=p_event#>>'{attribution,adset_id}')
      and (not ((p_event#>'{attribution}') ? 'ad_id')
        or c.provider_ad_id=p_event#>>'{attribution,ad_id}')
    limit 1;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_PROVIDER_ATTRIBUTION_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}'<>'unattributed' then
    raise exception 'PANDORA_GROWTH_OUTCOME_ATTRIBUTION_INVALID' using errcode='22023';
  end if;

  v_amount:=case when p_event ? 'money' then
    (p_event#>>'{money,amount_minor}')::bigint else null end;
  v_currency:=case when p_event ? 'money' then
    p_event#>>'{money,currency}' else null end;

  insert into public.pandora_growth_outcome_receipts(
    organization_id,tracking_tenant_id,project_id,event_name,event_id,outcome_id,
    acquisition_path,journey_id,subject_id,occurred_at,delivery_source,evidence,
    attribution,amount_minor,currency,retention,is_test,claim_sha256
  ) values (
    v_org,v_tenant,v_project,p_event->>'event_name',p_event->>'event_id',
    p_event->>'outcome_id',p_event->>'acquisition_path',p_event->>'journey_id',
    p_event->>'subject_id',(p_event->>'occurred_at')::timestamptz,
    p_event->>'delivery_source',p_event->'evidence',p_event->'attribution',
    v_amount,v_currency,p_event->'retention',(p_event->>'is_test')::boolean,p_claim_sha256
  ) returning id into v_receipt_id;

  v_event_type:=case p_event->>'event_name'
    when 'lead_submitted' then 'lead'
    when 'lead_qualified' then 'qualified_lead'
    when 'demo_completed' then 'booking'
    when 'payment_settled' then 'sale'
    when 'refund_settled' then 'refund'
    else 'event'
  end;

  insert into public.pandora_tracking_events(
    tenant_id,campaign_id,click_id,event_type,event_name,source,
    external_event_id,value,currency,occurred_at,metadata,
    schema_version,consent,is_test
  ) values (
    v_tenant,v_campaign_id,v_click_id,v_event_type,p_event->>'event_name','server',
    p_event->>'event_id',null,null,(p_event->>'occurred_at')::timestamptz,
    '{}'::jsonb,1,'{"analytics":false,"marketing":false}'::jsonb,(p_event->>'is_test')::boolean
  )
  on conflict (tenant_id,event_name,external_event_id)
    where external_event_id is not null do nothing;

  select e.id into v_tracking_event_id
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
    and e.external_event_id=p_event->>'event_id'
  limit 1;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'receiptId',v_receipt_id,
    'trackingEventId',v_tracking_event_id,
    'isTest',(p_event->>'is_test')::boolean,
    'moneyProjection','minor_units_only'
  );
end;
$function$;
revoke all on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  to service_role;



create or replace view public.pandora_tracking_campaign_daily_v1 as
with click_agg as (
  select tenant_id, campaign_id, occurred_at::date as day,
         count(*)::bigint as clicks
  from public.pandora_tracking_clicks
  where is_test is false
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
  where campaign_id is not null and is_test is false
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

comment on column public.pandora_growth_outcome_receipts.is_test is
  'Controlled/synthetic acceptance marker. Must be explicit in the outcome contract.';
comment on column public.pandora_tracking_clicks.is_test is
  'Controlled test visit marker. Campaign KPI projection excludes these rows.';

commit;
