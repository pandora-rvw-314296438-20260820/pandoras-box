-- Pandora Worker D static build durable-claim boundary repair.
-- Phase 1 claims commit on one scheduler tick; Phase 2 external storage authorization/readback occurs only on a later tick.
-- Existing authorization, source/version binding, lease, idempotency and Worker-E verification contracts are preserved.

CREATE OR REPLACE FUNCTION private.pandora_worker_d_finalize_static_web_20260830(p_build_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public', 'storage'
AS $function$
declare
  v_job public.pandora_build_jobs%rowtype;
  v_version public.pandora_project_versions%rowtype;
  v_source public.pandora_artifact_versions%rowtype;
  v_source_artifact public.pandora_artifacts%rowtype;
  v_claim public.pandora_build_jobs%rowtype;
  v_lease_sha text;
  v_pat text;
  v_management extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_readback extensions.http_response;
  v_source_text text;
  v_payload jsonb;
  v_files jsonb;
  v_sorted_files jsonb;
  v_entry jsonb;
  v_prev_file text := null;
  v_file text;
  v_decoded bytea;
  v_file_sha text;
  v_total_bytes bigint := 0;
  v_has_index boolean := false;
  v_runtime jsonb;
  v_runtime_text text;
  v_runtime_sha text;
  v_step_id uuid;
  v_finalized jsonb;
begin
  if p_build_job_id is null then
    raise exception 'STATIC_BUILD_JOB_REQUIRED' using errcode='22023';
  end if;

  select * into v_job from public.pandora_build_jobs where id=p_build_job_id for update;
  if not found or v_job.job_kind<>'build' or v_job.status not in ('queued','claimed','running') or v_job.target_project_version_id is null then
    raise exception 'STATIC_BUILD_JOB_NOT_QUEUED' using errcode='55000';
  end if;

  select * into v_version from public.pandora_project_versions
  where id=v_job.target_project_version_id
    and organization_id=v_job.organization_id
    and project_id=v_job.project_id
    and project_spec_id=v_job.project_spec_id
    and build_job_id=v_job.id
  for update;
  if not found
     or v_version.lifecycle_status<>'draft'
     or v_version.source_kind<>'artifact_snapshot'
     or v_version.source_ref<>v_version.id::text
     or v_version.source_commit is not null
     or v_version.root_artifact_version_id is null
     or v_version.artifact_digest_sha256 is not null
     or coalesce(v_version.source_payload->>'buildAdapter','')<>'static-web' then
    raise exception 'STATIC_BUILD_VERSION_INVALID' using errcode='23514';
  end if;

  select * into v_source from public.pandora_artifact_versions
  where id=v_version.root_artifact_version_id
    and organization_id=v_job.organization_id
    and project_id=v_job.project_id;
  if not found
     or v_source.content_sha256 is distinct from v_version.source_sha256
     or v_source.storage_provider<>'supabase_storage'
     or v_source.storage_bucket<>'pandora-build-artifacts'
     or v_source.byte_size<=0
     or v_source.byte_size>26214400 then
    raise exception 'STATIC_BUILD_SOURCE_INVALID' using errcode='23514';
  end if;
  select * into v_source_artifact from public.pandora_artifacts where id=v_source.artifact_id;
  if not found or v_source_artifact.artifact_kind<>'source_snapshot'
     or v_source_artifact.organization_id<>v_job.organization_id
     or v_source_artifact.project_id<>v_job.project_id then
    raise exception 'STATIC_BUILD_SOURCE_ARTIFACT_INVALID' using errcode='23514';
  end if;

  if v_job.status='queued' then
    v_lease_sha:=encode(extensions.digest(convert_to('pandora-worker-d-static-web|'||v_job.id::text||'|'||gen_random_uuid()::text,'utf8'),'sha256'),'hex');
    v_claim:=private.pandora_claim_build_job(v_job.id,'pandora-worker-d-static-web',v_lease_sha,300);
    if v_claim.status<>'claimed' or v_claim.target_project_version_id is distinct from v_version.id then
      raise exception 'STATIC_BUILD_CLAIM_FAILED' using errcode='55000';
    end if;
    return jsonb_build_object('state','claimed','buildJobId',v_claim.id,'projectVersionId',v_version.id,'workerIdentity',v_claim.worker_identity,'leaseExpiresAt',v_claim.lease_expires_at);
  end if;

  if v_job.status not in ('claimed','running')
     or v_job.worker_identity is distinct from 'pandora-worker-d-static-web'
     or v_job.lease_owner is distinct from 'pandora-worker-d-static-web'
     or v_job.lease_token_sha256 !~ '^[0-9a-f]{64}$'
     or v_job.lease_expires_at is null
     or v_job.lease_expires_at<=clock_timestamp() then
    raise exception 'STATIC_BUILD_LEASE_INVALID' using errcode='40001';
  end if;

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
        extensions.http_header('user-agent','Pandora-Worker-D-Static-Web/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_management.status=200;
  end loop;
  if v_management.status is distinct from 200 then
    v_pat:=null;
    raise exception 'STATIC_BUILD_STORAGE_AUTH_UNAVAILABLE' using errcode='55000';
  end if;
  begin
    v_keys:=v_management.content::jsonb;
  exception when others then
    v_pat:=null;
    raise exception 'STATIC_BUILD_STORAGE_AUTH_INVALID' using errcode='55000';
  end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then
    raise exception 'STATIC_BUILD_SERVICE_ROLE_UNAVAILABLE' using errcode='55000';
  end if;

  select * into v_readback from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/pandora-build-artifacts/'||v_source.storage_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_readback.status<>200
     or octet_length(coalesce(v_readback.content,''))<>v_source.byte_size
     or encode(extensions.digest(convert_to(coalesce(v_readback.content,''),'utf8'),'sha256'),'hex')<>v_source.content_sha256 then
    raise exception 'STATIC_BUILD_SOURCE_READBACK_MISMATCH' using errcode='55000';
  end if;

  v_source_text:=v_readback.content;
  begin
    v_payload:=v_source_text::jsonb;
  exception when others then
    raise exception 'STATIC_BUILD_SOURCE_JSON_INVALID' using errcode='22023';
  end;
  if jsonb_typeof(v_payload)<>'object'
     or v_payload->>'kind'<>'pandora.source-bundle.v1'
     or coalesce((v_payload->>'schemaVersion')::integer,0)<>1
     or v_payload->>'projectSpecId'<>v_job.project_spec_id::text
     or v_payload->>'buildAdapter'<>'static-web' then
    raise exception 'STATIC_BUILD_SOURCE_SCHEMA_INVALID' using errcode='22023';
  end if;

  v_files:=v_payload->'files';
  if jsonb_typeof(v_files)<>'array' or jsonb_array_length(v_files)<1 or jsonb_array_length(v_files)>120 then
    raise exception 'STATIC_BUILD_FILES_INVALID' using errcode='22023';
  end if;

  select jsonb_agg(value order by (value->>'file') collate "C") into v_sorted_files
  from jsonb_array_elements(v_files);
  for v_entry in select value from jsonb_array_elements(v_sorted_files)
  loop
    if jsonb_typeof(v_entry)<>'object' then raise exception 'STATIC_BUILD_FILE_INVALID' using errcode='22023'; end if;
    v_file:=nullif(v_entry->>'file','');
    if v_file is null or length(v_file)>512 or left(v_file,1)='/' or right(v_file,1)='/'
       or position(E'\\' in v_file)>0 or position('?' in v_file)>0 or position('#' in v_file)>0
       or exists(select 1 from unnest(string_to_array(v_file,'/')) seg(part) where part in ('','.', '..') or length(part)>255) then
      raise exception 'STATIC_BUILD_FILE_PATH_INVALID' using errcode='22023';
    end if;
    if v_prev_file is not null and v_prev_file collate "C" >= v_file collate "C" then
      raise exception 'STATIC_BUILD_FILES_NOT_CANONICAL' using errcode='22023';
    end if;
    v_prev_file:=v_file;
    if v_file='index.html' then v_has_index:=true; end if;
    if v_entry->>'encoding'<>'base64' or nullif(v_entry->>'data','') is null then
      raise exception 'STATIC_BUILD_FILE_ENCODING_INVALID' using errcode='22023';
    end if;
    begin
      v_decoded:=decode(v_entry->>'data','base64');
    exception when others then
      raise exception 'STATIC_BUILD_FILE_BASE64_INVALID' using errcode='22023';
    end;
    if octet_length(v_decoded)>10485760 then raise exception 'STATIC_BUILD_FILE_TOO_LARGE' using errcode='22023'; end if;
    v_total_bytes:=v_total_bytes+octet_length(v_decoded);
    if v_total_bytes>26214400 then raise exception 'STATIC_BUILD_OUTPUT_TOO_LARGE' using errcode='22023'; end if;
    v_file_sha:=encode(extensions.digest(v_decoded,'sha256'),'hex');
    if v_entry->>'sha256'<>v_file_sha or coalesce((v_entry->>'byteSize')::bigint,-1)<>octet_length(v_decoded) then
      raise exception 'STATIC_BUILD_FILE_DIGEST_MISMATCH' using errcode='22023';
    end if;
  end loop;
  if not v_has_index then raise exception 'STATIC_BUILD_ENTRYPOINT_MISSING' using errcode='22023'; end if;

  v_runtime:=jsonb_build_object(
    'kind','pandora.runtime-bundle.v1',
    'schemaVersion',1,
    'projectVersionId',v_version.id,
    'buildJobId',v_job.id,
    'sourceKind',v_version.source_kind,
    'sourceRef',v_version.source_ref,
    'sourceCommit',v_version.source_commit,
    'files',v_sorted_files
  );
  v_runtime_text:=v_runtime::text;
  v_runtime_sha:=encode(extensions.digest(convert_to(v_runtime_text,'utf8'),'sha256'),'hex');

  insert into public.pandora_build_job_steps(
    organization_id,project_id,build_job_id,step_key,sequence,step_kind,status,
    idempotency_key,attempt_count,max_attempts,input_sha256,result_sha256,started_at,completed_at
  ) values (
    v_job.organization_id,v_job.project_id,v_job.id,'static_web_package',1,'build','succeeded',
    v_job.idempotency_key||':static-web-package',1,1,v_source.content_sha256,v_runtime_sha,now(),now()
  ) returning id into v_step_id;

  v_finalized:=private.pandora_finalize_runtime_bundle_20260829(v_version.id,v_job.id,v_step_id,v_runtime_text);
  return jsonb_build_object(
    'state','waiting_verification',
    'buildJobId',v_job.id,
    'projectVersionId',v_version.id,
    'buildStepId',v_step_id,
    'sourceSha256',v_source.content_sha256,
    'runtimeBundleSha256',v_runtime_sha,
    'finalization',v_finalized
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.pandora_converge_static_site_build_20260830(p_build_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
declare
  v_job public.pandora_build_jobs%rowtype;
  v_version public.pandora_project_versions%rowtype;
  v_dep public.pandora_project_deployments%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_provider jsonb;
  v_body jsonb;
  v_state text;
  v_team text;
  v_key text;
  v_verification jsonb;
  v_worker_d jsonb;
  v_run_id uuid;
  v_now timestamptz;
begin
  select * into v_job from public.pandora_build_jobs where id=p_build_job_id;
  if not found or v_job.job_kind<>'build' or v_job.target_project_version_id is null then
    raise exception 'STATIC_CONVERGENCE_JOB_INVALID' using errcode='22023';
  end if;
  select * into v_version from public.pandora_project_versions
   where id=v_job.target_project_version_id and organization_id=v_job.organization_id and project_id=v_job.project_id;
  if not found or coalesce(v_version.source_payload->>'buildAdapter','')<>'static-web' then
    raise exception 'STATIC_CONVERGENCE_ADAPTER_INVALID' using errcode='22023';
  end if;
  if v_job.status='succeeded' and v_version.lifecycle_status in ('verified','preview_ready','live') then
    return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','ready','replayed',true);
  end if;
  if v_job.status in ('queued','claimed','running') and v_version.artifact_digest_sha256 is null then
    v_worker_d:=private.pandora_worker_d_finalize_static_web_20260830(v_job.id);
    if coalesce(v_worker_d->>'state','')='claimed' then
      return v_worker_d;
    end if;
  elsif v_job.status not in ('claimed','running','waiting_verification') then
    return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state',v_job.status);
  end if;

  select * into v_job from public.pandora_build_jobs where id=p_build_job_id;
  select * into v_version from public.pandora_project_versions where id=v_job.target_project_version_id;
  if v_version.root_artifact_version_id is null or v_version.artifact_digest_sha256 is null
     or v_version.lifecycle_status not in ('built','verification_pending','verified','preview_ready') then
    raise exception 'STATIC_CONVERGENCE_RUNTIME_ARTIFACT_MISSING' using errcode='55000';
  end if;

  select * into v_dep from public.pandora_project_deployments
   where organization_id=v_job.organization_id and project_id=v_job.project_id and version_id=v_version.id and environment='preview'
   order by created_at desc limit 1;
  if not found then
    select * into v_op from public.pandora_runtime_operations
     where organization_id=v_job.organization_id and project_id=v_job.project_id and project_version_id=v_version.id and action='create_preview'
     order by created_at desc limit 1;
    if not found then
      v_key:=encode(extensions.digest(convert_to('static-auto-preview|'||v_job.organization_id::text||'|'||v_job.project_id::text||'|'||v_version.id::text||'|'||v_version.artifact_digest_sha256,'utf8'),'sha256'),'hex');
      insert into public.pandora_runtime_operations(
        idempotency_key,action,organization_id,project_id,project_version_id,environment,provider,authorization_ref,status
      ) values (
        v_key,'create_preview',v_job.organization_id,v_job.project_id,v_version.id,'preview','vercel','owner:'||v_job.requested_by::text,'claimed'
      ) returning * into v_op;
    elsif v_op.status='succeeded' then
      update public.pandora_runtime_operations set status='claimed',ambiguous=false,normalized_error='{}'::jsonb,finished_at=null,updated_at=clock_timestamp()
       where id=v_op.id returning * into v_op;
    end if;
    perform private.pandora_worker_f_resume_exact_preview_20260830(v_job.project_id,v_version.id,v_op.id);
    select * into v_dep from public.pandora_project_deployments
     where organization_id=v_job.organization_id and project_id=v_job.project_id and version_id=v_version.id and environment='preview'
     order by created_at desc limit 1;
    if not found then return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','previewing'); end if;
  end if;

  if upper(coalesce(v_dep.provider_state,''))<>'READY' then
    select config_value into strict v_team from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;
    v_provider:=private.pandora_worker_f_vercel_api_20260829('GET','/v13/deployments/'||v_dep.provider_deployment_id||'?teamId='||v_team,null);
    v_body:=coalesce(v_provider->'body','{}'::jsonb);
    v_state:=upper(coalesce(v_body->>'readyState',v_body->>'status',''));
    v_now:=clock_timestamp();
    if coalesce((v_provider->>'status')::integer,0)=200 and v_state='READY' then
      update public.pandora_project_deployments
         set provider_state='READY',status='ready_for_verification',verification_state='ready_for_verification',
             ready_at=coalesce(ready_at,v_now),failed_at=null,last_provider_check_at=v_now,updated_at=v_now
       where id=v_dep.id returning * into v_dep;
      update public.pandora_runtime_environments
         set status='ready',verification_state='ready_for_verification',last_reconciled_at=v_now,updated_at=v_now
       where organization_id=v_job.organization_id and project_id=v_job.project_id and environment='preview' and current_deployment_id=v_dep.id;
      update public.projectos_projects
         set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||
           jsonb_build_object('stage','preview_ready','runtimeStatus','verifying','previewUrl',v_dep.url,'previewVersionId',v_version.id::text,
             'previewDeploymentId',v_dep.provider_deployment_id,'previewVerificationState','ready_for_verification','runtimeUpdatedAt',v_now),true),updated_at=v_now
       where id=v_job.project_id;
    elsif v_state in ('ERROR','CANCELED') then
      update public.pandora_project_deployments set provider_state=v_state,status='failed',verification_state='failed',failed_at=v_now,last_provider_check_at=v_now,updated_at=v_now where id=v_dep.id;
      update public.pandora_build_job_attempts set status='failed',finished_at=coalesce(finished_at,v_now),failure_class='runtime' where build_job_id=v_job.id and status='running';
      update public.pandora_build_jobs set status='failed',current_stage='failed',completed_at=v_now,error_code='PREVIEW_RUNTIME_FAILED',public_error_summary='Pandora could not prepare the exact preview.',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,updated_at=v_now where id=v_job.id and status not in ('succeeded','failed','cancelled');
      return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','blocked','stage','preview');
    else
      return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','working','stage','previewing','providerState',v_state);
    end if;
  end if;

  v_verification:=private.pandora_worker_e_verify_runtime_20260829(v_dep.id,'static_site',v_job.requested_by);
  if upper(coalesce(v_verification->>'status',''))='PASS' then
    v_run_id:=(v_verification->>'verificationRunId')::uuid;
    v_now:=clock_timestamp();
    update public.pandora_project_deployments set status='ready',verification_state='live_verified',last_provider_check_at=v_now,updated_at=v_now where id=v_dep.id;
    update public.pandora_runtime_environments set status='ready',verification_state='live_verified',last_reconciled_at=v_now,updated_at=v_now
     where organization_id=v_job.organization_id and project_id=v_job.project_id and environment='preview' and current_deployment_id=v_dep.id;
    update public.projectos_projects
       set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||
         jsonb_build_object('stage','preview_ready','runtimeStatus','ready','previewUrl',v_dep.url,'previewVersionId',v_version.id::text,
           'previewDeploymentId',v_dep.provider_deployment_id,'previewVerificationState','verified','runtimeUpdatedAt',v_now),true),updated_at=v_now
     where id=v_job.project_id;
    perform private.pandora_close_verified_static_build_20260830(v_job.id,v_run_id);
    return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','ready','previewUrl',v_dep.url,'verificationRunId',v_run_id);
  end if;

  v_now:=clock_timestamp();
  update public.pandora_build_job_attempts set status='failed',finished_at=coalesce(finished_at,v_now),failure_class='verification' where build_job_id=v_job.id and status='running';
  update public.pandora_build_jobs set status='failed',current_stage='failed',completed_at=v_now,error_code='VERIFICATION_FAILED',public_error_summary='Pandora found something to resolve before this version can be published.',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,updated_at=v_now where id=v_job.id and status not in ('succeeded','failed','cancelled');
  return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_version.id,'state','blocked','stage','verification','verificationRunId',v_verification->>'verificationRunId');
end;
$function$;