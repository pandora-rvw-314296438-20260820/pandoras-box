
begin;

create or replace function public.pandora_github_memory_branch_add_v1(
  p_branch text,
  p_files jsonb,
  p_commit_message text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_env jsonb;
  v_head text;
  v_tree_sha text;
  v_file jsonb;
  v_path text;
  v_content text;
  v_blob_sha text;
  v_entries jsonb:='[]'::jsonb;
  v_written jsonb:='[]'::jsonb;
  v_new_tree text;
  v_new_commit text;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_MEMORY_BRANCH_ADD_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if p_branch !~ '^chatgpt/[A-Za-z0-9._/-]{6,220}$'
     or jsonb_typeof(p_files)<>'array'
     or jsonb_array_length(p_files) not between 1 and 8
     or char_length(coalesce(btrim(p_commit_message),'')) not between 5 and 200 then
    raise exception 'PANDORA_MEMORY_BRANCH_ADD_INPUT_INVALID' using errcode='22023';
  end if;

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/ref/heads/'||p_branch,null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PANDORA_MEMORY_BRANCH_ADD_REF_READ_FAILED'; end if;
  v_head:=v_env#>>'{body,object,sha}';

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/commits/'||v_head,null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PANDORA_MEMORY_BRANCH_ADD_COMMIT_READ_FAILED'; end if;
  v_tree_sha:=v_env#>>'{body,tree,sha}';

  for v_file in select value from jsonb_array_elements(p_files)
  loop
    v_path:=coalesce(v_file->>'path','');
    v_content:=coalesce(v_file->>'content','');

    if v_path !~ '^docs/capabilities/evidence/[A-Za-z0-9._-]+\.(json|md)$'
       or length(v_content) not between 1 and 250000 then
      raise exception 'PANDORA_MEMORY_BRANCH_ADD_FILE_INVALID: %',v_path using errcode='22023';
    end if;

    v_env:=private.pandora_integration_github_api_20260825(
      'POST',v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'PANDORA_MEMORY_BRANCH_ADD_BLOB_FAILED: %',v_path;
    end if;
    v_blob_sha:=v_env#>>'{body,sha}';

    v_entries:=v_entries||jsonb_build_array(
      jsonb_build_object('path',v_path,'mode','100644','type','blob','sha',v_blob_sha)
    );
    v_written:=v_written||jsonb_build_array(v_path);
  end loop;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/trees',
    jsonb_build_object('base_tree',v_tree_sha,'tree',v_entries)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_BRANCH_ADD_TREE_FAILED'; end if;
  v_new_tree:=v_env#>>'{body,sha}';

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/commits',
    jsonb_build_object('message',btrim(p_commit_message),'tree',v_new_tree,'parents',jsonb_build_array(v_head))
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_BRANCH_ADD_COMMIT_FAILED'; end if;
  v_new_commit:=v_env#>>'{body,sha}';

  v_env:=private.pandora_integration_github_api_20260825(
    'PATCH',v_prefix||'/git/refs/heads/'||p_branch,
    jsonb_build_object('sha',v_new_commit,'force',false)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_BRANCH_ADD_REF_UPDATE_FAILED'; end if;

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/ref/heads/'||p_branch,null);
  if coalesce((v_env->>'status')::integer,0)<>200 or v_env#>>'{body,object,sha}'<>v_new_commit then
    raise exception 'PANDORA_MEMORY_BRANCH_ADD_READBACK_FAILED';
  end if;

  return jsonb_build_object(
    'ok',true,'branch',p_branch,'previousSha',v_head,'commitSha',v_new_commit,
    'files',v_written,'credentialSource','supabase-vault',
    'mainMutated',false,'forceUpdateUsed',false
  );
end;
$function$;

revoke all on function public.pandora_github_memory_branch_add_v1(text,jsonb,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_memory_branch_add_v1(text,jsonb,text)
to service_role;

commit;
;
