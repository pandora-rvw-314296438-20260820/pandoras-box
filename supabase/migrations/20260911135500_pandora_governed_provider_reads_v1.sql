-- Pandora governed bounded provider reads v1
-- Centralizes live provider reads behind one fail-closed adapter boundary.

create or replace function private.pandora_governed_provider_read_v1(
  p_organization_id uuid,
  p_provider text,
  p_action text,
  p_target jsonb default '{}'::jsonb
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
  v_repo text;
  v_pr integer;
  v_project_ref text;
  v_token text;
  v_response jsonb;
  v_status integer;
  v_body jsonb;
  v_http extensions.http_response;
  v_vercel_project text;
  v_team text;
begin
  if v_uid is null then raise exception 'pandora_governed_read_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_governed_read_owner_required' using errcode='42501'; end if;
  if v_provider not in ('github','supabase','vercel') then raise exception 'pandora_governed_read_provider_not_supported' using errcode='22023'; end if;
  if v_action not in ('repository.read','pull_request.read','project.read','deployment.read') then raise exception 'pandora_governed_read_action_not_supported' using errcode='22023'; end if;

  if v_provider='github' then
    if v_action not in ('repository.read','pull_request.read') then raise exception 'pandora_governed_read_action_provider_mismatch' using errcode='22023'; end if;
    v_repo := nullif(p_target->>'repository','');
    if v_repo is null then raise exception 'pandora_governed_read_repository_required' using errcode='22023'; end if;
    if not (v_repo in ('pandora-rvw-314296438-20260820/pandoras-box','pandora-rvw-314296438-20260820/pandoras-box-memory')
      or exists (select 1 from public.projectos_projects p where p.organization_id=p_organization_id and p.repository=v_repo)) then
      raise exception 'pandora_governed_read_repository_not_allowlisted' using errcode='42501';
    end if;
    if v_action='pull_request.read' then
      begin v_pr := (p_target->>'pullRequest')::integer; exception when others then v_pr := null; end;
      if v_pr is null or v_pr<1 then raise exception 'pandora_governed_read_pull_request_required' using errcode='22023'; end if;
      v_response := private.pandora_integration_github_api_20260825('GET','/repos/'||v_repo||'/pulls/'||v_pr::text,null);
    else
      v_response := private.pandora_integration_github_api_20260825('GET','/repos/'||v_repo,null);
    end if;
    v_status := coalesce((v_response->>'status')::integer,0); v_body := v_response->'body';
    if v_status<200 or v_status>=300 or v_body is null then
      return jsonb_build_object('ok',false,'provider','github','action',v_action,'httpStatus',v_status,'target',p_target,'authority','governed_adapter','observedAt',now());
    end if;
    if v_action='pull_request.read' then
      return jsonb_build_object('ok',true,'provider','github','action',v_action,'httpStatus',v_status,'authority','governed_adapter','observedAt',now(),
        'facts',jsonb_build_object('repository',v_repo,'pullRequest',v_pr,'state',v_body->>'state','merged',coalesce((v_body->>'merged')::boolean,false),
          'headSha',v_body#>>'{head,sha}','base',v_body#>>'{base,ref}','updatedAt',v_body->>'updated_at'));
    end if;
    return jsonb_build_object('ok',true,'provider','github','action',v_action,'httpStatus',v_status,'authority','governed_adapter','observedAt',now(),
      'facts',jsonb_build_object('repository',coalesce(v_body->>'full_name',v_repo),'defaultBranch',v_body->>'default_branch','pushedAt',v_body->>'pushed_at',
        'openIssues',v_body->'open_issues_count','visibility',v_body->>'visibility','archived',coalesce((v_body->>'archived')::boolean,false)));
  end if;

  if v_provider='supabase' then
    if v_action<>'project.read' then raise exception 'pandora_governed_read_action_provider_mismatch' using errcode='22023'; end if;
    v_project_ref := nullif(lower(p_target->>'projectRef'),'');
    if v_project_ref is null or v_project_ref !~ '^[a-z]{20}$' then raise exception 'pandora_governed_read_supabase_project_required' using errcode='22023'; end if;
    if v_project_ref not in ('jcyqixttuebxqqfkjonq','ivmvufhcsezyhczzondn') and not exists (
      select 1 from public.projectos_integration_health h where h.organization_id=p_organization_id and h.provider='supabase' and h.details->>'projectRef'=v_project_ref
    ) then raise exception 'pandora_governed_read_supabase_project_not_allowlisted' using errcode='42501'; end if;
    select decrypted_secret into v_token from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','Supabase_access') and nullif(trim(decrypted_secret),'') is not null
    order by case when name='mcpmaster_supabase_account_1_pat' then 0 else 1 end limit 1;
    if nullif(trim(v_token),'') is null then return jsonb_build_object('ok',false,'provider','supabase','action',v_action,'reason','needs_connection','authority','governed_adapter','observedAt',now()); end if;
    perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000'); perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
    select * into v_http from extensions.http(('GET'::extensions.http_method,('https://api.supabase.com/v1/projects/'||v_project_ref)::varchar,
      array[extensions.http_header('authorization','Bearer '||v_token),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Governed-Read/1.0')]::extensions.http_header[],null::varchar,null::varchar)::extensions.http_request);
    begin v_body := nullif(v_http.content,'')::jsonb; exception when others then v_body := null; end;
    if v_http.status<200 or v_http.status>=300 or v_body is null then
      return jsonb_build_object('ok',false,'provider','supabase','action',v_action,'httpStatus',v_http.status,'projectRef',v_project_ref,'authority','governed_adapter','observedAt',now());
    end if;
    return jsonb_build_object('ok',true,'provider','supabase','action',v_action,'httpStatus',v_http.status,'authority','governed_adapter','observedAt',now(),
      'facts',jsonb_build_object('projectRef',v_project_ref,'name',v_body->>'name','status',v_body->>'status','region',v_body->>'region','organizationId',v_body->>'organization_id'));
  end if;

  if v_action not in ('project.read','deployment.read') then raise exception 'pandora_governed_read_action_provider_mismatch' using errcode='22023'; end if;
  v_vercel_project := nullif(p_target->>'project','');
  if v_vercel_project is null then raise exception 'pandora_governed_read_vercel_project_required' using errcode='22023'; end if;
  if not exists (select 1 from public.pandora_runtime_environments e where e.organization_id=p_organization_id and e.provider='vercel' and e.provider_project_id=v_vercel_project)
     and not exists (select 1 from public.pandora_project_domains d join public.projectos_projects p on p.id=d.project_id
       where p.organization_id=p_organization_id and d.provider='vercel' and d.provider_project_id=v_vercel_project) then
    raise exception 'pandora_governed_read_vercel_project_not_allowlisted' using errcode='42501';
  end if;
  select config_value into v_team from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true limit 1;
  if nullif(v_team,'') is null then return jsonb_build_object('ok',false,'provider','vercel','action',v_action,'reason','provider_config_missing','authority','governed_adapter','observedAt',now()); end if;
  v_response := private.pandora_worker_f_vercel_api_20260829('GET','/v9/projects/'||v_vercel_project||'?teamId='||v_team,null);
  v_status := coalesce((v_response->>'status')::integer,0); v_body := v_response->'body';
  if v_status<200 or v_status>=300 or v_body is null then return jsonb_build_object('ok',false,'provider','vercel','action',v_action,'httpStatus',v_status,'project',v_vercel_project,'authority','governed_adapter','observedAt',now()); end if;
  return jsonb_build_object('ok',true,'provider','vercel','action',v_action,'httpStatus',v_status,'authority','governed_adapter','observedAt',now(),
    'facts',jsonb_build_object('project',coalesce(v_body->>'name',v_vercel_project),'id',v_body->>'id','framework',v_body->>'framework','updatedAt',v_body->>'updatedAt'));
end;
$$;

revoke all on function private.pandora_governed_provider_read_v1(uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function private.pandora_governed_provider_read_v1(uuid,text,text,jsonb) to service_role;

create or replace function public.pandora_chat_universal_dispatch_v3(
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
  v_uid uuid := auth.uid(); v_message text := trim(coalesce(p_message,'')); v_provider text; v_action text;
  v_target jsonb := '{}'::jsonb; v_repo text; v_pr integer; v_project_ref text; v_vercel_project text;
  v_read jsonb; v_facts jsonb; v_reply text; v_thread_id uuid := p_thread_id;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;
  if v_message ~* '\m(fix|change|update|deploy|publish|delete|create|write|merge|apply|configure|reconnect|install|remove|pause|restore|repair|edit|rename|move|send)\M' then
    return public.pandora_chat_universal_dispatch_v2(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;
  if v_message ~* '\m(github|repository|repo|pull request|pull requests|codebase|source code)\M' then v_provider := 'github';
  elsif v_message ~* '\m(supabase|postgres|postgresql|database|sql|backend database)\M' then v_provider := 'supabase';
  elsif v_message ~* '\m(vercel|deployment|deployments|hosting)\M' then v_provider := 'vercel';
  else return public.pandora_chat_universal_dispatch_v2(p_organization_id,p_message,p_thread_id,p_project_id); end if;

  if v_provider='github' then
    v_repo := substring(v_message from '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
    if v_repo is null and p_project_id is not null then select repository into v_repo from public.projectos_projects where id=p_project_id and organization_id=p_organization_id; end if;
    if v_repo is null and v_message ~* '\mpandora' then v_repo := 'pandora-rvw-314296438-20260820/pandoras-box'; end if;
    begin v_pr := nullif(substring(v_message from '#([0-9]{1,9})'),'')::integer; exception when others then v_pr := null; end;
    v_action := case when v_pr is not null and v_message ~* '\m(pr|pull request)\M' then 'pull_request.read' else 'repository.read' end;
    if v_repo is null then return public.pandora_chat_universal_dispatch_v2(p_organization_id,p_message,p_thread_id,p_project_id); end if;
    v_target := jsonb_build_object('repository',v_repo,'pullRequest',v_pr);
  elsif v_provider='supabase' then
    v_action := 'project.read'; v_project_ref := substring(lower(v_message) from '([a-z]{20})');
    if v_project_ref is null and p_project_id is not null then select h.details->>'projectRef' into v_project_ref from public.projectos_integration_health h
      where h.organization_id=p_organization_id and h.project_id=p_project_id and h.provider='supabase' order by h.updated_at desc limit 1; end if;
    if v_project_ref is null and v_message ~* '\mpandora' then v_project_ref := 'jcyqixttuebxqqfkjonq'; end if;
    if v_project_ref is null then return public.pandora_chat_universal_dispatch_v2(p_organization_id,p_message,p_thread_id,p_project_id); end if;
    v_target := jsonb_build_object('projectRef',v_project_ref);
  else
    v_action := 'project.read';
    if p_project_id is not null then select e.provider_project_id into v_vercel_project from public.pandora_runtime_environments e
      where e.organization_id=p_organization_id and e.project_id=p_project_id and e.provider='vercel'
      order by case e.environment when 'production' then 0 when 'preview' then 1 else 2 end,e.updated_at desc limit 1; end if;
    if v_vercel_project is null then select d.provider_project_id into v_vercel_project from public.pandora_project_domains d join public.projectos_projects p on p.id=d.project_id
      where p.organization_id=p_organization_id and d.provider='vercel' and (v_message ilike '%'||d.provider_project_id||'%' or v_message ilike '%'||p.name||'%')
      order by d.updated_at desc nulls last limit 1; end if;
    if v_vercel_project is null then return public.pandora_chat_universal_dispatch_v2(p_organization_id,p_message,p_thread_id,p_project_id); end if;
    v_target := jsonb_build_object('project',v_vercel_project);
  end if;

  v_read := private.pandora_governed_provider_read_v1(p_organization_id,v_provider,v_action,v_target); v_facts := coalesce(v_read->'facts','{}'::jsonb);
  if coalesce((v_read->>'ok')::boolean,false) then
    v_reply := case v_provider
      when 'github' then case when v_action='pull_request.read' then format('GitHub verified read: PR #%s in %s is %s%s. Head %s targets %s. Last updated %s.',
        coalesce(v_facts->>'pullRequest','?'),coalesce(v_facts->>'repository','unknown'),coalesce(v_facts->>'state','unknown'),case when coalesce((v_facts->>'merged')::boolean,false) then ' and merged' else '' end,
        coalesce(v_facts->>'headSha','unknown'),coalesce(v_facts->>'base','unknown'),coalesce(v_facts->>'updatedAt','unknown'))
      else format('GitHub verified read: %s uses %s as default branch; pushed %s; visibility %s.',coalesce(v_facts->>'repository','unknown'),coalesce(v_facts->>'defaultBranch','unknown'),coalesce(v_facts->>'pushedAt','unknown'),coalesce(v_facts->>'visibility','unknown')) end
      when 'supabase' then format('Supabase verified read: %s (%s) is %s in %s.',coalesce(v_facts->>'name','unknown'),coalesce(v_facts->>'projectRef','unknown'),coalesce(v_facts->>'status','unknown'),coalesce(v_facts->>'region','unknown'))
      else format('Vercel verified read: project %s (%s), framework %s.',coalesce(v_facts->>'project','unknown'),coalesce(v_facts->>'id','unknown'),coalesce(v_facts->>'framework','unknown')) end;
  else v_reply := format('%s provider read could not be verified. Pandora will not substitute cached or invented state.',initcap(v_provider)); end if;

  if v_thread_id is not null then
    if not exists (select 1 from public.pandora_intelligence_threads t where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active') then raise exception 'pandora_chat_thread_not_found' using errcode='22023'; end if;
  else
    insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
    values(p_organization_id,p_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()) returning id into v_thread_id;
  end if;
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
    values(v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb);
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
    values(v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object('intent','inspect_project','confidence',1,'needsClarification',false,'clarifyingQuestion',null,
        'route',jsonb_build_object('provider',v_provider,'action',v_action,'mode','read','projectRequired',false),'capabilityResult',v_read),
      'pandora_governed_adapter','bounded-read-v1');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;
  return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','inspect_project','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'handoff',null,'capabilityResult',v_read);
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v3(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v3(uuid,text,uuid,uuid) to authenticated;
