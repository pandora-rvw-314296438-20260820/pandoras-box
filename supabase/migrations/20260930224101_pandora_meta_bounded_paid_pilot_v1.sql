
begin;

create table if not exists private.pandora_meta_paid_pilot_authorizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  installation_id uuid not null,
  tracking_campaign_id uuid not null references public.pandora_tracking_campaigns(id) on delete restrict,
  ad_account_id text not null,
  meta_campaign_id text not null,
  meta_adset_id text not null,
  meta_ad_id text not null,
  currency text not null check(currency='PHP'),
  max_spend_minor bigint not null check(max_spend_minor=500000),
  duration_seconds integer not null check(duration_seconds=604800),
  stop_conditions jsonb not null check(jsonb_typeof(stop_conditions)='array'),
  approved_by text not null,
  evidence_ref text not null,
  authorized_at timestamptz not null,
  state text not null check(state in ('approved','prepared','active','stopped','completed','failed')),
  prepared_at timestamptz,
  activated_at timestamptz,
  end_at timestamptz,
  stopped_at timestamptz,
  last_receipt_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,meta_campaign_id)
);
alter table private.pandora_meta_paid_pilot_authorizations enable row level security;
revoke all on private.pandora_meta_paid_pilot_authorizations from public,anon,authenticated,service_role;

create table if not exists private.pandora_meta_paid_pilot_receipts (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references private.pandora_meta_paid_pilot_authorizations(id) on delete restrict,
  organization_id uuid not null,
  project_id uuid not null,
  request_key text not null,
  action text not null check(action in ('prepare','activate','monitor','stop')),
  state text not null,
  before_state jsonb not null default '{}'::jsonb,
  provider_responses jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  spend_minor_observed bigint,
  error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,request_key)
);
alter table private.pandora_meta_paid_pilot_receipts enable row level security;
revoke all on private.pandora_meta_paid_pilot_receipts from public,anon,authenticated,service_role;

insert into private.pandora_meta_paid_pilot_authorizations(
  organization_id,project_id,installation_id,tracking_campaign_id,ad_account_id,
  meta_campaign_id,meta_adset_id,meta_ad_id,currency,max_spend_minor,duration_seconds,
  stop_conditions,approved_by,evidence_ref,authorized_at,state
)
select
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
  '2582faeb-5431-427b-93ba-d7e803eba3c1'::uuid,
  b.tracking_campaign_id,
  'act_993057100414281',
  '120251929350590047',
  '120251929352200047',
  '120251929352870047',
  'PHP',
  500000,
  604800,
  '[
    "manual_owner_stop",
    "lifetime_spend_ceiling_reached",
    "pilot_period_elapsed",
    "meta_auth_or_provider_failure",
    "provider_state_or_readback_mismatch",
    "spend_divergence",
    "stale_or_invalid_measurement_evidence",
    "kill_switch"
  ]'::jsonb,
  'owner-current-chat-2026-10-01',
  'owner delegated pilot envelope selection: You do it; assistant selected smallest meaningful bounded pilot: PHP 5000 total / 7 days',
  '2026-09-30T22:15:00Z'::timestamptz,
  'approved'
from private.pandora_meta_measurement_bindings b
join public.pandora_tracking_campaigns c on c.id=b.tracking_campaign_id
where b.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and b.project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and b.installation_id='2582faeb-5431-427b-93ba-d7e803eba3c1'::uuid
  and b.meta_campaign_id='120251929350590047'
  and b.meta_adset_id='120251929352200047'
  and b.meta_ad_id='120251929352870047'
  and c.metadata->>'purpose'='controlled-test'
  and c.metadata->'business_kpi' is not distinct from 'false'::jsonb
on conflict(organization_id,project_id,meta_campaign_id) do update
set ad_account_id=excluded.ad_account_id,
    meta_adset_id=excluded.meta_adset_id,
    meta_ad_id=excluded.meta_ad_id,
    currency=excluded.currency,
    max_spend_minor=excluded.max_spend_minor,
    duration_seconds=excluded.duration_seconds,
    stop_conditions=excluded.stop_conditions,
    approved_by=excluded.approved_by,
    evidence_ref=excluded.evidence_ref,
    authorized_at=excluded.authorized_at,
    state=case
      when private.pandora_meta_paid_pilot_authorizations.state in ('active','stopped','completed')
        then private.pandora_meta_paid_pilot_authorizations.state
      else 'approved'
    end,
    updated_at=clock_timestamp();

