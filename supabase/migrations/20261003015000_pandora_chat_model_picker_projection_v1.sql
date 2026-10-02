begin;
create or replace function public.pandora_chat_model_picker_v1(
  p_organization_id uuid,
  p_thread_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_selection jsonb;
  v_models jsonb;
begin
  if v_user_id is null then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
      and m.role in ('owner','admin')
  ) then raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode='42501'; end if;
  if p_thread_id is not null then
    if not exists (
      select 1 from public.pandora_intelligence_threads t
      where t.id=p_thread_id and t.organization_id=p_organization_id and t.status='active'
    ) then raise exception 'THREAD_NOT_FOUND' using errcode='P0002'; end if;
    select jsonb_build_object(
      'selectionMode',r.selection_mode,
      'requestedProvider',r.requested_provider,
      'requestedModel',r.requested_model,
      'fallbackMode',r.fallback_mode,
      'reasoningMode',r.reasoning_mode
    ) into v_selection
    from private.pandora_intelligence_thread_routing_state r
    where r.thread_id=p_thread_id and r.organization_id=p_organization_id;
  end if;
  v_selection:=coalesce(v_selection,jsonb_build_object(
    'selectionMode','auto','requestedProvider',null,'requestedModel',null,
    'fallbackMode','allow_fallback','reasoningMode','auto'
  ));
  select coalesce(jsonb_agg(jsonb_build_object(
    'routingProvider','bedrock',
    'providerName',c.provider_name,
    'modelId',c.model_id,
    'modelName',c.model_name,
    'selectable',c.routable=true and c.conversational=true
      and c.present_in_latest_sync=true
      and c.runtime_verification_status='passed'
      and c.lifecycle_status='ACTIVE',
    'availability',case when c.routable=true and c.conversational=true
      and c.present_in_latest_sync=true
      and c.runtime_verification_status='passed'
      and c.lifecycle_status='ACTIVE'
      then 'available' else 'unavailable' end,
    'unavailableReason',case
      when c.routable=true and c.runtime_verification_status='passed'
        and c.lifecycle_status='ACTIVE' then null
      when c.agreement_status<>'AVAILABLE' then 'Payment or provider agreement required'
      when c.authorization_status<>'AUTHORIZED' then 'Access denied'
      when c.entitlement_status<>'AVAILABLE' then 'Not entitled'
      when c.region_availability<>'AVAILABLE' then 'Unavailable in this region'
      when c.runtime_verification_status='failed' and c.probe_http_status=403 then 'Access denied'
      when c.runtime_verification_status='failed' then 'Runtime verification failed'
      else 'Unavailable'
    end,
    'lastVerifiedAt',c.last_verified_at
  ) order by case when c.routable then 0 else 1 end,c.provider_name,c.model_name,c.model_id),'[]'::jsonb)
  into v_models
  from private.pandora_bedrock_reasoning_catalog c
  where c.conversational=true
    and c.present_in_latest_sync=true
    and c.lifecycle_status<>'REMOVED';
  return jsonb_build_object(
    'contractVersion','pandora-chat-model-picker-v1',
    'selection',v_selection,
    'models',v_models
  );
end;
$$;
revoke all on function public.pandora_chat_model_picker_v1(uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_model_picker_v1(uuid,uuid) to authenticated,service_role;
commit;
