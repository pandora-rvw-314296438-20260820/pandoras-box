
create or replace function private.pandora_growth_chat_dispatch_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth','pg_temp'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_norm text:=lower(regexp_replace(trim(coalesce(p_message,'')),'[[:space:]]+',' ','g'));
  v_center jsonb;
  v_thread_id uuid:=p_thread_id;
  v_reply text;
  v_campaigns integer:=0;
  v_outcomes integer:=0;
  v_memory integer:=0;
  v_experiments integer:=0;
  v_leads integer:=0;
  v_latest_memory jsonb;
  v_mutation_requested boolean:=false;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;

  if v_norm='' or length(v_norm)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  if not (
    v_norm ~ '\m(marketing|growth|campaign|campaigns|roas|cac|lead|leads|experiment|experiments|spend|conversion|conversions)\M'
    or v_norm ~ '(facebook[[:space:]]+marketing|meta[[:space:]]+marketing|facebook[[:space:]]+campaign|meta[[:space:]]+campaign)'
  ) then
    return jsonb_build_object('handled',false);
  end if;

  v_mutation_requested := v_norm ~ '\m(create|publish|activate|launch|increase|decrease|change|edit|update|pause|resume|delete|budget|spend|scale)\M'
    and v_norm ~ '\m(campaign|campaigns|ad|ads|adset|adsets|budget|spend)\M';

  v_center:=public.pandora_marketing_growth_command_center_v2(p_organization_id);
  v_campaigns:=jsonb_array_length(coalesce(v_center->'campaigns','[]'::jsonb));
  v_outcomes:=jsonb_array_length(coalesce(v_center->'outcomes','[]'::jsonb));
  v_memory:=jsonb_array_length(coalesce(v_center->'approvedMemory','[]'::jsonb));
  v_experiments:=jsonb_array_length(coalesce(v_center->'experimentRuns','[]'::jsonb));
  v_leads:=jsonb_array_length(coalesce(v_center->'leadStages','[]'::jsonb));
  if v_memory>0 then v_latest_memory:=v_center->'approvedMemory'->0; end if;

  if v_mutation_requested then
    v_reply:=format(
      'Marketing & Growth is live and I verified its control plane. I will not mutate or spend from a read-only chat request: campaign mutation, publishing and spend remain unauthorized. Current evidence: %s tracked campaign(s), %s outcome group(s), %s experiment run(s), %s approved Memory receipt(s).',
      v_campaigns,v_outcomes,v_experiments,v_memory
    );
  else
    v_reply:=format(
      'Marketing & Growth is live. I verified %s tracked campaign(s), %s business outcome group(s), %s lead-stage record(s), %s experiment run(s), and %s approved Memory receipt(s). The current safety state still denies campaign mutation, publishing and spend. %s',
      v_campaigns,v_outcomes,v_leads,v_experiments,v_memory,
      case when v_latest_memory is null
        then 'No approved growth Memory receipt is currently attached.'
        else 'Latest approved Memory record: '||coalesce(v_latest_memory->>'memoryRecordId','unknown')||'.'
      end
    );
  end if;

  if v_thread_id is not null then
    perform 1
    from public.pandora_intelligence_threads t
    where t.id=v_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=v_uid
      and t.status='active';
    if not found then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(
      organization_id,project_id,created_by,title,status,last_message_at
    ) values(
      p_organization_id,p_project_id,v_uid,
      left(regexp_replace(trim(p_message),'[[:space:]]+',' ','g'),80),
      'active',clock_timestamp()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values(
    v_thread_id,p_organization_id,p_project_id,'user',p_message,'[]'::jsonb
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values(
    v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent','inspect_growth',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'handoff',null,
      'providerReadback',jsonb_build_object(
        'capability','growth.evidence.read',
        'verified',true,
        'sourceMode',v_center->>'sourceMode',
        'tenant',v_center->'tenant',
        'campaignCount',v_campaigns,
        'outcomeGroupCount',v_outcomes,
        'leadStageCount',v_leads,
        'experimentRunCount',v_experiments,
        'approvedMemoryCount',v_memory,
        'latestApprovedMemory',v_latest_memory,
        'approvalGates',v_center->'approvalGates',
        'authority',v_center->'authority',
        'mutationRequested',v_mutation_requested,
        'observedAt',clock_timestamp()
      )
    ),
    'pandora_native_capability',
    'deterministic-growth-readback-v1'
  );

  update public.pandora_intelligence_threads
  set last_message_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent','inspect_growth',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'projectRequired',false,
    'handoff',null,
    'providerReadback',jsonb_build_object(
      'capability','growth.evidence.read',
      'verified',true,
      'campaignCount',v_campaigns,
      'outcomeGroupCount',v_outcomes,
      'leadStageCount',v_leads,
      'experimentRunCount',v_experiments,
      'approvedMemoryCount',v_memory,
      'latestApprovedMemory',v_latest_memory,
      'approvalGates',v_center->'approvalGates',
      'authority',v_center->'authority',
      'mutationRequested',v_mutation_requested,
      'observedAt',clock_timestamp()
    )
  );
