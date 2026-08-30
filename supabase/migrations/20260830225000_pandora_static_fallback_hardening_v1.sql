-- Pandora static fallback hardening v1.
-- Canonicalizes the live-proven Supabase preview fallback, commit-visible Worker E verification,
-- superseded-build cleanup, and generated-source artifact parent lineage.

CREATE OR REPLACE FUNCTION private.pandora_commit_generated_build_intake_20260829(p_organization_id uuid, p_project_id uuid, p_project_spec_id uuid, p_requested_by uuid, p_idempotency_key text, p_source_sha256 text, p_source_byte_size bigint, p_storage_path text, p_model_run_id uuid, p_build_adapter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_spec public.pandora_project_specs%rowtype;
  v_existing public.pandora_build_jobs%rowtype;
  v_artifact_id uuid;
  v_artifact_version_id uuid;
  v_parent_artifact_version_id uuid;
  v_project_version_id uuid := gen_random_uuid();
  v_build_job_id uuid := gen_random_uuid();
  v_artifact_version integer;
  v_parent_artifact_version integer;
  v_source_intent_id uuid;
begin
  if p_organization_id is null or p_project_id is null or p_project_spec_id is null or p_requested_by is null then
    raise exception 'BUILD_INTAKE_IDENTITY_REQUIRED' using errcode='22023';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(trim(p_idempotency_key)) > 200 then
    raise exception 'BUILD_INTAKE_IDEMPOTENCY_INVALID' using errcode='22023';
  end if;
  if p_source_sha256 !~ '^[0-9a-f]{64}$' or p_source_byte_size <= 0 or p_source_byte_size > 26214400 then
    raise exception 'BUILD_INTAKE_SOURCE_INVALID' using errcode='22023';
  end if;
  if p_storage_path is null or length(p_storage_path) > 1024 or p_storage_path ~ '(^/|\.\.|\\|\x00)' then
    raise exception 'BUILD_INTAKE_STORAGE_PATH_INVALID' using errcode='22023';
  end if;
  if p_build_adapter not in ('static-web','node-vite-web','node-next-web','flutter-web','flutter-android-apk') then
    raise exception 'BUILD_INTAKE_ADAPTER_INVALID' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || p_project_id::text, 0));

  select * into v_existing
  from public.pandora_build_jobs
  where organization_id = p_organization_id
    and project_id = p_project_id
    and idempotency_key = trim(p_idempotency_key)
  limit 1;
  if found then
    return jsonb_build_object(
      'state', case when v_existing.status = 'succeeded' then 'ready' when v_existing.status = 'failed' then 'blocked' else 'working' end,
      'buildJobId', v_existing.id,
      'projectVersionId', v_existing.target_project_version_id
    );
  end if;

  select * into v_spec
  from public.pandora_project_specs
  where id = p_project_spec_id
    and organization_id = p_organization_id
    and project_id = p_project_id
    and status = 'active'
  for share;
  if not found then raise exception 'BUILD_INTAKE_PROJECT_SPEC_STALE' using errcode='23514'; end if;
  v_source_intent_id := v_spec.source_intent_id;

  if not exists (select 1 from public.memberships where organization_id = p_organization_id and user_id = p_requested_by and status = 'active') then
    raise exception 'BUILD_INTAKE_REQUESTER_NOT_MEMBER' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.pandora_model_runs
    where id = p_model_run_id and organization_id = p_organization_id and project_id = p_project_id
      and project_spec_id = p_project_spec_id and status = 'succeeded'
  ) then raise exception 'BUILD_INTAKE_MODEL_RUN_INVALID' using errcode='23514'; end if;

  insert into public.pandora_artifacts (organization_id, project_id, logical_key, artifact_kind)
  values (p_organization_id, p_project_id, 'source:' || p_project_spec_id::text, 'source_snapshot')
  on conflict (project_id, logical_key) do update set logical_key = excluded.logical_key
  returning id into v_artifact_id;

  select id into v_artifact_version_id
  from public.pandora_artifact_versions
  where artifact_id = v_artifact_id and content_sha256 = p_source_sha256
  limit 1;

  if v_artifact_version_id is null then
    select id,version into v_parent_artifact_version_id,v_parent_artifact_version
    from public.pandora_artifact_versions
    where artifact_id=v_artifact_id
    order by version desc
    limit 1
    for share;
    if found then v_artifact_version:=v_parent_artifact_version+1;
    else v_artifact_version:=1; v_parent_artifact_version_id:=null; end if;
    v_artifact_version_id := gen_random_uuid();
    insert into public.pandora_artifact_versions (
      id, organization_id, project_id, artifact_id, version, parent_version_id, content_sha256, byte_size, media_type,
      storage_provider, storage_bucket, storage_path, produced_by_model_run_id, provenance_redacted
    ) values (
      v_artifact_version_id, p_organization_id, p_project_id, v_artifact_id, v_artifact_version, v_parent_artifact_version_id,
      p_source_sha256, p_source_byte_size, 'application/json', 'supabase_storage', 'pandora-build-artifacts', p_storage_path,
      p_model_run_id,
      jsonb_build_object('projectSpecId', p_project_spec_id, 'sourceIntentId', v_source_intent_id, 'buildAdapter', p_build_adapter,
        'parentArtifactVersionId',v_parent_artifact_version_id)
    );
  end if;

  insert into public.pandora_project_versions (
    id, organization_id, project_id, kind, source_payload, source_sha256, created_by,
    project_spec_id, root_artifact_version_id, lifecycle_status
  ) values (
    v_project_version_id, p_organization_id, p_project_id, 'preview',
    jsonb_build_object('kind','artifact_snapshot','artifactVersionId',v_artifact_version_id,'buildAdapter',p_build_adapter),
    p_source_sha256, p_requested_by, p_project_spec_id, v_artifact_version_id, 'draft'
  );

  insert into public.pandora_build_jobs (
    id, organization_id, project_id, project_spec_id, source_intent_id, target_project_version_id,
    requested_by, job_kind, status, current_stage, idempotency_key, max_attempts
  ) values (
    v_build_job_id, p_organization_id, p_project_id, p_project_spec_id, v_source_intent_id, v_project_version_id,
    p_requested_by, 'build', 'queued', 'building', trim(p_idempotency_key), 3
  );

  update public.pandora_project_versions set build_job_id = v_build_job_id where id = v_project_version_id;
  update public.pandora_model_runs set build_job_id = v_build_job_id where id = p_model_run_id and build_job_id is null;

  insert into public.pandora_build_job_steps (
    organization_id, project_id, build_job_id, step_key, sequence, step_kind, status,
    idempotency_key, attempt_count, max_attempts, input_sha256, result_sha256, started_at, completed_at
  ) values (
    p_organization_id, p_project_id, v_build_job_id, 'source_snapshot', 0, 'source_generation', 'succeeded',
    trim(p_idempotency_key) || ':source', 1, 1, v_spec.content_sha256, p_source_sha256, now(), now()
  );

  return jsonb_build_object(
    'state','working','buildJobId',v_build_job_id,'projectVersionId',v_project_version_id,
    'sourceArtifactVersionId',v_artifact_version_id,'sourceSha256',p_source_sha256,'buildAdapter',p_build_adapter
  );
