-- Pandora Worker F safe first-preview bootstrap and exact preview recovery.
-- Vercel assigns the first no-Git deployment to Production; Pandora creates a non-customer baseline first, then fail-closes if the customer deployment is still Production.

drop function if exists public.pandora_worker_f_ensure_preview_environment_20260830(text);
drop function if exists private.pandora_worker_f_ensure_preview_environment_20260830(text);

CREATE OR REPLACE FUNCTION private.pandora_worker_f_resume_exact_preview_20260830(p_project_id uuid, p_version_id uuid, p_operation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_ver public.pandora_project_versions%rowtype;
  v_art public.pandora_artifact_versions%rowtype;
  v_project public.projectos_projects%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_team text;
  v_provider_project_id text;
  v_provider_project_name text;
  v_pat text;
  v_keys_response extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_object extensions.http_response;
  v_bundle jsonb;
  v_files jsonb;
  v_provider jsonb;
  v_body jsonb;
  v_status integer;
  v_provider_deployment_id text;
  v_provider_state text;
  v_provider_target text;
  v_url text;
  v_now timestamptz:=clock_timestamp();
  v_dep_id uuid;
  v_verification_state text;
  v_deployment_status text;
  v_journey jsonb;
begin
  select * into v_ver from public.pandora_project_versions where id=p_version_id and project_id=p_project_id;
  if not found or v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null or v_ver.build_job_id is null or v_ver.project_spec_id is null then raise exception 'exact built version required' using errcode='22023'; end if;
  if v_ver.lifecycle_status not in ('built','verification_pending','verified','preview_ready') then raise exception 'version is not preview eligible' using errcode='22023'; end if;
  select * into v_art from public.pandora_artifact_versions where id=v_ver.root_artifact_version_id and project_id=p_project_id and organization_id=v_ver.organization_id;
  if not found or v_art.storage_provider<>'supabase_storage' or v_art.storage_bucket<>'pandora-build-artifacts' or v_art.content_sha256<>v_ver.artifact_digest_sha256 then raise exception 'runtime artifact identity mismatch' using errcode='22023'; end if;
  select * into v_project from public.projectos_projects where id=p_project_id and organization_id=v_ver.organization_id;
  if not found then raise exception 'project unavailable' using errcode='22023'; end if;
  select * into v_op from public.pandora_runtime_operations where id=p_operation_id and project_id=p_project_id and project_version_id=p_version_id and action='create_preview' for update;
  if not found or v_op.status not in ('failed','claimed','running') then raise exception 'preview operation is not resumable' using errcode='22023'; end if;
  if exists(select 1 from public.pandora_project_deployments where project_id=p_project_id and version_id=p_version_id and environment='preview') then raise exception 'preview already exists' using errcode='23505'; end if;

  v_journey:=coalesce(v_project.config->'customerJourney','{}'::jsonb);
  v_provider_project_id:=coalesce(v_journey->>'vercelProjectId','');
  v_provider_project_name:=coalesce(v_journey->>'vercelProjectName','');
  if v_provider_project_id !~ '^prj_[A-Za-z0-9]+$' or v_provider_project_name='' then raise exception 'Vercel project unavailable' using errcode='22023'; end if;
  select config_value into strict v_team from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;

  for v_pat in select decrypted_secret from vault.decrypted_secrets where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat') order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end loop
    select * into v_keys_response from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[extensions.http_header('authorization','Bearer '||v_pat),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Worker-F-Resume/1.0')]::extensions.http_header[],null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_keys_response.status=200;
  end loop;
  if v_keys_response.status is distinct from 200 then v_pat:=null; raise exception 'artifact credential unavailable' using errcode='55000'; end if;
  begin v_keys:=v_keys_response.content::jsonb; exception when others then v_pat:=null; raise exception 'key response invalid' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'storage credential unavailable' using errcode='55000'; end if;

  select * into v_object from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/'||v_art.storage_bucket||'/'||v_art.storage_path)::varchar,
    array[extensions.http_header('authorization','Bearer '||v_service_role),extensions.http_header('apikey',v_service_role),extensions.http_header('cache-control','no-store')]::extensions.http_header[],null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_object.status<>200 or octet_length(coalesce(v_object.content,''))<>v_art.byte_size or encode(extensions.digest(convert_to(coalesce(v_object.content,''),'utf8'),'sha256'),'hex')<>v_art.content_sha256 then raise exception 'artifact readback mismatch' using errcode='22023'; end if;
  begin v_bundle:=v_object.content::jsonb; exception when others then raise exception 'runtime bundle invalid' using errcode='22023'; end;
  if v_bundle->>'kind'<>'pandora.runtime-bundle.v1' or coalesce((v_bundle->>'schemaVersion')::integer,0)<>1 or v_bundle->>'projectVersionId'<>p_version_id::text or v_bundle->>'buildJobId'<>v_ver.build_job_id::text then raise exception 'runtime bundle lineage mismatch' using errcode='22023'; end if;
  select jsonb_agg(jsonb_build_object('file',e->>'file','data',e->>'data','encoding',e->>'encoding') order by e->>'file') into v_files from jsonb_array_elements(coalesce(v_bundle->'files','[]'::jsonb)) e;
  if jsonb_typeof(v_files)<>'array' or jsonb_array_length(v_files)<1 then raise exception 'runtime bundle files missing' using errcode='22023'; end if;

  update public.pandora_runtime_operations set status='running',ambiguous=false,normalized_error='{}'::jsonb,started_at=coalesce(started_at,v_now),finished_at=null,updated_at=v_now where id=p_operation_id;
  v_provider:=private.pandora_worker_f_vercel_api_20260829('POST','/v13/deployments?teamId='||v_team,jsonb_build_object(
    'name',v_provider_project_name,
    'project',v_provider_project_id,
    'target','preview',
    'files',v_files,
    'meta',jsonb_build_object(
      'pandoraOperationId',v_op.idempotency_key,
      'pandoraProjectId',p_project_id::text,
      'pandoraProjectVersionId',p_version_id::text,
      'pandoraArtifactDigest',v_ver.artifact_digest_sha256,
      'pandoraSourceKind',v_ver.source_kind,
      'pandoraSourceRef',v_ver.source_ref,
      'pandoraAuthorizationRef',v_op.authorization_ref,
      'pandoraEnvironment','preview'
    )
  ));
  v_status:=coalesce((v_provider->>'status')::integer,0); v_body:=coalesce(v_provider->'body','{}'::jsonb);
  if v_status not in (200,201) then
    update public.pandora_runtime_operations set status=case when v_status=409 then 'uncertain' else 'failed' end,ambiguous=(v_status=409),normalized_error=jsonb_build_object('code',coalesce(v_body->'error'->>'code','provider_preview_failed'),'providerStatus',v_status),finished_at=case when v_status=409 then null else clock_timestamp() end,updated_at=clock_timestamp() where id=p_operation_id;
    return jsonb_build_object('ok',false,'providerStatus',v_status,'providerCode',coalesce(v_body->'error'->>'code','provider_preview_failed'));
  end if;

  v_provider_deployment_id:=coalesce(v_body->>'id',v_body->>'uid','');
  v_provider_state:=upper(coalesce(v_body->>'readyState',v_body->>'status','QUEUED'));
  v_provider_target:=lower(coalesce(v_body->>'target',''));
  if v_provider_deployment_id !~ '^dpl_[A-Za-z0-9]+$' or v_provider_target='production' then raise exception 'provider preview target mismatch' using errcode='22023'; end if;
  v_url:=case when coalesce(v_body->>'url','')<>'' then 'https://' || regexp_replace(v_body->>'url','^https?://','','i') else null end;
  v_verification_state:=case when v_provider_state='READY' then 'ready_for_verification' when v_provider_state in ('ERROR','CANCELED') then 'failed' else 'not_verified' end;
  v_deployment_status:=case when v_provider_state='READY' then 'ready_for_verification' when v_provider_state in ('ERROR','CANCELED') then 'failed' else lower(v_provider_state) end;

  insert into public.pandora_project_deployments(organization_id,project_id,version_id,provider,environment,provider_project_id,provider_deployment_id,url,status,source_sha256,artifact_digest,source_commit_sha,authorization_ref,idempotency_key,provider_state,immutable_url,last_provider_check_at,ready_at,failed_at,verification_state,metadata)
  values(v_ver.organization_id,p_project_id,p_version_id,'vercel','preview',v_provider_project_id,v_provider_deployment_id,v_url,v_deployment_status,v_ver.source_sha256,v_ver.artifact_digest_sha256,v_ver.source_commit,v_op.authorization_ref,v_op.idempotency_key,v_provider_state,v_url,clock_timestamp(),case when v_provider_state='READY' then clock_timestamp() else null end,case when v_provider_state in ('ERROR','CANCELED') then clock_timestamp() else null end,v_verification_state,jsonb_build_object('providerName',v_provider_project_name,'pandoraOperationId',v_op.idempotency_key,'rootArtifactVersionId',v_ver.root_artifact_version_id,'projectSpecId',v_ver.project_spec_id,'buildJobId',v_ver.build_job_id)) returning id into v_dep_id;

  insert into public.pandora_runtime_environments(organization_id,project_id,environment,provider,provider_project_id,status,current_version_id,current_deployment_id,verification_state,last_reconciled_at,updated_at)
  values(v_ver.organization_id,p_project_id,'preview','vercel',v_provider_project_id,case when v_provider_state='READY' then 'ready' when v_provider_state in ('ERROR','CANCELED') then 'failed' else 'provisioning' end,p_version_id,v_dep_id,v_verification_state,clock_timestamp(),clock_timestamp())
  on conflict(project_id,environment) do update set provider=excluded.provider,provider_project_id=excluded.provider_project_id,status=excluded.status,current_version_id=excluded.current_version_id,current_deployment_id=excluded.current_deployment_id,verification_state=excluded.verification_state,last_reconciled_at=excluded.last_reconciled_at,updated_at=excluded.updated_at;

  update public.pandora_project_versions set lifecycle_status=case when v_provider_state in ('ERROR','CANCELED') then 'rejected' else 'verification_pending' end where id=p_version_id;
  update public.projectos_projects set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object('stage',case when v_provider_state='READY' then 'preview_ready' when v_provider_state in ('ERROR','CANCELED') then 'needs_attention' else 'building' end,'runtimeStatus',case when v_provider_state='READY' then 'verifying' when v_provider_state in ('ERROR','CANCELED') then 'failed' else 'working' end,'previewUrl',v_url,'previewVersionId',p_version_id::text,'previewDeploymentId',v_provider_deployment_id,'previewVerificationState',v_verification_state,'runtimeUpdatedAt',clock_timestamp()),true),updated_at=clock_timestamp() where id=p_project_id;
  update public.pandora_runtime_operations set status=case when v_provider_state in ('ERROR','CANCELED') then 'failed' else 'succeeded' end,ambiguous=false,provider_resource_id=v_provider_deployment_id,result_facts=jsonb_build_object('projectVersionId',p_version_id,'providerDeploymentId',v_provider_deployment_id,'artifactDigest',v_ver.artifact_digest_sha256,'sourceCommit',v_ver.source_commit,'verificationState',v_verification_state),finished_at=clock_timestamp(),last_reconciled_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_operation_id;
  return jsonb_build_object('ok',true,'deploymentId',v_dep_id,'providerDeploymentId',v_provider_deployment_id,'providerState',v_provider_state,'previewUrl',v_url,'verificationState',v_verification_state);
end;
$function$;


CREATE OR REPLACE FUNCTION private.pandora_worker_f_vercel_api_20260829(p_method text, p_path text, p_body jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
  v_method extensions.http_method;
  v_url text;
  v_base_path text;
  v_safe_headers jsonb := '{}'::jsonb;
  v_team_id text;
  v_project_id text;
  v_list_response extensions.http_response;
  v_list_body jsonb;
  v_bootstrap_response extensions.http_response;
  v_bootstrap_body jsonb;
  v_actual_response extensions.http_response;
  v_actual_body jsonb;
  v_delete_response extensions.http_response;
  v_project_patch extensions.http_response;
  v_bootstrap_html text := '<!doctype html><html><head><meta charset="utf-8"><title>Pandora Preview Bootstrap</title></head><body></body></html>';
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST','PATCH','DELETE') then raise exception 'unsupported Vercel method' using errcode='22023'; end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\\r\\n]' then raise exception 'invalid Vercel path' using errcode='22023'; end if;
  select config_value into strict v_team_id from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;
  if not (p_path ~ ('[?&]teamId='||v_team_id||'(&|$)')) then raise exception 'Vercel request is not scoped to the configured team' using errcode='22023'; end if;
  v_base_path:=split_part(p_path,'?',1);
  if not (
    (upper(p_method)='POST' and v_base_path='/v11/projects')
    or (upper(p_method)='GET' and v_base_path ~ '^/v9/projects/(prj_[A-Za-z0-9]+|[a-z0-9][a-z0-9-]{0,99})$')
    or (upper(p_method)='PATCH' and v_base_path ~ '^/v9/projects/prj_[A-Za-z0-9]+$')
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

  -- Vercel assigns the first no-Git deployment to Production. Pandora's API
  -- already asks for target=preview, so translate that intent into a safe
  -- provider sequence: non-customer bootstrap first, then the exact customer
  -- bundle with no target. Fail closed if the customer deployment is still
  -- classified as Production.
  if upper(p_method)='POST' and v_base_path='/v13/deployments' and coalesce(p_body->>'target','')='preview' then
    v_project_id := coalesce(p_body->>'project','');
    if v_project_id !~ '^prj_[A-Za-z0-9]+$' then raise exception 'invalid Vercel preview project' using errcode='22023'; end if;
    if jsonb_typeof(p_body->'files') <> 'array' or jsonb_array_length(p_body->'files') < 1 then raise exception 'preview requires files' using errcode='22023'; end if;

    select * into v_list_response from extensions.http((
      'GET'::extensions.http_method,
      ('https://api.vercel.com/v6/deployments?projectId='||v_project_id||'&limit=1&teamId='||v_team_id)::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
      ]::extensions.http_header[], null::varchar, null::varchar
    )::extensions.http_request);
    begin v_list_body:=coalesce(nullif(v_list_response.content,'')::jsonb,'{}'::jsonb); exception when others then v_list_body:='{}'::jsonb; end;
    if v_list_response.status<>200 then
      v_token:=null;
      return jsonb_build_object('status',v_list_response.status,'contentType',v_list_response.content_type,'headers','{}'::jsonb,'body',v_list_body);
    end if;

    if coalesce(jsonb_array_length(coalesce(v_list_body->'deployments','[]'::jsonb)),0)=0 then
      v_bootstrap_body := jsonb_build_object(
        'name',coalesce(p_body->>'name','pandora-preview-bootstrap'),
        'project',v_project_id,
        'autoAssignCustomDomains',false,
        'files',jsonb_build_array(jsonb_build_object('file','index.html','data',encode(convert_to(v_bootstrap_html,'utf8'),'base64'),'encoding','base64')),
        'meta',jsonb_build_object('pandoraBootstrap','preview-baseline-v1','pandoraEnvironment','bootstrap')
      );
      select * into v_bootstrap_response from extensions.http((
        'POST'::extensions.http_method,
        ('https://api.vercel.com/v13/deployments?teamId='||v_team_id)::varchar,
        array[
          extensions.http_header('authorization','Bearer '||v_token),
          extensions.http_header('content-type','application/json'),
          extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
        ]::extensions.http_header[], 'application/json'::varchar, v_bootstrap_body::text::varchar
      )::extensions.http_request);
      if v_bootstrap_response.status not in (200,201) then
        begin v_body:=coalesce(nullif(v_bootstrap_response.content,'')::jsonb,'{}'::jsonb); exception when others then v_body:=jsonb_build_object('raw',left(coalesce(v_bootstrap_response.content,''),2000)); end;
        v_token:=null;
        return jsonb_build_object('status',v_bootstrap_response.status,'contentType',v_bootstrap_response.content_type,'headers','{}'::jsonb,'body',v_body);
      end if;
    end if;

    v_actual_body := (p_body - 'target') || jsonb_build_object('autoAssignCustomDomains',false);
    select * into v_actual_response from extensions.http((
      'POST'::extensions.http_method,
      ('https://api.vercel.com/v13/deployments?teamId='||v_team_id)::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('content-type','application/json'),
        extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
      ]::extensions.http_header[], 'application/json'::varchar, v_actual_body::text::varchar
    )::extensions.http_request);
    begin v_body:=coalesce(nullif(v_actual_response.content,'')::jsonb,'{}'::jsonb); exception when others then v_body:=jsonb_build_object('raw',left(coalesce(v_actual_response.content,''),5000)); end;

    if v_actual_response.status in (200,201) and lower(coalesce(v_body->>'target',''))='production' then
      if coalesce(v_body->>'id',v_body->>'uid','') ~ '^dpl_[A-Za-z0-9]+$' then
        select * into v_delete_response from extensions.http((
          'DELETE'::extensions.http_method,
          ('https://api.vercel.com/v13/deployments/'||coalesce(v_body->>'id',v_body->>'uid')||'?teamId='||v_team_id)::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_token),
            extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
          ]::extensions.http_header[], null::varchar, null::varchar
        )::extensions.http_request);
      end if;
      v_token:=null;
      return jsonb_build_object('status',409,'contentType','application/json','headers','{}'::jsonb,'body',jsonb_build_object('error',jsonb_build_object('code','preview_provider_target_mismatch','message','Vercel classified the customer preview as production; deployment was rejected.')));
    end if;

    select coalesce(jsonb_object_agg(lower(h.field),h.value),'{}'::jsonb) into v_safe_headers
    from unnest(v_actual_response.headers) h where lower(h.field) in ('retry-after','x-ratelimit-limit','x-ratelimit-remaining','x-ratelimit-reset');
    v_token:=null;
    return jsonb_build_object('status',v_actual_response.status,'contentType',v_actual_response.content_type,'headers',v_safe_headers,'body',v_body);
  end if;

  v_method:=upper(p_method)::extensions.http_method;
  v_url:='https://api.vercel.com'||p_path;
  select * into v_response from extensions.http((
    v_method,v_url::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin v_body:=nullif(v_response.content,'')::jsonb;
  exception when others then v_body:=case when nullif(v_response.content,'') is null then null else jsonb_build_object('raw',left(v_response.content,5000)) end; end;

  -- Pandora customer previews must be fetchable by Pandora/Worker E and by the
  -- customer's app. Remove Vercel Authentication/password protection on
  -- projects created through this governed broker.
  if upper(p_method)='POST' and v_base_path='/v11/projects' and v_response.status in (200,201) and coalesce(v_body->>'id','') ~ '^prj_[A-Za-z0-9]+$' then
    select * into v_project_patch from extensions.http((
      'PATCH'::extensions.http_method,
      ('https://api.vercel.com/v9/projects/'||(v_body->>'id')||'?teamId='||v_team_id)::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('content-type','application/json'),
        extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.1')
      ]::extensions.http_header[], 'application/json'::varchar,
      '{"ssoProtection":null,"passwordProtection":null}'::varchar
    )::extensions.http_request);
    if v_project_patch.status not in (200,201) then
      v_token:=null;
      return jsonb_build_object('status',503,'contentType','application/json','headers','{}'::jsonb,'body',jsonb_build_object('error',jsonb_build_object('code','preview_access_configuration_failed')));
    end if;
  end if;

  select coalesce(jsonb_object_agg(lower(h.field),h.value),'{}'::jsonb) into v_safe_headers
  from unnest(v_response.headers) h where lower(h.field) in ('retry-after','x-ratelimit-limit','x-ratelimit-remaining','x-ratelimit-reset');
  v_token:=null;
  return jsonb_build_object('status',v_response.status,'contentType',v_response.content_type,'headers',v_safe_headers,'body',v_body);
end;
$function$;


revoke all on function private.pandora_worker_f_vercel_api_20260829(text,text,jsonb) from public, anon, authenticated;
revoke all on function private.pandora_worker_f_resume_exact_preview_20260830(uuid,uuid,uuid) from public, anon, authenticated;
