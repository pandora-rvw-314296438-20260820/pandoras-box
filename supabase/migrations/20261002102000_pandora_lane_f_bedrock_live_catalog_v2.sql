begin;

alter table private.pandora_bedrock_reasoning_catalog
  add column if not exists region text not null default 'us-east-1',
  add column if not exists output_modalities text[] not null default '{}'::text[],
  add column if not exists lifecycle_status text not null default 'UNKNOWN',
  add column if not exists authorization_status text,
  add column if not exists entitlement_availability text,
  add column if not exists agreement_status text,
  add column if not exists region_availability text,
  add column if not exists workflow_scopes text[] not null default '{}'::text[],
  add column if not exists availability_state text not null default 'discovered',
  add column if not exists runtime_verification_status text not null default 'not_tested',
  add column if not exists last_verified_at timestamptz,
  add column if not exists routable boolean not null default false,
  add column if not exists sync_run_id uuid,
  add column if not exists discovered_at timestamptz not null default now(),
  add column if not exists retired_at timestamptz,
  add column if not exists last_probe_input_tokens bigint not null default 0,
  add column if not exists last_probe_output_tokens bigint not null default 0,
  add column if not exists last_probe_total_tokens bigint not null default 0,
  add column if not exists last_probe_provider_request_id text,
  add column if not exists last_probe_error_code text;

alter table private.pandora_bedrock_reasoning_catalog
  drop constraint if exists pandora_bedrock_reasoning_catalog_runtime_state_check,
  add constraint pandora_bedrock_reasoning_catalog_runtime_state_check
    check (runtime_state in ('discovered','provider_hold','account_denied','onboarding_required','throttled','verified_available')),
  add constraint pandora_bedrock_catalog_lifecycle_check
    check (lifecycle_status in ('ACTIVE','LEGACY','REMOVED','UNKNOWN')),
  add constraint pandora_bedrock_catalog_availability_state_check
    check (availability_state in ('discovered','authorized','entitled','region_available','runtime_tested','routable','retired')),
  add constraint pandora_bedrock_catalog_runtime_verification_check
    check (runtime_verification_status in ('not_tested','passed','failed','skipped_non_conversational','retired')),
  add constraint pandora_bedrock_catalog_probe_usage_check
    check (last_probe_input_tokens>=0 and last_probe_output_tokens>=0 and last_probe_total_tokens>=0),
  add constraint pandora_bedrock_catalog_routable_check
    check (
      routable=false or (
        availability_state='routable'
        and runtime_verification_status='passed'
        and lifecycle_status='ACTIVE'
        and 'conversation'=any(workflow_scopes)
        and authorization_status='AUTHORIZED'
        and entitlement_availability='AVAILABLE'
        and region_availability='AVAILABLE'
      )
    );

create index if not exists pandora_bedrock_catalog_routable_idx
  on private.pandora_bedrock_reasoning_catalog(routable,provider_name,model_name);
create index if not exists pandora_bedrock_catalog_workflow_gin
  on private.pandora_bedrock_reasoning_catalog using gin(workflow_scopes);

