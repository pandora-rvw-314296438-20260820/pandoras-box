create or replace function private.pandora_temp_memory_task94_deploy_20260903()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','vault','extensions','public'
as $function$
declare
  v_commit constant text := 'bfe88db4622a208eace9d1de025404d2d878e397';
  v_slug constant text := 'pandora-projectos-bridge';
  v_repo_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory/contents/supabase/functions/pandora-projectos-bridge/';
  v_git jsonb;
  v_git_deno jsonb;
  v_index text;
  v_deno text;
  v_source_sha text;
  v_deno_sha text;
  v_boundary text;
  v_metadata jsonb;
  v_body text;
  v_token text;
  v_probe extensions.http_response;
  v_response extensions.http_response;
  v_response_body jsonb;
begin
  v_git := private.pandora_integration_github_api_20260825(
    'GET', v_repo_prefix || 'index.ts?ref=' || v_commit, null
  );
  if coalesce((v_git->>'status')::integer,0) <> 200 then
    raise exception 'Task94 exact Memory bridge source unavailable' using errcode='55000';
  end if;
  v_index := convert_from(decode(replace(v_git->'body'->>'content',E'\n',''),'base64'),'utf8');
  if nullif(v_index,'') is null or octet_length(v_index) > 1048576 then
    raise exception 'Task94 exact Memory bridge source invalid' using errcode='22023';
  end if;
  if position('evidence_privacy_v3' in v_index)=0
     or position('raw_source_code_block' in v_index)=0
     or position('prompt_transcript' in v_index)=0
     or position('env_config_dump' in v_index)=0
     or position('raw_source_multiline' in v_index)=0 then
    raise exception 'Task94 privacy-v3 markers absent from exact Memory source' using errcode='55000';
  end if;

  v_git_deno := private.pandora_integration_github_api_20260825(
    'GET', v_repo_prefix || 'deno.json?ref=' || v_commit, null
  );
  if coalesce((v_git_deno->>'status')::integer,0) <> 200 then
    raise exception 'Task94 exact Memory bridge import map unavailable' using errcode='55000';
  end if;
  v_deno := convert_from(decode(replace(v_git_deno->'body'->>'content',E'\n',''),'base64'),'utf8');
  if nullif(v_deno,'') is null or octet_length(v_deno) > 65536 then
    raise exception 'Task94 exact Memory bridge import map invalid' using errcode='22023';
  end if;

  v_source_sha := encode(extensions.digest(convert_to(v_index,'utf8'),'sha256'),'hex');
  v_deno_sha := encode(extensions.digest(convert_to(v_deno,'utf8'),'sha256'),'hex');
  v_boundary := '----PandoraMemoryTask94' || substr(v_source_sha,1,20);
  if position(v_boundary in v_index)>0 or position(v_boundary in v_deno)>0 then
    raise exception 'Task94 multipart boundary collision' using errcode='22023';
  end if;

  v_metadata := jsonb_build_object(
    'name',v_slug,
    'entrypoint_path','index.ts',
    'import_map_path','deno.json',
    'verify_jwt',false
  );
  v_body := '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'||v_metadata::text||
    E'\r\n--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\nContent-Type: application/typescript\r\n\r\n'||v_index||E'\r\n'||
    '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="deno.json"\r\nContent-Type: application/json\r\n\r\n'||v_deno||E'\r\n'||
    '--'||v_boundary||E'--\r\n';

  for v_token in
    select decrypted_secret
    from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_probe from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/ivmvufhcsezyhczzondn'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Memory-Task94-Exact-Deploy/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_probe.status=200;
  end loop;
  if v_probe.status is distinct from 200 or nullif(v_token,'') is null then
    raise exception 'Memory Supabase management credential unavailable' using errcode='55000';
  end if;

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/ivmvufhcsezyhczzondn/functions/deploy?slug='||v_slug)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','multipart/form-data; boundary='||v_boundary),
      extensions.http_header('user-agent','Pandora-Memory-Task94-Exact-Deploy/1.0')
    ]::extensions.http_header[],
    ('multipart/form-data; boundary='||v_boundary)::varchar,
    v_body::varchar
  )::extensions.http_request);
  v_token := null;
  if v_response.status<>201 then
    raise exception 'Memory Task94 Edge deployment failed with status %',v_response.status using errcode='55000';
  end if;
  begin
    v_response_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    raise exception 'Memory Task94 Edge deployment returned invalid JSON' using errcode='55000';
  end;

  return jsonb_build_object(
    'deployed',true,
    'projectRef','ivmvufhcsezyhczzondn',
    'commitSha',v_commit,
    'slug',v_slug,
    'sourceSha256',v_source_sha,
    'importMapSha256',v_deno_sha,
    'verifyJwt',false,
    'version',v_response_body->'version',
    'ezbrSha256',v_response_body->'ezbr_sha256'
  );
end;
$function$;

revoke all on function private.pandora_temp_memory_task94_deploy_20260903() from public,anon,authenticated;
grant execute on function private.pandora_temp_memory_task94_deploy_20260903() to service_role;