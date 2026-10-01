-- FB-041..FB-045: bounded zero-delivery Meta action broker.
-- Only PAUSE is supported, only for the exact controlled-test binding.
-- No create/delete/publish/budget/spend authority is introduced.
begin;

create table if not exists private.pandora_meta_zero_delivery_control (
  organization_id uuid not null,
  project_id uuid not null,
  kill_switch_active boolean not null default false,
  evidence_ref text not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,project_id)
);
alter table private.pandora_meta_zero_delivery_control enable row level security;
revoke all on private.pandora_meta_zero_delivery_control from public,anon,authenticated,service_role;

create table if not exists private.pandora_meta_zero_delivery_action_approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  installation_id uuid not null,
  target_type text not null check(target_type in ('campaign','adset','ad')),
  target_id text not null check(target_id ~ '^[1-9][0-9]{0,63}$'),
  action text not null check(action='pause'),
  payload jsonb not null check(payload = jsonb_build_object('status','PAUSED')),
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
  approved_by text not null check(char_length(approved_by) between 3 and 255),
  evidence_ref text not null check(char_length(evidence_ref) between 3 and 1000),
  approved_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  max_provider_writes integer not null default 1 check(max_provider_writes=1),
  consumed_provider_writes integer not null default 0 check(consumed_provider_writes between 0 and 1),
  state text not null default 'approved' check(state in ('approved','consumed','expired','revoked')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,id)
);
alter table private.pandora_meta_zero_delivery_action_approvals enable row level security;
revoke all on private.pandora_meta_zero_delivery_action_approvals from public,anon,authenticated,service_role;

create table if not exists private.pandora_meta_zero_delivery_action_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  approval_id uuid not null references private.pandora_meta_zero_delivery_action_approvals(id) on delete restrict,
  request_key text not null check(request_key ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'),
  target_type text not null check(target_type in ('campaign','adset','ad')),
  target_id text not null check(target_id ~ '^[1-9][0-9]{0,63}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
  state text not null check(state in ('submitted','confirmed_state','failed')),
  before_state jsonb,
  provider_http_status integer,
  provider_accepted boolean,
  provider_response jsonb,
  after_state jsonb,
  desired_state_confirmed boolean not null default false,
  mutation_success_claimed boolean not null default false,
  spend_authorized boolean not null default false check(spend_authorized is false),
  error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,request_key),
  unique(approval_id)
);
alter table private.pandora_meta_zero_delivery_action_receipts enable row level security;
revoke all on private.pandora_meta_zero_delivery_action_receipts from public,anon,authenticated,service_role;

create or replace function private.pandora_meta_zero_delivery_target_is_allowed_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_installation_id uuid,
  p_target_type text,
  p_target_id text
) returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
  select exists(
    select 1
    from private.pandora_meta_measurement_bindings b
    join public.pandora_tracking_campaigns c on c.id=b.tracking_campaign_id
    where b.organization_id=p_organization_id
      and b.project_id=p_project_id
      and b.installation_id=p_installation_id
      and c.metadata->>'purpose'='controlled-test'
      and c.metadata->'business_kpi' is not distinct from 'false'::jsonb
      and c.metadata->'delivery_authorized' is not distinct from 'false'::jsonb
      and case p_target_type
        when 'campaign' then b.meta_campaign_id=p_target_id
        when 'adset' then b.meta_adset_id=p_target_id
        when 'ad' then b.meta_ad_id=p_target_id
        else false
      end
  );