end;
$function$

revoke all on function private.pandora_commit_generated_build_intake_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_commit_generated_build_intake_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) to service_role;

CREATE OR REPLACE FUNCTION private.pandora_create_supabase_preview_fallback_20260830(p_project_id uuid, p_version_id uuid, p_operation_id uuid, p_reason text DEFAULT 'vercel_payment_required'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
declare
  v_ver public.pandora_project_versions%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_project public.projectos_projects%rowtype;
  v_token text;
  v_token_hash text;
  v_expires timestamptz:=clock_timestamp()+interval '7 days';
  v_provider_deployment_id text:='spv_'||replace(gen_random_uuid()::text,'-','');
  v_url text;
  v_dep_id uuid;
  v_now timestamptz:=clock_timestamp();
  v_code text;
  v_status integer;
begin
  select * into v_ver from public.pandora_project_versions
   where id=p_version_id and project_id=p_project_id for update;
  if not found or v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null
     or v_ver.build_job_id is null or v_ver.lifecycle_status not in ('built','verification_pending') then
    raise exception 'SUPABASE_PREVIEW_VERSION_INVALID' using errcode='22023';
  end if;
  select * into v_op from public.pandora_runtime_operations
   where id=p_operation_id and project_id=p_project_id and project_version_id=p_version_id and action='create_preview' for update;
  if not found or v_op.status<>'failed' then
    raise exception 'SUPABASE_PREVIEW_OPERATION_NOT_FAILED' using errcode='22023';
  end if;
  v_code:=lower(coalesce(v_op.normalized_error->>'code',''));
  begin v_status:=coalesce((v_op.normalized_error->>'providerStatus')::integer,0); exception when others then v_status:=0; end;
  if v_status<>402 and v_code not in ('payment_required','api_deployments_daily_quota','api-deployments-free-per-day') then
    raise exception 'SUPABASE_PREVIEW_FALLBACK_NOT_ALLOWED' using errcode='42501';
  end if;
  if exists(select 1 from public.pandora_project_deployments where project_id=p_project_id and version_id=p_version_id and environment='preview') then
    raise exception 'SUPABASE_PREVIEW_ALREADY_EXISTS' using errcode='23505';
  end if;
  select * into v_project from public.projectos_projects
   where id=p_project_id and organization_id=v_ver.organization_id for update;
  if not found then raise exception 'SUPABASE_PREVIEW_PROJECT_INVALID' using errcode='22023'; end if;

  v_token:=encode(extensions.digest(convert_to(gen_random_uuid()::text||'|'||clock_timestamp()::text||'|'||v_ver.artifact_digest_sha256,'utf8'),'sha256'),'hex');
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  v_url:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/'||v_token||'/index.html';

  insert into public.pandora_project_deployments(
    organization_id,project_id,version_id,provider,environment,provider_project_id,provider_deployment_id,url,status,
    source_sha256,artifact_digest,source_commit_sha,authorization_ref,idempotency_key,provider_state,immutable_url,stable_url,
    last_provider_check_at,ready_at,expires_at,verification_state,metadata
  ) values (
    v_ver.organization_id,p_project_id,p_version_id,'supabase_preview','preview','pandora-preview-host',v_provider_deployment_id,v_url,'ready_for_verification',
    v_ver.source_sha256,v_ver.artifact_digest_sha256,v_ver.source_commit,v_op.authorization_ref,v_op.idempotency_key,'READY',v_url,v_url,
    v_now,v_now,v_expires,'ready_for_verification',jsonb_build_object('host','pandora-preview-host','fallbackReason',p_reason,'pandoraOperationId',v_op.idempotency_key)
  ) returning id into v_dep_id;

  insert into public.pandora_runtime_environments(
    organization_id,project_id,environment,provider,provider_project_id,status,current_version_id,current_deployment_id,verification_state,last_reconciled_at,updated_at
  ) values (
    v_ver.organization_id,p_project_id,'preview','supabase_preview','pandora-preview-host','ready',p_version_id,v_dep_id,'ready_for_verification',v_now,v_now
  )
  on conflict(project_id,environment) do update set
    provider=excluded.provider,provider_project_id=excluded.provider_project_id,status=excluded.status,
    current_version_id=excluded.current_version_id,current_deployment_id=excluded.current_deployment_id,
    verification_state=excluded.verification_state,last_reconciled_at=excluded.last_reconciled_at,updated_at=excluded.updated_at;

  update public.pandora_project_versions set lifecycle_status='verification_pending' where id=p_version_id and lifecycle_status='built';
  update public.projectos_projects
     set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object(
       'stage','preview_ready','runtimeStatus','verifying','previewUrl',v_url,'previewProvider','supabase_preview',
       'previewVersionId',p_version_id::text,'previewDeploymentId',v_provider_deployment_id,
       'previewVerificationState','ready_for_verification','runtimeUpdatedAt',v_now
     ),true),updated_at=v_now
   where id=p_project_id and organization_id=v_ver.organization_id;

  update public.pandora_runtime_operations
     set status='succeeded',ambiguous=false,provider_resource_id=v_provider_deployment_id,
         result_facts=jsonb_build_object(
           'projectVersionId',p_version_id,'providerDeploymentId',v_provider_deployment_id,'artifactDigest',v_ver.artifact_digest_sha256,
           'sourceCommit',v_ver.source_commit,'verificationState','ready_for_verification','fallbackReason',p_reason,
           'previewProvider','supabase_preview','previewCapabilityHash',v_token_hash,'previewCapabilityExpiresAt',v_expires
         ),
         normalized_error='{}'::jsonb,finished_at=v_now,last_reconciled_at=v_now,updated_at=v_now
   where id=p_operation_id;

  return jsonb_build_object('ok',true,'deploymentId',v_dep_id,'providerDeploymentId',v_provider_deployment_id,
    'providerState','READY','previewUrl',v_url,'verificationState','ready_for_verification','previewProvider','supabase_preview');
