-- Pandora release helper: exact source-convergence worker deployment allowlist.\n-- The worker retains verify_jwt=false because its body enforces the existing internal-key boundary.\nCREATE OR REPLACE FUNCTION private.pandora_release_deploy_edge_from_github_20260829(p_commit_sha text, p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_path text;
  v_verify_jwt boolean;
  v_import_map_path text;
  v_git jsonb;
  v_git_deno jsonb;
  v_index text;
  v_deno text := null;
  v_source_sha text;
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
  case p_slug
    when 'pandora-project-runtime' then
      v_path := 'supabase/functions/pandora-project-runtime/index.ts';
      v_verify_jwt := true;
      v_import_map_path := 'deno.json';
    when 'pandora-vercel-runtime-webhook' then
      v_path := 'supabase/functions/pandora-vercel-runtime-webhook/index.ts';
      v_verify_jwt := false;
      v_import_map_path := null;
    when 'pandora-project-source-generator' then
      v_path := 'supabase/functions/pandora-project-source-generator/index.ts';
      v_verify_jwt := true;
      v_import_map_path := null;
    when 'pandora-project-spec-compiler' then
      v_path := 'supabase/functions/pandora-project-spec-compiler/index.ts';
      v_verify_jwt := true;
      v_import_map_path := null;
    when 'pandora-source-convergence-worker' then
      v_path := 'supabase/functions/pandora-source-convergence-worker/index.ts';
      v_verify_jwt := false;
      v_import_map_path := null;
    else
      raise exception 'Edge function slug outside Pandora release allowlist' using errcode='22023';
  end case;

  v_git := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/'||v_path||'?ref='||p_commit_sha,
    null
  );
  if coalesce((v_git->>'status')::integer,0) <> 200 then
    raise exception 'exact Edge source unavailable at requested commit' using errcode='55000';
  end if;
  begin
    v_index := convert_from(decode(replace(v_git->'body'->>'content',E'\n',''),'base64'),'utf8');
  exception when others then
    raise exception 'exact Edge source decode failed' using errcode='55000';
  end;
  if nullif(v_index,'') is null or octet_length(v_index)>1048576 then
    raise exception 'exact Edge source is empty or exceeds release bound' using errcode='22023';
  end if;

  if v_import_map_path is not null then
    v_git_deno := private.pandora_integration_github_api_20260825(
      'GET',
      '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/supabase/functions/'||p_slug||'/'||v_import_map_path||'?ref='||p_commit_sha,
      null
    );
    if coalesce((v_git_deno->>'status')::integer,0) <> 200 then
      raise exception 'exact Edge import map unavailable at requested commit' using errcode='55000';
    end if;
    begin
      v_deno := convert_from(decode(replace(v_git_deno->'body'->>'content',E'\n',''),'base64'),'utf8');
    exception when others then
      raise exception 'exact Edge import map decode failed' using errcode='55000';
    end;
    if nullif(v_deno,'') is null or octet_length(v_deno)>65536 then
      raise exception 'exact Edge import map invalid' using errcode='22023';
    end if;
  end if;

  v_source_sha := encode(extensions.digest(convert_to(v_index,'utf8'),'sha256'),'hex');
  v_boundary := '----PandoraEdge'||substr(v_source_sha,1,24);
  if position(v_boundary in v_index)>0 or (v_deno is not null and position(v_boundary in v_deno)>0) then
    raise exception 'multipart boundary collision' using errcode='22023';
  end if;
  v_metadata := jsonb_strip_nulls(jsonb_build_object(
    'name',p_slug,
    'entrypoint_path','index.ts',
    'import_map_path',v_import_map_path,
    'verify_jwt',v_verify_jwt
  ));
  v_body := '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'||v_metadata::text||
    E'\r\n--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\nContent-Type: application/typescript\r\n\r\n'||v_index||E'\r\n';
  if v_deno is not null then
    v_body := v_body||'--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="deno.json"\r\nContent-Type: application/json\r\n\r\n'||v_deno||E'\r\n';
  end if;
  v_body := v_body||'--'||v_boundary||E'--\r\n';

  for v_token in
    select decrypted_secret
    from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_probe from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Exact-Edge-Release/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_probe.status=200;
  end loop;
  if v_probe.status is distinct from 200 or nullif(v_token,'') is null then
    raise exception 'Supabase management credential unavailable for Pandora project' using errcode='55000';
  end if;

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/functions/deploy?slug='||p_slug)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','multipart/form-data; boundary='||v_boundary),
      extensions.http_header('user-agent','Pandora-Exact-Edge-Release/1.0')
    ]::extensions.http_header[],
    ('multipart/form-data; boundary='||v_boundary)::varchar,
    v_body::varchar
  )::extensions.http_request);
  if v_response.status<>201 then
    v_token:=null;
    raise exception 'Supabase Edge deployment failed with status %',v_response.status using errcode='55000';
  end if;
  begin
    v_response_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_token:=null;
    raise exception 'Supabase Edge deployment returned invalid JSON' using errcode='55000';
  end;
  v_token:=null;
  return jsonb_build_object(
    'deployed',true,
    'commitSha',p_commit_sha,
    'slug',p_slug,
    'sourceSha256',v_source_sha,
    'verifyJwt',v_verify_jwt,
    'version',v_response_body->'version',
    'ezbrSha256',v_response_body->'ezbr_sha256'
  );
end;
$function$
