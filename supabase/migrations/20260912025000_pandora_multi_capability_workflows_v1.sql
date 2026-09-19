-- Pandora multi-capability workflows v1
-- One user request may span multiple governed capabilities without collapsing reads and mutations into one unsafe action.

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
  v_parts text[];
  v_part text;
  v_provider text;
  v_action text;
  v_mode text;
  v_target jsonb;
  v_repo text;
  v_pr integer;
  v_project_ref text;
  v_vercel_project text;
  v_result jsonb;
  v_steps jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_failed boolean := false;
  v_write_count integer := 0;
  v_read_count integer := 0;
begin
  if v_uid is null then raise exception 'pandora_workflow_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_workflow_owner_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_workflow_invalid_message' using errcode='22023'; end if;

  -- Preserve user order. We intentionally require explicit clause boundaries for multi-step execution.
  v_parts := regexp_split_to_array(v_message, '(?i)[[:space:]]+(?:and[[:space:]]+then|then)[[:space:]]+|[;]');
  if coalesce(array_length(v_parts,1),0) < 2 then
    return jsonb_build_object('handled',false,'reason','single_or_unsegmented_request');
  end if;

  foreach v_part in array v_parts loop
    v_part := trim(v_part);
    if v_part='' then continue; end if;
    v_provider := null; v_action := null; v_mode := null; v_target := '{}'::jsonb; v_result := null;

    if v_part ~* '\m(github|repository|repo|pull request|pull requests|codebase|source code)\M' then v_provider := 'github';
    elsif v_part ~* '\m(supabase|postgres|postgresql|database|sql|backend database)\M' then v_provider := 'supabase';
    elsif v_part ~* '\m(vercel|deployment|deployments|hosting|publish|go live)\M' then v_provider := 'vercel';
    elsif v_part ~* '\m(posthog|analytics|funnel|retention|events)\M' then v_provider := 'posthog';
    elsif v_part ~* '(google[[:space:]]+drive|drive[[:space:]]+file|drive[[:space:]]+folder)' then v_provider := 'google_drive';
    elsif v_part ~* '(google[[:space:]]+sheets?|spreadsheet|workbook)' then v_provider := 'google_sheets';
    end if;

    if v_provider is null then
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'index',v_index,'clause',v_part,'status','needs_clarification','reason','provider_not_resolved','verifiedComplete',false));
      v_failed := true; v_index := v_index + 1; continue;
    end if;

    if v_part ~* '\m(fix|change|update|deploy|publish|delete|create|write|merge|apply|configure|reconnect|install|remove|pause|restore|repair|edit|rename|move|send)\M' then
      v_mode := 'write';
      v_action := case v_provider
        when 'github' then 'repository.write'
        when 'supabase' then 'project.write'
        when 'vercel' then 'deployment.write'
        when 'posthog' then 'analytics.manage'
        when 'google_drive' then 'files.write'
        when 'google_sheets' then 'sheets.write'
        else 'unknown' end;
      v_result := private.pandora_governed_mutation_request_v1(p_organization_id,v_provider,v_action,v_part,p_project_id);
      v_write_count := v_write_count + 1;
    else
      v_mode := 'read';
      if v_provider='github' then
        v_repo := substring(v_part from '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
        if v_repo is null and p_project_id is not null then
          select repository into v_repo from public.projectos_projects where id=p_project_id and organization_id=p_organization_id;
        end if;
        if v_repo is null and v_part ~* '\mpandora' then v_repo := 'pandora-rvw-314296438-20260820/pandoras-box'; end if;
        begin v_pr := nullif(substring(v_part from '#([0-9]{1,9})'),'')::integer; exception when others then v_pr := null; end;
        v_action := case when v_pr is not null and v_part ~* '\m(pr|pull request)\M' then 'pull_request.read' else 'repository.read' end;
        if v_repo is not null then v_target := jsonb_build_object('repository',v_repo,'pullRequest',v_pr); end if;
      elsif v_provider='supabase' then
        v_action := 'project.read'; v_project_ref := substring(lower(v_part) from '([a-z]{20})');
        if v_project_ref is null and p_project_id is not null then
          select h.details->>'projectRef' into v_project_ref from public.projectos_integration_health h
          where h.organization_id=p_organization_id and h.project_id=p_project_id and h.provider='supabase' order by h.updated_at desc limit 1;
        end if;
        if v_project_ref is null and v_part ~* '\mpandora' then v_project_ref := 'jcyqixttuebxqqfkjonq'; end if;
        if v_project_ref is not null then v_target := jsonb_build_object('projectRef',v_project_ref); end if;
      elsif v_provider='vercel' then
        v_action := 'project.read';
        if p_project_id is not null then select e.provider_project_id into v_vercel_project from public.pandora_runtime_environments e
          where e.organization_id=p_organization_id and e.project_id=p_project_id and e.provider='vercel'
          order by case e.environment when 'production' then 0 when 'preview' then 1 else 2 end,e.updated_at desc limit 1; end if;
        if v_vercel_project is null then select d.provider_project_id into v_vercel_project from public.pandora_project_domains d join public.projectos_projects p on p.id=d.project_id
          where p.organization_id=p_organization_id and d.provider='vercel' and (v_part ilike '%'||d.provider_project_id||'%' or v_part ilike '%'||p.name||'%')
          order by d.updated_at desc nulls last limit 1; end if;
        if v_vercel_project is not null then v_target := jsonb_build_object('project',v_vercel_project); end if;
      else
        v_action := case v_provider when 'posthog' then 'analytics.read' when 'google_drive' then 'files.read' when 'google_sheets' then 'sheets.read' else 'unknown' end;
      end if;

      if v_provider not in ('github','supabase','vercel') then
        v_result := jsonb_build_object('ok',false,'provider',v_provider,'action',v_action,'reason','runtime_authority_unavailable','verifiedComplete',false,'authority','governed_adapter');
      elsif v_target='{}'::jsonb then
        v_result := jsonb_build_object('ok',false,'provider',v_provider,'action',v_action,'reason','target_not_resolved','verifiedComplete',false,'authority','governed_adapter');
      else
        v_result := private.pandora_governed_provider_read_v1(p_organization_id,v_provider,v_action,v_target);
      end if;
      v_read_count := v_read_count + 1;
    end if;

    if not coalesce((v_result->>'ok')::boolean,false) then v_failed := true; end if;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object(
      'index',v_index,'clause',v_part,'provider',v_provider,'action',v_action,'mode',v_mode,
      'status',case when coalesce((v_result->>'ok')::boolean,false) then case when v_mode='write' then 'routed_to_projectos' else 'verified_read' end else 'blocked' end,
      'result',v_result,'verifiedComplete',case when v_mode='read' then coalesce((v_result->>'ok')::boolean,false) else false end));
    v_index := v_index + 1;
  end loop;

  if v_index < 2 then return jsonb_build_object('handled',false,'reason','less_than_two_resolved_steps'); end if;
  return jsonb_build_object(
    'handled',true,'workflow',true,'status',case when v_failed then 'blocked_or_partial' else case when v_write_count>0 then 'awaiting_governed_execution' else 'verified' end end,
    'stepCount',v_index,'readCount',v_read_count,'writeCount',v_write_count,'steps',v_steps,
    'verifiedComplete',case when not v_failed and v_write_count=0 then true else false end,
    'completionRequires',case when v_write_count>0 then jsonb_build_array('all_projectos_plans_authorized','one_time_execution_claims','provider_readbacks','evidence') else '[]'::jsonb end,
    'observedAt',now());
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
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_chat_invalid_message' using errcode='22023'; end if;

  v_workflow := private.pandora_multi_capability_workflow_v1(p_organization_id,v_message,p_project_id);
  if not coalesce((v_workflow->>'handled')::boolean,false) then
    return public.pandora_chat_universal_dispatch_v4(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;

  v_reply := case v_workflow->>'status'
    when 'verified' then format('Pandora completed %s governed read steps and verified each provider result.',v_workflow->>'stepCount')
    when 'awaiting_governed_execution' then format('Pandora resolved %s ordered capability steps. Safe reads are verified; consequential steps are routed through ProjectOS and are not complete until provider readback and evidence succeed.',v_workflow->>'stepCount')
    else format('Pandora resolved %s ordered capability steps, but at least one step is blocked or unresolved. No blocked step was treated as complete.',v_workflow->>'stepCount') end;

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
    jsonb_build_object('intent','multi_capability_workflow','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'workflow',v_workflow),
    'pandora_workflow_router','workflow-v1');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;
  return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','multi_capability_workflow','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'workflow',v_workflow);
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v5(uuid,text,uuid,uuid) to authenticated;
