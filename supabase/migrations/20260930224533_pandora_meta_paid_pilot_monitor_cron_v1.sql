
begin;

create or replace function public.pandora_meta_monitor_paid_pilot_v1(
  p_authorization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  c private.pandora_meta_zero_delivery_control%rowtype;
  v_runtime jsonb; v_token text; v_spend jsonb; v_campaign jsonb; v_adset jsonb; v_ad jsonb;
  v_minor bigint; v_reason text; v_stop jsonb; v_receipt uuid;
  v_campaign_http integer; v_adset_http integer; v_ad_http integer;
  v_daily_budget bigint;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  select * into a
  from private.pandora_meta_paid_pilot_authorizations
  where id=p_authorization_id
  for update;
  if not found then
    raise exception 'PANDORA_META_PAID_PILOT_AUTHORIZATION_NOT_FOUND' using errcode='P0002';
  end if;

  if a.state not in ('active','prepared') then
    return jsonb_build_object('ok',true,'state',a.state,'action','none');
  end if;

  select * into c
  from private.pandora_meta_zero_delivery_control
  where organization_id=a.organization_id and project_id=a.project_id;

  v_runtime:=public.pandora_meta_runtime_secret_v1(a.organization_id,a.installation_id,'marketing');
  v_token:=v_runtime->>'token';

  v_spend:=private.pandora_meta_pilot_spend_v1(v_token,a.meta_campaign_id);
  v_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  v_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time');
  v_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_token:=null;

  v_minor:=nullif(v_spend->>'spendMinor','')::bigint;
  v_campaign_http:=coalesce((v_campaign->>'httpStatus')::integer,599);
  v_adset_http:=coalesce((v_adset->>'httpStatus')::integer,599);
  v_ad_http:=coalesce((v_ad->>'httpStatus')::integer,599);
  begin v_daily_budget:=nullif(v_adset#>>'{body,daily_budget}','')::bigint; exception when others then v_daily_budget:=null; end;

  if a.state='active' and coalesce(c.kill_switch_active,false) then
    v_reason:='kill_switch';
  elsif coalesce((v_spend->>'httpStatus')::integer,599)<>200
     or v_campaign_http<>200 or v_adset_http<>200 or v_ad_http<>200 then
    v_reason:='meta_auth_or_provider_failure';
  elsif v_minor is not null and v_minor>=a.max_spend_minor then
    v_reason:='lifetime_spend_ceiling_reached';
  elsif clock_timestamp()>=a.end_at then
    v_reason:='pilot_period_elapsed';
  elsif v_daily_budget is null or v_daily_budget<>a.daily_budget_minor then
    v_reason:='spend_divergence';
  elsif a.state='active' and (
      v_campaign#>>'{body,status}'<>'ACTIVE'
      or v_adset#>>'{body,status}'<>'ACTIVE'
      or v_ad#>>'{body,status}'<>'ACTIVE'
    ) then
    v_reason:='provider_state_or_readback_mismatch';
  end if;

  insert into private.pandora_meta_paid_pilot_receipts(
    authorization_id,organization_id,project_id,request_key,action,state,
    before_state,after_state,spend_minor_observed,error_code
  ) values (
    a.id,a.organization_id,a.project_id,
    'monitor-'||to_char(clock_timestamp() at time zone 'UTC','YYYYMMDDHH24MISSMS'),
    'monitor',
    case when v_reason is null then 'confirmed' else 'stop_required' end,
    '{}'::jsonb,
    jsonb_build_object('campaign',v_campaign,'adset',v_adset,'ad',v_ad,'spend',v_spend),
    v_minor,v_reason
  ) returning id into v_receipt;

  if v_reason is not null and a.state='active' then
    v_stop:=public.pandora_meta_stop_paid_pilot_v1(
      a.id,
      'auto-stop-'||replace(v_receipt::text,'-',''),
      v_reason
    );
    return jsonb_build_object(
      'ok',coalesce((v_stop->>'ok')::boolean,false),
      'action','stop','reason',v_reason,
      'spendMinor',v_minor,'stop',v_stop
    );
  end if;

  return jsonb_build_object(
    'ok',true,'action','none','state',a.state,
    'spendMinor',v_minor,'maxSpendMinor',a.max_spend_minor,
    'dailyBudgetMinor',a.daily_budget_minor,'endAt',a.end_at,
    'campaign',v_campaign,'adset',v_adset,'ad',v_ad,
    'killSwitchActive',coalesce(c.kill_switch_active,false)
  );
end;
$function$;

create or replace function public.pandora_meta_monitor_active_paid_pilots_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  r record;
  v_results jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  for r in
    select id
    from private.pandora_meta_paid_pilot_authorizations
    where state='active'
    order by activated_at
  loop
    begin
      v_result:=public.pandora_meta_monitor_paid_pilot_v1(r.id);
    exception when others then
      v_result:=jsonb_build_object('ok',false,'authorizationId',r.id,'error',sqlstate);
    end;
    v_results:=v_results||jsonb_build_array(jsonb_build_object('authorizationId',r.id,'result',v_result));
  end loop;

  return jsonb_build_object('ok',true,'checked',jsonb_array_length(v_results),'results',v_results);
end;
$function$;

revoke all on function public.pandora_meta_monitor_active_paid_pilots_v1()
from public,anon,authenticated;
grant execute on function public.pandora_meta_monitor_active_paid_pilots_v1()
to service_role;

do $block$
declare
  j record;
begin
  for j in select jobid from cron.job where jobname='pandora-meta-paid-pilot-monitor-v1'
  loop
    perform cron.unschedule(j.jobid);
  end loop;
  perform cron.schedule(
    'pandora-meta-paid-pilot-monitor-v1',
    '*/5 * * * *',
    $cron$select public.pandora_meta_monitor_active_paid_pilots_v1();$cron$
  );
end
$block$;

commit;
;
