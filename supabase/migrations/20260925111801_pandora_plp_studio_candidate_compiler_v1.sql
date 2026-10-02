
begin;

create or replace function public.pandora_plp_studio_prepare_candidate_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_intent_id uuid,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp'
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_project public.projectos_projects%rowtype;
  v_intent public.pandora_project_intents%rowtype;
  v_existing public.pandora_plp_studio_candidates%rowtype;
  v_active public.pandora_plp_studio_candidates%rowtype;
  v_prefix constant text:='/repos/pandora-rvw-314296438-20260820/plp';
  v_env jsonb;
  v_head text;
  v_parent_sha text;
  v_base_main_sha text;
  v_commit jsonb;
  v_tree_sha text;
  v_tree jsonb;
  v_candidates jsonb:='[]'::jsonb;
  v_files jsonb:='[]'::jsonb;
  v_file jsonb;
  v_blob jsonb;
  v_blob_sha text;
  v_path text;
  v_content text;
  v_total integer:=0;
  v_count integer:=0;
  v_source text:='';
  v_tree_list text:='';
  v_focus_source text;
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
  v_tree_entries jsonb:='[]'::jsonb;
  v_new_tree_sha text;
  v_new_commit_sha text;
  v_commit_message text;
  v_reply text;
  v_files_changed jsonb:='[]'::jsonb;
  v_candidate_id uuid;
