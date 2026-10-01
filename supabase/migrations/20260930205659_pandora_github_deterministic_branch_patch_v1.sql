
begin;

create or replace function public.pandora_github_branch_replace_v1(
  p_branch text,
  p_replacements jsonb,
  p_new_files jsonb,
  p_commit_message text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box';
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_env jsonb;
  v_ref jsonb;
  v_head text;
  v_commit jsonb;
  v_tree_sha text;
  v_tree jsonb;
  v_change jsonb;
  v_path text;
  v_old text;
  v_new text;
  v_blob_sha text;
  v_blob jsonb;
  v_content text;
  v_occurrences integer;
  v_tree_entries jsonb:='[]'::jsonb;
  v_new_tree text;
  v_new_commit text;
  v_written jsonb:='[]'::jsonb;
  v_readback jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if p_branch !~ '^chatgpt/[A-Za-z0-9._/-]{6,220}$'
     or char_length(coalesce(btrim(p_commit_message),'')) not between 5 and 200
     or jsonb_typeof(coalesce(p_replacements,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_new_files,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_replacements,'[]'::jsonb))>16
     or jsonb_array_length(coalesce(p_new_files,'[]'::jsonb))>8
     or jsonb_array_length(coalesce(p_replacements,'[]'::jsonb))
        + jsonb_array_length(coalesce(p_new_files,'[]'::jsonb))<1 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_INPUT_INVALID' using errcode='22023';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/'||p_branch,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_REF_READ_FAILED';
  end if;
  v_ref:=v_env->'body';
  v_head:=v_ref->'object'->>'sha';
  if v_head !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_HEAD_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/commits/'||v_head,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_COMMIT_READ_FAILED';
  end if;
  v_commit:=v_env->'body';
  v_tree_sha:=v_commit->'tree'->>'sha';
  if v_tree_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_TREE_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/trees/'||v_tree_sha||'?recursive=1',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_TREE_READ_FAILED';
  end if;
  v_tree:=v_env->'body';

  for v_change in select value from jsonb_array_elements(coalesce(p_replacements,'[]'::jsonb))
  loop
    v_path:=coalesce(v_change->>'path','');
    v_old:=v_change->>'old';
    v_new:=v_change->>'new';

    if v_path not in (
      'test/audit-final-migration-order.test.js',
      'scripts/replay-supabase-migrations.mjs',
      '.gitleaks.toml'
    )
       or coalesce(v_old,'')=''
       or v_new is null
       or length(v_old)>30000
       or length(v_new)>50000 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_CHANGE_INVALID: %',v_path using errcode='22023';
    end if;

    select e->>'sha' into v_blob_sha
    from jsonb_array_elements(coalesce(v_tree->'tree','[]'::jsonb)) e
    where e->>'type'='blob' and e->>'path'=v_path
    limit 1;
    if v_blob_sha !~ '^[0-9a-f]{40}$' then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_TARGET_MISSING: %',v_path;
    end if;

    v_env:=private.pandora_integration_github_api_20260825(
      'GET',v_prefix||'/git/blobs/'||v_blob_sha,null
    );
    if coalesce((v_env->>'status')::integer,0)<>200 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_BLOB_READ_FAILED: %',v_path;
    end if;
    v_blob:=v_env->'body';
    if v_blob->>'encoding'<>'base64' then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_ENCODING_INVALID: %',v_path;
    end if;
    v_content:=convert_from(
      decode(regexp_replace(coalesce(v_blob->>'content',''),'[[:space:]]','','g'),'base64'),
      'UTF8'
    );

    v_occurrences:=(length(v_content)-length(replace(v_content,v_old,'')))/greatest(length(v_old),1);
    if v_occurrences<>1 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_NOT_UNIQUE: % count=%',v_path,v_occurrences;
    end if;
    v_content:=replace(v_content,v_old,v_new);

    v_env:=private.pandora_integration_github_api_20260825(
      'POST',v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_BLOB_WRITE_FAILED: %',v_path;
    end if;
    v_blob_sha:=v_env->'body'->>'sha';
    v_tree_entries:=v_tree_entries||jsonb_build_array(
      jsonb_build_object('path',v_path,'mode','100644','type','blob','sha',v_blob_sha)
    );
    v_written:=v_written||jsonb_build_array(v_path);
  end loop;

  for v_change in select value from jsonb_array_elements(coalesce(p_new_files,'[]'::jsonb))
  loop
    v_path:=coalesce(v_change->>'path','');
    v_content:=coalesce(v_change->>'content','');
    if not (
      v_path='.gitleaks.toml'
      or v_path ~ '^supabase/migrations/[0-9]{14}_[a-z0-9_]+\.sql$'
    )
       or length(v_content) not between 1 and 500000 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_NEW_FILE_INVALID: %',v_path using errcode='22023';
    end if;

    v_env:=private.pandora_integration_github_api_20260825(
      'POST',v_prefix||'/git/blobs',
      jsonb_build_object('content',v_content,'encoding','utf-8')
    );
    if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
      raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_NEW_BLOB_FAILED: %',v_path;
    end if;
    v_blob_sha:=v_env->'body'->>'sha';
    v_tree_entries:=v_tree_entries||jsonb_build_array(
      jsonb_build_object('path',v_path,'mode','100644','type','blob','sha',v_blob_sha)
    );
    v_written:=v_written||jsonb_build_array(v_path);
  end loop;

  if (select count(*)<>count(distinct value::text) from jsonb_array_elements(v_written)) then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_DUPLICATE_PATH';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/trees',
    jsonb_build_object('base_tree',v_tree_sha,'tree',v_tree_entries)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_TREE_WRITE_FAILED';
  end if;
  v_new_tree:=v_env->'body'->>'sha';

  v_env:=private.pandora_integration_github_api_20260825(
    'POST',v_prefix||'/git/commits',
    jsonb_build_object(
      'message',btrim(p_commit_message),
      'tree',v_new_tree,
      'parents',jsonb_build_array(v_head)
    )
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_COMMIT_WRITE_FAILED';
  end if;
  v_new_commit:=v_env->'body'->>'sha';

  v_env:=private.pandora_integration_github_api_20260825(
    'PATCH',v_prefix||'/git/refs/heads/'||p_branch,
    jsonb_build_object('sha',v_new_commit,'force',false)
  );
  if coalesce((v_env->>'status')::integer,0) not between 200 and 299 then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_REF_UPDATE_FAILED';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/'||p_branch,null
  );
  if coalesce((v_env->>'status')::integer,0)<>200
     or v_env->'body'->'object'->>'sha'<>v_new_commit then
    raise exception 'PANDORA_GITHUB_BRANCH_REPLACE_READBACK_FAILED';
  end if;
  v_readback:=v_env->'body';

  return jsonb_build_object(
    'ok',true,
    'branch',p_branch,
    'previousSha',v_head,
    'commitSha',v_new_commit,
    'files',v_written,
    'credentialSource','supabase-vault',
    'forceUpdateUsed',false,
    'mainMutated',false
  );
end;
$function$;

revoke all on function public.pandora_github_branch_replace_v1(text,jsonb,jsonb,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_branch_replace_v1(text,jsonb,jsonb,text)
to service_role;

comment on function public.pandora_github_branch_replace_v1(text,jsonb,jsonb,text)
is 'Deterministic exact-snippet protected-branch patcher for closeout CI/source repairs. Uses Supabase Vault GitHub transport, never main and never force update.';

commit;
;
