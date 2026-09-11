-- Pandora multi-capability workflow routing v1
-- One owner request may span multiple providers. This migration plans and records
-- the ordered workflow only; it never bypasses ProjectOS or claims provider completion.

create or replace function private.pandora_workflow_step_v1(
  p_registry jsonb,
  p_sequence integer,
  p_provider text,
  p_action text,
  p_mode text,
  p_reason text
) returns jsonb
language sql
stable
set search_path = pg_catalog, public, private, pg_temp
as $$
  select jsonb_build_object(
    'sequence', p_sequence,
    'provider', p_provider,
    'action', p_action,
    'mode', p_mode,
    'reason', p_reason,
    'runtimeAvailable', exists(
      select 1
      from jsonb_array_elements(coalesce(p_registry->'providers','[]'::jsonb)) p,
           jsonb_array_elements(coalesce(p->'actions','[]'::jsonb)) a
      where p->>'provider'=p_provider
        and coalesce((p->>'canUseNow')::boolean,false)
        and a->>'name'=p_action
        and coalesce((a->>'available')::boolean,false)
    ),
    'authority', case when p_mode='write' then 'projectos' else 'governed_adapter' end,
    'verifiedComplete', false
  );
$$;

revoke all on function private.pandora_workflow_step_v1(jsonb,integer,text,text,text,text)
  from public, anon, authenticated;
grant execute on function private.pandora_workflow_step_v1(jsonb,integer,text,text,text,text)
  to service_role;

create or replace function private.pandora_multi_capability_workflow_v1(
  p_organization_id uuid,
  p_message text,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_registry jsonb;
  v_steps jsonb := '[]'::jsonb;
  v_step jsonb;
  v_provider_count integer := 0;
  v_available_count integer := 0;
  v_has_write boolean := false;
  v_project public.projectos_projects%rowtype;
  v_intake jsonb;
  v_idempotency text;
  v_blocked jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_multi_workflow_sign_in_required' using errcode='42501';
  end if;
  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then
    raise exception 'pandora_multi_workflow_owner_required' using errcode='42501';
  end if;
  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_multi_workflow_invalid_message' using errcode='22023';
  end if;

  if p_project_id is not null then
    select * into v_project
    from public.projectos_projects
    where organization_id=p_organization_id and id=p_project_id
    limit 1;
    if not found then
      raise exception 'pandora_multi_workflow_project_not_found' using errcode='22023';
    end if;
  end if;

  v_registry := public.pandora_plugin_runtime_registry_v4(p_organization_id);

  if v_message ~* '\m(posthog|analytics|funnel|retention|events)\M'
     and v_message ~* '\m(github|repository|repo|code|codebase|source)\M'
     and v_message ~* '\m(fix|repair|change|update|edit)\M'
     and v_message ~* '\m(vercel|deploy|deployment|publish|go live)\M' then

    v_step := private.pandora_workflow_step_v1(v_registry,1,'posthog','analytics.read','read','inspect product/runtime signals');
    v_steps := v_steps || jsonb_build_array(v_step);
    v_step := private.pandora_workflow_step_v1(v_registry,2,'github','repository.read','read','inspect the exact source before changing it');
    v_steps := v_steps || jsonb_build_array(v_step);
    v_step := private.pandora_workflow_step_v1(v_registry,3,'github','repository.write','write','apply the bounded source correction through ProjectOS');
    v_steps := v_steps || jsonb_build_array(v_step);
    v_step := private.pandora_workflow_step_v1(v_registry,4,'vercel','deployment.write','write','publish only after source and verification gates succeed');
    v_steps := v_steps || jsonb_build_array(v_step);
  else
    if v_message ~* '\m(github|repository|repo|pull request|codebase|source code)\M' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'github',
          case when v_message ~* '\m(fix|change|update|delete|create|write|merge|apply|repair|edit|rename|move)\M' then 'repository.write' else 'repository.read' end,
          case when v_message ~* '\m(fix|change|update|delete|create|write|merge|apply|repair|edit|rename|move)\M' then 'write' else 'read' end,
          'GitHub source step'
        )
      );
    end if;
    if v_message ~* '\m(supabase|postgres|postgresql|database|sql|backend database)\M' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'supabase',
          case when v_message ~* '\m(fix|change|update|delete|create|write|apply|configure|repair|edit)\M' then 'project.write' else 'project.read' end,
          case when v_message ~* '\m(fix|change|update|delete|create|write|apply|configure|repair|edit)\M' then 'write' else 'read' end,
          'Supabase project step'
        )
      );
    end if;
    if v_message ~* '\m(posthog|analytics|funnel|retention|events)\M' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'posthog',
          case when v_message ~* '\m(change|update|create|configure|write|edit)\M' then 'analytics.manage' else 'analytics.read' end,
          case when v_message ~* '\m(change|update|create|configure|write|edit)\M' then 'write' else 'read' end,
          'PostHog analytics step'
        )
      );
    end if;
    if v_message ~* '\m(vercel|deployment|deployments|hosting|publish|go live)\M' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'vercel',
          case when v_message ~* '\m(deploy|publish|change|update|create|configure|write|rollback|restore)\M' then 'deployment.write' else 'deployment.read' end,
          case when v_message ~* '\m(deploy|publish|change|update|create|configure|write|rollback|restore)\M' then 'write' else 'read' end,
          'Vercel deployment step'
        )
      );
    end if;
    if v_message ~* '(google[[:space:]]+drive|drive[[:space:]]+file|drive[[:space:]]+folder)' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'google_drive',
          case when v_message ~* '\m(change|update|delete|create|write|move|rename|upload|edit)\M' then 'files.write' else 'files.read' end,
          case when v_message ~* '\m(change|update|delete|create|write|move|rename|upload|edit)\M' then 'write' else 'read' end,
          'Google Drive step'
        )
      );
    end if;
    if v_message ~* '(google[[:space:]]+sheets?|spreadsheet|workbook)' then
      v_steps := v_steps || jsonb_build_array(
        private.pandora_workflow_step_v1(
          v_registry,jsonb_array_length(v_steps)+1,'google_sheets',
          case when v_message ~* '\m(change|update|delete|create|write|move|rename|edit)\M' then 'sheets.write' else 'sheets.read' end,
          case when v_message ~* '\m(change|update|delete|create|write|move|rename|edit)\M' then 'write' else 'read' end,
          'Google Sheets step'
        )
      );
    end if;
  end if;

  v_provider_count := jsonb_array_length(v_steps);
  if v_provider_count < 2 then
    return jsonb_build_object('handled',false,'reason','single_capability','stepCount',v_provider_count);
  end if;

  select count(*) filter (where coalesce((step->>'runtimeAvailable')::boolean,false)),
         bool_or(step->>'mode'='write')
    into v_available_count, v_has_write
  from jsonb_array_elements(v_steps) step;

  select coalesce(jsonb_agg(jsonb_build_object(
      'provider',step->>'provider',
      'action',step->>'action',
      'reason','runtime_authority_unavailable'
    )),'[]'::jsonb)
    into v_blocked
  from jsonb_array_elements(v_steps) step
  where not coalesce((step->>'runtimeAvailable')::boolean,false);

  v_idempotency := encode(extensions.digest(
    p_organization_id::text||':'||v_uid::text||':'||coalesce(p_project_id::text,'')||':multi_capability:'||lower(v_message),
    'sha256'
  ),'hex');

  v_intake := public.projectos_accept_intake(
    p_organization_id,
    v_uid,
    v_message,
    case when p_project_id is not null then v_project.project_key else null end,
    case when p_project_id is not null then v_project.name else null end,
    case when p_project_id is not null then v_project.repository else null end,
    'work','pandora_chat',v_idempotency
  );

  return jsonb_build_object(
    'handled',true,
    'workflowType','multi_capability',
    'executionMode','sequential_governed',
    'stepCount',v_provider_count,
    'availableStepCount',v_available_count,
    'allRuntimeAuthorityAvailable',v_available_count=v_provider_count,
    'containsMutation',coalesce(v_has_write,false),
    'steps',v_steps,
    'blockedBy',v_blocked,
    'intakeId',v_intake#>>'{intake,id}',
    'projectId',v_intake#>>'{project,id}',
    'projectRequired',false,
    'verifiedComplete',false,
    'completionRequires',jsonb_build_array('ordered_step_execution','authorization_for_each_consequential_step','provider_readback_per_step','cross_step_evidence','final_workflow_verification'),
    'observedAt',now()
  );
