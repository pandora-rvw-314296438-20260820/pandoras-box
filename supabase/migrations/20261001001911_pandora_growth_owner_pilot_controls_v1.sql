
begin;

create or replace function public.pandora_growth_paid_pilot_owner_control_v1(
  p_organization_id uuid,
  p_action text,
  p_request_key text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_project_id uuid;
  v_role text;
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  c public.pandora_tracking_campaigns%rowtype;
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_previous_claims text:=current_setting('request.jwt.claims',true);
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'PANDORA_GROWTH_OWNER_SIGN_IN_REQUIRED' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_user_id
    and m.status='active'
  limit 1;
  if v_role is distinct from 'owner' then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_REQUIRED' using errcode='42501';
  end if;

  if v_action not in ('prepare','activate','stop') then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_ACTION_INVALID' using errcode='22023';
  end if;
  if p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$' then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_REQUEST_KEY_INVALID' using errcode='22023';
  end if;

  select t.project_id into v_project_id
  from public.pandora_tracking_tenants t
  where t.organization_id=p_organization_id
    and t.workspace_key='pandora-platform'
    and t.status='active'
  order by t.created_at
  limit 1;
  if v_project_id is null then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_PROJECT_UNAVAILABLE' using errcode='P0002';
  end if;

  select * into a
  from private.pandora_meta_paid_pilot_authorizations
  where organization_id=p_organization_id
    and project_id=v_project_id
  order by updated_at desc,created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_AUTHORIZATION_UNAVAILABLE' using errcode='P0002';
  end if;

  if a.currency<>'PHP'
     or a.max_spend_minor<>500000
     or a.daily_budget_minor<>40000
     or a.duration_seconds<>604800 then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_ENVELOPE_MISMATCH' using errcode='42501';
  end if;

  select * into c
  from public.pandora_tracking_campaigns
  where id=a.tracking_campaign_id;
  if not found
     or c.metadata->>'purpose'<>'promote-pandora'
     or c.metadata->'business_kpi' is distinct from 'true'::jsonb
     or c.metadata->>'tracking_mode'<>'business'
     or c.metadata->>'tracked_redirect'<>'https://mcpmaster.vercel.app/t/pandora-meta-main' then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_TRACKING_MISMATCH' using errcode='42501';
  end if;

  if v_action in ('prepare','activate')
     and coalesce((c.metadata->>'provider_creative_ready')::boolean,false) is not true then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_CREATIVE_NOT_READY' using errcode='42501';
  end if;

  if v_action='prepare' and a.state<>'approved' then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_PREPARE_STATE_INVALID' using errcode='42501';
  end if;
  if v_action='activate' and a.state<>'prepared' then
    raise exception 'PANDORA_GROWTH_OWNER_CONTROL_ACTIVATE_STATE_INVALID' using errcode='42501';
  end if;
  if v_action='stop' and a.state not in ('approved','prepared','active') then
    return jsonb_build_object(
      'ok',true,
      'action','stop',
      'state',a.state,
      'noOp',true,
      'authorizationId',a.id
    );
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role','service_role')::text,
    true
  );
  begin
    if v_action='prepare' then
      v_result:=public.pandora_meta_prepare_paid_pilot_v1(a.id,p_request_key);
    elsif v_action='activate' then
      v_result:=public.pandora_meta_activate_paid_pilot_v1(a.id,p_request_key);
    else
      v_result:=public.pandora_meta_stop_paid_pilot_v1(
        a.id,
        p_request_key,
        coalesce(nullif(btrim(p_reason),''),'owner paused from Marketing & Growth')
      );
    end if;
  exception when others then
    perform set_config('request.jwt.claims',coalesce(v_previous_claims,''),true);
    raise;
  end;
  perform set_config('request.jwt.claims',coalesce(v_previous_claims,''),true);

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ownerControl',true,
    'action',v_action,
    'authorizationId',a.id,
    'trackingCampaignId',a.tracking_campaign_id
  );
end;
$function$;

revoke all on function public.pandora_growth_paid_pilot_owner_control_v1(
  uuid,text,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.pandora_growth_paid_pilot_owner_control_v1(
  uuid,text,text,text
) to authenticated;

commit;
;
