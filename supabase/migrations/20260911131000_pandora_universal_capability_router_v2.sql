-- Pandora universal capability router v2
-- Deterministically resolves natural-language capability intent before model chat.
-- Multi-capability requests fail closed into clarification until chained workflows land.

create or replace function public.pandora_chat_universal_dispatch_v2(
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
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_provider text;
  v_action text;
  v_mode text;
  v_mutating boolean;
  v_candidates text[] := array[]::text[];
  v_candidate_count integer := 0;
  v_routed_message text;
  v_result jsonb;
  v_thread_id uuid := p_thread_id;
  v_reply text;
  v_registry jsonb;
  v_intake jsonb;
  v_idempotency text;
  v_project public.projectos_projects%rowtype;
  v_project_key text;
  v_project_name text;
  v_repository text;
  v_vercel jsonb;
  v_vercel_body jsonb;
  v_production jsonb;
  v_facts jsonb;
  v_http_status integer;
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

  if v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;

  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  if v_message ~* '\m(connection|connections|connector|connectors|capability|capabilities|plugin|plugins|available tools|tools)\M'
     or v_message ~* '(what[[:space:]]+can[[:space:]]+you[[:space:]]+do|what[[:space:]]+are[[:space:]]+you[[:space:]]+able[[:space:]]+to[[:space:]]+do|what[[:space:]]+can[[:space:]]+pandora[[:space:]]+do)' then
    return public.pandora_chat_universal_dispatch_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  if v_message ~* '\m(github|repository|repo|branch|commit|pull request|pull requests|codebase|source code)\M'
     or v_message ~* '(check|inspect|review|open|read|show).*(code|repo|repository|pull request|branch)' then
    v_candidates := array_append(v_candidates,'github');
  end if;

  if v_message ~* '\m(supabase|postgres|postgresql|database|sql|database table|backend database)\M'
     or v_message ~* '(check|inspect|query|read|show|update|change).*(database|table|sql|postgres)' then
    v_candidates := array_append(v_candidates,'supabase');
  end if;

  if v_message ~* '\m(vercel|deployment|deployments|hosting)\M'
     or v_message ~* '(deploy|publish|go live|production domain|custom domain|live site)' then
    v_candidates := array_append(v_candidates,'vercel');
  end if;

  if v_message ~* '\m(posthog|analytics|funnel|funnels|retention|session replay|product usage|events)\M'
     or v_message ~* '(check|inspect|show|query|analyze|analyse).*(analytics|events|funnel|retention|usage)' then
    v_candidates := array_append(v_candidates,'posthog');
  end if;

  if v_message ~* '(google[[:space:]]+drive|drive[[:space:]]+file|drive[[:space:]]+folder|shared[[:space:]]+drive)'
     or v_message ~* '(find|open|read|search|update|change).*(document|doc|file|folder).*(drive)' then
    v_candidates := array_append(v_candidates,'google_drive');
  end if;

  if v_message ~* '(google[[:space:]]+sheets?|spreadsheet|workbook)'
     or v_message ~* '(open|read|search|update|change|edit).*(sheet|spreadsheet|workbook)' then
    v_candidates := array_append(v_candidates,'google_sheets');
  end if;

  select count(distinct x) into v_candidate_count from unnest(v_candidates) x;

  if v_candidate_count = 0 then
    return jsonb_build_object('handled',false);
  end if;

  if v_candidate_count > 1 then
    select array_agg(distinct x order by x) into v_candidates from unnest(v_candidates) x;
    v_reply := format(
      'I found more than one possible capability for this request: %s. Tell me which outcome should happen first. I will not guess or silently chain provider actions.',
      array_to_string(v_candidates, ', ')
    );

    if v_thread_id is not null then
      if not exists (
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
        p_organization_id,p_project_id,v_uid,
        left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
        'active',now()
      ) returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,attachment_manifest
    ) values (
      v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
    );

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values (
      v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','clarify_capability',
        'confidence',1,
        'needsClarification',true,
        'clarifyingQuestion',v_reply,
        'route',jsonb_build_object(
          'candidateProviders',to_jsonb(v_candidates),
          'mode','multi_capability',
          'projectRequired',false
        )
      ),
      'pandora_capability_router','deterministic-v2'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now()
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,
      'threadId',v_thread_id,
      'reply',v_reply,
      'intent','clarify_capability',
      'confidence',1,
      'needsClarification',true,
      'clarifyingQuestion',v_reply,
      'handoff',null,
      'capabilityResult',jsonb_build_object(
        'authority','capability_router',
        'candidateProviders',to_jsonb(v_candidates),
        'projectRequired',false
      )
    );
  end if;

  select min(x) into v_provider from unnest(v_candidates) x;

  v_mutating := v_message ~* '\m(fix|change|update|deploy|publish|delete|create|write|merge|apply|configure|reconnect|install|remove|pause|restore|repair|edit|rename|move|send)\M';
  v_mode := case when v_mutating then 'write' else 'read' end;

  v_action := case v_provider
    when 'github' then case
      when not v_mutating and v_message ~* '\m(pull request|pull requests|pr)\M' then 'pull_request.read'
      when v_mutating then 'repository.write'
      else 'repository.read'
    end
    when 'supabase' then case when v_mutating then 'project.write' else 'project.read' end
    when 'vercel' then case when v_mutating then 'deployment.write' else 'deployment.read' end
    when 'posthog' then case when v_mutating then 'analytics.manage' else 'analytics.query' end
    when 'google_drive' then case when v_mutating then 'files.write' else 'files.read' end
    when 'google_sheets' then case when v_mutating then 'sheets.write' else 'sheets.read' end
    else 'unknown'
  end;

  if v_provider <> 'vercel' then
    v_routed_message := case v_provider
      when 'github' then 'GitHub'
      when 'supabase' then 'Supabase'
      when 'posthog' then 'PostHog'
      when 'google_drive' then 'Google Drive'
      when 'google_sheets' then 'Google Sheets'
      else initcap(replace(v_provider,'_',' '))
    end || ': ' || v_message;

    v_result := public.pandora_chat_capability_dispatch_v1(
      p_organization_id,
      v_routed_message,
      p_thread_id,
      p_project_id
    );

    if coalesce(v_result->>'handled','false')='true' then
      v_thread_id := nullif(v_result->>'threadId','')::uuid;

      if v_thread_id is not null then
        with latest_user as (
          select id
          from public.pandora_intelligence_messages
          where thread_id=v_thread_id
            and organization_id=p_organization_id
            and author_role='user'
            and content=v_routed_message
          order by created_at desc, id desc
          limit 1
        )
        update public.pandora_intelligence_messages m
        set content=v_message
        from latest_user l
        where m.id=l.id;
      end if;

      v_result := jsonb_set(
        v_result,
        '{capabilityResult,router}',
        jsonb_build_object(
          'provider',v_provider,
          'action',v_action,
          'mode',v_mode,
          'inferred',true,
          'projectRequired',false
        ),
        true
      );

      if v_result #>> '{handoff,required}' = 'true' then
        v_result := jsonb_set(v_result,'{handoff,request}',to_jsonb(v_message),true);
      end if;

      return v_result;
    end if;
  end if;

  v_registry := public.pandora_plugin_runtime_registry_v4(p_organization_id);

  if v_provider='vercel' and not v_mutating then
    v_vercel := private.pandora_exact_vercel_api_20260825(
      'GET',
      '/v9/projects/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
      null
    );
    v_http_status := nullif(v_vercel->>'status','')::integer;

    if v_http_status = 200 then
      v_vercel_body := coalesce(v_vercel->'body','{}'::jsonb);
      v_production := coalesce(v_vercel_body #> '{targets,production}','{}'::jsonb);
      v_facts := jsonb_strip_nulls(jsonb_build_object(
        'projectId',v_vercel_body->>'id',
        'projectName',v_vercel_body->>'name',
        'deploymentId',v_production->>'id',
        'deploymentUrl',v_production->>'url',
        'readyState',v_production->>'readyState',
        'readySubstate',v_production->>'readySubstate',
        'sourceSha',v_production #>> '{meta,githubCommitSha}'
      ));
      v_reply := format(
        'Vercel verified read: %s production deployment %s is %s%s%s.',
        coalesce(v_vercel_body->>'name','mcpmaster'),
        coalesce(v_production->>'id','unknown'),
        coalesce(v_production->>'readyState','unknown'),
        case when nullif(v_production->>'readySubstate','') is null then '' else '/'||v_production->>'readySubstate' end,
        case when nullif(v_production #>> '{meta,githubCommitSha}','') is null then '' else ' at source '||(v_production #>> '{meta,githubCommitSha}') end
      );
    else
      v_facts := '{}'::jsonb;
      v_reply := 'Vercel live read could not be verified from the bounded provider adapter. I will not invent deployment state.';
    end if;

    if v_thread_id is not null then
      if not exists (
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
        p_organization_id,p_project_id,v_uid,
        left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
        'active',now()
      ) returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,attachment_manifest
    ) values (
      v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
    );

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values (
      v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','inspect_provider',
        'confidence',1,
        'needsClarification',false,
        'clarifyingQuestion',null,
        'route',jsonb_build_object(
          'provider','vercel','action','deployment.read','mode','read','projectRequired',false
        ),
        'capabilityResult',jsonb_build_object(
          'ok',v_http_status=200,
          'authority','governed_adapter',
          'provider','vercel',
          'action','deployment.read',
          'mode','read',
          'httpStatus',v_http_status,
          'facts',v_facts,
          'router',jsonb_build_object(
            'provider','vercel','action','deployment.read','mode','read','inferred',true,'projectRequired',false
          )
        )
      ),
      'pandora_capability_router','deterministic-v2'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now()
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,
      'threadId',v_thread_id,
      'reply',v_reply,
      'intent','inspect_provider',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'handoff',null,
      'capabilityResult',jsonb_build_object(
        'ok',v_http_status=200,
        'authority','governed_adapter',
        'provider','vercel',
        'action','deployment.read',
        'mode','read',
        'httpStatus',v_http_status,
        'facts',v_facts,
        'router',jsonb_build_object(
          'provider','vercel','action','deployment.read','mode','read','inferred',true,'projectRequired',false
        )
      )
    );
  end if;

  if v_provider='vercel' and v_mutating then
    if p_project_id is not null then
      select * into v_project
      from public.projectos_projects
      where organization_id=p_organization_id and id=p_project_id
      limit 1;
      if not found then
        raise exception 'pandora_chat_project_not_found' using errcode='22023';
      end if;
      v_project_key := v_project.project_key;
      v_project_name := v_project.name;
      v_repository := v_project.repository;
    end if;

    v_idempotency := encode(
      extensions.digest(
        p_organization_id::text || ':' || coalesce(p_project_id::text,'') || ':vercel:' || v_message,
        'sha256'
      ),
      'hex'
    );

    v_intake := public.projectos_accept_intake(
      p_organization_id,
      v_uid,
      v_message,
      v_project_key,
      v_project_name,
      v_repository,
      'work',
      'pandora_chat',
      v_idempotency
    );

    v_reply := 'I resolved this request to Vercel deployment.write and sent it to ProjectOS for governed execution. It is not complete until provider readback and verification succeed.';

    if v_thread_id is not null then
      if not exists (
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
        p_organization_id,p_project_id,v_uid,
        left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
        'active',now()
      ) returning id into v_thread_id;
    end if;

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,attachment_manifest
    ) values (
      v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
    );

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values (
      v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','publish',
        'confidence',1,
        'needsClarification',false,
        'clarifyingQuestion',null,
        'route',jsonb_build_object(
          'provider','vercel',
          'action','deployment.write',
          'mode','write',
          'projectRequired',false
        ),
        'capabilityResult',jsonb_build_object(
          'provider','vercel',
          'authority','projectos',
          'intakeId',v_intake #>> '{intake,id}',
          'projectId',v_intake #>> '{project,id}',
          'status',v_intake #>> '{intake,status}'
        )
      ),
      'pandora_capability_router','deterministic-v2'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now()
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,
      'threadId',v_thread_id,
      'reply',v_reply,
      'intent','publish',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'handoff',case
        when nullif(v_intake #>> '{project,id}','') is not null then
          jsonb_build_object(
            'required',true,
            'request',v_message,
            'projectId',v_intake #>> '{project,id}',
            'source','projectos_intake',
            'intakeId',v_intake #>> '{intake,id}'
          )
        else null
      end,
      'capabilityResult',jsonb_build_object(
        'provider','vercel',
        'authority','projectos',
        'action','deployment.write',
        'mode','write',
        'intakeId',v_intake #>> '{intake,id}',
        'projectId',v_intake #>> '{project,id}',
        'status',v_intake #>> '{intake,status}',
        'router',jsonb_build_object(
          'provider','vercel',
          'action','deployment.write',
          'mode','write',
          'inferred',true,
          'projectRequired',false
        )
      )
    );
  end if;

  v_reply := format(
    'I resolved this request to %s %s. Pandora does not yet expose a bounded live-read adapter for this route, so I will not invent provider results.',
    initcap(replace(v_provider,'_',' ')),
    v_action
  );

  if v_thread_id is not null then
    if not exists (
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
      p_organization_id,p_project_id,v_uid,
      left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
      'active',now()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values (
    v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values (
    v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent','inspect_provider',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'route',jsonb_build_object(
        'provider',v_provider,
        'action',v_action,
        'mode',v_mode,
        'projectRequired',false
      ),
      'capabilityResult',jsonb_build_object(
        'authority','capability_router',
        'provider',v_provider,
        'action',v_action,
        'mode',v_mode,
        'registry',v_registry
      )
    ),
    'pandora_capability_router','deterministic-v2'
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(),updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent','inspect_provider',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'handoff',null,
    'capabilityResult',jsonb_build_object(
      'authority','capability_router',
      'provider',v_provider,
      'action',v_action,
      'mode',v_mode,
      'registry',v_registry,
      'router',jsonb_build_object(
        'provider',v_provider,
        'action',v_action,
        'mode',v_mode,
        'inferred',true,
        'projectRequired',false
      )
    )
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v2(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v2(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_universal_dispatch_v2(uuid,text,uuid,uuid)
is 'Deterministic universal capability router. Resolves natural-language provider/action intent before model chat, asks instead of guessing on multi-provider ambiguity, preserves ProjectOS governance, and keeps Projects optional.';