begin
  if v_uid is null then raise exception 'PLP_STUDIO_SIGN_IN_REQUIRED' using errcode='42501'; end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then raise exception 'PLP_STUDIO_OWNER_REQUIRED' using errcode='42501'; end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) not between 8 and 200 then
    raise exception 'PLP_STUDIO_IDEMPOTENCY_INVALID' using errcode='22023';
  end if;

  select * into v_project
  from public.projectos_projects
  where id=p_project_id and organization_id=p_organization_id
    and project_key='plp-boracay'
    and repository='pandora-rvw-314296438-20260820/plp';
  if not found then raise exception 'PLP_STUDIO_PROJECT_INVALID' using errcode='22023'; end if;

  select * into v_intent
  from public.pandora_project_intents
  where id=p_source_intent_id and organization_id=p_organization_id
    and project_id=p_project_id and intent_kind='change';
  if not found or nullif(trim(v_intent.intent_text),'') is null then
    raise exception 'PLP_STUDIO_INTENT_INVALID' using errcode='22023';
  end if;

  select * into v_existing
  from public.pandora_plp_studio_candidates
  where project_id=p_project_id and idempotency_key=trim(p_idempotency_key)
  limit 1;
  if found then
    if v_existing.source_intent_id is distinct from p_source_intent_id then
      raise exception 'PLP_STUDIO_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'replayed',true,'candidateId',v_existing.id,
      'baseMainSha',v_existing.base_main_sha,'candidateSha',v_existing.candidate_sha,
      'candidateTreeSha',v_existing.candidate_tree_sha,'status',v_existing.status,
      'filesChanged',v_existing.files_changed,'summary',v_existing.change_summary
    );
  end if;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'GET',v_prefix||'/git/ref/heads/main',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PLP_STUDIO_GITHUB_MAIN_READ_FAILED';
  end if;
  v_head:=v_env#>>'{body,object,sha}';
  if v_head !~ '^[0-9a-f]{40}$' then raise exception 'PLP_STUDIO_GITHUB_MAIN_INVALID'; end if;
  v_base_main_sha:=v_head;
  v_parent_sha:=v_head;

  select * into v_active
  from public.pandora_plp_studio_candidates
  where project_id=p_project_id and status='preview_ready'
  order by created_at desc
  limit 1;
  if found and v_active.base_main_sha=v_head then
    v_parent_sha:=v_active.candidate_sha;
    v_base_main_sha:=v_active.base_main_sha;
  end if;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'GET',v_prefix||'/git/commits/'||v_parent_sha,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PLP_STUDIO_GITHUB_COMMIT_READ_FAILED'; end if;
  v_commit:=coalesce(v_env->'body','{}'::jsonb);
  v_tree_sha:=v_commit#>>'{tree,sha}';
  if v_tree_sha !~ '^[0-9a-f]{40}$' then raise exception 'PLP_STUDIO_GITHUB_TREE_INVALID'; end if;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'GET',v_prefix||'/git/trees/'||v_tree_sha||'?recursive=1',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PLP_STUDIO_GITHUB_TREE_READ_FAILED'; end if;
  v_tree:=coalesce(v_env->'body','{}'::jsonb);

  select string_agg(e->>'path', E'\n' order by e->>'path')
  into v_tree_list
  from jsonb_array_elements(coalesce(v_tree->'tree','[]'::jsonb)) e
  where e->>'type'='blob'
    and lower(e->>'path') ~ '\.(jsx|tsx|js|ts|css|html|json)$'
    and lower(e->>'path') !~ '(node_modules|/build/|/dist/|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$)';

  select (regexp_match(v_intent.intent_text,'source=([^ :]+)'))[1] into v_focus_source;

  select coalesce(jsonb_agg(q.item order by q.score desc,q.sz asc,q.path asc),'[]'::jsonb)
  into v_candidates
  from (
    select e as item,
      e->>'path' as path,
      coalesce((e->>'size')::integer,0) as sz,
      (case when v_focus_source is not null and e->>'path'=v_focus_source then 500 else 0 end)
      +(case when lower(e->>'path') in ('src/main.jsx','src/main.tsx','src/app.jsx','src/app.tsx','index.html') then 65 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(home|hero|landing|homepage)\M' and lower(e->>'path') ~ '(home|hero|landing|index|app)' then 130 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(booking|reservation|reserve|calendar)\M' and lower(e->>'path') ~ '(booking|reservation|calendar|availability)' then 150 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(room|rooms|villa|accommodation|stay)\M' and lower(e->>'path') ~ '(room|villa|accommodation|stay)' then 130 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(admin|dashboard|owner|staff)\M' and lower(e->>'path') ~ '(admin|dashboard|owner|staff)' then 140 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(payment|paypal|xendit|price|rate|revenue)\M' and lower(e->>'path') ~ '(payment|paypal|xendit|price|rate|revenue)' then 140 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(guest|guests|concierge|contact)\M' and lower(e->>'path') ~ '(guest|concierge|contact)' then 120 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(nav|menu|header|footer|sidebar)\M' and lower(e->>'path') ~ '(nav|menu|header|footer|sidebar|app)' then 130 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(ui|ux|design|style|color|font|spacing|layout)\M' and lower(e->>'path') ~ '(css|style|theme|design|app|index)' then 125 else 0 end)
      +(case when lower(v_intent.intent_text) ~ '\m(copy|text|heading|title|description|content)\M' and lower(e->>'path') ~ '(content|copy|home|app|index)' then 100 else 0 end)
      +(case when lower(e->>'path') like 'src/%' then 25 else 0 end)
      +(case when lower(e->>'path') like 'public/%' then 10 else 0 end)
      +(case when lower(e->>'path') like 'api/%' then 8 else 0 end)
      +(case when lower(e->>'path') ~ '\.(jsx|tsx|css|html)$' then 20 else 0 end) as score
    from jsonb_array_elements(coalesce(v_tree->'tree','[]'::jsonb)) e
    where e->>'type'='blob'
      and coalesce((e->>'size')::integer,0) between 1 and 100000
      and lower(e->>'path') ~ '^(src/|api/|public/|index\.html$|admin\.html$|booking\.html$|accommodation\.html$|experiences\.html$|vercel\.json$|package\.json$)'
      and lower(e->>'path') ~ '\.(jsx|tsx|js|ts|css|html|json)$'
  ) q
  where q.score>20;

  for v_file in select value from jsonb_array_elements(v_candidates)
  loop
    exit when v_count>=12;
    if v_total+coalesce((v_file->>'size')::integer,0)>240000 then continue; end if;
    v_blob_sha:=v_file->>'sha';
    v_path:=v_file->>'path';
    if v_blob_sha !~ '^[0-9a-f]{40}$' or coalesce(v_path,'')='' then continue; end if;

    v_env:=public.pandora_enterprise_direct_github_v1(
      p_organization_id,'GET',v_prefix||'/git/blobs/'||v_blob_sha,null
    );
    if coalesce((v_env->>'status')::integer,0)<>200 then continue; end if;
    v_blob:=coalesce(v_env->'body','{}'::jsonb);
    if coalesce(v_blob->>'encoding','')<>'base64' then continue; end if;
    begin
      v_content:=convert_from(
        decode(regexp_replace(coalesce(v_blob->>'content',''),'[[:space:]]','','g'),'base64'),
        'UTF8'
      );
    exception when others then continue;
    end;
    if v_content='' or length(v_content)>120000 then continue; end if;

    v_files:=v_files||jsonb_build_array(jsonb_build_object(
      'path',v_path,'sha',v_blob_sha,'content',v_content
    ));
    v_source:=v_source||E'\n\n--- FILE: '||v_path||E' ---\n'||v_content;
    v_total:=v_total+length(v_content);
    v_count:=v_count+1;
  end loop;

  if v_count=0 then raise exception 'PLP_STUDIO_NO_SOURCE'; end if;

  v_model_request:=jsonb_build_object(
    'systemInstruction',jsonb_build_object(
      'parts',jsonb_build_array(jsonb_build_object(
        'text',
        'You are the PLP Studio source editor. Return JSON only with keys reply, commitMessage, changes. changes must contain 1 to 6 unique-path objects shaped {path,edits:[{old,new}]}. Every old snippet must be copied exactly from one supplied file and occur exactly once. Use the smallest safe targeted replacements. Modify only supplied paths. Preserve unrelated resort, booking, auth, payment, analytics, security, and responsive behavior. Never include secrets or credentials. Never weaken access control, audit, payment verification, or security headers. Do not create placeholders. Do not claim deployment or publication. The change will be previewed before Publish can move production.'
      ))
    ),
    'contents',jsonb_build_array(jsonb_build_object(
      'role','user',
      'parts',jsonb_build_array(jsonb_build_object(
        'text',
        'Owner change request: '||v_intent.intent_text||
        E'\n\nExact PLP base main SHA: '||v_base_main_sha||
        E'\nExact candidate parent SHA: '||v_parent_sha||
        E'\nRepository file inventory:\n'||left(coalesce(v_tree_list,''),30000)||
        E'\n\nSupplied source files:'||v_source
      ))
    )),
    'generationConfig',jsonb_build_object(
      'responseMimeType','application/json',
      'temperature',0.1,
      'maxOutputTokens',12000
    )
  );

  v_model_env:=public.pandora_worker_b_gemini_request_20260829(
    'gemini-3.1-pro-preview',v_model_request
  );
  if coalesce((v_model_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PLP_STUDIO_MODEL_FAILED';
  end if;
  v_raw:=v_model_env#>>'{body,candidates,0,content,parts,0,text}';
  if nullif(trim(coalesce(v_raw,'')),'') is null then raise exception 'PLP_STUDIO_MODEL_EMPTY'; end if;
  begin v_plan:=v_raw::jsonb; exception when others then raise exception 'PLP_STUDIO_MODEL_INVALID_JSON'; end;

  v_changes:=coalesce(v_plan->'changes','[]'::jsonb);
  if jsonb_typeof(v_changes)<>'array' or jsonb_array_length(v_changes) not between 1 and 6 then
    raise exception 'PLP_STUDIO_MODEL_INVALID_CHANGES';
  end if;
  if (
    select count(*)<>count(distinct value->>'path') from jsonb_array_elements(v_changes)
  ) then raise exception 'PLP_STUDIO_DUPLICATE_PATH'; end if;

  v_commit_message:=left(coalesce(nullif(trim(v_plan->>'commitMessage'),''),'feat(plp): preview Pandora Studio change'),200);
  v_reply:=left(coalesce(nullif(trim(v_plan->>'reply'),''),'Pandora prepared a PLP preview candidate.'),1200);

  for v_change in select value from jsonb_array_elements(v_changes)
  loop
    v_path:=trim(coalesce(v_change->>'path',''));
    select f->>'content' into v_content from jsonb_array_elements(v_files) f
     where f->>'path'=v_path limit 1;
    if v_content is null then raise exception 'PLP_STUDIO_MODEL_PATH_NOT_SUPPLIED'; end if;

    v_edits:=coalesce(v_change->'edits','[]'::jsonb);
    if jsonb_typeof(v_edits)<>'array' or jsonb_array_length(v_edits) not between 1 and 12 then
      raise exception 'PLP_STUDIO_MODEL_INVALID_EDITS';
    end if;

    for v_edit in select value from jsonb_array_elements(v_edits)
    loop
      v_old:=v_edit->>'old';
      v_new:=v_edit->>'new';
      if coalesce(v_old,'')='' or v_new is null or length(v_old)>24000 or length(v_new)>36000 then
        raise exception 'PLP_STUDIO_MODEL_EDIT_INVALID';
      end if;
      v_occurrences:=(length(v_content)-length(replace(v_content,v_old,'')))/greatest(length(v_old),1);
      if v_occurrences<>1 then raise exception 'PLP_STUDIO_MODEL_EDIT_NOT_UNIQUE'; end if;
      v_content:=replace(v_content,v_old,v_new);
    end loop;

    if length(v_content)>180000 then raise exception 'PLP_STUDIO_RESULT_TOO_LARGE'; end if;
    if v_content ~ '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
       or v_content ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@'
    then raise exception 'PLP_STUDIO_CREDENTIAL_MATERIAL_REJECTED'; end if;

    v_env:=public.pandora_enterprise_direct_github_v1(
      p_organization_id,'POST',v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'PLP_STUDIO_GITHUB_BLOB_WRITE_FAILED';
    end if;
    v_blob_sha:=v_env#>>'{body,sha}';
    if v_blob_sha !~ '^[0-9a-f]{40}$' then raise exception 'PLP_STUDIO_GITHUB_BLOB_INVALID'; end if;

    v_tree_entries:=v_tree_entries||jsonb_build_array(jsonb_build_object(
      'path',v_path,'mode','100644','type','blob','sha',v_blob_sha
    ));
    v_files_changed:=v_files_changed||to_jsonb(v_path);
  end loop;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'POST',v_prefix||'/git/trees',
    jsonb_build_object('base_tree',v_tree_sha,'tree',v_tree_entries)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PLP_STUDIO_GITHUB_TREE_WRITE_FAILED';
  end if;
  v_new_tree_sha:=v_env#>>'{body,sha}';
  if v_new_tree_sha !~ '^[0-9a-f]{40}$' then raise exception 'PLP_STUDIO_GITHUB_TREE_WRITE_INVALID'; end if;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'POST',v_prefix||'/git/commits',
    jsonb_build_object(
      'message',v_commit_message,
      'tree',v_new_tree_sha,
      'parents',jsonb_build_array(v_parent_sha)
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PLP_STUDIO_GITHUB_COMMIT_WRITE_FAILED';
  end if;
  v_new_commit_sha:=v_env#>>'{body,sha}';
  if v_new_commit_sha !~ '^[0-9a-f]{40}$' then raise exception 'PLP_STUDIO_GITHUB_COMMIT_INVALID'; end if;

  v_env:=public.pandora_enterprise_direct_github_v1(
    p_organization_id,'GET',v_prefix||'/git/commits/'||v_new_commit_sha,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200
     or v_env#>>'{body,sha}'<>v_new_commit_sha
     or v_env#>>'{body,tree,sha}'<>v_new_tree_sha
  then raise exception 'PLP_STUDIO_GITHUB_COMMIT_READBACK_FAILED'; end if;

  insert into public.pandora_plp_studio_candidates(
    organization_id,project_id,requested_by,source_intent_id,idempotency_key,
    base_main_sha,candidate_sha,candidate_tree_sha,files_changed,change_summary,status
  ) values(
    p_organization_id,p_project_id,v_uid,p_source_intent_id,trim(p_idempotency_key),
    v_base_main_sha,v_new_commit_sha,v_new_tree_sha,v_files_changed,v_reply,'preview_building'
  )
  returning id into v_candidate_id;

  return jsonb_build_object(
    'ok',true,'replayed',false,'candidateId',v_candidate_id,
    'baseMainSha',v_base_main_sha,'parentSha',v_parent_sha,
    'candidateSha',v_new_commit_sha,'candidateTreeSha',v_new_tree_sha,
    'filesChanged',v_files_changed,'summary',v_reply
  );
end;
$fn$;

revoke all on function public.pandora_plp_studio_prepare_candidate_v1(uuid,uuid,uuid,text)
  from public,anon;
grant execute on function public.pandora_plp_studio_prepare_candidate_v1(uuid,uuid,uuid,text)
  to authenticated;

commit;
;