create or replace function private.pandora_meta_pilot_get_v1(
  p_token text,
  p_id text,
  p_fields text
) returns jsonb
language plpgsql
set search_path='pg_catalog','extensions'
as $function$
declare
  v_resp extensions.http_response;
begin
  select * into v_resp from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||p_id||'?fields='||p_fields)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||p_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Paid-Pilot/1.0')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  return jsonb_build_object(
    'httpStatus',v_resp.status,
    'body',case when nullif(v_resp.content,'') is null then '{}'::jsonb else v_resp.content::jsonb end
  );
exception when others then
  return jsonb_build_object('httpStatus',599,'body','{}'::jsonb,'error','provider_read_failed');
end;
$function$;
revoke all on function private.pandora_meta_pilot_get_v1(text,text,text)
from public,anon,authenticated,service_role;

create or replace function private.pandora_meta_pilot_post_v1(
  p_token text,
  p_id text,
  p_form text
) returns jsonb
language plpgsql
set search_path='pg_catalog','extensions'
as $function$
declare
  v_resp extensions.http_response;
  v_body jsonb;
begin
  select * into v_resp from extensions.http((
    'POST'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||p_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||p_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','application/x-www-form-urlencoded'),
      extensions.http_header('user-agent','Pandora-Paid-Pilot/1.0')
    ]::extensions.http_header[],
    'application/x-www-form-urlencoded'::varchar,
    p_form::varchar
  )::extensions.http_request);
  begin
    v_body:=case when nullif(v_resp.content,'') is null then '{}'::jsonb else v_resp.content::jsonb end;
  exception when others then
    v_body:='{}'::jsonb;
  end;
  return jsonb_build_object(
    'httpStatus',v_resp.status,
    'accepted',v_resp.status=200 and coalesce((v_body->>'success')::boolean,false),
    'body',case when jsonb_typeof(v_body)='object' then v_body-'access_token'-'token' else '{}'::jsonb end
  );
exception when others then
  return jsonb_build_object('httpStatus',599,'accepted',false,'body','{}'::jsonb,'error','provider_write_failed');
end;
$function$;
revoke all on function private.pandora_meta_pilot_post_v1(text,text,text)
from public,anon,authenticated,service_role;

create or replace function private.pandora_meta_pilot_spend_v1(
  p_token text,
  p_campaign_id text
) returns jsonb
language plpgsql
set search_path='pg_catalog','extensions'
as $function$
declare
  v_resp extensions.http_response;
  v_body jsonb;
  v_spend numeric:=0;
  v_minor bigint:=0;