$function$;
revoke all on function private.pandora_meta_zero_delivery_target_is_allowed_v1(uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function private.pandora_meta_zero_delivery_target_is_allowed_v1(uuid,uuid,uuid,text,text)
  to service_role;

create or replace function public.pandora_meta_issue_zero_delivery_action_approval_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_installation_id uuid,
  p_target_type text,
  p_target_id text,
  p_approved_by text,
  p_evidence_ref text,
  p_ttl_seconds integer default 900
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_payload jsonb:=jsonb_build_object('status','PAUSED');
  v_hash text;
  v_id uuid;
  v_expires timestamptz;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_ZERO_DELIVERY_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_target_type not in ('campaign','adset','ad')
    or p_target_id !~ '^[1-9][0-9]{0,63}$'
    or p_ttl_seconds not between 60 and 900
    or char_length(coalesce(btrim(p_approved_by),'')) not between 3 and 255
    or char_length(coalesce(btrim(p_evidence_ref),'')) not between 3 and 1000 then
    raise exception 'PANDORA_META_ZERO_DELIVERY_APPROVAL_INVALID' using errcode='22023';
  end if;
  if private.pandora_meta_zero_delivery_target_is_allowed_v1(
      p_organization_id,p_project_id,p_installation_id,p_target_type,p_target_id
    ) is not true then
    raise exception 'PANDORA_META_ZERO_DELIVERY_TARGET_DENIED' using errcode='42501';
  end if;
  v_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_expires:=clock_timestamp()+make_interval(secs=>p_ttl_seconds);
  insert into private.pandora_meta_zero_delivery_action_approvals(
    organization_id,project_id,installation_id,target_type,target_id,action,payload,
    payload_sha256,approved_by,evidence_ref,expires_at
  ) values (
    p_organization_id,p_project_id,p_installation_id,p_target_type,p_target_id,'pause',v_payload,
    v_hash,btrim(p_approved_by),btrim(p_evidence_ref),v_expires
  ) returning id into v_id;
  return jsonb_build_object(
    'ok',true,'approvalId',v_id,'action','pause','targetType',p_target_type,
    'targetId',p_target_id,'payload',v_payload,'payloadSha256',v_hash,
    'expiresAt',v_expires,'maxProviderWrites',1,'spendAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_meta_issue_zero_delivery_action_approval_v1(
  uuid,uuid,uuid,text,text,text,text,integer
) from public,anon,authenticated;
grant execute on function public.pandora_meta_issue_zero_delivery_action_approval_v1(
  uuid,uuid,uuid,text,text,text,text,integer
) to service_role;

create or replace function public.pandora_meta_set_zero_delivery_kill_switch_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_active boolean,
  p_evidence_ref text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_targets jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_ZERO_DELIVERY_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if char_length(coalesce(btrim(p_evidence_ref),'')) not between 3 and 1000 then
    raise exception 'PANDORA_META_ZERO_DELIVERY_KILL_SWITCH_INVALID' using errcode='22023';
  end if;
  insert into private.pandora_meta_zero_delivery_control(
    organization_id,project_id,kill_switch_active,evidence_ref,updated_at
  ) values (
    p_organization_id,p_project_id,p_active,btrim(p_evidence_ref),clock_timestamp()
  )
  on conflict(organization_id,project_id) do update
  set kill_switch_active=excluded.kill_switch_active,
      evidence_ref=excluded.evidence_ref,
      updated_at=excluded.updated_at;

  select coalesce(jsonb_agg(jsonb_build_object(
    'campaignId',b.meta_campaign_id,'adsetId',b.meta_adset_id,'adId',b.meta_ad_id
  ) order by c.id),'[]'::jsonb)
  into v_targets
  from private.pandora_meta_measurement_bindings b
  join public.pandora_tracking_campaigns c on c.id=b.tracking_campaign_id
  where b.organization_id=p_organization_id and b.project_id=p_project_id
    and c.metadata->>'purpose'='controlled-test'
    and c.metadata->'business_kpi' is not distinct from 'false'::jsonb
    and c.metadata->'delivery_authorized' is not distinct from 'false'::jsonb;

  return jsonb_build_object(
    'ok',true,'killSwitchActive',p_active,
    'newNonPauseActionsAllowed',false,
    'authorizedPauseTargets',case when p_active then v_targets else '[]'::jsonb end,
    'incurredSpendReversible',false,
    'spendAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_meta_set_zero_delivery_kill_switch_v1(uuid,uuid,boolean,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_set_zero_delivery_kill_switch_v1(uuid,uuid,boolean,text)
  to service_role;

create or replace function public.pandora_meta_execute_zero_delivery_action_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_approval_id uuid,
  p_request_key text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_approval private.pandora_meta_zero_delivery_action_approvals%rowtype;
  v_existing private.pandora_meta_zero_delivery_action_receipts%rowtype;
  v_control private.pandora_meta_zero_delivery_control%rowtype;
  v_runtime jsonb;
  v_token text;
  v_before extensions.http_response;
  v_post extensions.http_response;
  v_after extensions.http_response;
  v_before_body jsonb:='{}'::jsonb;
  v_post_body jsonb:='{}'::jsonb;
  v_after_body jsonb:='{}'::jsonb;
  v_provider_accepted boolean:=false;
  v_confirmed boolean:=false;
  v_receipt_id uuid;
  v_hash text;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_ZERO_DELIVERY_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if coalesce(p_request_key,'') !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$' then
    raise exception 'PANDORA_META_ZERO_DELIVERY_REQUEST_KEY_INVALID' using errcode='22023';
  end if;

  select * into v_existing
  from private.pandora_meta_zero_delivery_action_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and request_key=p_request_key;
  if found then
    return jsonb_build_object(
      'ok',v_existing.desired_state_confirmed,
      'duplicate',true,'receiptId',v_existing.id,'state',v_existing.state,
      'providerHttpStatus',v_existing.provider_http_status,
      'providerAccepted',v_existing.provider_accepted,
      'desiredStateConfirmed',v_existing.desired_state_confirmed,
      'mutationSuccessClaimed',v_existing.mutation_success_claimed,
      'spendAuthorized',false
    );
  end if;

  select * into v_approval
  from private.pandora_meta_zero_delivery_action_approvals
  where id=p_approval_id and organization_id=p_organization_id and project_id=p_project_id
  for update;
  if not found then
    raise exception 'PANDORA_META_ZERO_DELIVERY_APPROVAL_NOT_FOUND' using errcode='P0002';
  end if;
  if v_approval.state<>'approved'
    or v_approval.expires_at<=clock_timestamp()
    or v_approval.consumed_provider_writes>=v_approval.max_provider_writes
    or v_approval.action<>'pause'
    or v_approval.payload is distinct from jsonb_build_object('status','PAUSED') then
    raise exception 'PANDORA_META_ZERO_DELIVERY_APPROVAL_FENCED' using errcode='42501';
  end if;
  v_hash:=encode(extensions.digest(convert_to(v_approval.payload::text,'UTF8'),'sha256'),'hex');
  if v_hash is distinct from v_approval.payload_sha256 then
    raise exception 'PANDORA_META_ZERO_DELIVERY_APPROVAL_TAMPERED' using errcode='42501';
  end if;
  if private.pandora_meta_zero_delivery_target_is_allowed_v1(
      p_organization_id,p_project_id,v_approval.installation_id,
      v_approval.target_type,v_approval.target_id
    ) is not true then
    raise exception 'PANDORA_META_ZERO_DELIVERY_TARGET_DENIED' using errcode='42501';
  end if;

  select * into v_control
  from private.pandora_meta_zero_delivery_control
  where organization_id=p_organization_id and project_id=p_project_id;
  -- Kill switch forbids every future action class except this fail-safe PAUSE broker.
  -- This function has no create/delete/publish/budget path.

  insert into private.pandora_meta_zero_delivery_action_receipts(
    organization_id,project_id,approval_id,request_key,target_type,target_id,
    payload_sha256,state,spend_authorized
  ) values (
    p_organization_id,p_project_id,v_approval.id,p_request_key,
    v_approval.target_type,v_approval.target_id,v_approval.payload_sha256,
    'submitted',false
  ) returning id into v_receipt_id;

  v_runtime:=public.pandora_meta_runtime_secret_v1(
    p_organization_id,v_approval.installation_id,'marketing'
  );
  v_token:=v_runtime->>'token';

  select * into v_before
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||v_approval.target_id||
      '?fields=id,status,effective_status')::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Zero-Delivery-Action/1.0')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  begin v_before_body:=coalesce(nullif(v_before.content,'')::jsonb,'{}'::jsonb);
  exception when others then v_before_body:='{}'::jsonb; end;

  select * into v_post
  from extensions.http((
    'POST'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||v_approval.target_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','application/x-www-form-urlencoded'),
      extensions.http_header('user-agent','Pandora-Zero-Delivery-Action/1.0')
    ]::extensions.http_header[],
    'application/x-www-form-urlencoded'::varchar,
    'status=PAUSED'::varchar
  )::extensions.http_request);
  begin v_post_body:=coalesce(nullif(v_post.content,'')::jsonb,'{}'::jsonb);
  exception when others then v_post_body:='{}'::jsonb; end;
  v_provider_accepted:=v_post.status=200
    and coalesce((v_post_body->>'success')::boolean,false) is true;

  select * into v_after
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||v_approval.target_id||
      '?fields=id,status,effective_status')::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Zero-Delivery-Action/1.0')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_token:=null;
  begin v_after_body:=coalesce(nullif(v_after.content,'')::jsonb,'{}'::jsonb);
  exception when others then v_after_body:='{}'::jsonb; end;

  v_confirmed:=v_after.status=200
    and v_after_body->>'id'=v_approval.target_id
    and coalesce(v_after_body->>'status',v_after_body->>'effective_status')='PAUSED';

  update private.pandora_meta_zero_delivery_action_receipts
  set state=case when v_confirmed then 'confirmed_state' else 'failed' end,
      before_state=v_before_body,
      provider_http_status=v_post.status,
      provider_accepted=v_provider_accepted,
      provider_response=case
        when jsonb_typeof(v_post_body)='object' then
          v_post_body - 'access_token' - 'token'
        else '{}'::jsonb end,
      after_state=v_after_body,
      desired_state_confirmed=v_confirmed,
      mutation_success_claimed=false,
      error_code=case when v_confirmed then null else 'provider_state_unconfirmed' end,
      updated_at=clock_timestamp()
  where id=v_receipt_id;

  if v_confirmed then
    update private.pandora_meta_zero_delivery_action_approvals
    set consumed_provider_writes=1,state='consumed',updated_at=clock_timestamp()
    where id=v_approval.id;
  end if;

  return jsonb_build_object(
    'ok',v_confirmed,
    'duplicate',false,
    'receiptId',v_receipt_id,
    'state',case when v_confirmed then 'confirmed_state' else 'failed' end,
    'targetType',v_approval.target_type,'targetId',v_approval.target_id,
    'payloadSha256',v_approval.payload_sha256,
    'providerHttpStatus',v_post.status,
    'providerAccepted',v_provider_accepted,
    'beforeState',v_before_body,
    'afterState',v_after_body,
    'desiredStateConfirmed',v_confirmed,
    'mutationSuccessClaimed',false,
    'killSwitchActive',coalesce(v_control.kill_switch_active,false),
    'maxProviderWrites',1,'consumedProviderWrites',case when v_confirmed then 1 else 0 end,
    'spendAuthorized',false,'incurredSpendReversible',false
  );
