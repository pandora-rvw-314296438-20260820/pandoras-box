create or replace function private.pandora_worker_e_verify_supabase_production_20260831(
  p_deployment_id uuid,
  p_requested_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','private','public','extensions'
as $$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_art public.pandora_artifact_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_preview public.pandora_project_deployments%rowtype;
  v_preview_run public.pandora_verification_runs%rowtype;
  v_host public.pandora_runtime_operations%rowtype;
  v_facts jsonb;
  v_token text;
  v_token_hash text;
  v_expires timestamptz;
  v_runtime extensions.http_response;
  v_runtime_body text := '';
  v_runtime_digest text;
  v_preview_runtime_digest text;
  v_required_pass integer := 0;
  v_failed integer := 0;
  v_evidence_ok boolean := false;
  v_host_ok boolean := false;
  v_runtime_ok boolean := false;
  v_body_match boolean := false;
  v_secret_ok boolean := false;
  v_acceptance_ok boolean := false;
  v_all boolean := false;
  v_builder text;
  v_identity text;
  v_run_id uuid;
  v_existing uuid;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id;
  if not found or v_dep.provider<>'supabase_static' or v_dep.environment<>'production'
     or v_dep.provider_project_id<>'pandora-preview-host' or v_dep.provider_state<>'READY'
     or v_dep.provider_deployment_id !~ '^spp_[0-9a-f]{32}$'
     or v_dep.url !~ '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$'
     or v_dep.verification_state not in ('ready_for_verification','live_verified') then
    raise exception 'SUPABASE_PRODUCTION_EXACT_DEPLOYMENT_REQUIRED' using errcode='22023';
  end if;

  select * into v_ver from public.pandora_project_versions where id=v_dep.version_id;
  if not found or v_ver.organization_id<>v_dep.organization_id or v_ver.project_id<>v_dep.project_id
     or v_ver.project_spec_id is null or v_ver.build_job_id is null or v_ver.root_artifact_version_id is null
     or v_ver.artifact_digest_sha256 is null or v_ver.verification_run_id is null then
    raise exception 'SUPABASE_PRODUCTION_VERSION_LINEAGE_INVALID' using errcode='22023';
  end if;
  if v_dep.source_sha256<>v_ver.source_sha256
     or v_dep.artifact_digest is distinct from v_ver.artifact_digest_sha256
     or v_dep.source_commit_sha is distinct from v_ver.source_commit then
    raise exception 'SUPABASE_PRODUCTION_DEPLOYMENT_IDENTITY_INVALID' using errcode='22023';
  end if;

  select * into v_art from public.pandora_artifact_versions where id=v_ver.root_artifact_version_id;
  if not found or v_art.organization_id<>v_ver.organization_id or v_art.project_id<>v_ver.project_id
     or v_art.content_sha256<>v_ver.artifact_digest_sha256 then
    raise exception 'SUPABASE_PRODUCTION_ARTIFACT_INVALID' using errcode='22023';
  end if;
  select * into v_job from public.pandora_build_jobs where id=v_ver.build_job_id;
  if not found then raise exception 'SUPABASE_PRODUCTION_BUILD_INVALID' using errcode='22023'; end if;
  v_builder:=coalesce(nullif(v_job.worker_identity,''),'worker-d-build-runtime');
  if v_builder like 'worker-e%' then raise exception 'builder and verifier must be independent' using errcode='22023'; end if;

  select * into v_preview
  from public.pandora_project_deployments
  where organization_id=v_ver.organization_id and project_id=v_ver.project_id and version_id=v_ver.id
    and environment='preview' and provider='supabase_preview' and verification_state='live_verified'
  order by created_at desc limit 1;
  if not found then raise exception 'VERIFIED_SUPABASE_PREVIEW_REQUIRED' using errcode='22023'; end if;

  select * into v_preview_run
  from public.pandora_verification_runs
  where id=v_ver.verification_run_id and organization_id=v_ver.organization_id and project_id=v_ver.project_id
    and project_version_id=v_ver.id and project_spec_id=v_ver.project_spec_id and build_job_id=v_ver.build_job_id
    and target_environment='preview' and required_check_profile='static_site' and status='PASS'
    and preview_deployment_id=v_preview.provider_deployment_id
    and source_kind=v_ver.source_kind and source_ref=v_ver.source_ref and source_commit is not distinct from v_ver.source_commit
    and source_digest=v_ver.source_sha256 and artifact_digest=v_ver.artifact_digest_sha256
    and migration_set_digest is not distinct from v_ver.migration_set_digest_sha256
    and runtime_target_digest is not distinct from v_ver.runtime_target_digest_sha256;
  if not found then raise exception 'INDEPENDENT_PREVIEW_VERIFICATION_REQUIRED' using errcode='22023'; end if;

  select count(*) filter(where status<>'PASS'),
         count(*) filter(where status='PASS' and check_key in ('source_format','source_lint','secret_scan','visual_responsive','runtime_health','acceptance_requirements'))
    into v_failed,v_required_pass
  from public.pandora_verification_checks where verification_run_id=v_preview_run.id;
  v_secret_ok:=exists(select 1 from public.pandora_verification_checks where verification_run_id=v_preview_run.id and check_key='secret_scan' and status='PASS');
  v_acceptance_ok:=exists(select 1 from public.pandora_verification_checks where verification_run_id=v_preview_run.id and check_key='acceptance_requirements' and status='PASS');
  v_evidence_ok:=exists(select 1 from public.pandora_verification_evidence where verification_run_id=v_preview_run.id and artifact_version_id=v_art.id and content_sha256=v_art.content_sha256);
  select details_redacted->>'runtimeBodySha256' into v_preview_runtime_digest
  from public.pandora_verification_checks
  where verification_run_id=v_preview_run.id and status='PASS' and details_redacted ? 'runtimeBodySha256'
  order by case check_key when 'runtime_health' then 0 when 'acceptance_requirements' then 1 else 2 end
  limit 1;
  if v_failed<>0 or v_required_pass<>6 or not v_evidence_ok or v_preview_runtime_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'INDEPENDENT_PREVIEW_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;

  select * into v_host
  from public.pandora_runtime_operations
  where organization_id=v_ver.organization_id and project_id=v_ver.project_id and project_version_id=v_ver.id
    and action='create_preview' and environment='production' and provider='supabase_preview'
    and provider_resource_id=v_dep.provider_deployment_id and status='succeeded'
  order by created_at desc limit 1;
  if not found then raise exception 'SUPABASE_PRODUCTION_HOST_CAPABILITY_REQUIRED' using errcode='22023'; end if;
  v_facts:=coalesce(v_host.result_facts,'{}'::jsonb);
  v_token:=split_part(regexp_replace(v_dep.url,'^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/','',''), '/', 1);
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  begin v_expires:=(v_facts->>'previewCapabilityExpiresAt')::timestamptz; exception when others then v_expires:=null; end;
  v_host_ok:=v_token ~ '^[0-9a-f]{64}$'
    and v_token_hash=coalesce(v_facts->>'previewCapabilityHash','')
    and v_facts->>'previewProvider'='supabase_preview'
    and v_facts->>'providerDeploymentId'=v_dep.provider_deployment_id
    and lower(coalesce(v_facts->>'artifactDigest',''))=v_ver.artifact_digest_sha256
    and v_expires is not null and v_expires>v_now;

  begin
    select * into v_runtime from extensions.http((
      'GET'::extensions.http_method,v_dep.url::varchar,
      array[extensions.http_header('user-agent','Pandora-Worker-E-Supabase-Production/1.0'),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    v_runtime_ok:=v_runtime.status between 200 and 399;
    v_runtime_body:=left(coalesce(v_runtime.content,''),1048576);
  exception when others then
    v_runtime_ok:=false;
    v_runtime_body:='';
  end;
  v_runtime_digest:=encode(extensions.digest(convert_to(v_runtime_body,'utf8'),'sha256'),'hex');
  v_body_match:=v_runtime_ok and v_runtime_digest=v_preview_runtime_digest;

  v_identity:=encode(extensions.digest(convert_to(concat_ws('|','supabase-static-production-v1',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,v_ver.source_sha256,v_ver.artifact_digest_sha256,coalesce(v_ver.migration_set_digest_sha256,''),coalesce(v_ver.runtime_target_digest_sha256,''),v_preview_run.id::text),'utf8'),'sha256'),'hex');
  select id into v_existing from public.pandora_verification_runs where project_version_id=v_ver.id and identity_sha256=v_identity limit 1;
  if v_existing is not null then
    return (select jsonb_build_object('verificationRunId',id,'status',status,'profile',required_check_profile,'replayed',true,'provider','supabase_static') from public.pandora_verification_runs where id=v_existing);
  end if;

  v_run_id:=gen_random_uuid();
  insert into public.pandora_verification_runs(
    id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,requested_by,builder_identity,verifier_identity,identity_sha256,status,started_at
  ) values (
    v_run_id,v_ver.organization_id,v_ver.project_id,v_ver.project_spec_id,v_ver.id,v_ver.build_job_id,v_ver.source_kind,v_ver.source_ref,v_ver.source_commit,v_ver.source_sha256,v_ver.artifact_digest_sha256,
    v_ver.migration_set_digest_sha256,v_ver.runtime_target_digest_sha256,v_dep.provider_deployment_id,'production','production_release',p_requested_by,v_builder,'worker-e-supabase-production-verifier-v1',v_identity,'RUNNING',v_now
  );

  insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,failure_class,summary,details_redacted,started_at,completed_at)
  values
    (v_ver.organization_id,v_ver.project_id,v_run_id,'artifact_identity',case when v_evidence_ok then 'PASS' else 'FAIL' end,case when v_evidence_ok then null else 'build' end,'Production is bound to the independently verified artifact.',jsonb_build_object('artifactDigest',v_ver.artifact_digest_sha256,'previewVerificationRunId',v_preview_run.id),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'secret_scan',case when v_secret_ok then 'PASS' else 'FAIL' end,case when v_secret_ok then null else 'security' end,'Production inherits a PASS secret scan from the exact independently verified artifact.','{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'runtime_health',case when v_runtime_ok and v_host_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_host_ok then null else 'runtime' end,'Exact Supabase production runtime answers HTTPS.',jsonb_build_object('httpStatus',case when v_runtime_ok then v_runtime.status else null end,'runtimeBodySha256',v_runtime_digest,'provider','supabase_static'),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'acceptance_requirements',case when v_acceptance_ok and v_body_match then 'PASS' else 'FAIL' end,case when v_acceptance_ok and v_body_match then null else 'acceptance' end,'Production serves the same observable result that passed ProjectSpec acceptance.',jsonb_build_object('previewRuntimeBodySha256',v_preview_runtime_digest,'productionRuntimeBodySha256',v_runtime_digest),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'production_exact_version',case when v_host_ok and v_evidence_ok then 'PASS' else 'FAIL' end,case when v_host_ok and v_evidence_ok then null else 'runtime' end,'Production provider identity is bound to the exact verified project version.',jsonb_build_object('providerDeploymentId',v_dep.provider_deployment_id,'provider','supabase_static'),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'production_domain',case when v_runtime_ok and v_dep.url like 'https://%' then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_dep.url like 'https://%' then null else 'domain' end,'Provider production URL is HTTPS and healthy.',jsonb_build_object('provider','supabase_static'),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'production_runtime',case when v_body_match and v_host_ok then 'PASS' else 'FAIL' end,case when v_body_match and v_host_ok then null else 'runtime' end,'Production runtime is byte-equivalent to the independently verified preview response.',jsonb_build_object('runtimeBodySha256',v_runtime_digest,'previewVerificationRunId',v_preview_run.id),v_now,clock_timestamp());

  select bool_and(status='PASS') into v_all from public.pandora_verification_checks where verification_run_id=v_run_id;
  update public.pandora_verification_runs set status=case when v_all then 'PASS' else 'FAIL' end,completed_at=clock_timestamp() where id=v_run_id;
  insert into public.pandora_verification_evidence(organization_id,project_id,verification_run_id,artifact_version_id,evidence_type,media_type,content_sha256,storage_provider,storage_path)
  values(v_ver.organization_id,v_ver.project_id,v_run_id,v_art.id,'artifact_identity','application/json',v_art.content_sha256,v_art.storage_provider,v_art.storage_path);

  return jsonb_build_object('verificationRunId',v_run_id,'status',case when v_all then 'PASS' else 'FAIL' end,'profile','production_release','replayed',false,'provider','supabase_static','runtimeBodySha256',v_runtime_digest);
end;
$$;

revoke all on function private.pandora_worker_e_verify_supabase_production_20260831(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_supabase_production_20260831(uuid,uuid) to service_role;

create or replace function private.pandora_publish_supabase_fallback_20260831(
  p_project_id uuid,
  p_version_id uuid,
  p_requested_by uuid,
  p_expected_production_version_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_preview public.pandora_project_deployments%rowtype;
  v_preview_run public.pandora_verification_runs%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_existing public.pandora_project_deployments%rowtype;
  v_publish_op public.pandora_runtime_operations%rowtype;
  v_prod_id uuid;
  v_provider_id text;
  v_token text;
  v_token_hash text;
  v_url text;
  v_publish_key text;
  v_host_key text;
  v_verification jsonb;
  v_run_id uuid;
  v_final jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_project from public.projectos_projects where id=p_project_id for update;
  if not found then raise exception 'PROJECT_NOT_FOUND' using errcode='22023'; end if;
  if not exists(select 1 from public.memberships where organization_id=v_project.organization_id and user_id=p_requested_by and status='active' and role::text in ('owner','admin')) then
    raise exception 'OWNER_ROLE_REQUIRED' using errcode='42501';
  end if;

  select * into v_ver from public.pandora_project_versions
  where id=p_version_id and organization_id=v_project.organization_id and project_id=p_project_id for update;
  if not found or v_ver.lifecycle_status not in ('verified','production_candidate','live') or v_ver.verification_run_id is null
     or v_ver.project_spec_id is null or v_ver.build_job_id is null or v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null then
    raise exception 'VERIFIED_VERSION_REQUIRED' using errcode='22023';
  end if;

  select * into v_env from public.pandora_runtime_environments
  where organization_id=v_project.organization_id and project_id=p_project_id and environment='production' for update;
  if found then
    if v_env.current_version_id is distinct from p_expected_production_version_id then raise exception 'PRODUCTION_PRECONDITION_MISMATCH' using errcode='40001'; end if;
  elsif p_expected_production_version_id is not null then
    raise exception 'PRODUCTION_PRECONDITION_MISMATCH' using errcode='40001';
  end if;

  select * into v_existing from public.pandora_project_deployments
  where organization_id=v_project.organization_id and project_id=p_project_id and version_id=p_version_id and environment='production' and provider='supabase_static'
  order by created_at desc limit 1;
  if found then
    if v_existing.verification_state='live_verified' then
      return jsonb_build_object('deploymentId',v_existing.id,'projectVersionId',p_version_id,'state','live','liveUrl',v_project.config->'customerJourney'->>'liveUrl','replayed',true,'provider','supabase_static');
    end if;
    if v_existing.verification_state='ready_for_verification' then
      v_verification:=private.pandora_worker_e_verify_supabase_production_20260831(v_existing.id,p_requested_by);
      if upper(coalesce(v_verification->>'status',''))='PASS' then
        v_run_id:=(v_verification->>'verificationRunId')::uuid;
        return private.pandora_finalize_verified_production_20260830(v_existing.id,v_run_id)||jsonb_build_object('provider','supabase_static');
      end if;
      return jsonb_build_object('deploymentId',v_existing.id,'projectVersionId',p_version_id,'state','blocked','stage','production_verification','verificationRunId',v_verification->>'verificationRunId','provider','supabase_static');
    end if;
  end if;

  select * into v_preview from public.pandora_project_deployments
  where organization_id=v_project.organization_id and project_id=p_project_id and version_id=p_version_id and environment='preview' and provider='supabase_preview'
    and status='ready' and verification_state='live_verified' and provider_state='READY'
  order by created_at desc limit 1;
  if not found then raise exception 'VERIFIED_SUPABASE_PREVIEW_REQUIRED' using errcode='22023'; end if;

  select * into v_preview_run from public.pandora_verification_runs
  where id=v_ver.verification_run_id and status='PASS' and target_environment='preview' and required_check_profile='static_site'
    and organization_id=v_ver.organization_id and project_id=v_ver.project_id and project_version_id=v_ver.id
    and project_spec_id=v_ver.project_spec_id and build_job_id=v_ver.build_job_id
    and preview_deployment_id=v_preview.provider_deployment_id and source_kind=v_ver.source_kind and source_ref=v_ver.source_ref
    and source_commit is not distinct from v_ver.source_commit and source_digest=v_ver.source_sha256 and artifact_digest=v_ver.artifact_digest_sha256
    and migration_set_digest is not distinct from v_ver.migration_set_digest_sha256 and runtime_target_digest is not distinct from v_ver.runtime_target_digest_sha256;
  if not found then raise exception 'INDEPENDENT_PREVIEW_VERIFICATION_REQUIRED' using errcode='22023'; end if;

  v_publish_key:=encode(extensions.digest(convert_to(concat_ws('|','supabase-static-publish-v1',v_project.organization_id::text,p_project_id::text,p_version_id::text,coalesce(p_expected_production_version_id::text,'empty'),v_preview_run.id::text),'utf8'),'sha256'),'hex');
  select * into v_publish_op from public.pandora_runtime_operations where provider='supabase_static' and idempotency_key=v_publish_key for update;
  if found then
    if v_publish_op.status in ('claimed','running') then
      return jsonb_build_object('state','working','operationId',v_publish_op.id,'provider','supabase_static');
    elsif v_publish_op.status='failed' then
      update public.pandora_runtime_operations set status='running',ambiguous=false,normalized_error='{}'::jsonb,started_at=coalesce(started_at,v_now),finished_at=null,updated_at=v_now where id=v_publish_op.id returning * into v_publish_op;
    end if;
  else
    insert into public.pandora_runtime_operations(idempotency_key,action,organization_id,project_id,project_version_id,environment,provider,authorization_ref,verification_ref,provider_project_id,status,started_at)
    values(v_publish_key,'publish_version',v_project.organization_id,p_project_id,p_version_id,'production','supabase_static','owner:'||p_requested_by::text,v_preview_run.id::text,'pandora-preview-host','running',v_now)
    returning * into v_publish_op;
  end if;

  v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  v_provider_id:='spp_'||replace(gen_random_uuid()::text,'-','');
  v_url:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/'||v_token||'/index.html';
  v_host_key:=encode(extensions.digest(convert_to(concat_ws('|','supabase-static-host-v1',v_project.organization_id::text,p_project_id::text,p_version_id::text,v_provider_id),'utf8'),'sha256'),'hex');

  insert into public.pandora_runtime_operations(idempotency_key,action,organization_id,project_id,project_version_id,environment,provider,authorization_ref,verification_ref,provider_project_id,provider_resource_id,status,ambiguous,result_facts,started_at,finished_at,last_reconciled_at)
  values(v_host_key,'create_preview',v_project.organization_id,p_project_id,p_version_id,'production','supabase_preview','owner:'||p_requested_by::text,v_preview_run.id::text,'pandora-preview-host',v_provider_id,'succeeded',false,
    jsonb_build_object('previewCapabilityHash',v_token_hash,'previewCapabilityExpiresAt',v_now+interval '10 years','previewProvider','supabase_preview','providerDeploymentId',v_provider_id,'artifactDigest',v_ver.artifact_digest_sha256,'sourceKind',v_ver.source_kind,'sourceRef',v_ver.source_ref,'sourceCommit',v_ver.source_commit,'projectVersionId',p_version_id),v_now,v_now,v_now);

  insert into public.pandora_project_deployments(organization_id,project_id,version_id,provider,environment,provider_project_id,provider_deployment_id,url,status,source_sha256,promoted_from_id,artifact_digest,source_commit_sha,authorization_ref,verification_ref,idempotency_key,provider_state,immutable_url,last_provider_check_at,ready_at,verification_state,metadata)
  values(v_project.organization_id,p_project_id,p_version_id,'supabase_static','production','pandora-preview-host',v_provider_id,v_url,'ready_for_verification',v_ver.source_sha256,v_preview.id,v_ver.artifact_digest_sha256,v_ver.source_commit,'owner:'||p_requested_by::text,v_preview_run.id::text,v_publish_key,'READY',v_url,v_now,v_now,'ready_for_verification',jsonb_build_object('providerName','pandora-preview-host','previewVerificationRunId',v_preview_run.id,'sourceKind',v_ver.source_kind,'sourceRef',v_ver.source_ref,'fallbackFrom','vercel_api_deployment_quota'))
  returning id into v_prod_id;

  insert into public.pandora_runtime_environments(organization_id,project_id,environment,provider,provider_project_id,status,current_version_id,current_deployment_id,verification_state,last_reconciled_at,updated_at)
  values(v_project.organization_id,p_project_id,'production','supabase_static','pandora-preview-host','ready',p_version_id,v_prod_id,'ready_for_verification',v_now,v_now)
  on conflict(project_id,environment) do update set provider=excluded.provider,provider_project_id=excluded.provider_project_id,status=excluded.status,current_version_id=excluded.current_version_id,current_deployment_id=excluded.current_deployment_id,verification_state=excluded.verification_state,last_reconciled_at=excluded.last_reconciled_at,updated_at=excluded.updated_at;

  if p_expected_production_version_id is not null then
    update public.pandora_project_versions set rollback_eligible=true where id=p_expected_production_version_id and organization_id=v_project.organization_id and project_id=p_project_id;
  end if;
  update public.pandora_project_versions set lifecycle_status='production_candidate',promoted_at=v_now,rollback_eligible=true where id=p_version_id;
  update public.projectos_projects
     set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object('stage','publishing','runtimeStatus','verifying','productionCandidateUrl',v_url,'productionDeploymentId',v_provider_id,'publishedVersionId',p_version_id::text,'productionVerificationState','ready_for_verification','runtimeUpdatedAt',v_now),true),updated_at=v_now
   where id=p_project_id and organization_id=v_project.organization_id;
  update public.pandora_runtime_operations set status='succeeded',provider_resource_id=v_provider_id,result_facts=jsonb_build_object('projectVersionId',p_version_id,'providerDeploymentId',v_provider_id,'previewVerificationRunId',v_preview_run.id,'provider','supabase_static','verificationState','ready_for_verification'),finished_at=v_now,last_reconciled_at=v_now,updated_at=v_now where id=v_publish_op.id;

  v_verification:=private.pandora_worker_e_verify_supabase_production_20260831(v_prod_id,p_requested_by);
  if upper(coalesce(v_verification->>'status',''))<>'PASS' then
    update public.projectos_projects set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object('stage','needs_attention','runtimeStatus','failed','productionVerificationState','failed','runtimeUpdatedAt',clock_timestamp()),true),updated_at=clock_timestamp() where id=p_project_id;
    return jsonb_build_object('deploymentId',v_prod_id,'projectVersionId',p_version_id,'verificationRunId',v_verification->>'verificationRunId','state','blocked','stage','production_verification','provider','supabase_static');
  end if;
  v_run_id:=(v_verification->>'verificationRunId')::uuid;
  v_final:=private.pandora_finalize_verified_production_20260830(v_prod_id,v_run_id);
  return v_final||jsonb_build_object('provider','supabase_static');
end;
$$;

revoke all on function private.pandora_publish_supabase_fallback_20260831(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_publish_supabase_fallback_20260831(uuid,uuid,uuid,uuid) to service_role;

create or replace function public.pandora_publish_supabase_fallback_20260831(
  p_project_id uuid,
  p_version_id uuid,
  p_requested_by uuid,
  p_expected_production_version_id uuid default null
)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select private.pandora_publish_supabase_fallback_20260831(p_project_id,p_version_id,p_requested_by,p_expected_production_version_id);
$$;
revoke all on function public.pandora_publish_supabase_fallback_20260831(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.pandora_publish_supabase_fallback_20260831(uuid,uuid,uuid,uuid) to service_role;