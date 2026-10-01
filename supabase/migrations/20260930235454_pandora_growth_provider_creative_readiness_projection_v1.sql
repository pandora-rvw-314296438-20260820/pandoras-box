
begin;

create or replace function private.pandora_growth_paid_pilot_projection_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  r private.pandora_meta_paid_pilot_receipts%rowtype;
  c public.pandora_tracking_campaigns%rowtype;
  v_delivery jsonb:='{}'::jsonb;
  v_impressions bigint;
  v_clicks bigint;
  v_spend_minor bigint;
  v_monitor_healthy boolean:=false;
  v_provider_creative_ready boolean:=false;
begin
  select * into a
  from private.pandora_meta_paid_pilot_authorizations
  where organization_id=p_organization_id
    and project_id=p_project_id
  order by updated_at desc,created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'exists',false,
      'state','none',
      'authorizationGranted',false,
      'spendAuthorized',false,
      'deliveryAuthorized',false,
      'monitorHealthy',false,
      'providerCreativeReady',false
    );
  end if;

  select * into c
  from public.pandora_tracking_campaigns
  where id=a.tracking_campaign_id;

  v_provider_creative_ready:=
    coalesce((c.metadata->>'provider_creative_ready')::boolean,false);

  select * into r
  from private.pandora_meta_paid_pilot_receipts
  where authorization_id=a.id
    and action='monitor'
  order by created_at desc
  limit 1;

  if found then
    v_spend_minor:=r.spend_minor_observed;
    v_monitor_healthy:=
      r.state='confirmed'
      and r.error_code is null
      and r.created_at >= clock_timestamp()-interval '10 minutes';

    if jsonb_typeof(r.after_state#>'{spend,body,data}')='array'
       and jsonb_array_length(r.after_state#>'{spend,body,data}')>0 then
      begin
        v_impressions:=nullif(r.after_state#>>'{spend,body,data,0,impressions}','')::bigint;
      exception when others then v_impressions:=null; end;
      begin
        v_clicks:=nullif(r.after_state#>>'{spend,body,data,0,clicks}','')::bigint;
      exception when others then v_clicks:=null; end;
      v_delivery:=r.after_state#>'{spend,body,data,0}';
    end if;
  end if;

  return jsonb_build_object(
    'exists',true,
    'authorizationId',a.id,
    'state',a.state,
    'authorizationGranted',a.state in ('approved','prepared','active','stopped','completed'),
    'spendAuthorized',a.state in ('approved','prepared','active'),
    'deliveryAuthorized',a.state='active',
    'providerCreativeReady',v_provider_creative_ready,
    'providerCreativeBlocker',c.metadata->>'provider_creative_blocker',
    'trackingCampaignId',c.id,
    'trackingCampaignSlug',c.slug,
    'trackingMode',c.metadata->>'tracking_mode',
    'trackedRedirect',c.metadata->>'tracked_redirect',
    'businessKpi',coalesce((c.metadata->>'business_kpi')::boolean,false),
    'currency',a.currency,
    'maxSpendMinor',a.max_spend_minor,
    'dailyBudgetMinor',a.daily_budget_minor,
    'spendMinor',v_spend_minor,
    'remainingSpendMinor',case
      when v_spend_minor is null then null
      else greatest(a.max_spend_minor-v_spend_minor,0)
    end,
    'durationSeconds',a.duration_seconds,
    'authorizedAt',a.authorized_at,
    'preparedAt',a.prepared_at,
    'activatedAt',a.activated_at,
    'endAt',a.end_at,
    'stoppedAt',a.stopped_at,
    'adAccountId',a.ad_account_id,
    'campaignId',a.meta_campaign_id,
    'adsetId',a.meta_adset_id,
    'adId',a.meta_ad_id,
    'stopConditions',a.stop_conditions,
    'approvedBy',a.approved_by,
    'evidenceRef',a.evidence_ref,
    'lastMonitorReceiptId',r.id,
    'lastMonitorAt',r.created_at,
    'lastMonitorState',r.state,
    'lastMonitorError',r.error_code,
    'monitorHealthy',v_monitor_healthy,
    'deliveryObserved',coalesce(v_impressions,0)>0
      or coalesce(v_clicks,0)>0
      or coalesce(v_spend_minor,0)>0,
    'impressions',v_impressions,
    'clicks',v_clicks,
    'delivery',v_delivery
  );
end;
$function$;

revoke all on function private.pandora_growth_paid_pilot_projection_v1(uuid,uuid)
from public,anon,authenticated,service_role;

do $assert$
declare
  v jsonb;
begin
  v:=private.pandora_growth_paid_pilot_projection_v1(
    '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
    'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  );
  if v->>'trackingCampaignSlug'<>'pandora-meta-main'
     or v->>'trackingMode'<>'business'
     or coalesce((v->>'businessKpi')::boolean,false) is not true
     or v->>'trackedRedirect'<>'https://mcpmaster.vercel.app/t/pandora-meta-main'
     or coalesce((v->>'providerCreativeReady')::boolean,true) is not false
     or v->>'providerCreativeBlocker'<>'meta_app_development_mode' then
    raise exception 'PANDORA_GROWTH_PROVIDER_READINESS_PROJECTION_ASSERTION_FAILED';
  end if;
end
$assert$;

commit;
;
