
begin;

alter table private.pandora_meta_paid_pilot_authorizations
  add column if not exists daily_budget_minor bigint;

update private.pandora_meta_paid_pilot_authorizations
set daily_budget_minor=40000
where id='0150939a-5c04-4899-a82c-bb27a539dacf'::uuid;

alter table private.pandora_meta_paid_pilot_authorizations
  drop constraint if exists pandora_meta_paid_pilot_authorizations_daily_budget_minor_check;
alter table private.pandora_meta_paid_pilot_authorizations
  add constraint pandora_meta_paid_pilot_authorizations_daily_budget_minor_check
  check(daily_budget_minor=40000);

create or replace function public.pandora_meta_prepare_paid_pilot_v1(
  p_authorization_id uuid,
  p_request_key text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  c private.pandora_meta_zero_delivery_control%rowtype;
  v_existing private.pandora_meta_paid_pilot_receipts%rowtype;
  v_runtime jsonb;
  v_token text;
  v_campaign jsonb;
  v_adset jsonb;
  v_ad jsonb;
  v_spend jsonb;
  v_post jsonb;
  v_after jsonb;
  v_end timestamptz;
  v_end_epoch bigint;
  v_receipt uuid;
  v_ok boolean:=false;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$' then
    raise exception 'PANDORA_META_PAID_PILOT_REQUEST_KEY_INVALID' using errcode='22023';
  end if;

  select * into v_existing
  from private.pandora_meta_paid_pilot_receipts
  where request_key=p_request_key;
  if found then
    return jsonb_build_object(
      'ok',v_existing.state='confirmed','duplicate',true,
      'receiptId',v_existing.id,'state',v_existing.state
    );
  end if;

  select * into a
  from private.pandora_meta_paid_pilot_authorizations
  where id=p_authorization_id
  for update;

  if not found
     or a.state<>'approved'
     or a.max_spend_minor<>500000
     or a.daily_budget_minor<>40000
     or a.currency<>'PHP'
     or a.duration_seconds<>604800 then
    raise exception 'PANDORA_META_PAID_PILOT_AUTHORIZATION_INVALID' using errcode='42501';
  end if;

  if private.pandora_meta_zero_delivery_target_is_allowed_v1(
      a.organization_id,a.project_id,a.installation_id,'campaign',a.meta_campaign_id
    ) is not true
     or private.pandora_meta_zero_delivery_target_is_allowed_v1(
      a.organization_id,a.project_id,a.installation_id,'adset',a.meta_adset_id
    ) is not true
     or private.pandora_meta_zero_delivery_target_is_allowed_v1(
      a.organization_id,a.project_id,a.installation_id,'ad',a.meta_ad_id
    ) is not true then
    raise exception 'PANDORA_META_PAID_PILOT_TARGET_DENIED' using errcode='42501';
  end if;

  select * into c
  from private.pandora_meta_zero_delivery_control
  where organization_id=a.organization_id and project_id=a.project_id;
  if not found or c.kill_switch_active is not true then
    raise exception 'PANDORA_META_PAID_PILOT_PREPARE_REQUIRES_KILL_SWITCH' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(a.organization_id,a.installation_id,'marketing');
  v_token:=v_runtime->>'token';

  v_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  v_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time');
  v_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_spend:=private.pandora_meta_pilot_spend_v1(v_token,a.meta_campaign_id);

  if v_campaign#>>'{body,status}'<>'PAUSED'
     or v_adset#>>'{body,status}'<>'PAUSED'
     or v_ad#>>'{body,status}'<>'PAUSED'
     or coalesce((v_spend->>'httpStatus')::integer,0)<>200
     or coalesce((v_spend->>'spendMinor')::bigint,0)<>0 then
    v_token:=null;
    raise exception 'PANDORA_META_PAID_PILOT_PRECONDITION_FAILED' using errcode='42501';
  end if;

  v_end:=clock_timestamp()+make_interval(secs=>a.duration_seconds);
  v_end_epoch:=floor(extract(epoch from v_end))::bigint;

  insert into private.pandora_meta_paid_pilot_receipts(
    authorization_id,organization_id,project_id,request_key,action,state,
    before_state,spend_minor_observed
  ) values (
    a.id,a.organization_id,a.project_id,p_request_key,'prepare','submitted',
    jsonb_build_object('campaign',v_campaign,'adset',v_adset,'ad',v_ad,'spend',v_spend),
    coalesce((v_spend->>'spendMinor')::bigint,0)
  ) returning id into v_receipt;

  v_post:=private.pandora_meta_pilot_post_v1(
    v_token,a.meta_adset_id,
    'daily_budget='||a.daily_budget_minor::text||'&end_time='||v_end_epoch::text
  );

  v_after:=private.pandora_meta_pilot_get_v1(
    v_token,a.meta_adset_id,
    'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time'
  );
  v_token:=null;

  v_ok:=coalesce((v_post->>'accepted')::boolean,false)
    and v_after#>>'{body,status}'='PAUSED'
    and coalesce(nullif(v_after#>>'{body,daily_budget}','')::bigint,0)=a.daily_budget_minor
    and coalesce(nullif(v_after#>>'{body,lifetime_budget}','')::bigint,0)=0;

  update private.pandora_meta_paid_pilot_receipts
  set state=case when v_ok then 'confirmed' else 'failed' end,
      provider_responses=jsonb_build_object('budgetUpdate',v_post),
      after_state=jsonb_build_object('adset',v_after),
      error_code=case when v_ok then null else 'recurring_budget_unconfirmed' end,
      updated_at=clock_timestamp()
  where id=v_receipt;

  if v_ok then
    update private.pandora_meta_paid_pilot_authorizations
    set state='prepared',
        prepared_at=clock_timestamp(),
        end_at=v_end,
        last_receipt_id=v_receipt,
        updated_at=clock_timestamp()
    where id=a.id;
  end if;

  return jsonb_build_object(
    'ok',v_ok,
    'receiptId',v_receipt,
    'state',case when v_ok then 'prepared' else 'failed' end,
    'dailyBudgetMinor',a.daily_budget_minor,
    'maxSpendMinor',a.max_spend_minor,
    'currency',a.currency,
    'endAt',v_end,
    'killSwitchActive',true,
    'spendObservedMinor',coalesce((v_spend->>'spendMinor')::bigint,0),
    'providerBudgetResponse',v_post,
    'providerAdsetAfter',v_after
  );
end;
$function$;

commit;
;
