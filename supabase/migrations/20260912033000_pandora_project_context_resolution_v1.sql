-- Pandora project context resolution v1
-- Reuse existing systems when identity is explicit enough; never create or guess a project from fuzzy similarity.

create or replace function private.pandora_resolve_project_context_v1(
  p_organization_id uuid,
  p_message text,
  p_explicit_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $$
declare
  v_message text := lower(trim(coalesce(p_message,'')));
  v_repository text;
  v_top_score integer := 0;
  v_top_count integer := 0;
  v_project public.projectos_projects%rowtype;
  v_candidates jsonb := '[]'::jsonb;
begin
  if p_organization_id is null then
    raise exception 'pandora_project_context_organization_required' using errcode='22023';
  end if;
  if length(v_message) > 8000 then
    raise exception 'pandora_project_context_message_too_long' using errcode='22023';
  end if;

  if p_explicit_project_id is not null then
    select * into v_project
    from public.projectos_projects p
    where p.organization_id=p_organization_id
      and p.id=p_explicit_project_id
      and p.status <> 'archived'
    limit 1;

    if not found then
      return jsonb_build_object(
        'state','invalid_explicit',
        'resolved',false,
        'projectId',null,
        'candidateCount',0,
        'reason','explicit_project_not_found'
      );
    end if;

    return jsonb_build_object(
      'state','resolved',
      'resolved',true,
      'resolution','explicit_project_id',
      'projectId',v_project.id,
      'projectKey',v_project.project_key,
      'projectName',v_project.name,
      'repository',v_project.repository,
      'candidateCount',1
    );
  end if;

  if v_message='' then
    return jsonb_build_object('state','none','resolved',false,'projectId',null,'candidateCount',0);
  end if;

  v_repository := substring(v_message from '([a-z0-9_.-]+/[a-z0-9_.-]+)');

  with scored as (
    select
      p.*,
      case
        when v_repository is not null and lower(coalesce(p.repository,''))=v_repository then 100
        when p.project_key='mcpmaster' and v_message ~ '(pandoras-box|pandora''s box|mcpmaster)' then 95
        when length(trim(p.project_key)) >= 4 and position(lower(p.project_key) in v_message) > 0 then 90
        when p.repository is not null
          and length(split_part(p.repository,'/',2)) >= 5
          and position(lower(split_part(p.repository,'/',2)) in v_message) > 0 then 80
        when length(trim(p.name)) >= 4 and position(lower(p.name) in v_message) > 0 then 70
        else 0
      end as score
    from public.projectos_projects p
    where p.organization_id=p_organization_id
      and p.status <> 'archived'
  ), ranked as (
    select * from scored where score > 0
  )
  select coalesce(max(score),0) into v_top_score from ranked;

  if v_top_score=0 then
    return jsonb_build_object(
      'state','none',
      'resolved',false,
      'projectId',null,
      'candidateCount',0,
      'reason','no_high_confidence_existing_project_match'
    );
  end if;

  with scored as (
    select
      p.*,
      case
        when v_repository is not null and lower(coalesce(p.repository,''))=v_repository then 100
        when p.project_key='mcpmaster' and v_message ~ '(pandoras-box|pandora''s box|mcpmaster)' then 95
        when length(trim(p.project_key)) >= 4 and position(lower(p.project_key) in v_message) > 0 then 90
        when p.repository is not null
          and length(split_part(p.repository,'/',2)) >= 5
          and position(lower(split_part(p.repository,'/',2)) in v_message) > 0 then 80
        when length(trim(p.name)) >= 4 and position(lower(p.name) in v_message) > 0 then 70
        else 0
      end as score
    from public.projectos_projects p
    where p.organization_id=p_organization_id
      and p.status <> 'archived'
  ), top_candidates as (
    select * from scored where score=v_top_score order by updated_at desc, id
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object(
      'projectId',id,
      'projectKey',project_key,
      'projectName',name,
      'repository',repository,
      'score',score
    )),'[]'::jsonb)
  into v_top_count,v_candidates
  from top_candidates;

  if v_top_count <> 1 then
    return jsonb_build_object(
      'state','ambiguous',
      'resolved',false,
      'projectId',null,
      'candidateCount',v_top_count,
      'candidates',v_candidates,
      'reason','multiple_existing_projects_match'
    );
  end if;

  select p.* into v_project
  from public.projectos_projects p
  join jsonb_array_elements(v_candidates) c(value) on (c.value->>'projectId')::uuid=p.id
  where p.organization_id=p_organization_id
  limit 1;

  return jsonb_build_object(
    'state','resolved',
    'resolved',true,
    'resolution',case v_top_score
      when 100 then 'exact_repository'
      when 95 then 'canonical_alias'
      when 90 then 'project_key'
      when 80 then 'repository_name'
      when 70 then 'project_name'
      else 'unknown'
    end,
    'projectId',v_project.id,
    'projectKey',v_project.project_key,
    'projectName',v_project.name,
    'repository',v_project.repository,
    'candidateCount',1
  );
