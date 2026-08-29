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


-- Worker D -> Worker F exact runtime-bundle persistence bridge.
create or replace function private.pandora_finalize_runtime_bundle_20260829(
  p_project_version_id uuid,
  p_build_job_id uuid,
  p_build_step_id uuid,
  p_bundle text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public','storage'
as $$
declare
  v_version public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_step public.pandora_build_job_steps%rowtype;
  v_payload jsonb;
  v_files jsonb;
  v_entry jsonb;
  v_file text;
  v_prev_file text := null;
  v_decoded bytea;
  v_file_sha text;
  v_total_bytes bigint := 0;
  v_has_index boolean := false;
  v_bundle_sha text;
  v_bundle_bytes bigint;
  v_source_kind text;
  v_source_ref text;
  v_source_commit text;
  v_storage_path text;
  v_pat text;
  v_management extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_upload extensions.http_response;
  v_readback extensions.http_response;
  v_artifact_id uuid;
  v_artifact_version_id uuid;
  v_existing_digest text;
  v_existing_root uuid;
  v_existing_artifact_version uuid;
  v_now timestamptz := clock_timestamp();
begin
  if p_project_version_id is null or p_build_job_id is null or p_build_step_id is null then
    raise exception 'exact build lineage required' using errcode='22023';
  end if;
  if p_bundle is null or octet_length(p_bundle)<2 or octet_length(p_bundle)>26214400 then
    raise exception 'runtime bundle size outside bound' using errcode='22023';
  end if;
  begin
    v_payload := p_bundle::jsonb;
  exception when others then
    raise exception 'runtime bundle JSON invalid' using errcode='22023';
  end;
  if jsonb_typeof(v_payload)<>'object'
     or v_payload->>'kind'<>'pandora.runtime-bundle.v1'
     or coalesce((v_payload->>'schemaVersion')::integer,0)<>1 then
    raise exception 'runtime bundle schema unsupported' using errcode='22023';
  end if;

  select * into v_version from public.pandora_project_versions where id=p_project_version_id for update;
  if not found then raise exception 'project version not found' using errcode='22023'; end if;
  select * into v_job from public.pandora_build_jobs where id=p_build_job_id for update;
  if not found then raise exception 'build job not found' using errcode='22023'; end if;
  select * into v_step from public.pandora_build_job_steps where id=p_build_step_id for update;
  if not found then raise exception 'build step not found' using errcode='22023'; end if;

  if v_version.organization_id<>v_job.organization_id or v_version.project_id<>v_job.project_id
     or v_step.organization_id<>v_job.organization_id or v_step.project_id<>v_job.project_id
     or v_step.build_job_id<>v_job.id
     or v_job.target_project_version_id is distinct from v_version.id
     or v_version.build_job_id is distinct from v_job.id
     or v_version.project_spec_id is distinct from v_job.project_spec_id then
    raise exception 'runtime bundle durable lineage mismatch' using errcode='22023';
  end if;
  if v_step.status<>'succeeded' then
    raise exception 'successful Worker D build step required' using errcode='22023';
  end if;
  if v_job.status not in ('claimed','running','waiting_verification','succeeded') then
    raise exception 'build job state cannot finalize runtime bundle' using errcode='22023';
  end if;
  if v_version.lifecycle_status not in ('draft','built','verification_pending','verified','preview_ready') then
    raise exception 'project version state cannot bind runtime bundle' using errcode='22023';
  end if;

  v_source_kind := v_version.source_kind;
  v_source_ref := v_version.source_ref;
  v_source_commit := v_version.source_commit;
  if v_payload->>'projectVersionId'<>v_version.id::text
     or v_payload->>'buildJobId'<>v_job.id::text
     or v_payload->>'sourceKind'<>v_source_kind
     or v_payload->>'sourceRef'<>v_source_ref
     or nullif(v_payload->>'sourceCommit','') is distinct from v_source_commit then
    raise exception 'runtime bundle source lineage mismatch' using errcode='22023';
  end if;
  if v_source_kind='git_commit' and (v_source_commit is null or v_source_ref<>v_source_commit) then
    raise exception 'git source identity invalid' using errcode='22023';
  end if;
  if v_source_kind='artifact_snapshot' and (v_source_commit is not null or v_source_ref<>v_version.id::text) then
    raise exception 'artifact snapshot identity invalid' using errcode='22023';
  end if;

  v_files := v_payload->'files';
  if jsonb_typeof(v_files)<>'array' or jsonb_array_length(v_files)<1 or jsonb_array_length(v_files)>1000 then
    raise exception 'runtime bundle files invalid' using errcode='22023';
  end if;
  for v_entry in select value from jsonb_array_elements(v_files)
  loop
    if jsonb_typeof(v_entry)<>'object' then raise exception 'runtime file invalid' using errcode='22023'; end if;
    v_file := nullif(v_entry->>'file','');
    if v_file is null or length(v_file)>512 or left(v_file,1)='/' or right(v_file,1)='/'
       or position(E'\\' in v_file)>0 or position(chr(0) in v_file)>0
       or position('?' in v_file)>0 or position('#' in v_file)>0
       or exists (select 1 from unnest(string_to_array(v_file,'/')) s where s in ('','.', '..') or length(s)>255) then
      raise exception 'runtime file path invalid' using errcode='22023';
    end if;
    if v_prev_file is not null and v_prev_file collate "C" >= v_file collate "C" then
      raise exception 'runtime files not canonical' using errcode='22023';
    end if;
    v_prev_file := v_file;
    if v_file='index.html' then v_has_index:=true; end if;
    if v_entry->>'encoding'<>'base64' or nullif(v_entry->>'data','') is null then
      raise exception 'runtime file encoding invalid' using errcode='22023';
    end if;
    begin
      v_decoded := decode(v_entry->>'data','base64');
    exception when others then
      raise exception 'runtime file base64 invalid' using errcode='22023';
    end;
    if replace(encode(v_decoded,'base64'),E'\n','')<>v_entry->>'data' then
      raise exception 'runtime file base64 noncanonical' using errcode='22023';
    end if;
    if octet_length(v_decoded)>10485760 then raise exception 'runtime file too large' using errcode='22023'; end if;
    v_total_bytes:=v_total_bytes+octet_length(v_decoded);
    if v_total_bytes>26214400 then raise exception 'runtime bundle decoded files too large' using errcode='22023'; end if;
    v_file_sha:=encode(extensions.digest(v_decoded,'sha256'),'hex');
    if v_entry->>'sha256'<>v_file_sha or coalesce((v_entry->>'byteSize')::bigint,-1)<>octet_length(v_decoded) then
      raise exception 'runtime file digest or size mismatch' using errcode='22023';
    end if;
  end loop;
  if not v_has_index then raise exception 'runtime bundle entrypoint missing' using errcode='22023'; end if;

  v_bundle_bytes:=octet_length(p_bundle);
  v_bundle_sha:=encode(extensions.digest(convert_to(p_bundle,'utf8'),'sha256'),'hex');
  v_storage_path:='runtime/'||v_version.project_id::text||'/'||v_version.id::text||'/'||v_bundle_sha||'.json';

  -- Idempotent durable replay: an existing binding must be byte-identical.
  v_existing_root:=v_version.root_artifact_version_id;
  v_existing_digest:=v_version.artifact_digest_sha256;
  if v_existing_root is not null or v_existing_digest is not null then
    if v_existing_root is null or v_existing_digest is distinct from v_bundle_sha then
      raise exception 'project version already bound to different runtime artifact' using errcode='23505';
    end if;
    select id into v_existing_artifact_version
    from public.pandora_artifact_versions
    where id=v_existing_root and organization_id=v_version.organization_id and project_id=v_version.project_id
      and content_sha256=v_bundle_sha and storage_provider='supabase_storage'
      and storage_bucket='pandora-build-artifacts' and storage_path=v_storage_path;
    if v_existing_artifact_version is null then
      raise exception 'existing runtime artifact binding drifted' using errcode='55000';
    end if;
    return jsonb_build_object('replayed',true,'projectVersionId',v_version.id,'buildJobId',v_job.id,
      'artifactVersionId',v_existing_artifact_version,'artifactDigest',v_bundle_sha,'byteSize',v_bundle_bytes,
      'storageProvider','supabase_storage','storageBucket','pandora-build-artifacts','storagePath',v_storage_path);
  end if;

  -- Resolve the control project's service-role key through Vault-held Management credentials.
  for v_pat in
    select decrypted_secret from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_management from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_pat),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Runtime-Artifact-Finalizer/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_management.status=200;
  end loop;
  if v_management.status is distinct from 200 then
    v_pat:=null;
    raise exception 'Supabase management credential unavailable for artifact persistence' using errcode='55000';
  end if;
  begin v_keys:=v_management.content::jsonb; exception when others then v_pat:=null; raise exception 'Supabase API key response invalid' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'control project service role unavailable' using errcode='55000'; end if;

  select * into v_upload from extensions.http((
    'POST'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/pandora-build-artifacts/'||v_storage_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('x-upsert','false'),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    'application/json'::varchar,p_bundle::varchar
  )::extensions.http_request);
  if v_upload.status not in (200,201,409) then
    v_service_role:=null;
    raise exception 'runtime artifact storage upload failed with status %',v_upload.status using errcode='55000';
  end if;
  select * into v_readback from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/pandora-build-artifacts/'||v_storage_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_readback.status<>200 or octet_length(coalesce(v_readback.content,''))<>v_bundle_bytes
     or encode(extensions.digest(convert_to(coalesce(v_readback.content,''),'utf8'),'sha256'),'hex')<>v_bundle_sha then
    raise exception 'runtime artifact storage readback mismatch' using errcode='55000';
  end if;

  insert into public.pandora_artifacts(organization_id,project_id,logical_key,artifact_kind)
  values(v_version.organization_id,v_version.project_id,'runtime-bundle:'||v_version.id::text,'runtime_bundle')
  on conflict(project_id,logical_key) do nothing;
  select id into v_artifact_id from public.pandora_artifacts
  where project_id=v_version.project_id and logical_key='runtime-bundle:'||v_version.id::text and artifact_kind='runtime_bundle';
  if v_artifact_id is null then raise exception 'runtime artifact logical-key collision' using errcode='23505'; end if;

  select id,content_sha256 into v_existing_artifact_version,v_existing_digest
  from public.pandora_artifact_versions where artifact_id=v_artifact_id order by version desc limit 1;
  if v_existing_artifact_version is not null then
    if v_existing_digest<>v_bundle_sha then raise exception 'runtime artifact already has different content' using errcode='23505'; end if;
    v_artifact_version_id:=v_existing_artifact_version;
  else
    insert into public.pandora_artifact_versions(
      organization_id,project_id,artifact_id,version,content_sha256,byte_size,media_type,
      storage_provider,storage_bucket,storage_path,produced_by_build_step_id,provenance_redacted
    ) values (
      v_version.organization_id,v_version.project_id,v_artifact_id,1,v_bundle_sha,v_bundle_bytes,'application/json',
      'supabase_storage','pandora-build-artifacts',v_storage_path,v_step.id,
      jsonb_strip_nulls(jsonb_build_object(
        'buildJobId',v_job.id,'buildStepId',v_step.id,'projectVersionId',v_version.id,
        'projectSpecId',v_version.project_spec_id,'sourceKind',v_source_kind,'sourceRef',v_source_ref,'sourceCommit',v_source_commit,
        'finalizedAt',v_now,'schemaVersion','pandora.runtime-bundle.v1'
      ))
    ) returning id into v_artifact_version_id;
  end if;

  update public.pandora_project_versions
  set root_artifact_version_id=v_artifact_version_id,
      artifact_digest_sha256=v_bundle_sha,
      lifecycle_status=case when lifecycle_status='draft' then 'built' else lifecycle_status end
  where id=v_version.id and root_artifact_version_id is null and artifact_digest_sha256 is null;
  if not found then raise exception 'project version artifact compare-and-set failed' using errcode='40001'; end if;

  update public.pandora_build_jobs
  set status='waiting_verification',current_stage='verifying',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,
      heartbeat_at=v_now,updated_at=v_now
  where id=v_job.id and status in ('claimed','running','waiting_verification','succeeded');
  if not found then raise exception 'build job finalization compare-and-set failed' using errcode='40001'; end if;

  return jsonb_build_object('replayed',false,'projectVersionId',v_version.id,'buildJobId',v_job.id,
    'buildStepId',v_step.id,'artifactId',v_artifact_id,'artifactVersionId',v_artifact_version_id,
    'artifactDigest',v_bundle_sha,'byteSize',v_bundle_bytes,'sourceKind',v_source_kind,'sourceRef',v_source_ref,
    'storageProvider','supabase_storage','storageBucket','pandora-build-artifacts','storagePath',v_storage_path,
    'verificationState','waiting_verification');
end;
$$;

revoke all on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) to service_role;

create or replace function public.pandora_finalize_runtime_bundle_20260829(
  p_project_version_id uuid,p_build_job_id uuid,p_build_step_id uuid,p_bundle text
)
returns jsonb
language sql
security definer
set search_path=''
as $$ select private.pandora_finalize_runtime_bundle_20260829(p_project_version_id,p_build_job_id,p_build_step_id,p_bundle); $$;
revoke all on function public.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) to service_role;