end;
$$;

revoke all on function private.pandora_multi_capability_workflow_v1(uuid,text,uuid) from public, anon, authenticated;
grant execute on function private.pandora_multi_capability_workflow_v1(uuid,text,uuid) to service_role;

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
  v_workflow jsonb;
  v_thread_id uuid := p_thread_id;
  v_reply text;
  v_blocked integer;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  v_workflow := private.pandora_multi_capability_workflow_v1(p_organization_id,v_message,p_project_id);
  if not coalesce((v_workflow->>'handled')::boolean,false) then
    return public.pandora_chat_universal_dispatch_v4(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;

  v_blocked := jsonb_array_length(coalesce(v_workflow->'blockedBy','[]'::jsonb));
  if v_blocked > 0 then
    v_reply := format('I mapped this into %s ordered capability steps, but %s step%s lack current runtime authority. Nothing has been executed. The workflow is recorded and will remain blocked until those capabilities are available.',v_workflow->>'stepCount',v_blocked,case when v_blocked=1 then '' else 's' end);
  else
    v_reply := format('I mapped this into %s ordered capability steps and recorded one governed workflow intake. Consequential steps still require ProjectOS authorization, one-time execution, provider readback, and evidence before I can call the workflow complete.',v_workflow->>'stepCount');
  end if;

  if v_thread_id is not null then
    if not exists(select 1 from public.pandora_intelligence_threads t where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active') then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
    values(p_organization_id,p_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
  values(v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb);
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
  values(v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,jsonb_build_object('intent','multi_capability_workflow','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'workflow',v_workflow),'pandora_projectos_router','multi-capability-v1');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;

  return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','multi_capability_workflow','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
    'handoff',jsonb_build_object('required',true,'request',v_message,'projectId',nullif(v_workflow->>'projectId',''),'source','projectos_intake','intakeId',v_workflow->>'intakeId'),
    'workflow',v_workflow);
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) to authenticated;
