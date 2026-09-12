-- Pandora Universal Chat repository targeting v2
-- Keeps actionable repository work in chat, resolves high-confidence targets,
-- preserves the owner's exact prompt, and never lets target resolution grant authority.

create or replace function private.pandora_resolve_repository_target_v2(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_explicit_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $$
declare
  v_message text := lower(trim(coalesce(p_message,'')));
  v_repository text;
  v_project public.projectos_projects%rowtype;
  v_previous jsonb;
  v_continuation boolean := false;
begin
  if p_organization_id is null then
    raise exception 'pandora_repository_target_organization_required' using errcode='22023';
  end if;
  if length(v_message)>8000 then
    raise exception 'pandora_repository_target_message_too_long' using errcode='22023';
  end if;

  -- Explicit full repository identity always wins.
  v_repository := substring(v_message from '(?i)github\.com/([a-z0-9_.-]+/[a-z0-9_.-]+)');
  if v_repository is null then
    v_repository := substring(v_message from '([a-z0-9_.-]+/[a-z0-9_.-]+)');
  end if;
  if v_repository is not null then
    return jsonb_build_object(
      'state','resolved','resolved',true,'resolution','explicit_repository',
      'repository',v_repository,'projectId',null,'projectKey',null,
      'repositoryStatus','provider_identity','projectRequired',false
    );
  end if;

  -- Fixed canonical aliases are verified provider identities, not fuzzy guesses.
  if v_message ~ '(pandoras[- ]box[- ]memory|pandora''?s[ -]box[ -]memory|pandora memory repo|memory repo)' then
    return jsonb_build_object(
      'state','resolved','resolved',true,'resolution','canonical_repository_alias',
      'repository','pandora-rvw-314296438-20260820/pandoras-box-memory',
      'projectId',null,'projectKey','pandoras-box-memory',
      'repositoryStatus','provider_verified','projectRequired',false
    );
  end if;

  if v_message ~ '(pandoras[- ]box|pandora''?s[ -]box|mcpmaster)' then
    select * into v_project from public.projectos_projects p
    where p.organization_id=p_organization_id and p.project_key='mcpmaster' and p.status<>'archived'
    order by p.updated_at desc limit 1;
    return jsonb_build_object(
      'state','resolved','resolved',true,'resolution','canonical_repository_alias',
      'repository','pandora-rvw-314296438-20260820/pandoras-box',
      'projectId',v_project.id,'projectKey',coalesce(v_project.project_key,'mcpmaster'),
      'repositoryStatus','provider_verified','projectRequired',false
    );
  end if;

  -- PLP is a canonical, provider-verified repository. Provider readback on 2026-09-12 verified
  -- pandora-rvw-314296438-20260820/plp (repo id 1358856339, default branch main).
  if v_message ~ '\\mplp\\M|plp[- ]boracay|pueblo la perla' then
    select * into v_project from public.projectos_projects p
    where p.organization_id=p_organization_id and p.project_key='plp-boracay' and p.status<>'archived'
    order by p.updated_at desc limit 1;
    return jsonb_build_object(
      'state','resolved','resolved',true,'resolution','canonical_repository_alias',
      'repository','pandora-rvw-314296438-20260820/plp',
      'projectId',v_project.id,'projectKey',coalesce(v_project.project_key,'plp-boracay'),
      'projectName',coalesce(v_project.name,'PLP'),'repositoryStatus','provider_verified',
      'repositoryId',1358856339,'projectRequired',false
    );
  end if;

    if p_explicit_project_id is not null then
    select * into v_project from public.projectos_projects p
    where p.organization_id=p_organization_id and p.id=p_explicit_project_id and p.status<>'archived'
    limit 1;
    if found then
      return jsonb_build_object(
        'state','resolved','resolved',true,'resolution','explicit_project_context',
        'repository',v_project.repository,'projectId',v_project.id,'projectKey',v_project.project_key,
        'projectName',v_project.name,'repositoryStatus','project_bound','projectRequired',false
      );
    end if;
  end if;

  -- Short follow-ups such as "build it", "go ahead", and "continue" inherit only
  -- the last explicit, already-resolved target in this same authenticated thread.
  v_continuation := v_message ~ '^\s*(build it|build this|go ahead|do it|continue|continue it|finish it|run it|test it|fix it|deploy it|publish it|proceed|go)\s*[.!?]*\s*$';
  if v_continuation and p_thread_id is not null then
    select m.structured_response->'repositoryTarget' into v_previous
    from public.pandora_intelligence_messages m
    join public.pandora_intelligence_threads t on t.id=m.thread_id
    where m.thread_id=p_thread_id
      and m.organization_id=p_organization_id
      and t.organization_id=p_organization_id
      and t.created_by=auth.uid()
      and m.author_role='assistant'
      and jsonb_typeof(m.structured_response->'repositoryTarget')='object'
      and coalesce((m.structured_response#>>'{repositoryTarget,resolved}')::boolean,false)
    order by m.created_at desc,m.id desc
    limit 1;
    if v_previous is not null then
      return v_previous || jsonb_build_object('resolution','thread_continuation','projectRequired',false);
    end if;

    select p.* into v_project
    from public.pandora_intelligence_threads t
    join public.projectos_projects p on p.id=t.project_id
    where t.id=p_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=auth.uid()
      and t.status='active'
      and p.organization_id=p_organization_id
      and p.status<>'archived'
    limit 1;
    if found then
      return jsonb_build_object(
        'state','resolved','resolved',true,'resolution','thread_project_context',
        'repository',v_project.repository,'projectId',v_project.id,'projectKey',v_project.project_key,
        'projectName',v_project.name,'repositoryStatus','project_bound','projectRequired',false
      );
    end if;
  end if;

  return jsonb_build_object('state','none','resolved',false,'repository',null,'projectId',null,'projectRequired',false);
end;
$$;

revoke all on function private.pandora_resolve_repository_target_v2(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_resolve_repository_target_v2(uuid,text,uuid,uuid) to service_role;

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
  v_read_only := v_message ~* '\m(audit|inspect|review|check|read|show|open|scan|analy[sz]e)\M'
    and v_message !~* '\m(fix|change|update|repair|edit|merge|branch|commit|deploy|publish|build|continue|finish|run|test|implement|work|proceed|create|write|apply|configure|install|remove|restore)\M|go ahead|do it';

  if v_repository is not null then
    v_execution_message := 'GitHub repository '||v_repository||': '||v_message;
  elsif v_target_project_id is not null then
    v_execution_message := 'Existing Pandora project '||coalesce(v_target->>'projectKey',v_target_project_id::text)||': '||v_message;
  else
    return public.pandora_chat_universal_dispatch_v6(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;

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

  -- Build/change actions are admitted to ProjectOS, but target resolution never grants
  -- mutation authority. The owner API/worker path still requires authorization,
  -- one-time claim, provider readback, evidence, and truthful terminal state.
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
is 'Universal Chat repository targeting v2: preserves exact owner prompts, carries high-confidence target context across thread follow-ups, keeps execution inline, and retains ProjectOS as the only mutation authority.';
