-- Pandora direct capability provider fallback v1
-- Gemini remains first choice; Kimi is the bounded provider fallback when Gemini is unavailable.

CREATE OR REPLACE FUNCTION private.pandora_direct_box_code_edit_v1(p_organization_id uuid, p_message text, p_thread_id uuid DEFAULT NULL::uuid, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'auth', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_thread_id uuid := p_thread_id;
  v_message text := trim(coalesce(p_message,''));
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box';
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_env jsonb;
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
  v_kimi_request jsonb;
  v_model_used text := 'gemini-3.1-pro-preview';
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
  v_new_tree_sha text;
  v_new_commit_sha text;
  v_commit_message text;
  v_reply text;
  v_files_changed jsonb := '[]'::jsonb;
  v_branch text;
  v_branch_ref text;
  v_branch_digest text;
  v_pr jsonb;
  v_pr_no integer;
  v_pr_url text;
  v_readback_ref jsonb;
  v_readback_pr jsonb;
  v_structured jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_direct_box_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'pandora_direct_box_owner_required' using errcode='42501';
  end if;

  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_direct_box_invalid_message' using errcode='22023';
  end if;

  if v_thread_id is not null then
    perform 1
    from public.pandora_intelligence_threads t
    where t.id=v_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=v_uid
      and t.status='active';
    if not found then
      raise exception 'pandora_direct_box_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(
      organization_id,project_id,created_by,title,status,last_message_at
    ) values(
      p_organization_id,p_project_id,v_uid,
      left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
      'active',now()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values(
    v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
  );

  v_env := private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'pandora_direct_box_github_ref_read_failed';
  end if;
  v_ref := coalesce(v_env->'body','{}'::jsonb);
  v_head := v_ref->'object'->>'sha';
  if v_head !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_direct_box_github_head_invalid';
  end if;

  v_env := private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/commits/'||v_head,null);
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'pandora_direct_box_github_commit_read_failed';
  end if;
  v_commit := coalesce(v_env->'body','{}'::jsonb);
  v_tree_sha := v_commit->'tree'->>'sha';
  if v_tree_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_direct_box_github_tree_invalid';
  end if;

  v_env := private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/trees/'||v_tree_sha||'?recursive=1',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'pandora_direct_box_github_tree_read_failed';
  end if;
  v_tree := coalesce(v_env->'body','{}'::jsonb);

  select coalesce(jsonb_agg(q.item order by q.score desc, q.sz asc),'[]'::jsonb)
  into v_candidates
  from (
    select e as item,
      coalesce((e->>'size')::integer,0) as sz,
      (case when lower(e->>'path')='supabase/functions/pandora-intelligence-chat/index.ts' then 140 else 0 end) +
      (case when lower(e->>'path')='supabase/functions/pandora-intelligence-chat/activity.ts' then 120 else 0 end) +
      (case when lower(e->>'path') like 'packages/pandora-intelligence/%' then 95 else 0 end) +
      (case when lower(e->>'path') like 'packages/pandora-activity-theatre/%' then 90 else 0 end) +
      (case when lower(e->>'path') like 'packages/pandora-tools/%' then 80 else 0 end) +
      (case when lower(e->>'path') like 'apps/pandora-mobile/%' then 55 else 0 end) +
      (case when lower(e->>'path') like 'test/%' then 35 else 0 end) +
      (case when lower(v_message) ~ '\m(chat|ask pandora|capability|router|execute|execution|projectos)\M'
             and lower(e->>'path') ~ '(intelligence-chat|pandora-intelligence|capability|projectos-retirement)' then 110 else 0 end) +
      (case when lower(v_message) ~ '\m(activity|theatre|theater|progress|stream|event)\M'
             and lower(e->>'path') ~ '(activity|theatre|theater)' then 110 else 0 end) +
      (case when lower(v_message) ~ '\m(android|mobile|emulator|phone|flutter)\M'
             and lower(e->>'path') like 'apps/pandora-mobile/%' then 130 else 0 end) +
      (case when lower(v_message) ~ '\m(supabase|database|sql|migration)\M'
             and lower(e->>'path') ~ '(supabase/functions|supabase/migrations)' then 75 else 0 end) +
      (case when lower(v_message) ~ '\m(github|repo|repository|branch|pull request|pr)\M'
             and lower(e->>'path') ~ '(github|source|capability)' then 70 else 0 end) +
      (case when lower(v_message) ~ '\m(vercel|deploy|deployment|publish)\M'
             and lower(e->>'path') ~ '(vercel|deploy|release)' then 70 else 0 end) +
      (case when lower(e->>'path') ~ '\.(ts|js|mjs|dart|sql|json)$' then 10 else 0 end) as score
    from jsonb_array_elements(coalesce(v_tree->'tree','[]'::jsonb)) e
    where e->>'type'='blob'
      and coalesce((e->>'size')::integer,0) between 1 and 90000
      and lower(e->>'path') ~ '^(supabase/functions/|packages/|apps/pandora-mobile/|src/|test/)'
      and lower(e->>'path') ~ '\.(ts|js|mjs|dart|sql|json)$'
      and lower(e->>'path') !~ '(node_modules|/build/|/dist/|package-lock\.json$|pnpm-lock\.yaml$|yarn\.lock$)'
  ) q
  where q.score > 10;

  for v_file in select value from jsonb_array_elements(v_candidates)
  loop
    exit when v_count>=10;
    if v_total + coalesce((v_file->>'size')::integer,0) > 210000 then
      continue;
    end if;

    v_blob_sha := v_file->>'sha';
    v_path := v_file->>'path';
    if v_blob_sha !~ '^[0-9a-f]{40}$' or coalesce(v_path,'')='' then
      continue;
    end if;

    v_env := private.pandora_integration_github_api_20260825(
      'GET',v_prefix||'/git/blobs/'||v_blob_sha,null
    );
    if coalesce((v_env->>'status')::integer,0)<>200 then
      continue;
    end if;

    v_blob := coalesce(v_env->'body','{}'::jsonb);
    if coalesce(v_blob->>'encoding','')<>'base64' then
      continue;
    end if;

    begin
      v_content := convert_from(
        decode(regexp_replace(coalesce(v_blob->>'content',''),'[[:space:]]','','g'),'base64'),
        'UTF8'
      );
    exception when others then
      continue;
    end;

    if v_content='' or length(v_content)>120000 then
      continue;
    end if;

    v_files := v_files || jsonb_build_array(jsonb_build_object(
      'path',v_path,'sha',v_blob_sha,'content',v_content
    ));
    v_source := v_source || E'\n\n--- FILE: '||v_path||E' ---\n'||v_content;
    v_total := v_total + length(v_content);
    v_count := v_count + 1;
  end loop;

  if v_count=0 then
    raise exception 'pandora_direct_box_no_source';
  end if;

  v_model_request := jsonb_build_object(
    'systemInstruction',jsonb_build_object(
      'parts',jsonb_build_array(jsonb_build_object(
        'text',
        'You are Pandora Direct Source Editor for the canonical pandoras-box repository. The owner explicitly authorized this code change. Return JSON only with keys reply, commitMessage, changes. changes must contain 1 to 6 unique-path objects: {path, edits:[{old,new}]}. Each old snippet must be copied exactly from one supplied file and occur exactly once. Use the smallest safe targeted replacements. Modify only supplied paths. Preserve unrelated behavior. Never include credentials or secrets. Never weaken authorization, branch protection, audit, verification, or exact-source safety. Do not create placeholders. Do not claim merge, deployment, CI success, emulator success, or runtime success. This execution creates a protected branch and pull request only.'
      ))
    ),
    'contents',jsonb_build_array(jsonb_build_object(
      'role','user',
      'parts',jsonb_build_array(jsonb_build_object(
        'text',
        'Owner request: '||v_message||E'\n\nExact canonical main SHA: '||v_head||
        E'\nSupplied source files:'||v_source
      ))
    )),
    'generationConfig',jsonb_build_object(
      'responseMimeType','application/json',
      'temperature',0.1,
      'maxOutputTokens',10000
    )
  );

  v_model_env := public.pandora_worker_b_gemini_request_20260829(
    'gemini-3.1-pro-preview',
    v_model_request
  );

  if coalesce((v_model_env->>'status')::integer,0) between 200 and 299 then
    v_raw := v_model_env->'body'->'candidates'->0->'content'->'parts'->0->>'text';
  else
    v_model_used := 'kimi-k3';
    v_kimi_request := jsonb_build_object(
      'messages',jsonb_build_array(
        jsonb_build_object('role','system','content',v_model_request #>> '{systemInstruction,parts,0,text}'),
        jsonb_build_object('role','user','content',v_model_request #>> '{contents,0,parts,0,text}')
      ),
      'response_format',jsonb_build_object('type','json_object'),
      'reasoning_effort','high',
      'max_completion_tokens',10000,
      'stream',false
    );
    v_model_env := public.pandora_kimi_chat_request_v1('kimi-k3',v_kimi_request);
    if coalesce((v_model_env->>'status')::integer,0) not between 200 and 299
       or coalesce((v_model_env->>'ok')::boolean,false)<>true then
      raise exception 'pandora_direct_box_model_failed';
    end if;
    v_raw := v_model_env->'body'->'choices'->0->'message'->>'content';
  end if;
  if coalesce(trim(v_raw),'')='' then
    raise exception 'pandora_direct_box_model_empty';
  end if;

  begin
    v_plan := v_raw::jsonb;
  exception when others then
    raise exception 'pandora_direct_box_model_invalid_json';
  end;

  v_changes := coalesce(v_plan->'changes','[]'::jsonb);
  if jsonb_typeof(v_changes)<>'array'
     or jsonb_array_length(v_changes) not between 1 and 6 then
    raise exception 'pandora_direct_box_model_invalid_changes';
  end if;

  if (
    select count(*) <> count(distinct value->>'path')
    from jsonb_array_elements(v_changes)
  ) then
    raise exception 'pandora_direct_box_duplicate_change_path';
  end if;

  v_commit_message := left(
    coalesce(nullif(trim(v_plan->>'commitMessage'),''),'feat(pandora): apply direct capability edit'),
    200
  );
  v_reply := coalesce(
    nullif(trim(v_plan->>'reply'),''),
    'I prepared the requested Pandora source change.'
  );

  for v_change in select value from jsonb_array_elements(v_changes)
  loop
    v_path := trim(coalesce(v_change->>'path',''));

    select f->>'content' into v_content
    from jsonb_array_elements(v_files) f
    where f->>'path'=v_path
    limit 1;

    if v_content is null then
      raise exception 'pandora_direct_box_model_path_not_supplied';
    end if;

    v_edits := coalesce(v_change->'edits','[]'::jsonb);
    if jsonb_typeof(v_edits)<>'array'
       or jsonb_array_length(v_edits) not between 1 and 12 then
      raise exception 'pandora_direct_box_model_invalid_edits';
    end if;

    for v_edit in select value from jsonb_array_elements(v_edits)
    loop
      v_old := v_edit->>'old';
      v_new := v_edit->>'new';

      if coalesce(v_old,'')=''
         or v_new is null
         or length(v_old)>24000
         or length(v_new)>36000 then
        raise exception 'pandora_direct_box_model_edit_invalid';
      end if;

      v_occurrences := (
        length(v_content)-length(replace(v_content,v_old,''))
      ) / greatest(length(v_old),1);

      if v_occurrences<>1 then
        raise exception 'pandora_direct_box_model_edit_not_unique';
      end if;

      v_content := replace(v_content,v_old,v_new);
    end loop;

    if length(v_content)>180000 then
      raise exception 'pandora_direct_box_result_too_large';
    end if;

    if v_content ~ '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
       or v_content ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
      raise exception 'pandora_direct_box_credential_material_rejected';
    end if;

    v_env := private.pandora_integration_github_api_20260825(
      'POST',
      v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'pandora_direct_box_github_blob_write_failed';
    end if;

    v_blob_sha := v_env->'body'->>'sha';
    if v_blob_sha !~ '^[0-9a-f]{40}$' then
      raise exception 'pandora_direct_box_github_blob_invalid';
    end if;

    v_tree_entries := v_tree_entries || jsonb_build_array(jsonb_build_object(
      'path',v_path,'mode','100644','type','blob','sha',v_blob_sha
    ));
    v_files_changed := v_files_changed || to_jsonb(v_path);
  end loop;

  v_env := private.pandora_integration_github_api_20260825(
    'POST',
    v_prefix||'/git/trees',
    jsonb_build_object('base_tree',v_tree_sha,'tree',v_tree_entries)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'pandora_direct_box_github_tree_write_failed';
  end if;
  v_new_tree_sha := v_env->'body'->>'sha';
  if v_new_tree_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_direct_box_github_tree_write_invalid';
  end if;

  v_env := private.pandora_integration_github_api_20260825(
    'POST',
    v_prefix||'/git/commits',
    jsonb_build_object(
      'message',v_commit_message,
      'tree',v_new_tree_sha,
      'parents',jsonb_build_array(v_head)
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'pandora_direct_box_github_commit_write_failed';
  end if;
  v_new_commit_sha := v_env->'body'->>'sha';
  if v_new_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_direct_box_github_commit_invalid';
  end if;

  v_env := private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200
     or v_env->'body'->'object'->>'sha'<>v_head then
    raise exception 'pandora_direct_box_main_moved';
  end if;

  v_branch_digest := substr(
    encode(extensions.digest(
      p_organization_id::text||':'||v_head||':'||v_message||':'||clock_timestamp()::text,
      'sha256'
    ),'hex'),
    1,10
  );
  v_branch := 'chatgpt/pandora-direct-'||
    to_char(clock_timestamp() at time zone 'UTC','YYYYMMDDHH24MISS')||
    '-'||v_branch_digest;
  v_branch_ref := 'refs/heads/'||v_branch;

  v_env := private.pandora_integration_github_api_20260825(
    'POST',
    v_prefix||'/git/refs',
    jsonb_build_object('ref',v_branch_ref,'sha',v_new_commit_sha)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'pandora_direct_box_branch_create_failed';
  end if;

  v_env := private.pandora_integration_github_api_20260825(
    'POST',
    v_prefix||'/pulls',
    jsonb_build_object(
      'title',v_commit_message,
      'head',v_branch,
      'base','main',
      'body',
      'Pandora direct capability execution.'||E'\n\n'||
      'Owner request: '||left(v_message,2000)||E'\n\n'||
      'Exact base SHA: '||v_head||E'\n'||
      'Generated with bounded exact-snippet edits. No merge, deployment, or CI success is claimed by this operation.'
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'pandora_direct_box_pull_request_create_failed';
  end if;

  v_pr := coalesce(v_env->'body','{}'::jsonb);
  v_pr_no := nullif(v_pr->>'number','')::integer;
  v_pr_url := v_pr->>'html_url';
  if v_pr_no is null or v_pr_no<1 then
    raise exception 'pandora_direct_box_pull_request_invalid';
  end if;

  v_env := private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/'||v_branch,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'pandora_direct_box_branch_readback_failed';
  end if;
  v_readback_ref := coalesce(v_env->'body','{}'::jsonb);

  v_env := private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/pulls/'||v_pr_no::text,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'pandora_direct_box_pr_readback_failed';
  end if;
  v_readback_pr := coalesce(v_env->'body','{}'::jsonb);

  if v_readback_ref->'object'->>'sha'<>v_new_commit_sha
     or v_readback_pr #>> '{head,sha}'<>v_new_commit_sha
     or v_readback_pr #>> '{base,ref}'<>'main'
     or v_readback_pr->>'state'<>'open' then
    raise exception 'pandora_direct_box_provider_readback_mismatch';
  end if;

  v_reply := v_reply||
    ' GitHub verified branch '||v_branch||
    ' at '||substr(v_new_commit_sha,1,12)||
    ' with PR #'||v_pr_no::text||
    ' open against main. It is not merged or deployed yet.';

  v_structured := jsonb_build_object(
    'intent','direct_github_code_change',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'handoff',null,
    'providerReadback',jsonb_build_object(
      'provider','github',
      'verified',true,
      'repository',v_repo,
      'baseBranch','main',
      'baseSha',v_head,
      'branch',v_branch,
      'commitSha',v_new_commit_sha,
      'pullRequest',v_pr_no,
      'pullRequestUrl',v_pr_url,
      'pullRequestState','open',
      'files',v_files_changed,
      'verifiedAt',now()
    )
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values(
    v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,v_structured,
    'pandora_direct_github',v_model_used
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(),updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent','direct_github_code_change',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'projectRequired',false,
    'handoff',null,
    'providerReadback',v_structured->'providerReadback'
  );
end;
$function$;


revoke all on function private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid) from public,anon,authenticated;

do $contract$
declare v_definition text;
begin
  select pg_get_functiondef('private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure) into v_definition;
  if position('pandora_worker_b_gemini_request_20260829' in v_definition)=0 or position('pandora_kimi_chat_request_v1' in v_definition)=0 or position('v_model_used' in v_definition)=0 then
    raise exception 'pandora_direct_box_provider_fallback_missing' using errcode='55000';
  end if;
end
$contract$;
