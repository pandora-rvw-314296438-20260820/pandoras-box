create or replace function private.pandora_chat_project_request_mode_v1(p_message text)
returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_planning_artifact boolean;
  v_planning_signal boolean;
  v_informational_read boolean;
  v_deep_audit boolean;
  v_sequence_workspace_action boolean;
  v_direct_workspace_action boolean;
begin
  if v = '' then return 'default'; end if;

  v_planning_artifact :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(show|give|generate|draft|write|produce|make|create|build|outline)[[:space:]]+(me[[:space:]]+)?((a|an|the)[[:space:]]+)?((comprehensive|detailed|complete|full|entire|technical|implementation|development|project|build|deployment|migration|execution|action|step|by|step-by-step|end-to-end)[[:space:]]+){0,8}(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|steps)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(can|could|would|will)[[:space:]]+you[[:space:]]+(show|give|generate|draft|write|produce|make|create|build|outline)[[:space:]]+(me[[:space:]]+)?((a|an|the)[[:space:]]+)?((comprehensive|detailed|complete|full|entire|technical|implementation|development|project|build|deployment|migration|execution|action|step|by|step-by-step|end-to-end)[[:space:]]+){0,8}(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|steps)\\M';

  v_sequence_workspace_action :=
    v ~ E'\\m(then|after[[:space:]]+that)\\M[[:space:]]+(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|revamp|rework|restyle|refactor|rebuild)\\M'
    or v ~ E'\\mand\\M[[:space:]]+(then[[:space:]]+)?(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|revamp|rework|restyle|refactor|rebuild)\\M[[:space:]]+(it|this|that|them|the[[:space:]])'
    or v ~ E'[.!?][[:space:]]*(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|revamp|rework|restyle|refactor|rebuild)\\M';

  v_informational_read :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(update|brief|fill)[[:space:]]+me[[:space:]]+(on|about)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(what|how)[[:space:]]+(is|are|was|were|has|have|did|does)[[:space:]]+.*\\m(status|progress|state)\\M';

  v_direct_workspace_action :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|revamp|rework|restyle|refactor|rebuild)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*((can|could|would|will)[[:space:]]+you|i[[:space:]]+(want|need)[[:space:]]+you[[:space:]]+to|let''s|go[[:space:]]+ahead([[:space:]]+and)?)[[:space:]]+(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|revamp|rework|restyle|refactor|rebuild)\\M';

  v_deep_audit :=
    (v ~ E'\\m(audit|analy[sz]e)\\M' and v ~ E'\\m(entire|full|whole|repository|repo|project|codebase|source|code)\\M')
    or (v ~ E'\\m(inspect|review|scan)\\M' and v ~ E'\\m(entire|full|whole|repository|repo|project|codebase|source|all)\\M');

  v_planning_signal :=
    v ~ E'\\m(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|step-by-step|steps)\\M'
    or v ~ E'\\m(how[[:space:]]+(are|should|would|could|can)[[:space:]]+(we|i|you)|what[[:space:]]+should[[:space:]]+(we|i|you)|what[[:space:]]+would[[:space:]]+it[[:space:]]+take|best[[:space:]]+way[[:space:]]+to)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(can|could|would|should)[[:space:]]+(we|i)[[:space:]]+'
    or (v ~ E'\\m(explain|describe|outline|summari[sz]e)\\M' and v ~ E'\\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|deploy|publish|merge|migration|project|system|app|website|redesign|revamp|rework|restyle|refactor|rebuild)\\M')
    or (v ~ E'^(what|how|why|which|where|when)\\M' and v ~ E'\\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|deploy|publish|merge|project|system|app|website|status|progress|state|redesign|revamp|rework|restyle|refactor|rebuild)\\M');

  if v_sequence_workspace_action then return 'workspace_action'; end if;
  if v_planning_artifact then return 'project_intelligence'; end if;
  if v_informational_read then return 'project_intelligence'; end if;
  if v_direct_workspace_action then return 'workspace_action'; end if;
  if v_deep_audit then return 'repository_audit'; end if;
  if v_planning_signal then return 'project_intelligence'; end if;
  return 'default';
end;
$function$;

