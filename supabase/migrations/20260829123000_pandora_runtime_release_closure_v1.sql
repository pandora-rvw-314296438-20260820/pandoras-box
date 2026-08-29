-- Pandora runtime release closure: exact-source Edge deployment and safe provider retry facts.

create or replace function private.pandora_release_deploy_edge_from_github_20260829(
  p_commit_sha text,
  p_slug text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
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
$$;

revoke all on function private.pandora_release_deploy_edge_from_github_20260829(text,text) from public,anon,authenticated;
grant execute on function private.pandora_release_deploy_edge_from_github_20260829(text,text) to service_role;

create or replace function public.pandora_release_deploy_edge_from_github_20260829(p_commit_sha text,p_slug text)
returns jsonb
language sql
security definer
set search_path=''
as $$ select private.pandora_release_deploy_edge_from_github_20260829(p_commit_sha,p_slug); $$;
revoke all on function public.pandora_release_deploy_edge_from_github_20260829(text,text) from public,anon,authenticated;
grant execute on function public.pandora_release_deploy_edge_from_github_20260829(text,text) to service_role;

create or replace function private.pandora_worker_f_vercel_api_20260829(p_method text,p_path text,p_body jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
declare
  v_token text;
  v_team_id text;
  v_response extensions.http_response;
  v_body jsonb;
  v_method extensions.http_method;
  v_url text;
  v_base_path text;
  v_safe_headers jsonb := '{}'::jsonb;
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST','PATCH','DELETE') then raise exception 'unsupported Vercel method' using errcode='22023'; end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\\r\\n]' then raise exception 'invalid Vercel path' using errcode='22023'; end if;
  select config_value into strict v_team_id from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;
  if not (p_path ~ ('[?&]teamId='||v_team_id||'(&|$)')) then raise exception 'Vercel request is not scoped to the configured team' using errcode='22023'; end if;
  v_base_path:=split_part(p_path,'?',1);
  if not (
    (upper(p_method)='POST' and v_base_path='/v11/projects')
    or (upper(p_method)='GET' and v_base_path ~ '^/v9/projects/(prj_[A-Za-z0-9]+|[a-z0-9][a-z0-9-]{0,99})$')
    or (upper(p_method) in ('GET','POST') and v_base_path='/v13/deployments')
    or (upper(p_method)='GET' and v_base_path='/v6/deployments')
    or (upper(p_method)='GET' and v_base_path ~ '^/v13/deployments/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='PATCH' and v_base_path ~ '^/v12/deployments/dpl_[A-Za-z0-9]+/cancel$')
    or (upper(p_method)='DELETE' and v_base_path ~ '^/v13/deployments/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v10/projects/prj_[A-Za-z0-9]+/promote/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v1/projects/prj_[A-Za-z0-9]+/rollback/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v10/projects/prj_[A-Za-z0-9]+/domains$')
    or (upper(p_method)='GET' and v_base_path ~ '^/v9/projects/prj_[A-Za-z0-9]+/domains/[A-Za-z0-9.-]+$')
    or (upper(p_method)='GET' and v_base_path ~ '^/v6/domains/[A-Za-z0-9.-]+/config$')
  ) then raise exception 'Vercel path is outside Worker F runtime lane' using errcode='22023'; end if;
  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='vercel' limit 1;
  if nullif(trim(v_token),'') is null then raise exception 'Vercel provider credential unavailable' using errcode='55000'; end if;
  v_method:=upper(p_method)::extensions.http_method;
  v_url:='https://api.vercel.com'||p_path;
  select * into v_response from extensions.http((
    v_method,v_url::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.0')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin v_body:=nullif(v_response.content,'')::jsonb;
  exception when others then v_body:=case when nullif(v_response.content,'') is null then null else jsonb_build_object('raw',left(v_response.content,5000)) end; end;
  select coalesce(jsonb_object_agg(lower(h.field),h.value),'{}'::jsonb) into v_safe_headers
  from unnest(v_response.headers) h
  where lower(h.field) in ('retry-after','x-ratelimit-limit','x-ratelimit-remaining','x-ratelimit-reset');
  v_token:=null;
  return jsonb_build_object('status',v_response.status,'contentType',v_response.content_type,'headers',v_safe_headers,'body',v_body);
end;
$$;
