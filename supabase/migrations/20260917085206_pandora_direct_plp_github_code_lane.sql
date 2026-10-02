do $$
begin
  if to_regprocedure('public.pandora_chat_universal_dispatch_v9_legacy_20260917(uuid,text,uuid,uuid)') is null then
    alter function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
      rename to pandora_chat_universal_dispatch_v9_legacy_20260917;
  end if;
end $$;

create or replace function private.pandora_direct_plp_code_edit_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','auth','extensions','pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_thread_id uuid := p_thread_id;
  v_message text := trim(coalesce(p_message,''));
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/plp';
  v_env jsonb;
  v_body jsonb;
  v_ref jsonb;
  v_head text;
  v_commit jsonb;
  v_tree_sha text;
  v_tree jsonb;
  v_candidates jsonb := '[]'::jsonb;
  v_files jsonb := '[]'::jsonb;
  v_file jsonb;
  v_blob jsonb;
  v_blob_sha text;
  v_path text;
  v_content text;
  v_total integer := 0;
  v_count integer := 0;
  v_source text := '';
  v_model_request jsonb;
  v_model_env jsonb;
  v_raw text;
  v_plan jsonb;
  v_changes jsonb;
  v_change jsonb;
  v_edits jsonb;
  v_edit jsonb;
  v_old text;
  v_new text;
  v_occurrences integer;
  v_tree_entries jsonb := '[]'::jsonb;
  v_new_tree jsonb;
  v_new_tree_sha text;
  v_new_commit jsonb;
  v_new_commit_sha text;
  v_current_head text;
  v_readback_head text;
  v_commit_message text;
  v_reply text;
  v_files_changed jsonb := '[]'::jsonb;
  v_structured jsonb;