create table if not exists private.pandora_bedrock_catalog_sync_state(
  singleton boolean primary key default true check(singleton),
  active_sync_id uuid,
  state text not null default 'idle' check(state in ('idle','running','succeeded','failed')),
  started_at timestamptz,
  completed_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
insert into private.pandora_bedrock_catalog_sync_state(singleton) values(true) on conflict(singleton) do nothing;
alter table private.pandora_bedrock_catalog_sync_state enable row level security;
revoke all on private.pandora_bedrock_catalog_sync_state from public,anon,authenticated,service_role;

create table if not exists private.pandora_bedrock_sync_nonces(
  nonce uuid primary key,
  issued_at timestamptz not null,
  consumed_at timestamptz not null default now()
);
alter table private.pandora_bedrock_sync_nonces enable row level security;
revoke all on private.pandora_bedrock_sync_nonces from public,anon,authenticated,service_role;

create or replace function public.pandora_bedrock_sync_nonce_consume_v1(p_nonce uuid,p_issued_at bigint)
returns boolean
language plpgsql security definer set search_path to 'pg_catalog','private','public'
as $$
declare v_now bigint:=floor(extract(epoch from clock_timestamp()))::bigint;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  if p_nonce is null or p_issued_at is null or abs(v_now-p_issued_at)>120 then return false; end if;
  delete from private.pandora_bedrock_sync_nonces where consumed_at<clock_timestamp()-interval '15 minutes';
  insert into private.pandora_bedrock_sync_nonces(nonce,issued_at) values(p_nonce,to_timestamp(p_issued_at)) on conflict do nothing;
  return found;
end;$$;
revoke all on function public.pandora_bedrock_sync_nonce_consume_v1(uuid,bigint) from public,anon,authenticated;
grant execute on function public.pandora_bedrock_sync_nonce_consume_v1(uuid,bigint) to service_role;

create or replace function public.pandora_bedrock_catalog_sync_claim_v1()
returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public'
as $$
declare v_row private.pandora_bedrock_catalog_sync_state%rowtype;v_id uuid:=gen_random_uuid();
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  select * into strict v_row from private.pandora_bedrock_catalog_sync_state where singleton=true for update;
  if v_row.state='running' and v_row.started_at>clock_timestamp()-interval '20 minutes' then
    return jsonb_build_object('mode','busy','syncId',v_row.active_sync_id,'startedAt',v_row.started_at);
  end if;
  update private.pandora_bedrock_catalog_sync_state
    set active_sync_id=v_id,state='running',started_at=clock_timestamp(),completed_at=null,last_error=null,updated_at=clock_timestamp()
    where singleton=true;
  return jsonb_build_object('mode','execute','syncId',v_id);
end;$$;
revoke all on function public.pandora_bedrock_catalog_sync_claim_v1() from public,anon,authenticated;
grant execute on function public.pandora_bedrock_catalog_sync_claim_v1() to service_role;

create or replace function public.pandora_apply_bedrock_catalog_sync_v2(
  p_sync_id uuid,p_region text,p_observed_at timestamptz,p_models jsonb
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','private','public'
as $$
declare
  v_state private.pandora_bedrock_catalog_sync_state%rowtype;
  v_model jsonb;v_seen text[]:='{}'::text[];v_count integer:=0;v_retired integer:=0;v_routable_count integer:=0;
  v_id text;v_name text;v_provider text;v_target text;v_runtime_state text;v_runtime_reason text;
  v_input text[];v_output text[];v_inference text[];v_scopes text[];v_caps text[];
  v_lifecycle text;v_authorization text;v_entitlement text;v_agreement text;v_region_availability text;
  v_availability_state text;v_runtime_verification text;v_last_verified timestamptz;v_routable boolean;
  v_risk integer;v_in bigint;v_out bigint;v_total bigint;v_request_id text;v_probe_error text;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  if p_sync_id is null or p_region<>'us-east-1' or p_observed_at is null or jsonb_typeof(p_models)<>'array'
     or jsonb_array_length(p_models)<1 or jsonb_array_length(p_models)>500 then
    raise exception 'BEDROCK_SYNC_INPUT_INVALID' using errcode='22023';
  end if;
  select * into strict v_state from private.pandora_bedrock_catalog_sync_state where singleton=true for update;
  if v_state.state<>'running' or v_state.active_sync_id is distinct from p_sync_id then
    raise exception 'BEDROCK_SYNC_CLAIM_MISMATCH' using errcode='40001';
  end if;

  for v_model in select value from jsonb_array_elements(p_models)
  loop
    v_id:=nullif(trim(v_model->>'modelId'),'');v_name:=left(coalesce(nullif(trim(v_model->>'modelName'),''),v_id),240);
    v_provider:=left(coalesce(nullif(trim(v_model->>'providerName'),''),'Unknown'),120);
    v_target:=nullif(trim(v_model->>'invocationTarget'),'');
    if v_id is null or v_id!~'^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$' or v_id=any(v_seen) then
      raise exception 'BEDROCK_SYNC_MODEL_INVALID' using errcode='22023';
    end if;
    v_seen:=array_append(v_seen,v_id);
    select coalesce(array_agg(value),'{}'::text[]) into v_input from jsonb_array_elements_text(coalesce(v_model->'inputModalities','[]'::jsonb));
    select coalesce(array_agg(value),'{}'::text[]) into v_output from jsonb_array_elements_text(coalesce(v_model->'outputModalities','[]'::jsonb));
    select coalesce(array_agg(value),'{}'::text[]) into v_inference from jsonb_array_elements_text(coalesce(v_model->'inferenceTypes','[]'::jsonb));
    select coalesce(array_agg(value),'{}'::text[]) into v_scopes from jsonb_array_elements_text(coalesce(v_model->'workflowScopes','[]'::jsonb));
    select coalesce(array_agg(value),'{}'::text[]) into v_caps from jsonb_array_elements_text(coalesce(v_model->'capabilityClasses','[]'::jsonb));
    v_lifecycle:=coalesce(v_model->>'lifecycleStatus','UNKNOWN');v_authorization:=nullif(v_model->>'authorizationStatus','');
    v_entitlement:=nullif(v_model->>'entitlementAvailability','');v_agreement:=nullif(v_model->>'agreementStatus','');
    v_region_availability:=nullif(v_model->>'regionAvailability','');v_availability_state:=coalesce(v_model->>'availabilityState','discovered');
    v_runtime_verification:=coalesce(v_model->>'runtimeVerificationStatus','not_tested');v_runtime_state:=coalesce(v_model->>'runtimeState','provider_hold');
    v_runtime_reason:=left(coalesce(v_model->>'runtimeReason','sync_observed'),240);
    v_routable:=coalesce((v_model->>'routable')::boolean,false);v_risk:=coalesce((v_model->>'riskTier')::integer,2);
    v_in:=coalesce((v_model->>'lastProbeInputTokens')::bigint,0);v_out:=coalesce((v_model->>'lastProbeOutputTokens')::bigint,0);
    v_total:=coalesce((v_model->>'lastProbeTotalTokens')::bigint,0);v_request_id:=nullif(left(coalesce(v_model->>'lastProbeProviderRequestId',''),240),'');
    v_probe_error:=nullif(left(coalesce(v_model->>'lastProbeErrorCode',''),120),'');
    v_last_verified:=case when nullif(v_model->>'lastVerifiedAt','') is null then null else (v_model->>'lastVerifiedAt')::timestamptz end;
    if v_lifecycle not in ('ACTIVE','LEGACY','REMOVED','UNKNOWN')
       or v_availability_state not in ('discovered','authorized','entitled','region_available','runtime_tested','routable','retired')
       or v_runtime_verification not in ('not_tested','passed','failed','skipped_non_conversational','retired')
       or v_runtime_state not in ('discovered','provider_hold','account_denied','onboarding_required','throttled','verified_available')
       or v_risk<0 or v_risk>3 or v_in<0 or v_out<0 or v_total<0 then
      raise exception 'BEDROCK_SYNC_MODEL_STATE_INVALID' using errcode='22023';
    end if;
    insert into private.pandora_bedrock_reasoning_catalog(
      model_id,model_name,provider_name,invocation_target,input_modalities,inference_types,risk_tier,capability_classes,
      observed_at,source_ref,runtime_state,runtime_reason,runtime_observed_at,region,output_modalities,lifecycle_status,
      authorization_status,entitlement_availability,agreement_status,region_availability,workflow_scopes,availability_state,
      runtime_verification_status,last_verified_at,routable,sync_run_id,discovered_at,retired_at,
      last_probe_input_tokens,last_probe_output_tokens,last_probe_total_tokens,last_probe_provider_request_id,last_probe_error_code
    ) values(
      v_id,v_name,v_provider,coalesce(v_target,v_id),v_input,v_inference,v_risk,v_caps,p_observed_at,
      'aws:bedrock:us-east-1:live-control-plane',v_runtime_state,v_runtime_reason,
      case when v_runtime_verification in ('passed','failed') then v_last_verified else null end,p_region,v_output,v_lifecycle,
      v_authorization,v_entitlement,v_agreement,v_region_availability,v_scopes,v_availability_state,
      v_runtime_verification,v_last_verified,v_routable,p_sync_id,p_observed_at,null,
      v_in,v_out,v_total,v_request_id,v_probe_error
    )
    on conflict(model_id) do update set
      model_name=excluded.model_name,provider_name=excluded.provider_name,invocation_target=excluded.invocation_target,
      input_modalities=excluded.input_modalities,inference_types=excluded.inference_types,risk_tier=excluded.risk_tier,
      capability_classes=excluded.capability_classes,observed_at=excluded.observed_at,source_ref=excluded.source_ref,
      runtime_state=excluded.runtime_state,runtime_reason=excluded.runtime_reason,runtime_observed_at=excluded.runtime_observed_at,
      region=excluded.region,output_modalities=excluded.output_modalities,lifecycle_status=excluded.lifecycle_status,
      authorization_status=excluded.authorization_status,entitlement_availability=excluded.entitlement_availability,
      agreement_status=excluded.agreement_status,region_availability=excluded.region_availability,workflow_scopes=excluded.workflow_scopes,
      availability_state=excluded.availability_state,runtime_verification_status=excluded.runtime_verification_status,
      last_verified_at=excluded.last_verified_at,routable=excluded.routable,sync_run_id=excluded.sync_run_id,retired_at=null,
      last_probe_input_tokens=excluded.last_probe_input_tokens,last_probe_output_tokens=excluded.last_probe_output_tokens,
      last_probe_total_tokens=excluded.last_probe_total_tokens,last_probe_provider_request_id=excluded.last_probe_provider_request_id,
      last_probe_error_code=excluded.last_probe_error_code;
    v_count:=v_count+1;
  end loop;

  update private.pandora_bedrock_reasoning_catalog
    set lifecycle_status='REMOVED',availability_state='retired',runtime_verification_status='retired',
        routable=false,retired_at=p_observed_at,runtime_state='provider_hold',runtime_reason='not_present_in_live_aws_catalog',
        observed_at=p_observed_at,sync_run_id=p_sync_id
    where not(model_id=any(v_seen)) and lifecycle_status<>'REMOVED';
  get diagnostics v_retired=row_count;
  select count(*) into v_routable_count from private.pandora_bedrock_reasoning_catalog
    where routable=true and 'conversation'=any(workflow_scopes);

  insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at) values
    ('bedrock','routing_eligible',case when v_routable_count>0 then 'true' else 'false' end,true,clock_timestamp()),
    ('bedrock','runtime_state',case when v_routable_count>0 then 'active' else 'held' end,true,clock_timestamp()),
    ('bedrock','catalog_sync_id',p_sync_id::text,true,clock_timestamp()),
    ('bedrock','catalog_sync_at',p_observed_at::text,true,clock_timestamp()),
    ('bedrock','catalog_model_count',v_count::text,true,clock_timestamp()),
    ('bedrock','routable_conversation_models',v_routable_count::text,true,clock_timestamp())
  on conflict(provider,config_key) do update set config_value=excluded.config_value,active=true,updated_at=clock_timestamp();

  update private.pandora_bedrock_catalog_sync_state
    set state='succeeded',completed_at=clock_timestamp(),last_error=null,updated_at=clock_timestamp()
    where singleton=true and active_sync_id=p_sync_id;
  return jsonb_build_object('ok',true,'syncId',p_sync_id,'models',v_count,'retired',v_retired,'routable',v_routable_count);
end;$$;
revoke all on function public.pandora_apply_bedrock_catalog_sync_v2(uuid,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_apply_bedrock_catalog_sync_v2(uuid,text,timestamptz,jsonb) to service_role;

create or replace function public.pandora_bedrock_catalog_sync_fail_v1(p_sync_id uuid,p_reason text)
returns boolean
language plpgsql security definer set search_path to 'pg_catalog','private','public'
as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  update private.pandora_bedrock_catalog_sync_state
    set state='failed',completed_at=clock_timestamp(),last_error=left(coalesce(p_reason,'BEDROCK_SYNC_FAILED'),160),updated_at=clock_timestamp()
    where singleton=true and active_sync_id=p_sync_id and state='running';
  return found;
end;$$;
revoke all on function public.pandora_bedrock_catalog_sync_fail_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_bedrock_catalog_sync_fail_v1(uuid,text) to service_role;

create or replace function public.pandora_list_conversational_models_v1()
returns table(
  routing_provider text,provider_name text,model_id text,model_name text,region text,
  input_modalities text[],output_modalities text[],invocation_target text,lifecycle_status text,last_verified_at timestamptz
)
language plpgsql security definer set search_path to 'pg_catalog','private','public'
as $$
begin
  if coalesce(auth.role(),'') not in ('authenticated','service_role') then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  return query
  select 'bedrock'::text,c.provider_name,c.model_id,c.model_name,c.region,c.input_modalities,c.output_modalities,
         c.invocation_target,c.lifecycle_status,c.last_verified_at
  from private.pandora_bedrock_reasoning_catalog c
  where c.routable=true and c.availability_state='routable' and c.runtime_verification_status='passed'
    and 'conversation'=any(c.workflow_scopes)
  order by c.provider_name,c.model_name,c.model_id;
end;$$;
revoke all on function public.pandora_list_conversational_models_v1() from public,anon;
grant execute on function public.pandora_list_conversational_models_v1() to authenticated,service_role;

create or replace function public.pandora_bedrock_catalog_sync_status_v1()
returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public'
as $$
declare v_state private.pandora_bedrock_catalog_sync_state%rowtype;
begin
  if coalesce(auth.role(),'') not in ('authenticated','service_role') then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  select * into strict v_state from private.pandora_bedrock_catalog_sync_state where singleton=true;
  return jsonb_build_object(
    'syncId',v_state.active_sync_id,'state',v_state.state,'startedAt',v_state.started_at,'completedAt',v_state.completed_at,
    'lastError',v_state.last_error,
    'catalogModels',(select count(*) from private.pandora_bedrock_reasoning_catalog where lifecycle_status<>'REMOVED'),
    'routableConversationModels',(select count(*) from private.pandora_bedrock_reasoning_catalog where routable=true and 'conversation'=any(workflow_scopes))
  );
end;$$;
revoke all on function public.pandora_bedrock_catalog_sync_status_v1() from public,anon;
grant execute on function public.pandora_bedrock_catalog_sync_status_v1() to authenticated,service_role;

create or replace function private.pandora_bedrock_catalog_emit_sync_v1()
returns bigint
language plpgsql security definer
set search_path to 'pg_catalog','private','vault','extensions','net'
as $$
declare v_secret text;v_timestamp text;v_nonce uuid:=gen_random_uuid();v_message text;v_signature text;v_request_id bigint;
begin
  select decrypted_secret into strict v_secret from vault.decrypted_secrets
    where name=('pandora_ops_vercel_'||'wake_hmac_v1') limit 1;
  if nullif(trim(v_secret),'') is null then raise exception 'BEDROCK_SYNC_WAKE_SECRET_UNAVAILABLE' using errcode='55000'; end if;
  v_timestamp:=floor(extract(epoch from clock_timestamp()))::bigint::text;
  v_message:=v_timestamp||E'\n'||v_nonce::text||E'\nPOST\n/api/bedrock-model-catalog-sync\n{}';
  v_signature:=encode(extensions.hmac(convert_to(v_message,'UTF8'),convert_to(v_secret,'UTF8'),'sha256'),'hex');
  v_request_id:=net.http_post(
    url:='https://mcpmaster.vercel.app/api/bedrock-model-catalog-sync',
    body:='{}'::jsonb,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-pandora-wake-timestamp',v_timestamp,
      'x-pandora-wake-nonce',v_nonce::text,
      'x-pandora-wake-signature',v_signature
    ),
    timeout_milliseconds:=295000
  );
  v_secret:=null;v_signature:=null;v_message:=null;
  return v_request_id;
end;$$;
revoke all on function private.pandora_bedrock_catalog_emit_sync_v1() from public,anon,authenticated,service_role;

comment on table private.pandora_bedrock_reasoning_catalog is
  'Live AWS Bedrock catalog. Historical table name retained for compatibility; workflow_scopes contains the authoritative capability scope.';
comment on column private.pandora_bedrock_reasoning_catalog.routable is
  'True only after a successful bounded real Converse invocation through the Vercel OIDC Bedrock role and all authorization/entitlement/region/lifecycle gates pass.';

commit;
