-- Pandora governed mutations v1
-- Every supported mutation enters ProjectOS with deterministic idempotency and remains incomplete until execution readback/evidence.

create or replace function private.pandora_governed_mutation_request_v1(
  p_organization_id uuid,
  p_provider text,
  p_action text,
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
  v_provider text := lower(trim(coalesce(p_provider,'')));
  v_action text := lower(trim(coalesce(p_action,'')));
  v_message text := trim(coalesce(p_message,''));
  v_registry jsonb;
  v_available boolean := false;
  v_project public.projectos_projects%rowtype;
  v_idempotency text;
  v_intake jsonb;
begin
  if v_uid is null then raise exception 'pandora_mutation_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_mutation_owner_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_mutation_invalid_message' using errcode='22023'; end if;
  if not ((v_provider='github' and v_action='repository.write') or (v_provider='supabase' and v_action='project.write') or (v_provider='vercel' and v_action='deployment.write')) then
    return jsonb_build_object('ok',false,'provider',v_provider,'action',v_action,'reason','mutation_route_not_supported','authority','projectos','verifiedComplete',false,'observedAt',now());
  end if;

  v_registry := public.pandora_plugin_runtime_registry_v4(p_organization_id);
  select exists(
    select 1
    from jsonb_array_elements(coalesce(v_registry->'providers','[]'::jsonb)) p,
         jsonb_array_elements(coalesce(p->'actions','[]'::jsonb)) a
    where p->>'provider'=v_provider
      and coalesce((p->>'canUseNow')::boolean,false)
      and a->>'name'=v_action
      and coalesce((a->>'available')::boolean,false)
  ) into v_available;

  if not v_available then
    return jsonb_build_object('ok',false,'provider',v_provider,'action',v_action,'reason','runtime_authority_unavailable','authority','projectos','verifiedComplete',false,'observedAt',now());
  end if;

  if p_project_id is not null then
    select * into v_project from public.projectos_projects where organization_id=p_organization_id and id=p_project_id limit 1;
    if not found then raise exception 'pandora_mutation_project_not_found' using errcode='22023'; end if;
  end if;

  v_idempotency := encode(extensions.digest(
    p_organization_id::text||':'||v_uid::text||':'||coalesce(p_project_id::text,'')||':'||v_provider||':'||v_action||':'||lower(v_message),
    'sha256'),'hex');

  v_intake := public.projectos_accept_intake(
    p_organization_id,
    v_uid,
    v_message,
    case when p_project_id is not null then v_project.project_key else null end,
    case when p_project_id is not null then v_project.name else null end,
    case when p_project_id is not null then v_project.repository else null end,
    'work',
    'pandora_chat',
    v_idempotency
  );

  return jsonb_build_object(
    'ok',true,'provider',v_provider,'action',v_action,'authority','projectos',
    'idempotencyKey',v_idempotency,
    'intakeId',v_intake#>>'{intake,id}',
    'projectId',v_intake#>>'{project,id}',
    'status',v_intake#>>'{intake,status}',
    'verifiedComplete',false,
    'completionRequires',jsonb_build_array('plan','authorization_if_required','one_time_execution_claim','provider_readback','evidence'),
    'observedAt',now()
  );
end;
$$;

revoke all on function private.pandora_governed_mutation_request_v1(uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function private.pandora_governed_mutation_request_v1(uuid,text,text,text,uuid) to service_role;

create or replace function public.pandora_chat_universal_dispatch_v4(
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
  v_provider text;
  v_action text;
  v_mutating boolean;
  v_result jsonb;
  v_thread_id uuid := p_thread_id;
  v_reply text;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  v_mutating := v_message ~* '\m(fix|change|update|deploy|publish|delete|create|write|merge|apply|configure|reconnect|install|remove|pause|restore|repair|edit|rename|move|send)\M';
  if not v_mutating then return public.pandora_chat_universal_dispatch_v3(p_organization_id,p_message,p_thread_id,p_project_id); end if;

  if v_message ~* '\m(github|repository|repo|branch|commit|pull request|pull requests|codebase|source code)\M' then v_provider:='github';
  elsif v_message ~* '\m(supabase|postgres|postgresql|database|sql|database table|backend database)\M' then v_provider:='supabase';
  elsif v_message ~* '\m(vercel|deployment|deployments|hosting|publish|go live)\M' then v_provider:='vercel';
  elsif v_message ~* '\m(posthog|analytics|funnel|retention|events)\M' then v_provider:='posthog';
  elsif v_message ~* '(google[[:space:]]+drive|drive[[:space:]]+file|drive[[:space:]]+folder)' then v_provider:='google_drive';
  elsif v_message ~* '(google[[:space:]]+sheets?|spreadsheet|workbook)' then v_provider:='google_sheets';
  else return public.pandora_chat_universal_dispatch_v3(p_organization_id,p_message,p_thread_id,p_project_id); end if;

  v_action := case v_provider when 'github' then 'repository.write' when 'supabase' then 'project.write' when 'vercel' then 'deployment.write' when 'posthog' then 'analytics.manage' when 'google_drive' then 'files.write' when 'google_sheets' then 'sheets.write' else 'unknown' end;
  v_result := private.pandora_governed_mutation_request_v1(p_organization_id,v_provider,v_action,v_message,p_project_id);

  if coalesce((v_result->>'ok')::boolean,false) then
    v_reply := format('I routed this %s mutation into ProjectOS. It is not complete until authorization, one-time execution, provider readback, and evidence verification succeed.',initcap(replace(v_provider,'_',' ')));
  else
    v_reply := format('Pandora resolved this as %s %s, but current governed runtime authority is unavailable. No mutation was executed.',initcap(replace(v_provider,'_',' ')),v_action);
  end if;

  if v_thread_id is not null then
    if not exists(select 1 from public.pandora_intelligence_threads t where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active') then raise exception 'pandora_chat_thread_not_found' using errcode='22023'; end if;
  else
    insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
    values(p_organization_id,p_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
  values(v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb);
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
  values(v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
    jsonb_build_object('intent',case when v_provider='vercel' then 'publish' else 'change_project' end,'confidence',1,'needsClarification',false,'clarifyingQuestion',null,
      'route',jsonb_build_object('provider',v_provider,'action',v_action,'mode','write','projectRequired',false),'capabilityResult',v_result),
    'pandora_governed_adapter','mutation-v1');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;

  return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,
    'intent',case when v_provider='vercel' then 'publish' else 'change_project' end,'confidence',1,'needsClarification',false,'clarifyingQuestion',null,
    'handoff',case when coalesce((v_result->>'ok')::boolean,false) and nullif(v_result->>'projectId','') is not null then jsonb_build_object('required',true,'request',v_message,'projectId',v_result->>'projectId','source','projectos_intake','intakeId',v_result->>'intakeId') else null end,
    'capabilityResult',v_result);
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v4(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v4(uuid,text,uuid,uuid) to authenticated;