end;
$function$;

revoke all on function private.pandora_growth_chat_dispatch_v1(uuid,text,uuid,uuid)
from public,anon,authenticated;
grant execute on function private.pandora_growth_chat_dispatch_v1(uuid,text,uuid,uuid)
to authenticated,service_role;

create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','auth','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_direct_action boolean := false;
  v_plp_explicit boolean := false;
  v_box_explicit boolean := false;
  v_plp_context boolean := false;
  v_box_context boolean := false;
  v_tax_operation boolean := false;
  v_tax jsonb;
  v_growth jsonb;
  v_capability jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;

  if v_norm='' or length(v_norm)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_direct_action := v_norm ~ '\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|refactor|rewrite|finish|complete|make)\M';
  v_plp_explicit := v_norm ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M';
  v_box_explicit := v_norm ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo|this[[:space:]]+repo)\M';
  v_tax_operation := (
    v_norm ~ '\m(2550q|2551q|1702q|1702-rt|1601-eq)\M'
    or (
      v_norm ~ '\m(tax|taxes|vat|bir)\M'
      and v_norm ~ '\m(status|overview|position|ready|owe|due|reconcile|reconciliation|calculate|calculation|compute|file|filing|submit|sign|otp|pay|payment|prepare|build|create|package|return)\M'
    )
  );

  v_growth:=private.pandora_growth_chat_dispatch_v1(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
  if coalesce((v_growth->>'handled')::boolean,false) then
    return v_growth;
  end if;

  if v_tax_operation then
    v_tax := private.pandora_tax_chat_dispatch_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
    if coalesce((v_tax->>'handled')::boolean,false) then
      return v_tax;
    end if;
  end if;

  if p_thread_id is not null and (not v_plp_explicit or not v_box_explicit) then
    select
      coalesce(bool_or(lower(recent.content) ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M'),false),
      coalesce(bool_or(lower(recent.content) ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo)\M'),false)
    into v_plp_context,v_box_context
    from (
      select m.content
      from public.pandora_intelligence_messages m
      join public.pandora_intelligence_threads t on t.id=m.thread_id
      where m.thread_id=p_thread_id
        and m.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
      order by m.created_at desc
      limit 12
    ) recent;
  end if;

  if v_direct_action and (v_plp_explicit or (v_plp_context and not v_box_explicit)) then
    return private.pandora_direct_plp_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  if v_direct_action and (v_box_explicit or v_box_context) then
    return private.pandora_direct_box_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  v_capability := public.pandora_chat_capability_dispatch_native_v1(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
  if coalesce((v_capability->>'handled')::boolean,false) then
    return v_capability;
  end if;

  return jsonb_build_object(
    'handled',false,
    'routing','pandora_native_intelligence',
    'projectId',p_project_id,
    'projectRequired',false,
    'requestMode','intelligence'
  );
end;
$function$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
to authenticated,service_role;

comment on function private.pandora_growth_chat_dispatch_v1(uuid,text,uuid,uuid)
is 'Deterministic owner/admin Marketing & Growth evidence-chat path. Read-only provider evidence; never grants campaign mutation, publishing or spend authority.';
;