end;
$function$

revoke all on function private.pandora_create_supabase_preview_fallback_20260830(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_create_supabase_preview_fallback_20260830(uuid,uuid,uuid,text) to service_role;

CREATE OR REPLACE FUNCTION private.pandora_worker_e_verify_supabase_preview_20260830(p_deployment_id uuid, p_requested_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_art public.pandora_artifact_versions%rowtype;
  v_spec public.pandora_project_specs%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_facts jsonb;
  v_token text;
  v_token_hash text;
  v_expires timestamptz;
  v_pat text;
  v_keys_response extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_object extensions.http_response;
  v_bundle jsonb;
  v_entry jsonb;
  v_plain text;
  v_index text:=null;
  v_artifact_ok boolean:=false;
  v_secret_ok boolean:=true;
  v_lint_ok boolean:=false;
  v_responsive_ok boolean:=false;
  v_provider_ok boolean:=false;
  v_runtime extensions.http_response;
  v_runtime_ok boolean:=false;
  v_runtime_body text:='';
  v_runtime_digest text;
  v_acceptance_ok boolean:=false;
  v_all boolean:=false;
  v_run_id uuid;
  v_identity text;
  v_now timestamptz:=clock_timestamp();
  v_builder text;
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id;
  if not found or v_dep.provider<>'supabase_preview' or v_dep.environment<>'preview'
     or v_dep.provider_project_id<>'pandora-preview-host' or v_dep.provider_state<>'READY'
     or v_dep.provider_deployment_id !~ '^spv_[0-9a-f]{32}$'
     or v_dep.url is null or v_dep.verification_state not in ('ready_for_verification','live_verified') then
    raise exception 'SUPABASE_PREVIEW_EXACT_DEPLOYMENT_REQUIRED' using errcode='22023';
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_dep.version_id;
  if not found or v_ver.project_id<>v_dep.project_id or v_ver.organization_id<>v_dep.organization_id
     or v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null
     or v_ver.project_spec_id is null or v_ver.build_job_id is null then
    raise exception 'SUPABASE_PREVIEW_VERSION_LINEAGE_INVALID' using errcode='22023';
  end if;
  select * into v_art from public.pandora_artifact_versions where id=v_ver.root_artifact_version_id;
  if not found or v_art.organization_id<>v_ver.organization_id or v_art.project_id<>v_ver.project_id
     or v_art.content_sha256<>v_ver.artifact_digest_sha256 or v_art.storage_provider<>'supabase_storage'
     or v_art.storage_bucket<>'pandora-build-artifacts' then
    raise exception 'SUPABASE_PREVIEW_ARTIFACT_INVALID' using errcode='22023';
  end if;
  select * into v_spec from public.pandora_project_specs where id=v_ver.project_spec_id;
  if not found then raise exception 'SUPABASE_PREVIEW_SPEC_INVALID' using errcode='22023'; end if;
  select * into v_job from public.pandora_build_jobs where id=v_ver.build_job_id;
  if not found then raise exception 'SUPABASE_PREVIEW_JOB_INVALID' using errcode='22023'; end if;
  v_builder:=coalesce(nullif(v_job.worker_identity,''),'worker-d-build-runtime');
  if v_builder='worker-e-runtime-verifier-v1' then raise exception 'builder and verifier must be independent' using errcode='22023'; end if;

  select * into v_op from public.pandora_runtime_operations
   where project_id=v_dep.project_id and project_version_id=v_dep.version_id and action='create_preview'
     and idempotency_key=v_dep.idempotency_key and status='succeeded' limit 1;
  if not found or v_op.provider_resource_id is distinct from v_dep.provider_deployment_id then
    raise exception 'SUPABASE_PREVIEW_OPERATION_INVALID' using errcode='22023';
  end if;
  v_facts:=coalesce(v_op.result_facts,'{}'::jsonb);
  if v_facts->>'previewProvider'<>'supabase_preview'
     or v_facts->>'providerDeploymentId'<>v_dep.provider_deployment_id
     or lower(coalesce(v_facts->>'artifactDigest',''))<>v_ver.artifact_digest_sha256 then
    raise exception 'SUPABASE_PREVIEW_FACTS_INVALID' using errcode='22023';
  end if;
  v_token:=split_part(regexp_replace(v_dep.url,'^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/','',''), '/', 1);
  if v_token !~ '^[0-9a-f]{64}$' then raise exception 'SUPABASE_PREVIEW_TOKEN_INVALID' using errcode='22023'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  begin v_expires:=(v_facts->>'previewCapabilityExpiresAt')::timestamptz; exception when others then v_expires:=null; end;
  v_provider_ok:=v_token_hash=coalesce(v_facts->>'previewCapabilityHash','') and v_expires is not null and v_expires>v_now;

  for v_pat in
    select decrypted_secret from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_keys_response from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[extensions.http_header('authorization','Bearer '||v_pat),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Worker-E-Supabase-Preview/1.0')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_keys_response.status=200;
  end loop;
  if v_keys_response.status is distinct from 200 then v_pat:=null; raise exception 'SUPABASE_PREVIEW_STORAGE_AUTH_UNAVAILABLE' using errcode='55000'; end if;
  begin v_keys:=v_keys_response.content::jsonb; exception when others then v_pat:=null; raise exception 'SUPABASE_PREVIEW_STORAGE_KEYS_INVALID' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'SUPABASE_PREVIEW_STORAGE_KEY_UNAVAILABLE' using errcode='55000'; end if;
  select * into v_object from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/'||v_art.storage_bucket||'/'||v_art.storage_path)::varchar,
    array[extensions.http_header('authorization','Bearer '||v_service_role),extensions.http_header('apikey',v_service_role),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_object.status=200 and octet_length(coalesce(v_object.content,''))=v_art.byte_size
     and encode(extensions.digest(convert_to(coalesce(v_object.content,''),'utf8'),'sha256'),'hex')=v_art.content_sha256 then v_artifact_ok:=true; end if;
  if v_artifact_ok then begin v_bundle:=v_object.content::jsonb; exception when others then v_artifact_ok:=false; end; end if;
  if v_artifact_ok and (v_bundle->>'kind'<>'pandora.runtime-bundle.v1' or coalesce((v_bundle->>'schemaVersion')::integer,0)<>1
     or v_bundle->>'projectVersionId'<>v_ver.id::text or v_bundle->>'buildJobId'<>v_job.id::text) then v_artifact_ok:=false; end if;
  if v_artifact_ok then
    for v_entry in select value from jsonb_array_elements(coalesce(v_bundle->'files','[]'::jsonb)) loop
      begin v_plain:=convert_from(decode(v_entry->>'data','base64'),'utf8'); exception when others then v_artifact_ok:=false; exit; end;
      if encode(extensions.digest(convert_to(v_plain,'utf8'),'sha256'),'hex')<>v_entry->>'sha256' then v_artifact_ok:=false; exit; end if;
      if v_plain ~* '(AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|((api[_-]?key|secret|password|authorization)[[:space:]]*[:=][[:space:]]*[\"''][^\"'']{12,}[\"'']))' then v_secret_ok:=false; end if;
      if v_entry->>'file'='index.html' then v_index:=v_plain; end if;
    end loop;
  end if;
  v_lint_ok:=v_artifact_ok and v_index is not null and v_index ~* '<html' and v_index ~* '<body' and v_index ~* '</html>';
  v_responsive_ok:=v_lint_ok and v_index ~* 'name=[\"'']viewport[\"'']';

  if v_dep.url ~ '^https://[A-Za-z0-9.-]+(/.*)?$' then
    begin
      select * into v_runtime from extensions.http((
        'GET'::extensions.http_method,v_dep.url::varchar,
        array[extensions.http_header('user-agent','Pandora-Worker-E-Supabase-Preview/1.0'),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
        null::varchar,null::varchar
      )::extensions.http_request);
      v_runtime_ok:=v_runtime.status between 200 and 399;
      v_runtime_body:=left(coalesce(v_runtime.content,''),1048576);
    exception when others then v_runtime_ok:=false; end;
  end if;
  v_runtime_digest:=encode(extensions.digest(convert_to(coalesce(v_runtime_body,''),'utf8'),'sha256'),'hex');
  v_acceptance_ok:=v_runtime_ok and jsonb_typeof(v_spec.acceptance_scope->'functional')='array' and jsonb_array_length(v_spec.acceptance_scope->'functional')>0;
  if v_acceptance_ok and nullif(v_spec.business_summary,'') is not null then
    v_acceptance_ok:=position(lower(left(v_spec.business_summary,80)) in lower(v_runtime_body))>0
      or position(lower(left((select name from public.projectos_projects where id=v_ver.project_id),80)) in lower(v_runtime_body))>0;
  end if;

  v_identity:=encode(extensions.digest(convert_to(concat_ws('|',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,'static_site',v_ver.source_sha256,v_ver.artifact_digest_sha256,coalesce(v_ver.migration_set_digest_sha256,''),coalesce(v_ver.runtime_target_digest_sha256,'')),'utf8'),'sha256'),'hex');
  select id into v_run_id from public.pandora_verification_runs where project_version_id=v_ver.id and identity_sha256=v_identity limit 1;
  if v_run_id is not null then
    return (select jsonb_build_object('verificationRunId',id,'status',status,'profile',required_check_profile,'replayed',true) from public.pandora_verification_runs where id=v_run_id);
  end if;
  v_run_id:=gen_random_uuid();
  insert into public.pandora_verification_runs(
    id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,requested_by,builder_identity,verifier_identity,identity_sha256,status,started_at
  ) values (
    v_run_id,v_ver.organization_id,v_ver.project_id,v_ver.project_spec_id,v_ver.id,v_ver.build_job_id,v_ver.source_kind,v_ver.source_ref,v_ver.source_commit,v_ver.source_sha256,v_ver.artifact_digest_sha256,
    v_ver.migration_set_digest_sha256,v_ver.runtime_target_digest_sha256,v_dep.provider_deployment_id,'preview','static_site',p_requested_by,v_builder,'worker-e-supabase-preview-verifier-v1',v_identity,'RUNNING',v_now
  );
  insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,failure_class,summary,details_redacted,started_at,completed_at)
  values
    (v_ver.organization_id,v_ver.project_id,v_run_id,'source_format',case when v_artifact_ok then 'PASS' else 'FAIL' end,case when v_artifact_ok then null else 'source' end,case when v_artifact_ok then 'Exact runtime bundle is canonical.' else 'Exact runtime bundle failed canonical validation.' end,jsonb_build_object('artifactDigest',v_ver.artifact_digest_sha256),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'source_lint',case when v_lint_ok then 'PASS' else 'FAIL' end,case when v_lint_ok then null else 'source' end,case when v_lint_ok then 'Static entrypoint structure is valid.' else 'Static entrypoint structure failed.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'secret_scan',case when v_secret_ok then 'PASS' else 'FAIL' end,case when v_secret_ok then null else 'security' end,case when v_secret_ok then 'No standing secret material detected.' else 'Secret-shaped material detected.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'visual_responsive',case when v_responsive_ok then 'PASS' else 'FAIL' end,case when v_responsive_ok then null else 'visual' end,case when v_responsive_ok then 'Responsive viewport contract present.' else 'Responsive viewport contract missing.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'runtime_health',case when v_runtime_ok and v_provider_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_provider_ok then null else 'runtime' end,case when v_runtime_ok and v_provider_ok then 'Exact Supabase preview capability is live and answers HTTPS.' else 'Supabase preview runtime health failed.' end,jsonb_build_object('httpStatus',v_runtime.status,'runtimeBodySha256',v_runtime_digest,'previewProvider','supabase_preview'),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'acceptance_requirements',case when v_acceptance_ok then 'PASS' else 'FAIL' end,case when v_acceptance_ok then null else 'acceptance' end,case when v_acceptance_ok then 'Observable ProjectSpec acceptance is reachable.' else 'Observable ProjectSpec acceptance failed.' end,'{}'::jsonb,v_now,clock_timestamp());
  select bool_and(status='PASS') into v_all from public.pandora_verification_checks where verification_run_id=v_run_id;
  update public.pandora_verification_runs set status=case when v_all then 'PASS' else 'FAIL' end,completed_at=clock_timestamp() where id=v_run_id;
  insert into public.pandora_verification_evidence(organization_id,project_id,verification_run_id,artifact_version_id,evidence_type,media_type,content_sha256,storage_provider,storage_path)
  values(v_ver.organization_id,v_ver.project_id,v_run_id,v_art.id,'artifact_identity','application/json',v_art.content_sha256,v_art.storage_provider,v_art.storage_path);
  if v_all then update public.pandora_project_versions set verification_run_id=v_run_id,lifecycle_status='verified' where id=v_ver.id; end if;
  return jsonb_build_object('verificationRunId',v_run_id,'status',case when v_all then 'PASS' else 'FAIL' end,'profile','static_site','replayed',false,'providerReady',v_provider_ok,'runtimeHealthy',v_runtime_ok,'previewProvider','supabase_preview');
end;
$function$

revoke all on function private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid) to service_role;

CREATE OR REPLACE FUNCTION private.pandora_converge_static_site_build_v2_20260830(p_build_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_result jsonb;
  v_job public.pandora_build_jobs%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_dep public.pandora_project_deployments%rowtype;
  v_fallback jsonb;
  v_verification jsonb;
  v_run_id uuid;
  v_now timestamptz;
  v_code text;
  v_status integer;
begin
  select * into v_job from public.pandora_build_jobs where id=p_build_job_id;
  if not found or v_job.job_kind<>'build' or v_job.target_project_version_id is null then
    raise exception 'STATIC_CONVERGENCE_JOB_INVALID' using errcode='22023';
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_job.target_project_version_id;
  if not found or coalesce(v_ver.source_payload->>'buildAdapter','')<>'static-web' then
    raise exception 'STATIC_CONVERGENCE_ADAPTER_INVALID' using errcode='22023';
  end if;
  if v_job.status='succeeded' and v_ver.lifecycle_status in ('verified','preview_ready','live') then
    return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_ver.id,'state','ready','replayed',true);
  end if;

  select * into v_dep
  from public.pandora_project_deployments
  where organization_id=v_job.organization_id and project_id=v_job.project_id and version_id=v_ver.id
    and environment='preview' and provider='supabase_preview'
  order by created_at desc limit 1;
  if found and v_dep.provider_state='READY' and v_dep.verification_state='ready_for_verification' and v_dep.status='ready_for_verification' then
    v_verification:=private.pandora_worker_e_verify_supabase_preview_20260830(v_dep.id,v_job.requested_by);
    if upper(coalesce(v_verification->>'status',''))='PASS' then
      v_run_id:=(v_verification->>'verificationRunId')::uuid;
      v_now:=clock_timestamp();
      update public.pandora_project_deployments set status='ready',verification_state='live_verified',last_provider_check_at=v_now,updated_at=v_now where id=v_dep.id;
      update public.pandora_runtime_environments set status='ready',verification_state='live_verified',last_reconciled_at=v_now,updated_at=v_now
       where organization_id=v_job.organization_id and project_id=v_job.project_id and environment='preview' and current_deployment_id=v_dep.id;
      update public.projectos_projects
         set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||
           jsonb_build_object('stage','preview_ready','runtimeStatus','ready','previewUrl',v_dep.url,'previewProvider','supabase_preview',
             'previewVersionId',v_ver.id::text,'previewDeploymentId',v_dep.provider_deployment_id,'previewVerificationState','verified','runtimeUpdatedAt',v_now),true),updated_at=v_now
       where id=v_job.project_id;
      perform private.pandora_close_verified_static_build_20260830(v_job.id,v_run_id);
      return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_ver.id,'state','ready','previewUrl',v_dep.url,
        'verificationRunId',v_run_id,'previewProvider','supabase_preview','fallback',true);
    end if;
    v_now:=clock_timestamp();
    update public.pandora_project_deployments set status='failed',verification_state='failed',failed_at=v_now,updated_at=v_now where id=v_dep.id;
    update public.pandora_build_job_attempts set status='failed',finished_at=coalesce(finished_at,v_now),failure_class='verification' where build_job_id=v_job.id and status='running';
    update public.pandora_build_jobs set status='failed',current_stage='failed',completed_at=v_now,error_code='VERIFICATION_FAILED',
      public_error_summary='Pandora found something to resolve before this version can be published.',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,updated_at=v_now
     where id=v_job.id and status not in ('succeeded','failed','cancelled');
    return jsonb_build_object('buildJobId',v_job.id,'projectVersionId',v_ver.id,'state','blocked','stage','verification',
      'verificationRunId',v_verification->>'verificationRunId','previewProvider','supabase_preview');
  end if;

  v_result:=private.pandora_converge_static_site_build_20260830(p_build_job_id);
  if coalesce(v_result->>'state','')<>'previewing' then return v_result; end if;

  select * into v_job from public.pandora_build_jobs where id=p_build_job_id;
  select * into v_ver from public.pandora_project_versions where id=v_job.target_project_version_id;
  select * into v_op from public.pandora_runtime_operations
   where organization_id=v_job.organization_id and project_id=v_job.project_id and project_version_id=v_ver.id and action='create_preview'
   order by created_at desc limit 1;
  if not found or v_op.status<>'failed' then return v_result; end if;
  v_code:=lower(coalesce(v_op.normalized_error->>'code',''));
  begin v_status:=coalesce((v_op.normalized_error->>'providerStatus')::integer,0); exception when others then v_status:=0; end;
  if v_status<>402 and v_code not in ('payment_required','api_deployments_daily_quota','api-deployments-free-per-day') then return v_result; end if;

  v_fallback:=private.pandora_create_supabase_preview_fallback_20260830(v_job.project_id,v_ver.id,v_op.id,
    case when v_code<>'' then 'vercel_'||v_code else 'vercel_payment_required' end);
  return jsonb_build_object(
    'buildJobId',v_job.id,'projectVersionId',v_ver.id,'state','working','stage','preview_fallback_committed',
    'previewUrl',v_fallback->>'previewUrl','previewProvider','supabase_preview','fallback',true
  );
end;
$function$

revoke all on function private.pandora_converge_static_site_build_v2_20260830(uuid) from public,anon,authenticated;
grant execute on function private.pandora_converge_static_site_build_v2_20260830(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.pandora_converge_static_site_build_20260830(p_build_job_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select private.pandora_converge_static_site_build_v2_20260830($1); $function$

revoke all on function public.pandora_converge_static_site_build_20260830(uuid) from public,anon,authenticated;
grant execute on function public.pandora_converge_static_site_build_20260830(uuid) to service_role;

CREATE OR REPLACE FUNCTION private.pandora_converge_pending_static_sites_20260830(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit,5),20));
  v_job record;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  update public.pandora_build_job_attempts a
     set status='cancelled',finished_at=coalesce(finished_at,v_now),failure_class='superseded'
   where a.status='running'
     and exists(
       select 1 from public.pandora_build_jobs j
       join public.pandora_project_versions v on v.id=j.target_project_version_id and v.build_job_id=j.id
       where j.id=a.build_job_id and j.job_kind='build' and j.status in ('queued','waiting_verification')
         and coalesce(v.source_payload->>'buildAdapter','')='static-web'
         and exists(select 1 from public.pandora_project_versions newer
           where newer.project_id=v.project_id and newer.sequence_no>v.sequence_no and newer.lifecycle_status<>'rejected')
     );
  update public.pandora_build_jobs j
     set status='cancelled',current_stage='cancelled',completed_at=v_now,error_code='SUPERSEDED_BY_NEWER_VERSION',
         public_error_summary='A newer project version replaced this build.',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,updated_at=v_now
   from public.pandora_project_versions v
   where v.id=j.target_project_version_id and v.build_job_id=j.id
     and j.job_kind='build' and j.status in ('queued','waiting_verification')
     and coalesce(v.source_payload->>'buildAdapter','')='static-web'
     and exists(select 1 from public.pandora_project_versions newer
       where newer.project_id=v.project_id and newer.sequence_no>v.sequence_no and newer.lifecycle_status<>'rejected');

  for v_job in
    select j.id
    from public.pandora_build_jobs j
    join public.pandora_project_versions v on v.id=j.target_project_version_id and v.build_job_id=j.id
    where j.job_kind='build' and j.status in ('queued','waiting_verification')
      and coalesce(v.source_payload->>'buildAdapter','')='static-web'
      and not exists(select 1 from public.pandora_project_versions newer
        where newer.project_id=v.project_id and newer.sequence_no>v.sequence_no and newer.lifecycle_status<>'rejected')
    order by j.created_at
    limit v_limit
  loop
    begin
      v_result:=private.pandora_converge_static_site_build_v2_20260830(v_job.id);
      v_results:=v_results||jsonb_build_array(v_result);
    exception when others then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('buildJobId',v_job.id,'state','retry'));
    end;
  end loop;
  return jsonb_build_object('processed',jsonb_array_length(v_results),'results',v_results,'checkedAt',clock_timestamp());
end;
$function$

revoke all on function private.pandora_converge_pending_static_sites_20260830(integer) from public,anon,authenticated;
grant execute on function private.pandora_converge_pending_static_sites_20260830(integer) to service_role;

CREATE OR REPLACE FUNCTION public.pandora_converge_pending_static_sites_20260830(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select private.pandora_converge_pending_static_sites_20260830($1); $function$

revoke all on function public.pandora_converge_pending_static_sites_20260830(integer) from public,anon,authenticated;
grant execute on function public.pandora_converge_pending_static_sites_20260830(integer) to service_role;
