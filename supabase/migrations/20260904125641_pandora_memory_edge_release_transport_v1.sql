
-- P5 Task17: exact signed Memory-main -> canonical Memory Edge bridge release transport.
-- Fixed scope: pandoras-box-memory / ivmvufhcsezyhczzondn / pandora-projectos-bridge only.
create or replace function private.pandora_memory_release_deploy_projectos_bridge_20260904(p_commit_sha text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','vault','extensions','public'
as $function$
declare
  v_main jsonb;
  v_git jsonb;
  v_git_deno jsonb;
  v_index text;
  v_deno text;
  v_source_sha text;
  v_deno_sha text;
  v_tree_sha text;
  v_boundary text;
  v_metadata jsonb;
  v_body text;
  v_token text;
  v_probe extensions.http_response;
  v_response extensions.http_response;
  v_response_body jsonb;
begin
  if p_commit_sha is null or p_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'exact GitHub commit SHA required' using errcode='22023';
  end if;

  v_main := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory/branches/main',
    null
  );
  if coalesce((v_main->>'status')::integer,0) <> 200 then
    raise exception 'Memory main unavailable' using errcode='55000';
  end if;
  if coalesce(v_main->'body'->'commit'->>'sha','') <> p_commit_sha then
    raise exception 'requested Memory commit is not current main' using errcode='22023';
  end if;
  if coalesce((v_main->'body'->'commit'->'commit'->'verification'->>'verified')::boolean,false) is not true then
    raise exception 'Memory main signature verification required' using errcode='22023';
  end if;
  v_tree_sha := v_main->'body'->'commit'->'commit'->'tree'->>'sha';
  if coalesce(v_tree_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'Memory main tree unavailable' using errcode='55000';
  end if;

  v_git := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory/contents/supabase/functions/pandora-projectos-bridge/index.ts?ref='||p_commit_sha,
    null
  );
  if coalesce((v_git->>'status')::integer,0) <> 200 then
    raise exception 'exact Memory bridge source unavailable' using errcode='55000';
  end if;
  begin
    v_index := convert_from(decode(replace(v_git->'body'->>'content',E'\n',''),'base64'),'utf8');
  exception when others then
    raise exception 'exact Memory bridge source decode failed' using errcode='55000';
  end;
  if nullif(v_index,'') is null or octet_length(v_index)>1048576 then
    raise exception 'exact Memory bridge source invalid' using errcode='22023';
  end if;

  v_git_deno := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory/contents/supabase/functions/pandora-projectos-bridge/deno.json?ref='||p_commit_sha,
    null
  );
  if coalesce((v_git_deno->>'status')::integer,0) <> 200 then
    raise exception 'exact Memory bridge import map unavailable' using errcode='55000';
  end if;
  begin
    v_deno := convert_from(decode(replace(v_git_deno->'body'->>'content',E'\n',''),'base64'),'utf8');
  exception when others then
    raise exception 'exact Memory bridge import map decode failed' using errcode='55000';
  end;
  if nullif(v_deno,'') is null or octet_length(v_deno)>65536 then
    raise exception 'exact Memory bridge import map invalid' using errcode='22023';
  end if;

  v_source_sha := encode(extensions.digest(convert_to(v_index,'utf8'),'sha256'),'hex');
  v_deno_sha := encode(extensions.digest(convert_to(v_deno,'utf8'),'sha256'),'hex');
  v_boundary := '----PandoraMemoryEdge'||substr(v_source_sha,1,20);
  if position(v_boundary in v_index)>0 or position(v_boundary in v_deno)>0 then
    raise exception 'multipart boundary collision' using errcode='22023';
  end if;

  v_metadata := jsonb_build_object(
    'name','pandora-projectos-bridge',
    'entrypoint_path','index.ts',
    'import_map_path','deno.json',
    'verify_jwt',false
  );
  v_body := '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'||v_metadata::text||
    E'\r\n--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\nContent-Type: application/typescript\r\n\r\n'||v_index||E'\r\n' ||
    '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="deno.json"\r\nContent-Type: application/json\r\n\r\n'||v_deno||E'\r\n' ||
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
        extensions.http_header('user-agent','Pandora-Memory-Exact-Edge-Release/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_probe.status=200;
  end loop;
  if v_probe.status is distinct from 200 or nullif(v_token,'') is null then
    v_token:=null;
    raise exception 'Supabase management credential unavailable for canonical Memory project' using errcode='55000';
  end if;

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api.supabase.com/v1/projects/ivmvufhcsezyhczzondn/functions/deploy?slug=pandora-projectos-bridge'::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','multipart/form-data; boundary='||v_boundary),
      extensions.http_header('user-agent','Pandora-Memory-Exact-Edge-Release/1.0')
    ]::extensions.http_header[],
    ('multipart/form-data; boundary='||v_boundary)::varchar,
    v_body::varchar
  )::extensions.http_request);
  if v_response.status<>201 then
    v_token:=null;
    raise exception 'Memory Edge deployment failed with status %',v_response.status using errcode='55000';
  end if;
  begin
    v_response_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_token:=null;
    raise exception 'Memory Edge deployment returned invalid JSON' using errcode='55000';
  end;
  v_token:=null;

  return jsonb_build_object(
    'deployed',true,
    'repository','pandora-rvw-314296438-20260820/pandoras-box-memory',
    'commitSha',p_commit_sha,
    'treeSha',v_tree_sha,
    'projectRef','ivmvufhcsezyhczzondn',
    'slug','pandora-projectos-bridge',
    'sourceSha256',v_source_sha,
    'denoSha256',v_deno_sha,
    'verifyJwt',false,
    'version',v_response_body->'version',
    'ezbrSha256',v_response_body->'ezbr_sha256'
  );
end;
$function$;

revoke all on function private.pandora_memory_release_deploy_projectos_bridge_20260904(text) from public,anon,authenticated;
grant execute on function private.pandora_memory_release_deploy_projectos_bridge_20260904(text) to service_role;

create or replace function public.pandora_memory_release_deploy_projectos_bridge_v1(p_commit_sha text)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','private','public'
as $wrapper$
  select private.pandora_memory_release_deploy_projectos_bridge_20260904(p_commit_sha)
$wrapper$;
revoke all on function public.pandora_memory_release_deploy_projectos_bridge_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_memory_release_deploy_projectos_bridge_v1(text) to service_role;
