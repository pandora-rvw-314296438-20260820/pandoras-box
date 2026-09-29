-- G2 controlled CAPI acceptance and exact campaign binding.
-- Controlled-test events remain locally labeled and excluded from business KPIs.
-- This migration does not create privacy authority, spend authority or ad delivery.
begin;

create or replace function public.pandora_meta_enqueue_conversion_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_event_id uuid,
  p_binding_id uuid,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_event public.pandora_tracking_events%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_match private.pandora_meta_conversion_match_keys%rowtype;
  v_meta_name text;
  v_id uuid;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_CONVERSION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,p_policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_CONVERSION_PRIVACY_HOLD' using errcode='42501';
  end if;

  select e.* into v_event
  from public.pandora_tracking_events e
  join public.pandora_tracking_tenants t on t.id=e.tenant_id
  join public.pandora_tracking_campaigns c
    on c.id=e.campaign_id and c.tenant_id=e.tenant_id
  where e.id=p_tracking_event_id and t.organization_id=p_organization_id
    and t.project_id=p_project_id and e.source='server'
    and e.external_event_id is not null
    and (
      e.is_test is false
      or (
        e.is_test is true
        and c.provider='meta'
        and c.metadata->>'purpose'='controlled-test'
        and c.metadata->'business_kpi' is not distinct from 'false'::jsonb
        and c.metadata->'delivery_authorized' is not distinct from 'false'::jsonb
      )
    )
    and coalesce((e.consent->>'marketing')::boolean,false) is true
    and e.event_type in ('lead','qualified_lead','booking','sale')
  for update of e;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_EVENT_INELIGIBLE' using errcode='42501';
  end if;

  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.id=p_binding_id and b.organization_id=p_organization_id
    and b.project_id=p_project_id and b.tracking_tenant_id=v_event.tenant_id
    and b.tracking_campaign_id=v_event.campaign_id
  for share;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_BINDING_DENIED' using errcode='42501';
  end if;

  select * into v_match
  from private.pandora_meta_conversion_match_keys m
  where m.tracking_event_id=v_event.id and m.organization_id=p_organization_id
    and m.project_id=p_project_id and m.policy_version=p_policy_version;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_MATCH_REQUIRED' using errcode='42501';
  end if;

  v_meta_name:=case v_event.event_type
    when 'lead' then 'Lead'
    when 'qualified_lead' then 'Lead'
    when 'booking' then 'Schedule'
    when 'sale' then 'Purchase'
  end;

  insert into private.pandora_meta_conversion_outbox(
    organization_id,project_id,tracking_event_id,binding_id,policy_version,
    event_id,meta_event_name
  ) values (
    p_organization_id,p_project_id,v_event.id,v_binding.id,p_policy_version,
    v_event.external_event_id,v_meta_name
  )
  on conflict(organization_id,event_id) do update
  set updated_at=private.pandora_meta_conversion_outbox.updated_at
  returning id into v_id;
  return jsonb_build_object('ok',true,'outboxId',v_id,'state','pending');
end;
$function$;
revoke all on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
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
left join cost_agg co on co.tenant_id=k.tenant_id and co.campaign_id=k.campaign_id and co.day=k.day
where c.metadata->'business_kpi' is distinct from 'false'::jsonb;



comment on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text) is
  'Consent/privacy-gated conversion enqueue. Test events are eligible only on an exact controlled-test tracking campaign whose business_kpi and delivery_authorized metadata are both false; the exact event campaign must match the measurement binding.';

commit;