end;
$function$;
revoke all on function public.pandora_meta_execute_zero_delivery_action_v1(uuid,uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_execute_zero_delivery_action_v1(uuid,uuid,uuid,text)
  to service_role;

create or replace function public.pandora_meta_zero_delivery_action_status_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_control jsonb;
  v_approvals jsonb;
  v_receipts jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_META_ZERO_DELIVERY_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  select coalesce(to_jsonb(c),'{}'::jsonb) into v_control
  from private.pandora_meta_zero_delivery_control c
  where c.organization_id=p_organization_id and c.project_id=p_project_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'targetType',a.target_type,'targetId',a.target_id,'action',a.action,
    'payloadSha256',a.payload_sha256,'approvedBy',a.approved_by,
    'evidenceRef',a.evidence_ref,'approvedAt',a.approved_at,'expiresAt',a.expires_at,
    'state',a.state,'maxProviderWrites',a.max_provider_writes,
    'consumedProviderWrites',a.consumed_provider_writes
  ) order by a.created_at),'[]'::jsonb) into v_approvals
  from private.pandora_meta_zero_delivery_action_approvals a
  where a.organization_id=p_organization_id and a.project_id=p_project_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'approvalId',r.approval_id,'requestKey',r.request_key,
    'targetType',r.target_type,'targetId',r.target_id,'state',r.state,
    'providerHttpStatus',r.provider_http_status,'providerAccepted',r.provider_accepted,
    'desiredStateConfirmed',r.desired_state_confirmed,
    'mutationSuccessClaimed',r.mutation_success_claimed,
    'spendAuthorized',r.spend_authorized,'createdAt',r.created_at
  ) order by r.created_at),'[]'::jsonb) into v_receipts
  from private.pandora_meta_zero_delivery_action_receipts r
  where r.organization_id=p_organization_id and r.project_id=p_project_id;
  return jsonb_build_object(
    'ok',true,'control',v_control,'approvals',v_approvals,'receipts',v_receipts,
    'supportedActions',jsonb_build_array('pause'),
    'unsupportedActionsDenied',jsonb_build_array('create','delete','publish','budget_update','activate'),
    'spendAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_meta_zero_delivery_action_status_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_zero_delivery_action_status_v1(uuid,uuid)
  to service_role;

commit;