end;
$$;

revoke all on function private.pandora_resolve_project_context_v1(uuid,text,uuid) from public, anon, authenticated;
grant execute on function private.pandora_resolve_project_context_v1(uuid,text,uuid) to service_role;

create or replace function public.pandora_chat_universal_dispatch_v5(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_message text := trim(coalesce(p_message,''));
  v_project_context jsonb;
  v_effective_project_id uuid;
  v_workflow jsonb;
  v_result jsonb;
  v_thread_id uuid := p_thread_id;
  v_reply text;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  v_project_context := private.pandora_resolve_project_context_v1(
    p_organization_id,
    v_message,
    p_project_id
  );

  if v_project_context->>'state'='invalid_explicit' then
    raise exception 'pandora_chat_project_not_found' using errcode='22023';
  end if;

  if v_project_context->>'state'='ambiguous' then
    v_reply := 'I found more than one existing Pandora project that matches this request. Tell me the project name, project key, or repository to use. I will not guess or create a duplicate project.';

    if v_thread_id is not null then
      if not exists(
        select 1 from public.pandora_intelligence_threads t
        where t.id=v_thread_id
          and t.organization_id=p_organization_id
          and t.created_by=v_uid
          and t.status='active'
      ) then
        raise exception 'pandora_chat_thread_not_found' using errcode='22023';
      end if;
    else
      insert into public.pandora_intelligence_threads(
        organization_id,project_id,created_by,title,status,last_message_at
      ) values (
        p_organization_id,null,v_uid,
        left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
        'active',now()
      ) returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,attachment_manifest
    ) values (v_thread_id,p_organization_id,null,'user',v_message,'[]'::jsonb);

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values (
      v_thread_id,p_organization_id,null,'assistant',v_reply,
      jsonb_build_object(
        'intent','clarify_project',
        'confidence',1,
        'needsClarification',true,
        'clarifyingQuestion',v_reply,
        'projectContext',v_project_context
      ),
      'pandora_project_resolver','project-context-v1'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now()
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,
      'threadId',v_thread_id,
      'reply',v_reply,
      'intent','clarify_project',
      'confidence',1,
      'needsClarification',true,
      'clarifyingQuestion',v_reply,
      'projectContext',v_project_context
    );
  end if;

  v_effective_project_id := nullif(v_project_context->>'projectId','')::uuid;

  v_workflow := private.pandora_multi_capability_workflow_v1(
    p_organization_id,
    v_message,
    v_effective_project_id
  );

  if not coalesce((v_workflow->>'handled')::boolean,false) then
    v_result := public.pandora_chat_universal_dispatch_v4(
      p_organization_id,
      p_message,
      p_thread_id,
      v_effective_project_id
    );
    if jsonb_typeof(v_result)='object' then
      v_result := jsonb_set(v_result,'{projectContext}',v_project_context,true);
    end if;
    return v_result;
  end if;

  v_reply := case v_workflow->>'status'
    when 'verified' then format('Pandora completed %s governed read steps and verified each provider result.',v_workflow->>'stepCount')
    when 'awaiting_governed_execution' then format('Pandora resolved %s ordered capability steps. Safe reads are verified; consequential steps are routed through ProjectOS and are not complete until provider readback and evidence succeed.',v_workflow->>'stepCount')
    else format('Pandora resolved %s ordered capability steps, but at least one step is blocked or unresolved. No blocked step was treated as complete.',v_workflow->>'stepCount')
  end;

  if v_thread_id is not null then
    if not exists(
      select 1 from public.pandora_intelligence_threads t
      where t.id=v_thread_id
        and t.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
    ) then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(
      organization_id,project_id,created_by,title,status,last_message_at
    ) values (
      p_organization_id,v_effective_project_id,v_uid,
      left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
      'active',now()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values (v_thread_id,p_organization_id,v_effective_project_id,'user',v_message,'[]'::jsonb);

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values (
    v_thread_id,p_organization_id,v_effective_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent','multi_capability_workflow',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'workflow',v_workflow,
      'projectContext',v_project_context
    ),
    'pandora_workflow_router','workflow-v1'
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(),updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent','multi_capability_workflow',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'workflow',v_workflow,
    'projectContext',v_project_context
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) to authenticated;