create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','vault','auth','extensions','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_thread_id uuid := p_thread_id;
  v_thread_project_id uuid;
  v_project_id uuid := p_project_id;
  v_project_mode text;
  v_reply text;
  v_github_context boolean := false;
  v_repo text;
  v_github_result jsonb;
  v_github_status integer;
  v_github_body jsonb;
  v_default_branch text;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_chat_owner_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  if v_thread_id is not null then
    select t.project_id into v_thread_project_id
    from public.pandora_intelligence_threads t
    where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active';
    if not found then raise exception 'pandora_chat_thread_not_found' using errcode='22023'; end if;
    if v_project_id is null then v_project_id := v_thread_project_id; end if;
  end if;

  v_github_context :=
    v_norm ~ E'\\mgithub\\M'
    or (
      v_norm in ('connect','reconnect','try again','do it','yes','yes please','go ahead','proceed')
      and v_thread_id is not null
      and exists (
        select 1
        from (
          select m.content
          from public.pandora_intelligence_messages m
          where m.thread_id=v_thread_id and m.organization_id=p_organization_id
          order by m.created_at desc
          limit 8
        ) recent
        where lower(recent.content) ~ E'\\mgithub\\M'
      )
    );

  if v_github_context and (
    v_norm ~ E'\\m(connect|connected|connection|reconnect|authorize|authorization|access)\\M'
    or v_norm in ('connect','reconnect','try again','do it','yes','yes please','go ahead','proceed')
  ) then
    if v_project_id is not null then
      select p.repository into v_repo
      from public.projectos_projects p
      where p.id=v_project_id and p.organization_id=p_organization_id and p.status <> 'archived';
    end if;
    if coalesce(v_repo,'')='' then
      select p.id,p.repository into v_project_id,v_repo
      from public.projectos_projects p
      where p.organization_id=p_organization_id
        and p.status <> 'archived'
        and coalesce((p.config->>'enterpriseDefault')::boolean,false)=true
        and coalesce(p.repository,'')<>''
      order by p.updated_at desc
      limit 1;
    end if;
    if coalesce(v_repo,'')='' then v_repo := 'pandora-rvw-314296438-20260820/pandoras-box'; end if;
    if v_repo !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then raise exception 'pandora_chat_invalid_repository' using errcode='22023'; end if;

    begin
      v_github_result := private.pandora_integration_github_api_20260825('GET','/repos/'||v_repo,null);
      v_github_status := nullif(v_github_result->>'status','')::integer;
      v_github_body := coalesce(v_github_result->'body','{}'::jsonb);
    exception when others then
      v_github_status := 0;
      v_github_body := '{}'::jsonb;
    end;

    if v_thread_id is null then
      insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
      values(p_organization_id,v_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now())
      returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
    values(v_thread_id,p_organization_id,v_project_id,'user',v_message,'[]'::jsonb);

    if v_github_status=200 and coalesce(v_github_body->>'full_name','')=v_repo then
      v_default_branch := nullif(v_github_body->>'default_branch','');
      v_reply := format('GitHub is already connected. I just verified live access to %s. No new GitHub sign-in or authorization flow is needed.',v_repo);
      update public.connector_installations
      set last_health_check_at=now(),updated_at=now()
      where organization_id=p_organization_id and lower(provider)='github' and status='active';
      insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
      values(v_thread_id,p_organization_id,v_project_id,'assistant',v_reply,
        jsonb_build_object('intent','github_connection_verified','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'handoff',null,'providerReadback',jsonb_build_object('provider','github','verified',true,'repository',v_repo,'defaultBranch',v_default_branch,'verifiedAt',now())),
        'pandora_github_runtime','github-provider-readback-v1');
      update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now(),project_id=coalesce(v_project_id,project_id) where id=v_thread_id;
      return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','github_connection_verified','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,'handoff',null,'providerReadback',jsonb_build_object('provider','github','verified',true,'repository',v_repo,'defaultBranch',v_default_branch,'verifiedAt',now()));
    else
      v_reply := 'GitHub is configured, but Pandora could not verify the live provider connection on this attempt. No new authorization flow was started.';
      insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
      values(v_thread_id,p_organization_id,v_project_id,'assistant',v_reply,
        jsonb_build_object('intent','github_connection_check_failed','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'handoff',null,'providerReadback',jsonb_build_object('provider','github','verified',false,'repository',v_repo,'status',v_github_status,'verifiedAt',now())),
        'pandora_github_runtime','github-provider-readback-v1');
      update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now(),project_id=coalesce(v_project_id,project_id) where id=v_thread_id;
      return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','github_connection_check_failed','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,'handoff',null,'providerReadback',jsonb_build_object('provider','github','verified',false,'repository',v_repo,'status',v_github_status,'verifiedAt',now()));
    end if;
  end if;

  if v_project_id is not null then
    v_project_mode := private.pandora_chat_project_request_mode_v1(v_message);

    if v_project_mode='repository_audit' then
      return jsonb_build_object('handled',false,'routing','repository_audit_direct','projectId',v_project_id,'projectRequired',false,'requestMode',v_project_mode);
    end if;
    if v_project_mode='project_intelligence' then
      return jsonb_build_object('handled',false,'routing','project_intelligence_direct','projectId',v_project_id,'projectRequired',false,'requestMode',v_project_mode);
    end if;
    if v_project_mode='workspace_action' then
      if not exists (select 1 from public.projectos_projects p where p.id=v_project_id and p.organization_id=p_organization_id and p.status <> 'archived') then
        raise exception 'pandora_chat_project_not_found' using errcode='22023';
      end if;
      if v_thread_id is null then
        insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
        values(p_organization_id,v_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()) returning id into v_thread_id;
      end if;
      v_reply := 'I''ll handle this change here in chat. I won''t open another screen. I''ll report only after the real build starts or needs you.';
      insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
      values(v_thread_id,p_organization_id,v_project_id,'user',v_message,'[]'::jsonb);
      insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
      values(v_thread_id,p_organization_id,v_project_id,'assistant',v_reply,
        jsonb_build_object('intent','project_workspace_change','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,'requestMode',v_project_mode,'handoff',jsonb_build_object('required',true,'request',v_message,'projectId',v_project_id,'source','project_workspace_change')),
        'pandora_project_workspace_router','workspace-change-v4-chat-in-place');
      update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now(),project_id=v_project_id where id=v_thread_id;
      return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','project_workspace_change','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,'requestMode',v_project_mode,'handoff',jsonb_build_object('required',true,'request',v_message,'projectId',v_project_id,'source','project_workspace_change'));
    end if;
  end if;

  return jsonb_build_object('handled',false,'routing','pandora_native_intelligence','projectId',v_project_id,'projectRequired',false,'requestMode',coalesce(v_project_mode,'intelligence'));
end;
$function$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) to authenticated;
