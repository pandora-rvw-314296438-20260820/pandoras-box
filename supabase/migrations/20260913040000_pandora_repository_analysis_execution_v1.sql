
-- Pandora repository analysis execution v1
-- Deep repository analysis is a governed ProjectOS research intake, not a metadata read.

create or replace function private.pandora_governed_repository_analysis_request_v1(
  p_organization_id uuid,
  p_repository text,
  p_request_text text,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_repo text := trim(coalesce(p_repository,''));
  v_request text := trim(coalesce(p_request_text,''));
  v_readback jsonb;
  v_project public.projectos_projects%rowtype;
  v_intake jsonb;
  v_idempotency text;
  v_pushed_at text;
begin
  if v_uid is null then raise exception 'pandora_repository_analysis_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_repository_analysis_owner_required' using errcode='42501'; end if;
  if v_repo='' or v_request='' or length(v_request)>8000 then
    raise exception 'pandora_repository_analysis_request_invalid' using errcode='22023';
  end if;

  -- Repository identity is preflight truth only. It must never be confused with
  -- completion of the requested analysis.
  v_readback := private.pandora_governed_provider_read_v1(
    p_organization_id,'github','repository.read',jsonb_build_object('repository',v_repo)
  );
  if not coalesce((v_readback->>'ok')::boolean,false) then
    return jsonb_build_object(
      'ok',false,'provider','github','action','repository.analyze',
      'authority','projectos','repository',v_repo,'verifiedComplete',false,
      'executionState','blocked','reason','repository_preflight_failed',
      'repositoryReadback',v_readback,'observedAt',now()
    );
  end if;

  if p_project_id is not null then
    select * into v_project from public.projectos_projects p
    where p.organization_id=p_organization_id and p.id=p_project_id and p.status<>'archived' limit 1;
  end if;
  if v_project.id is null then
    select * into v_project from public.projectos_projects p
    where p.organization_id=p_organization_id and p.repository=v_repo and p.status<>'archived'
    order by p.updated_at desc limit 1;
  end if;

  v_pushed_at := coalesce(v_readback#>>'{facts,pushedAt}','unknown');
  v_idempotency := encode(digest(
    p_organization_id::text||':'||v_uid::text||':'||v_repo||':'||v_pushed_at||':'||v_request,
    'sha256'
  ),'hex');

  v_intake := public.projectos_accept_intake(
    p_organization_id,
    v_uid,
    v_request,
    coalesce(v_project.project_key, lower(regexp_replace(split_part(v_repo,'/',2),'[^a-zA-Z0-9._-]+','-','g'))),
    coalesce(v_project.name, initcap(replace(split_part(v_repo,'/',2),'-',' '))),
    v_repo,
    'research',
    'pandora_chat',
    v_idempotency
  );

  return jsonb_build_object(
    'ok',true,
    'provider','github',
    'action','repository.analyze',
    'authority','projectos',
    'repository',v_repo,
    'projectId',coalesce(v_intake#>>'{project,id}',v_project.id::text),
    'intakeId',v_intake#>>'{intake,id}',
    'intakeStatus',v_intake#>>'{intake,status}',
    'executionState','accepted',
    'verifiedComplete',false,
    'repositoryReadback',v_readback,
    'completionRule','ProjectOS execution, analysis evidence, and verified terminal state are required before completion may be claimed.',
    'observedAt',now()
  );
end;
$$;

revoke all on function private.pandora_governed_repository_analysis_request_v1(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function private.pandora_governed_repository_analysis_request_v1(uuid,text,text,uuid) to service_role;

create or replace function public.pandora_chat_universal_dispatch_v7(
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
  v_target jsonb;
  v_repository text;
  v_target_project_id uuid;
  v_actionable boolean;
  v_read_only boolean;
  v_deep_analysis boolean;
  v_execution_message text;
  v_result jsonb;
  v_thread_id uuid := p_thread_id;
  v_reply text;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  v_target := private.pandora_resolve_repository_target_v2(p_organization_id,v_message,p_thread_id,p_project_id);
  v_actionable := v_message ~* '\m(audit|inspect|review|check|read|show|open|scan|analy[sz]e|debug|fix|change|update|repair|edit|merge|branch|commit|deploy|publish|build|continue|finish|run|test|implement|work|proceed|create|write|apply|configure|install|remove|restore)\M|go ahead|do it';

  if not v_actionable or not coalesce((v_target->>'resolved')::boolean,false) then
    return public.pandora_chat_universal_dispatch_v6(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;

  v_repository := nullif(v_target->>'repository','');
  v_target_project_id := nullif(v_target->>'projectId','')::uuid;
  v_deep_analysis := v_message ~* '\m(audit|analy[sz]e)\M'
    or (
      v_message ~* '\m(inspect|review|scan)\M'
      and v_message ~* '\m(entire|full|whole|repository|repo|project|codebase|source|all)\M'
    );
  v_read_only := v_message ~* '\m(audit|inspect|review|check|read|show|open|scan|analy[sz]e)\M'
    and v_message !~* '\m(fix|change|update|repair|edit|merge|branch|commit|deploy|publish|build|continue|finish|run|test|implement|work|proceed|create|write|apply|configure|install|remove|restore)\M|go ahead|do it';

  if v_repository is not null then
    v_execution_message := 'GitHub repository '||v_repository||': '||v_message;
  elsif v_target_project_id is not null then
    v_execution_message := 'Existing Pandora project '||coalesce(v_target->>'projectKey',v_target_project_id::text)||': '||v_message;
  else
    return public.pandora_chat_universal_dispatch_v6(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;

  -- An audit/analysis is not a metadata lookup. Verify the repository as a
  -- preflight, then create a governed research intake that keeps the exact owner
  -- request and target context. Build Theatre may project only real persisted
  -- ProjectOS/provider events from that intake.
  if v_deep_analysis and v_repository is not null then
    v_result := private.pandora_governed_repository_analysis_request_v1(
      p_organization_id,v_repository,v_message,v_target_project_id
    );
    if coalesce((v_result->>'ok')::boolean,false) then
      v_reply := format(
        'I verified %s and admitted your full repository analysis to ProjectOS. The repository lookup is only preflight evidence; the analysis is not complete until ProjectOS produces and verifies the actual result.',
        v_repository
      );
    else
      v_reply := format(
        'I resolved this to %s, but repository verification failed, so Pandora did not pretend that a metadata lookup was a completed analysis.',
        v_repository
      );
    end if;

    if v_thread_id is not null then
      if not exists(select 1 from public.pandora_intelligence_threads t where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active') then
        raise exception 'pandora_chat_thread_not_found' using errcode='22023';
      end if;
    else
      insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
      values(p_organization_id,v_target_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now())
      returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
    values(v_thread_id,p_organization_id,v_target_project_id,'user',v_message,'[]'::jsonb);
    insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
    values(v_thread_id,p_organization_id,v_target_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','repository_analysis','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
        'repositoryTarget',v_target,'projectRequired',false,
        'capabilityResult',v_result,
        'handoff',case when coalesce((v_result->>'ok')::boolean,false)
          then jsonb_strip_nulls(jsonb_build_object(
            'required',true,
            'request',v_message,
            'projectId',coalesce(nullif(v_result->>'projectId','')::uuid,v_target_project_id),
            'repository',v_repository,
            'source','projectos_intake',
            'intakeId',v_result->>'intakeId',
            'executionKind','repository_analysis'
          )) else null end
      ),'pandora_repository_router','repository-analysis-v1');
    update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,'threadId',v_thread_id,'reply',v_reply,
      'intent','repository_analysis','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
      'repositoryTarget',v_target,'projectRequired',false,
      'handoff',case when coalesce((v_result->>'ok')::boolean,false)
        then jsonb_strip_nulls(jsonb_build_object(
          'required',true,
          'request',v_message,
          'projectId',coalesce(nullif(v_result->>'projectId','')::uuid,v_target_project_id),
          'repository',v_repository,
          'source','projectos_intake',
          'intakeId',v_result->>'intakeId',
          'executionKind','repository_analysis'
        )) else null end,
      'capabilityResult',v_result
    );
  end if;

  -- Bounded status/check reads may remain direct provider reads.
  if v_read_only and v_repository is not null then
    v_result := public.pandora_chat_universal_dispatch_v6(
      p_organization_id,v_execution_message,p_thread_id,v_target_project_id
    );
    if coalesce((v_result->>'handled')::boolean,false) then
      v_thread_id := nullif(v_result->>'threadId','')::uuid;
      if v_thread_id is not null then
        update public.pandora_intelligence_messages
        set content=v_message
        where id=(
          select id from public.pandora_intelligence_messages
          where thread_id=v_thread_id and organization_id=p_organization_id
            and author_role='user' and content=v_execution_message
          order by created_at desc,id desc limit 1
        );
      end if;
      v_result := jsonb_set(v_result,'{repositoryTarget}',v_target,true);
      v_result := jsonb_set(v_result,'{projectRequired}','false'::jsonb,true);
      return v_result;
    end if;
  end if;

  v_result := private.pandora_governed_mutation_request_v1(
    p_organization_id,'github','repository.write',v_execution_message,v_target_project_id
  );

  if coalesce((v_result->>'ok')::boolean,false) then
    v_reply := case
      when v_repository is not null then format('I resolved this to %s and routed your exact request through ProjectOS. Execution stays in this chat and is not complete until provider readback and evidence verify it.',v_repository)
      else format('I resolved this to existing project %s and routed your exact request through ProjectOS. Execution stays in this chat; the source binding must verify before Pandora can claim completion.',coalesce(v_target->>'projectKey','the selected project'))
    end;
  else
    v_reply := case
      when v_target->>'repositoryStatus'='degraded' then format('I resolved this to existing project %s, but its repository binding is currently degraded. I kept the request in chat and did not guess a replacement repository or execute an unverified mutation.',coalesce(v_target->>'projectKey','the selected project'))
      else 'I resolved the requested target, but current governed GitHub runtime authority is unavailable. No mutation was executed.'
    end;
  end if;

  if v_thread_id is not null then
    if not exists(select 1 from public.pandora_intelligence_threads t where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active') then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
    values(p_organization_id,v_target_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
  values(v_thread_id,p_organization_id,v_target_project_id,'user',v_message,'[]'::jsonb);
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
  values(v_thread_id,p_organization_id,v_target_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent','repository_action','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
      'repositoryTarget',v_target,'projectRequired',false,
      'capabilityResult',v_result,
      'handoff',case when coalesce((v_result->>'ok')::boolean,false)
        then jsonb_strip_nulls(jsonb_build_object(
          'required',true,'request',v_execution_message,'projectId',v_target_project_id,
          'source','projectos_intake','intakeId',v_result->>'intakeId'))
        else null end
    ),'pandora_repository_router','repository-target-v2');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,'threadId',v_thread_id,'reply',v_reply,
    'intent','repository_action','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
    'repositoryTarget',v_target,'projectRequired',false,
    'handoff',case when coalesce((v_result->>'ok')::boolean,false)
      then jsonb_strip_nulls(jsonb_build_object(
        'required',true,'request',v_execution_message,'projectId',v_target_project_id,
        'source','projectos_intake','intakeId',v_result->>'intakeId'))
      else null end,
    'capabilityResult',v_result
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v7(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v7(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_universal_dispatch_v7(uuid,text,uuid,uuid)
is 'Universal Chat repository execution v1: deep audit/analyze requests create governed ProjectOS research intake after provider preflight; bounded status reads stay direct; mutations retain ProjectOS authority.';
