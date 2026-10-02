begin;

create or replace function public.pandora_intelligence_model_catalog_v1(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','auth','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_models jsonb;
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode='42501';
  end if;

  with source as (
    select
      c.model_id,
      coalesce(nullif(c.model_name,''),c.model_id) as model_name,
      coalesce(nullif(c.provider_name,''),'Provider') as provider_name,
      c.routable,c.runtime_verification_status,c.lifecycle_status,
      c.agreement_status,c.authorization_status,c.entitlement_status,
      c.region_availability,c.runtime_state,c.runtime_reason,c.probe_http_status,
      (
        c.routable=true
        and c.runtime_verification_status='passed'
        and c.lifecycle_status='ACTIVE'
        and c.agreement_status='AVAILABLE'
        and c.authorization_status='AUTHORIZED'
        and c.entitlement_status='AVAILABLE'
        and c.region_availability='AVAILABLE'
        and c.conversational=true
        and c.present_in_latest_sync=true
      ) as available
    from private.pandora_bedrock_reasoning_catalog c
    where c.conversational=true
      and c.present_in_latest_sync=true
  ),
  decorated as (
    select s.*,
      case
        when s.available then null
        when coalesce(s.runtime_reason,'') ilike '%payment%'
          or coalesce(s.runtime_reason,'') ilike '%invalid_payment%'
          then 'Payment blocked'
        when s.authorization_status is distinct from 'AUTHORIZED'
          or coalesce(s.runtime_reason,'') ilike '%access_denied%'
          then 'Access denied'
        when s.entitlement_status is distinct from 'AVAILABLE'
          then 'Not entitled'
        when s.agreement_status is distinct from 'AVAILABLE'
          then 'Provider agreement required'
        when s.region_availability is distinct from 'AVAILABLE'
          then 'Unavailable in this region'
        when s.lifecycle_status is distinct from 'ACTIVE'
          then 'Model is not active'
        when s.runtime_verification_status is distinct from 'passed'
          then 'Runtime verification failed'
        else 'Unavailable'
      end as unavailable_reason
    from source s
  ),
  items as (
    select 0 as availability_order,''::text as provider_name,''::text as model_name,
      jsonb_build_object(
        'provider','auto','model','auto','label','Auto','providerLabel','Pandora',
        'available',true,'state','ready','routable',true,
        'runtimeVerificationStatus','passed','unavailableReason',null
      ) as item
    union all
    select case when d.available then 1 else 2 end,d.provider_name,d.model_name,
      jsonb_build_object(
        'provider','bedrock','model',d.model_id,'label',d.model_name,
        'providerLabel',d.provider_name,'available',d.available,
        'state',case when d.available then 'ready' else 'unavailable' end,
        'routable',d.routable,
        'runtimeVerificationStatus',d.runtime_verification_status,
        'unavailableReason',d.unavailable_reason
      )
    from decorated d
  )
  select coalesce(jsonb_agg(item order by availability_order,provider_name,model_name),'[]'::jsonb)
    into v_models from items;

  return jsonb_build_object(
    'contractVersion','pandora-intelligence-model-catalog-v2',
    'models',v_models,
    'observedAt',clock_timestamp()
  );
end;
$$;
revoke all on function public.pandora_intelligence_model_catalog_v1(uuid) from public,anon;
grant execute on function public.pandora_intelligence_model_catalog_v1(uuid) to authenticated,service_role;

create or replace function public.pandora_intelligence_thread_model_selection_v1(
  p_organization_id uuid,p_thread_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','auth','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_route private.pandora_intelligence_thread_routing_state%rowtype;
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.pandora_intelligence_threads t
    where t.id=p_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=v_user_id
      and t.status='active'
  ) then
    raise exception 'THREAD_NOT_FOUND' using errcode='P0002';
  end if;

  select r.* into v_route
  from private.pandora_intelligence_thread_routing_state r
  where r.thread_id=p_thread_id and r.organization_id=p_organization_id;

  if not found then
    return jsonb_build_object(
      'selectionMode','auto','requestedProvider',null,'requestedModel',null,
      'fallbackMode','allow_fallback','reasoningMode','auto',
      'executedProvider',null,'executedModel',null
    );
  end if;

  return jsonb_build_object(
    'selectionMode',v_route.selection_mode,
    'requestedProvider',v_route.requested_provider,
    'requestedModel',v_route.requested_model,
    'fallbackMode',v_route.fallback_mode,
    'reasoningMode',v_route.reasoning_mode,
    'executedProvider',v_route.provider,
    'executedModel',v_route.model,
    'updatedAt',v_route.updated_at
  );
end;
$$;
revoke all on function public.pandora_intelligence_thread_model_selection_v1(uuid,uuid) from public,anon;
grant execute on function public.pandora_intelligence_thread_model_selection_v1(uuid,uuid) to authenticated,service_role;

create or replace function public.pandora_intelligence_thread_model_selection_set_v1(
  p_organization_id uuid,
  p_thread_id uuid,
  p_selection_mode text,
  p_requested_provider text,
  p_requested_model text,
  p_fallback_mode text,
  p_reasoning_mode text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','auth','pg_temp'
as $
declare
  v_user_id uuid := auth.uid();
  v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin
  if v_user_id is null then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=v_user_id and m.status='active'
  ) then raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode='42501'; end if;
  if not exists (
    select 1 from public.pandora_intelligence_threads t
    where t.id=p_thread_id and t.organization_id=p_organization_id and t.created_by=v_user_id and t.status='active'
  ) then raise exception 'THREAD_NOT_FOUND' using errcode='P0002'; end if;
  if p_selection_mode not in ('auto','manual')
     or p_fallback_mode not in ('strict','allow_fallback')
     or p_reasoning_mode not in ('auto','fast','deep')
  then raise exception 'INVALID_MODEL_SELECTION' using errcode='22023'; end if;
  if p_selection_mode='manual' then
    if p_requested_provider is distinct from 'bedrock'
       or not exists (
         select 1 from private.pandora_bedrock_reasoning_catalog c
         where c.model_id=p_requested_model
           and c.conversational=true and c.present_in_latest_sync=true
           and c.lifecycle_status='ACTIVE'
           and c.agreement_status='AVAILABLE'
           and c.authorization_status='AUTHORIZED'
           and c.entitlement_status='AVAILABLE'
           and c.region_availability='AVAILABLE'
           and c.routable=true
           and c.runtime_verification_status='passed'
       )
    then raise exception 'MANUAL_MODEL_UNAVAILABLE' using errcode='22023'; end if;
  end if;
  insert into private.pandora_intelligence_thread_routing_state(
    thread_id,organization_id,provider,model,stickiness_mode,recovery_epoch,
    selection_mode,requested_provider,requested_model,fallback_mode,reasoning_mode
  ) values (
    p_thread_id,p_organization_id,null,null,'unassigned',0,
    p_selection_mode,
    case when p_selection_mode='manual' then p_requested_provider else null end,
    case when p_selection_mode='manual' then p_requested_model else null end,
    case when p_selection_mode='manual' then p_fallback_mode else 'allow_fallback' end,
    p_reasoning_mode
  )
  on conflict(thread_id) do update set
    selection_mode=excluded.selection_mode,
    requested_provider=excluded.requested_provider,
    requested_model=excluded.requested_model,
    fallback_mode=excluded.fallback_mode,
    reasoning_mode=excluded.reasoning_mode,
    updated_at=now()
  where pandora_intelligence_thread_routing_state.organization_id=excluded.organization_id;

  select r.* into strict v_row
  from private.pandora_intelligence_thread_routing_state r
  where r.thread_id=p_thread_id and r.organization_id=p_organization_id;

  return jsonb_build_object(
    'ok',true,
    'selection',jsonb_build_object(
      'selectionMode',v_row.selection_mode,
      'requestedProvider',v_row.requested_provider,
      'requestedModel',v_row.requested_model,
      'fallbackMode',v_row.fallback_mode,
      'reasoningMode',v_row.reasoning_mode,
      'executedProvider',v_row.provider,
      'executedModel',v_row.model,
      'updatedAt',v_row.updated_at
    )
  );
end;
$;
revoke all on function public.pandora_intelligence_thread_model_selection_set_v1(uuid,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.pandora_intelligence_thread_model_selection_set_v1(uuid,uuid,text,text,text,text,text) to authenticated,service_role;

create or replace function public.pandora_bedrock_chat_route_v1(p_model_id text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','pg_temp'
as $
declare
  v_row private.pandora_bedrock_reasoning_catalog%rowtype;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role'
  then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  select * into v_row
  from private.pandora_bedrock_reasoning_catalog c
  where c.model_id=p_model_id
    and c.conversational=true and c.present_in_latest_sync=true
    and c.lifecycle_status='ACTIVE'
    and c.agreement_status='AVAILABLE'
    and c.authorization_status='AUTHORIZED'
    and c.entitlement_status='AVAILABLE'
    and c.region_availability='AVAILABLE'
    and c.routable=true
    and c.runtime_verification_status='passed';
  if not found then raise exception 'MANUAL_MODEL_UNAVAILABLE' using errcode='22023'; end if;
  return jsonb_build_object(
    'modelId',v_row.model_id,
    'providerName',v_row.provider_name,
    'invocationTarget',v_row.invocation_target,
    'region',v_row.region
  );
end;
$;
revoke all on function public.pandora_bedrock_chat_route_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_bedrock_chat_route_v1(text) to service_role;

commit;
