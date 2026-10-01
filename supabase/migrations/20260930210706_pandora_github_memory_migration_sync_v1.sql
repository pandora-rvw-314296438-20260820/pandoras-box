
begin;

create or replace function public.pandora_github_memory_migration_sync_v1(
  p_path text,
  p_content text,
  p_commit_message text,
  p_branch_suffix text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_env jsonb;
  v_base_sha text;
  v_base_tree text;
  v_blob_sha text;
  v_tree_sha text;
  v_commit_sha text;
  v_branch text;
  v_pr_no integer;
  v_pr jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_MEMORY_SOURCE_SYNC_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if p_path !~ '^supabase/migrations/[0-9]{14}_[a-z0-9_]+\.sql$'
     or length(coalesce(p_content,'')) not between 1 and 500000
     or p_branch_suffix !~ '^[a-z0-9][a-z0-9._-]{5,100}$'
     or length(coalesce(btrim(p_commit_message),'')) not between 5 and 200 then
    raise exception 'PANDORA_MEMORY_SOURCE_SYNC_INPUT_INVALID' using errcode='22023';
  end if;

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/ref/heads/main',null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_MAIN_READ_FAILED'; end if;
  v_base_sha:=v_env#>>'{body,object,sha}';

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/git/commits/'||v_base_sha,null);
  if coalesce((v_env->>'status')::integer,0)<>200 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_COMMIT_READ_FAILED'; end if;
  v_base_tree:=v_env#>>'{body,tree,sha}';

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/blobs',jsonb_build_object('content',p_content,'encoding','utf-8')
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_BLOB_FAILED'; end if;
  v_blob_sha:=v_env#>>'{body,sha}';

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/trees',
    jsonb_build_object(
      'base_tree',v_base_tree,
      'tree',jsonb_build_array(jsonb_build_object('path',p_path,'mode','100644','type','blob','sha',v_blob_sha))
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_TREE_FAILED'; end if;
  v_tree_sha:=v_env#>>'{body,sha}';

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/commits',
    jsonb_build_object('message',btrim(p_commit_message),'tree',v_tree_sha,'parents',jsonb_build_array(v_base_sha))
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_COMMIT_FAILED'; end if;
  v_commit_sha:=v_env#>>'{body,sha}';

  v_branch:='chatgpt/'||p_branch_suffix;
  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/refs',jsonb_build_object('ref','refs/heads/'||v_branch,'sha',v_commit_sha)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_BRANCH_FAILED'; end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/pulls',
    jsonb_build_object(
      'title',btrim(p_commit_message),
      'head',v_branch,
      'base','main',
      'body','Provider-verified Memory source synchronization. Exact base: '||v_base_sha||
             E'\nFile: '||p_path||
             E'\nNo main mutation, force update, approval authority, or execution authority is introduced.'
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then raise exception 'PANDORA_MEMORY_SOURCE_SYNC_PR_FAILED'; end if;
  v_pr:=v_env->'body';
  v_pr_no=nullif(v_pr->>'number','')::integer;

  v_env:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/pulls/'||v_pr_no::text,null);
  if coalesce((v_env->>'status')::integer,0)<>200
     or v_env#>>'{body,head,sha}'<>v_commit_sha
     or v_env#>>'{body,base,ref}'<>'main'
     or v_env#>>'{body,state}'<>'open' then
    raise exception 'PANDORA_MEMORY_SOURCE_SYNC_READBACK_FAILED';
  end if;

  return jsonb_build_object(
    'ok',true,'repository','pandora-rvw-314296438-20260820/pandoras-box-memory',
    'baseSha',v_base_sha,'branch',v_branch,'commitSha',v_commit_sha,
    'pullRequest',v_pr_no,'pullRequestUrl',v_pr->>'html_url',
    'credentialSource','supabase-vault','mainMutated',false,'forceUpdateUsed',false
  );
end;
$function$;

revoke all on function public.pandora_github_memory_migration_sync_v1(text,text,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_memory_migration_sync_v1(text,text,text,text)
to service_role;

commit;
;