begin
  if v_uid is null then raise exception 'pandora_direct_plp_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_direct_plp_owner_required' using errcode='42501'; end if;
  if v_message='' or length(v_message)>8000 then raise exception 'pandora_direct_plp_invalid_message' using errcode='22023'; end if;

  if v_thread_id is not null then
    perform 1 from public.pandora_intelligence_threads t
    where t.id=v_thread_id and t.organization_id=p_organization_id and t.created_by=v_uid and t.status='active';
    if not found then raise exception 'pandora_direct_plp_thread_not_found' using errcode='22023'; end if;
  else
    insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title,status,last_message_at)
    values(p_organization_id,p_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now())
    returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
  values(v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb);

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'pandora_direct_plp_github_read_failed'; end if;
  v_ref := coalesce(v_env->'body','{}'::jsonb);
  v_head := v_ref->'object'->>'sha';
  if v_head !~ '^[0-9a-f]{40}$' then raise exception 'pandora_direct_plp_github_head_invalid'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/commits/'||v_head,null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'pandora_direct_plp_github_read_failed'; end if;
  v_commit := coalesce(v_env->'body','{}'::jsonb);
  v_tree_sha := v_commit->'tree'->>'sha';
  if v_tree_sha !~ '^[0-9a-f]{40}$' then raise exception 'pandora_direct_plp_github_tree_invalid'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/trees/'||v_tree_sha||'?recursive=1',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'pandora_direct_plp_github_read_failed'; end if;
  v_tree := coalesce(v_env->'body','{}'::jsonb);

  select coalesce(jsonb_agg(q.item order by q.score desc, q.sz asc),'[]'::jsonb)
  into v_candidates
  from (
    select e as item,
      coalesce((e->>'size')::integer,0) as sz,
      (case when lower(e->>'path') like 'src/admin/%' then 80 else 0 end) +
      (case when lower(e->>'path') like 'api/%' then 25 else 0 end) +
      (case when lower(e->>'path') like 'public/admin%' then 35 else 0 end) +
      (case when lower(v_message) ~ '\madmin\M' and lower(e->>'path') like '%admin%' then 60 else 0 end) +
      (case when lower(v_message) ~ '\m(dashboard|overview)\M' and lower(e->>'path') like '%dashboard%' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(payment|payments|paypal|xendit)\M' and lower(e->>'path') like '%payment%' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(booking|bookings|reservation|reservations)\M' and lower(e->>'path') ~ '(booking|reservation)' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(guest|guests)\M' and lower(e->>'path') like '%guest%' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(room|rooms|availability)\M' and lower(e->>'path') ~ '(room|availability)' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(settings|setting)\M' and lower(e->>'path') like '%setting%' then 45 else 0 end) +
      (case when lower(v_message) ~ '\m(ui|ux|design|style|redesign)\M' and lower(e->>'path') ~ '(css|design|admin)' then 35 else 0 end) +
      (case when lower(e->>'path') ~ '\.(jsx|tsx|js|ts|css|html)$' then 12 else 0 end) as score
    from jsonb_array_elements(coalesce(v_tree->'tree','[]'::jsonb)) e
    where e->>'type'='blob'
      and coalesce((e->>'size')::integer,0) between 1 and 80000
      and lower(e->>'path') ~ '^(src/|api/|public/|admin\.html$|package\.json$)'
      and lower(e->>'path') ~ '\.(jsx|tsx|js|ts|css|html|json)$'
  ) q;

  for v_file in select value from jsonb_array_elements(v_candidates)
  loop
    exit when v_count>=10;
    if v_total + coalesce((v_file->>'size')::integer,0) > 160000 then continue; end if;
    v_blob_sha := v_file->>'sha';
    v_path := v_file->>'path';
    if v_blob_sha !~ '^[0-9a-f]{40}$' or coalesce(v_path,'')='' then continue; end if;
    v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/blobs/'||v_blob_sha,null);
    if coalesce((v_env->>'status')::integer,0)<>200 then continue; end if;
    v_blob := coalesce(v_env->'body','{}'::jsonb);
    if coalesce(v_blob->>'encoding','')<>'base64' then continue; end if;
    begin
      v_content := convert_from(decode(regexp_replace(coalesce(v_blob->>'content',''),'[[:space:]]','','g'),'base64'),'UTF8');
    exception when others then
      continue;
    end;
    if v_content='' or length(v_content)>100000 then continue; end if;
    v_files := v_files || jsonb_build_array(jsonb_build_object('path',v_path,'sha',v_blob_sha,'content',v_content));
    v_source := v_source || E'\n\n--- FILE: '||v_path||E' ---\n'||v_content;
    v_total := v_total + length(v_content);
    v_count := v_count + 1;
  end loop;
  if v_count=0 then raise exception 'pandora_direct_plp_no_source'; end if;

  v_model_request := jsonb_build_object(
    'messages',jsonb_build_array(
      jsonb_build_object('role','system','content',
        'You are Pandora Direct GitHub Editor for the Pueblo La Perla Boracay repository. The owner explicitly authorized direct GitHub code edits without ProjectOS. Return JSON only with keys reply, commitMessage, changes. changes must contain 1 to 4 objects: {path, edits:[{old,new}]}. Each old snippet must be copied exactly from one supplied file and occur exactly once. Use small targeted replacements, not whole-file rewrites. Modify only supplied paths. Preserve unrelated behavior. Never include credentials or secrets. Do not create placeholders. Do not claim deployment; only describe the code change.'),
      jsonb_build_object('role','user','content','Owner request: '||v_message||E'\n\nPLP repository main head: '||v_head||E'\nSupplied source files:'||v_source)
    ),
    'response_format',jsonb_build_object('type','json_object'),
    'reasoning_effort','high',
    'max_completion_tokens',10000,
    'stream',false
  );

  v_model_env := public.pandora_kimi_chat_request_v1('kimi-k3',v_model_request);
  if coalesce((v_model_env->>'status')::integer,0) not between 200 and 299 then raise exception 'pandora_direct_plp_model_failed'; end if;
  v_raw := v_model_env->'body'->'choices'->0->'message'->>'content';
  if coalesce(v_raw,'')='' then raise exception 'pandora_direct_plp_model_empty'; end if;
  begin v_plan := v_raw::jsonb; exception when others then raise exception 'pandora_direct_plp_model_invalid_json'; end;
  v_changes := coalesce(v_plan->'changes','[]'::jsonb);
  if jsonb_typeof(v_changes)<>'array' or jsonb_array_length(v_changes) not between 1 and 4 then raise exception 'pandora_direct_plp_model_invalid_changes'; end if;
  v_commit_message := left(coalesce(nullif(trim(v_plan->>'commitMessage'),''),'feat(plp): apply Pandora direct GitHub edit'),200);
  v_reply := coalesce(nullif(trim(v_plan->>'reply'),''),'I updated the requested PLP code directly in GitHub.');

  for v_change in select value from jsonb_array_elements(v_changes)
  loop
    v_path := trim(coalesce(v_change->>'path',''));
    select f->>'content' into v_content from jsonb_array_elements(v_files) f where f->>'path'=v_path limit 1;
    if v_content is null then raise exception 'pandora_direct_plp_model_path_not_supplied'; end if;
    v_edits := coalesce(v_change->'edits','[]'::jsonb);
    if jsonb_typeof(v_edits)<>'array' or jsonb_array_length(v_edits) not between 1 and 8 then raise exception 'pandora_direct_plp_model_invalid_edits'; end if;
    for v_edit in select value from jsonb_array_elements(v_edits)
    loop
      v_old := v_edit->>'old';
      v_new := v_edit->>'new';
      if coalesce(v_old,'')='' or v_new is null or length(v_old)>20000 or length(v_new)>30000 then raise exception 'pandora_direct_plp_model_edit_invalid'; end if;
      v_occurrences := (length(v_content)-length(replace(v_content,v_old,'')))/greatest(length(v_old),1);
      if v_occurrences<>1 then raise exception 'pandora_direct_plp_model_edit_not_unique'; end if;
      v_content := replace(v_content,v_old,v_new);
    end loop;
    if length(v_content)>160000 then raise exception 'pandora_direct_plp_result_too_large'; end if;
    if v_content ~ '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' then raise exception 'pandora_direct_plp_credential_material_rejected'; end if;
    v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'POST',v_prefix||'/git/blobs',jsonb_build_object('content',v_content,'encoding','utf-8'));
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'pandora_direct_plp_github_blob_write_failed'; end if;
    v_blob_sha := v_env->'body'->>'sha';
    if v_blob_sha !~ '^[0-9a-f]{40}$' then raise exception 'pandora_direct_plp_github_blob_invalid'; end if;
    v_tree_entries := v_tree_entries || jsonb_build_array(jsonb_build_object('path',v_path,'mode','100644','type','blob','sha',v_blob_sha));
    v_files_changed := v_files_changed || to_jsonb(v_path);
  end loop;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'POST',v_prefix||'/git/trees',jsonb_build_object('base_tree',v_tree_sha,'tree',v_tree_entries));
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'pandora_direct_plp_github_tree_write_failed'; end if;
  v_new_tree := coalesce(v_env->'body','{}'::jsonb);
  v_new_tree_sha := v_new_tree->>'sha';
  if v_new_tree_sha !~ '^[0-9a-f]{40}$' then raise exception 'pandora_direct_plp_github_tree_write_invalid'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'POST',v_prefix||'/git/commits',jsonb_build_object('message',v_commit_message,'tree',v_new_tree_sha,'parents',jsonb_build_array(v_head)));
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'pandora_direct_plp_github_commit_write_failed'; end if;
  v_new_commit := coalesce(v_env->'body','{}'::jsonb);
  v_new_commit_sha := v_new_commit->>'sha';
  if v_new_commit_sha !~ '^[0-9a-f]{40}$' then raise exception 'pandora_direct_plp_github_commit_invalid'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'pandora_direct_plp_github_read_failed'; end if;
  v_current_head := v_env->'body'->'object'->>'sha';
  if v_current_head<>v_head then raise exception 'pandora_direct_plp_head_moved'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'PATCH',v_prefix||'/git/refs/heads/main',jsonb_build_object('sha',v_new_commit_sha,'force',false));
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'pandora_direct_plp_ref_update_failed'; end if;

  v_env := public.pandora_enterprise_direct_github_v1(p_organization_id,'GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'pandora_direct_plp_github_read_failed'; end if;
  v_readback_head := v_env->'body'->'object'->>'sha';
  if v_readback_head<>v_new_commit_sha then raise exception 'pandora_direct_plp_readback_failed'; end if;

  v_reply := v_reply||' GitHub commit '||substr(v_new_commit_sha,1,12)||' is verified on PLP main.';
  v_structured := jsonb_build_object(
    'intent','direct_github_code_change','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'handoff',null,
    'providerReadback',jsonb_build_object('provider','github','verified',true,'repository','pandora-rvw-314296438-20260820/plp','branch','main','baseSha',v_head,'commitSha',v_new_commit_sha,'files',v_files_changed,'verifiedAt',now())
  );
  insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,structured_response,provider,model)
  values(v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,v_structured,'pandora_direct_github','kimi-k3');
  update public.pandora_intelligence_threads set last_message_at=now(),updated_at=now() where id=v_thread_id;

  return jsonb_build_object('handled',true,'threadId',v_thread_id,'reply',v_reply,'intent','direct_github_code_change','confidence',1,'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,'handoff',null,'providerReadback',v_structured->'providerReadback');
end;
$$;

create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','auth','pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_direct_target boolean := false;
  v_direct_action boolean := false;
begin
  if v_uid is null then raise exception 'pandora_chat_sign_in_required' using errcode='42501'; end if;
  v_direct_action := v_norm ~ E'\\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|refactor|rewrite)\\M';
  v_direct_target := v_norm ~ E'\\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\\M';
  if not v_direct_target and p_thread_id is not null then
    v_direct_target := exists(
      select 1 from (
        select m.content from public.pandora_intelligence_messages m
        join public.pandora_intelligence_threads t on t.id=m.thread_id
        where m.thread_id=p_thread_id and m.organization_id=p_organization_id
          and t.created_by=v_uid and t.status='active'
        order by m.created_at desc limit 12
      ) recent
      where lower(recent.content) ~ E'\\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\\M'
    );
  end if;
  if v_direct_action and v_direct_target then
    return private.pandora_direct_plp_code_edit_v1(p_organization_id,p_message,p_thread_id,p_project_id);
  end if;
  return public.pandora_chat_universal_dispatch_v9_legacy_20260917(p_organization_id,p_message,p_thread_id,p_project_id);
end;
$$;

revoke all on function private.pandora_direct_plp_code_edit_v1(uuid,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) to authenticated,service_role;
revoke all on function public.pandora_chat_universal_dispatch_v9_legacy_20260917(uuid,text,uuid,uuid) from public,anon,authenticated;
;