begin
  select * into v_resp from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||p_campaign_id||
      '/insights?fields=spend,impressions,clicks&date_preset=maximum')::varchar,
    array[
      extensions.http_header('authorization','Bearer '||p_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Paid-Pilot/1.0')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  begin
    v_body:=case when nullif(v_resp.content,'') is null then '{}'::jsonb else v_resp.content::jsonb end;
  exception when others then
    v_body:='{}'::jsonb;
  end;
  if v_resp.status=200 and jsonb_typeof(v_body->'data')='array' and jsonb_array_length(v_body->'data')>0 then
    begin v_spend:=coalesce((v_body->'data'->0->>'spend')::numeric,0); exception when others then v_spend:=0; end;
  end if;
  v_minor:=round(v_spend*100)::bigint;
  return jsonb_build_object(
    'httpStatus',v_resp.status,
    'spendMinor',v_minor,
    'spendMajor',v_spend,
    'currency','PHP',
    'body',v_body
  );
exception when others then
  return jsonb_build_object('httpStatus',599,'spendMinor',null,'currency','PHP','body','{}'::jsonb);
end;
$function$;
revoke all on function private.pandora_meta_pilot_spend_v1(text,text)
from public,anon,authenticated,service_role;

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

  select * into v_existing from private.pandora_meta_paid_pilot_receipts
  where request_key=p_request_key;
  if found then
    return jsonb_build_object('ok',v_existing.state='confirmed','duplicate',true,'receiptId',v_existing.id,'state',v_existing.state);
  end if;

  select * into a from private.pandora_meta_paid_pilot_authorizations
  where id=p_authorization_id for update;
  if not found or a.state<>'approved' or a.max_spend_minor<>500000 or a.currency<>'PHP' or a.duration_seconds<>604800 then
    raise exception 'PANDORA_META_PAID_PILOT_AUTHORIZATION_INVALID' using errcode='42501';
  end if;
  if private.pandora_meta_zero_delivery_target_is_allowed_v1(a.organization_id,a.project_id,a.installation_id,'campaign',a.meta_campaign_id) is not true
     or private.pandora_meta_zero_delivery_target_is_allowed_v1(a.organization_id,a.project_id,a.installation_id,'adset',a.meta_adset_id) is not true
     or private.pandora_meta_zero_delivery_target_is_allowed_v1(a.organization_id,a.project_id,a.installation_id,'ad',a.meta_ad_id) is not true then
    raise exception 'PANDORA_META_PAID_PILOT_TARGET_DENIED' using errcode='42501';
  end if;

  select * into c from private.pandora_meta_zero_delivery_control
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
    authorization_id,organization_id,project_id,request_key,action,state,before_state,spend_minor_observed
  ) values (
    a.id,a.organization_id,a.project_id,p_request_key,'prepare','submitted',
    jsonb_build_object('campaign',v_campaign,'adset',v_adset,'ad',v_ad,'spend',v_spend),
    coalesce((v_spend->>'spendMinor')::bigint,0)
  ) returning id into v_receipt;

  v_post:=private.pandora_meta_pilot_post_v1(
    v_token,a.meta_adset_id,
    'daily_budget=0&lifetime_budget='||a.max_spend_minor::text||'&end_time='||v_end_epoch::text
  );
  v_after:=private.pandora_meta_pilot_get_v1(
    v_token,a.meta_adset_id,
    'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time'
  );
  v_token:=null;

  v_ok:=coalesce((v_post->>'accepted')::boolean,false)
    and v_after#>>'{body,status}'='PAUSED'
    and coalesce(nullif(v_after#>>'{body,lifetime_budget}','')::bigint,0)=a.max_spend_minor;

  update private.pandora_meta_paid_pilot_receipts
  set state=case when v_ok then 'confirmed' else 'failed' end,
      provider_responses=jsonb_build_object('budgetUpdate',v_post),
      after_state=jsonb_build_object('adset',v_after),
      error_code=case when v_ok then null else 'budget_cap_unconfirmed' end,
      updated_at=clock_timestamp()
  where id=v_receipt;

  if v_ok then
    update private.pandora_meta_paid_pilot_authorizations
    set state='prepared',prepared_at=clock_timestamp(),end_at=v_end,last_receipt_id=v_receipt,updated_at=clock_timestamp()
    where id=a.id;
  end if;

  return jsonb_build_object(
    'ok',v_ok,'receiptId',v_receipt,'state',case when v_ok then 'prepared' else 'failed' end,
    'maxSpendMinor',a.max_spend_minor,'currency',a.currency,'endAt',v_end,
    'killSwitchActive',true,'spendObservedMinor',coalesce((v_spend->>'spendMinor')::bigint,0),
    'providerBudgetResponse',v_post,'providerAdsetAfter',v_after
  );
end;
$function$;
revoke all on function public.pandora_meta_prepare_paid_pilot_v1(uuid,text)
from public,anon,authenticated;
grant execute on function public.pandora_meta_prepare_paid_pilot_v1(uuid,text)
to service_role;

create or replace function public.pandora_meta_stop_paid_pilot_v1(
  p_authorization_id uuid,
  p_request_key text,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  v_existing private.pandora_meta_paid_pilot_receipts%rowtype;
  v_runtime jsonb; v_token text;
  r_campaign jsonb; r_adset jsonb; r_ad jsonb;
  v_after_campaign jsonb; v_after_adset jsonb; v_after_ad jsonb; v_spend jsonb;
  v_receipt uuid; v_ok boolean;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'
     or char_length(coalesce(btrim(p_reason),'')) not between 3 and 1000 then
    raise exception 'PANDORA_META_PAID_PILOT_STOP_INPUT_INVALID' using errcode='22023';
  end if;
  select * into v_existing from private.pandora_meta_paid_pilot_receipts where request_key=p_request_key;
  if found then
    return jsonb_build_object('ok',v_existing.state='confirmed','duplicate',true,'receiptId',v_existing.id,'state',v_existing.state);
  end if;
  select * into a from private.pandora_meta_paid_pilot_authorizations where id=p_authorization_id for update;
  if not found then raise exception 'PANDORA_META_PAID_PILOT_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(a.organization_id,a.installation_id,'marketing');
  v_token:=v_runtime->>'token';

  insert into private.pandora_meta_paid_pilot_receipts(
    authorization_id,organization_id,project_id,request_key,action,state,before_state
  ) values (
    a.id,a.organization_id,a.project_id,p_request_key,'stop','submitted',
    jsonb_build_object(
      'campaign',private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status'),
      'adset',private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status'),
      'ad',private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status')
    )
  ) returning id into v_receipt;

  r_campaign:=private.pandora_meta_pilot_post_v1(v_token,a.meta_campaign_id,'status=PAUSED');
  r_adset:=private.pandora_meta_pilot_post_v1(v_token,a.meta_adset_id,'status=PAUSED');
  r_ad:=private.pandora_meta_pilot_post_v1(v_token,a.meta_ad_id,'status=PAUSED');

  v_after_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  v_after_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status');
  v_after_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_spend:=private.pandora_meta_pilot_spend_v1(v_token,a.meta_campaign_id);
  v_token:=null;

  v_ok:=v_after_campaign#>>'{body,status}'='PAUSED'
    and v_after_adset#>>'{body,status}'='PAUSED'
    and v_after_ad#>>'{body,status}'='PAUSED';

  perform public.pandora_meta_set_zero_delivery_kill_switch_v1(
    a.organization_id,a.project_id,true,'paid-pilot stop: '||btrim(p_reason)
  );

  update public.pandora_tracking_campaigns
  set metadata=metadata||jsonb_build_object(
      'delivery_authorized',false,
      'paid_pilot_state','stopped',
      'paid_pilot_stop_reason',btrim(p_reason)
    ),
    updated_at=clock_timestamp()
  where id=a.tracking_campaign_id;

  update private.pandora_meta_paid_pilot_authorizations
  set state=case when v_ok then 'stopped' else 'failed' end,
      stopped_at=clock_timestamp(),last_receipt_id=v_receipt,updated_at=clock_timestamp()
  where id=a.id;

  update private.pandora_meta_paid_pilot_receipts
  set state=case when v_ok then 'confirmed' else 'failed' end,
      provider_responses=jsonb_build_object('campaignPause',r_campaign,'adsetPause',r_adset,'adPause',r_ad),
      after_state=jsonb_build_object('campaign',v_after_campaign,'adset',v_after_adset,'ad',v_after_ad),
      spend_minor_observed=nullif(v_spend->>'spendMinor','')::bigint,
      error_code=case when v_ok then null else 'pause_state_unconfirmed' end,
      updated_at=clock_timestamp()
  where id=v_receipt;

  return jsonb_build_object(
    'ok',v_ok,'receiptId',v_receipt,'state',case when v_ok then 'stopped' else 'failed' end,
    'reason',btrim(p_reason),'spendMinor',v_spend->'spendMinor',
    'campaign',v_after_campaign,'adset',v_after_adset,'ad',v_after_ad,
    'killSwitchActive',true
  );
end;
$function$;
revoke all on function public.pandora_meta_stop_paid_pilot_v1(uuid,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_meta_stop_paid_pilot_v1(uuid,text,text)
to service_role;

create or replace function public.pandora_meta_activate_paid_pilot_v1(
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
  v_runtime jsonb; v_token text;
  b_campaign jsonb; b_adset jsonb; b_ad jsonb; v_spend jsonb;
  r_ad jsonb; r_adset jsonb; r_campaign jsonb;
  a_campaign jsonb; a_adset jsonb; a_ad jsonb;
  v_receipt uuid; v_ok boolean:=false; v_comp jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$' then
    raise exception 'PANDORA_META_PAID_PILOT_REQUEST_KEY_INVALID' using errcode='22023';
  end if;

  select * into v_existing from private.pandora_meta_paid_pilot_receipts where request_key=p_request_key;
  if found then
    return jsonb_build_object('ok',v_existing.state='confirmed','duplicate',true,'receiptId',v_existing.id,'state',v_existing.state);
  end if;

  select * into a from private.pandora_meta_paid_pilot_authorizations
  where id=p_authorization_id for update;
  if not found or a.state<>'prepared' or a.end_at<=clock_timestamp() then
    raise exception 'PANDORA_META_PAID_PILOT_NOT_PREPARED' using errcode='42501';
  end if;

  select * into c from private.pandora_meta_zero_delivery_control
  where organization_id=a.organization_id and project_id=a.project_id;
  if not found or c.kill_switch_active is not true then
    raise exception 'PANDORA_META_PAID_PILOT_ACTIVATE_REQUIRES_KILL_SWITCH' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(a.organization_id,a.installation_id,'marketing');
  v_token:=v_runtime->>'token';
  b_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  b_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time');
  b_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_spend:=private.pandora_meta_pilot_spend_v1(v_token,a.meta_campaign_id);

  if b_campaign#>>'{body,status}'<>'PAUSED'
     or b_adset#>>'{body,status}'<>'PAUSED'
     or b_ad#>>'{body,status}'<>'PAUSED'
     or coalesce(nullif(b_adset#>>'{body,lifetime_budget}','')::bigint,0)<>a.max_spend_minor
     or coalesce((v_spend->>'spendMinor')::bigint,0)<>0 then
    v_token:=null;
    raise exception 'PANDORA_META_PAID_PILOT_ACTIVATION_PRECONDITION_FAILED' using errcode='42501';
  end if;

  insert into private.pandora_meta_paid_pilot_receipts(
    authorization_id,organization_id,project_id,request_key,action,state,before_state,spend_minor_observed
  ) values (
    a.id,a.organization_id,a.project_id,p_request_key,'activate','submitted',
    jsonb_build_object('campaign',b_campaign,'adset',b_adset,'ad',b_ad,'spend',v_spend),
    coalesce((v_spend->>'spendMinor')::bigint,0)
  ) returning id into v_receipt;

  -- Bottom-up activation keeps the campaign paused until the last write.
  r_ad:=private.pandora_meta_pilot_post_v1(v_token,a.meta_ad_id,'status=ACTIVE');
  if coalesce((r_ad->>'accepted')::boolean,false) then
    r_adset:=private.pandora_meta_pilot_post_v1(v_token,a.meta_adset_id,'status=ACTIVE');
  else
    r_adset:=jsonb_build_object('accepted',false,'skipped',true);
  end if;
  if coalesce((r_adset->>'accepted')::boolean,false) then
    r_campaign:=private.pandora_meta_pilot_post_v1(v_token,a.meta_campaign_id,'status=ACTIVE');
  else
    r_campaign:=jsonb_build_object('accepted',false,'skipped',true);
  end if;

  a_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  a_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status,daily_budget,lifetime_budget,budget_remaining,end_time');
  a_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_token:=null;

  v_ok:=coalesce((r_ad->>'accepted')::boolean,false)
    and coalesce((r_adset->>'accepted')::boolean,false)
    and coalesce((r_campaign->>'accepted')::boolean,false)
    and a_campaign#>>'{body,status}'='ACTIVE'
    and a_adset#>>'{body,status}'='ACTIVE'
    and a_ad#>>'{body,status}'='ACTIVE'
    and coalesce(nullif(a_adset#>>'{body,lifetime_budget}','')::bigint,0)=a.max_spend_minor;

  if not v_ok then
    v_comp:=public.pandora_meta_stop_paid_pilot_v1(
      a.id,p_request_key||'-compensate','activation provider/readback mismatch'
    );
  else
    perform public.pandora_meta_set_zero_delivery_kill_switch_v1(
      a.organization_id,a.project_id,false,'paid pilot active under FB-046 bounded authorization'
    );
    update public.pandora_tracking_campaigns
    set metadata=metadata||jsonb_build_object(
        'delivery_authorized',true,
        'paid_pilot_state','active',
        'paid_pilot_authorization_id',a.id::text,
        'paid_pilot_max_spend_minor',a.max_spend_minor,
        'paid_pilot_currency',a.currency,
        'paid_pilot_end_at',a.end_at
      ),
      updated_at=clock_timestamp()
    where id=a.tracking_campaign_id;
    update private.pandora_meta_paid_pilot_authorizations
    set state='active',activated_at=clock_timestamp(),last_receipt_id=v_receipt,updated_at=clock_timestamp()
    where id=a.id;
  end if;

  update private.pandora_meta_paid_pilot_receipts
  set state=case when v_ok then 'confirmed' else 'failed' end,
      provider_responses=jsonb_build_object('adActivate',r_ad,'adsetActivate',r_adset,'campaignActivate',r_campaign),
      after_state=jsonb_build_object('campaign',a_campaign,'adset',a_adset,'ad',a_ad),
      error_code=case when v_ok then null else 'activation_state_unconfirmed' end,
      updated_at=clock_timestamp()
  where id=v_receipt;

  return jsonb_build_object(
    'ok',v_ok,'receiptId',v_receipt,'state',case when v_ok then 'active' else 'failed' end,
    'maxSpendMinor',a.max_spend_minor,'currency',a.currency,'endAt',a.end_at,
    'campaign',a_campaign,'adset',a_adset,'ad',a_ad,
    'killSwitchActive',not v_ok,
    'compensation',v_comp
  );
end;
$function$;
revoke all on function public.pandora_meta_activate_paid_pilot_v1(uuid,text)
from public,anon,authenticated;
grant execute on function public.pandora_meta_activate_paid_pilot_v1(uuid,text)
to service_role;

create or replace function public.pandora_meta_monitor_paid_pilot_v1(
  p_authorization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  v_runtime jsonb; v_token text; v_spend jsonb; v_campaign jsonb; v_adset jsonb; v_ad jsonb;
  v_minor bigint; v_reason text; v_stop jsonb; v_receipt uuid;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_PAID_PILOT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  select * into a from private.pandora_meta_paid_pilot_authorizations where id=p_authorization_id for update;
  if not found then raise exception 'PANDORA_META_PAID_PILOT_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;
  if a.state not in ('active','prepared') then
    return jsonb_build_object('ok',true,'state',a.state,'action','none');
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(a.organization_id,a.installation_id,'marketing');
  v_token:=v_runtime->>'token';
  v_spend:=private.pandora_meta_pilot_spend_v1(v_token,a.meta_campaign_id);
  v_campaign:=private.pandora_meta_pilot_get_v1(v_token,a.meta_campaign_id,'id,status,effective_status');
  v_adset:=private.pandora_meta_pilot_get_v1(v_token,a.meta_adset_id,'id,status,effective_status,lifetime_budget,budget_remaining,end_time');
  v_ad:=private.pandora_meta_pilot_get_v1(v_token,a.meta_ad_id,'id,status,effective_status');
  v_token:=null;
  v_minor:=nullif(v_spend->>'spendMinor','')::bigint;

  if coalesce((v_spend->>'httpStatus')::integer,599)<>200 then
    v_reason:='provider_spend_read_failed';
  elsif v_minor is not null and v_minor>=a.max_spend_minor then
    v_reason:='lifetime_spend_ceiling_reached';
  elsif clock_timestamp()>=a.end_at then
    v_reason:='pilot_period_elapsed';
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
    'monitor',case when v_reason is null then 'confirmed' else 'stop_required' end,
    '{}'::jsonb,
    jsonb_build_object('campaign',v_campaign,'adset',v_adset,'ad',v_ad,'spend',v_spend),
    v_minor,v_reason
  ) returning id into v_receipt;

  if v_reason is not null and a.state='active' then
    v_stop:=public.pandora_meta_stop_paid_pilot_v1(
      a.id,'auto-stop-'||replace(v_receipt::text,'-',''),v_reason
    );
    return jsonb_build_object('ok',coalesce((v_stop->>'ok')::boolean,false),'action','stop','reason',v_reason,'spendMinor',v_minor,'stop',v_stop);
  end if;

  return jsonb_build_object(
    'ok',true,'action','none','state',a.state,'spendMinor',v_minor,
    'maxSpendMinor',a.max_spend_minor,'endAt',a.end_at,
    'campaign',v_campaign,'adset',v_adset,'ad',v_ad
  );
end;
$function$;
revoke all on function public.pandora_meta_monitor_paid_pilot_v1(uuid)
from public,anon,authenticated;
grant execute on function public.pandora_meta_monitor_paid_pilot_v1(uuid)
to service_role;

commit;
;
