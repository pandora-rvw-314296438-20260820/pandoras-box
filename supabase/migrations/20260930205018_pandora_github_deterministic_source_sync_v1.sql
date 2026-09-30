
begin;

create or replace function public.pandora_github_source_sync_v1(
  p_files jsonb,
  p_commit_message text,
  p_branch_suffix text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box';
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_env jsonb;
  v_head text;
  v_commit jsonb;
  v_tree_sha text;
  v_file jsonb;
  v_path text;
  v_content text;
  v_blob_sha text;
  v_tree_entries jsonb:='[]'::jsonb;
  v_new_tree text;
  v_new_commit text;
  v_branch text;
  v_branch_ref text;
  v_pr jsonb;
  v_pr_no integer;
  v_read_ref jsonb;
  v_read_pr jsonb;
  v_files_written jsonb:='[]'::jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if jsonb_typeof(p_files)<>'array'
     or jsonb_array_length(p_files) not between 1 and 12
     or char_length(coalesce(btrim(p_commit_message),'')) not between 5 and 200
     or coalesce(p_branch_suffix,'') !~ '^[a-z0-9][a-z0-9._-]{5,100}$' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_INPUT_INVALID' using errcode='22023';
  end if;

  if (
    select count(*)<>count(distinct value->>'path')
    from jsonb_array_elements(p_files)
  ) then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_DUPLICATE_PATH' using errcode='22023';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/main',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_MAIN_READ_FAILED';
  end if;
  v_head:=v_env->'body'->'object'->>'sha';
  if v_head !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_MAIN_SHA_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/commits/'||v_head,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_COMMIT_READ_FAILED';
  end if;
  v_commit:=v_env->'body';
  v_tree_sha:=v_commit->'tree'->>'sha';
  if v_tree_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_TREE_SHA_INVALID';
  end if;

  for v_file in select value from jsonb_array_elements(p_files)
  loop
    v_path:=coalesce(v_file->>'path','');
    v_content:=coalesce(v_file->>'content','');

    if v_path !~ '^supabase/migrations/[0-9]{14}_[a-z0-9_]+\.sql$'
       or length(v_content) not between 1 and 250000
       or octet_length(v_content)>500000 then
      raise exception 'PANDORA_GITHUB_SOURCE_SYNC_FILE_INVALID: %',v_path using errcode='22023';
    end if;

    if v_content ~ '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
       or v_content ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
      raise exception 'PANDORA_GITHUB_SOURCE_SYNC_CREDENTIAL_REJECTED: %',v_path using errcode='22023';
    end if;

    v_env:=private.pandora_integration_github_api_20260825(
      'POST',v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'PANDORA_GITHUB_SOURCE_SYNC_BLOB_WRITE_FAILED: %',v_path;
    end if;
    v_blob_sha:=v_env->'body'->>'sha';
    if v_blob_sha !~ '^[0-9a-f]{40}$' then
      raise exception 'PANDORA_GITHUB_SOURCE_SYNC_BLOB_SHA_INVALID';
    end if;

    v_tree_entries:=v_tree_entries||jsonb_build_array(jsonb_build_object(
      'path',v_path,'mode','100644','type','blob','sha',v_blob_sha
    ));
    v_files_written:=v_files_written||jsonb_build_array(v_path);
  end loop;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/trees',
    jsonb_build_object('base_tree',v_tree_sha,'tree',v_tree_entries)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_TREE_WRITE_FAILED';
  end if;
  v_new_tree:=v_env->'body'->>'sha';
  if v_new_tree !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_NEW_TREE_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/commits',
    jsonb_build_object(
      'message',btrim(p_commit_message),
      'tree',v_new_tree,
      'parents',jsonb_build_array(v_head)
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_COMMIT_WRITE_FAILED';
  end if;
  v_new_commit:=v_env->'body'->>'sha';
  if v_new_commit !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_NEW_COMMIT_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/main',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200
     or v_env->'body'->'object'->>'sha'<>v_head then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_MAIN_MOVED';
  end if;

  v_branch:='chatgpt/'||p_branch_suffix;
  v_branch_ref:='refs/heads/'||v_branch;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/refs',
    jsonb_build_object('ref',v_branch_ref,'sha',v_new_commit)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_BRANCH_CREATE_FAILED';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/pulls',
    jsonb_build_object(
      'title',btrim(p_commit_message),
      'head',v_branch,
      'base','main',
      'body',
      'Deterministic source synchronization from provider-verified production migrations.'||E'\n\n'||
      'Exact base SHA: '||v_head||E'\n'||
      'Files: '||v_files_written::text||E'\n\n'||
      'This operation does not claim merge, deployment, CI success, or release completion.'
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_PR_CREATE_FAILED';
  end if;
  v_pr:=v_env->'body';
  v_pr_no:=nullif(v_pr->>'number','')::integer;
  if v_pr_no is null or v_pr_no<1 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_PR_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/'||v_branch,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_BRANCH_READBACK_FAILED';
  end if;
  v_read_ref:=v_env->'body';

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/pulls/'||v_pr_no::text,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_PR_READBACK_FAILED';
  end if;
  v_read_pr:=v_env->'body';

  if v_read_ref->'object'->>'sha'<>v_new_commit
     or v_read_pr#>>'{head,sha}'<>v_new_commit
     or v_read_pr#>>'{base,ref}'<>'main'
     or v_read_pr->>'state'<>'open' then
    raise exception 'PANDORA_GITHUB_SOURCE_SYNC_READBACK_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok',true,
    'repository',v_repo,
    'baseSha',v_head,
    'branch',v_branch,
    'commitSha',v_new_commit,
    'pullRequest',v_pr_no,
    'pullRequestUrl',v_pr->>'html_url',
    'pullRequestState','open',
    'files',v_files_written,
    'credentialSource','supabase-vault',
    'mainMutated',false,
    'forceUpdateUsed',false
  );
end;
$function$;

revoke all on function public.pandora_github_source_sync_v1(jsonb,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_source_sync_v1(jsonb,text,text)
to service_role;

comment on function public.pandora_github_source_sync_v1(jsonb,text,text)
is 'Service-role-only deterministic GitHub source sync for canonical pandoras-box migration files. Uses the Vault-backed Github_supabase transport; never mutates main or force-updates refs.';

commit;
;
