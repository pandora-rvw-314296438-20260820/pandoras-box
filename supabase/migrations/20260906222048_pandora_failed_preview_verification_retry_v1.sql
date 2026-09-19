begin;

CREATE OR REPLACE FUNCTION private.pandora_retry_failed_preview_verification_20260906(p_deployment_id uuid, p_requested_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_previous_run public.pandora_verification_runs%rowtype;
  v_result jsonb;
  v_run_id uuid;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
  for update;

  if not found
     or v_dep.environment<>'preview'
     or v_dep.provider<>'supabase_preview'
     or v_dep.provider_state<>'READY'
     or v_dep.status<>'failed'
     or v_dep.verification_state<>'failed'
     or v_dep.url is null then
    raise exception 'PREVIEW_VERIFICATION_RETRY_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and environment='preview'
    and current_deployment_id=v_dep.id
    and current_version_id=v_dep.version_id
  for update;
  if not found then
    raise exception 'PREVIEW_VERIFICATION_RETRY_ENVIRONMENT_INVALID' using errcode='40001';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
  for update;
  if not found
     or v_ver.build_job_id is null
     or v_ver.lifecycle_status not in ('verification_pending','verified') then
    raise exception 'PREVIEW_VERIFICATION_RETRY_VERSION_INVALID' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_build_jobs
  where id=v_ver.build_job_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
  for update;
  if not found
     or v_job.status<>'failed'
     or v_job.error_code<>'VERIFICATION_FAILED'
     or v_job.target_project_version_id<>v_ver.id then
    raise exception 'PREVIEW_VERIFICATION_RETRY_BUILD_INVALID' using errcode='22023';
  end if;

  select * into v_previous_run
  from public.pandora_verification_runs
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and project_version_id=v_ver.id
    and build_job_id=v_job.id
    and preview_deployment_id=v_dep.provider_deployment_id
    and target_environment='preview'
    and required_check_profile='static_site'
    and status='FAIL'
  order by completed_at desc nulls last,created_at desc
  limit 1;
  if not found then
    raise exception 'PREVIEW_VERIFICATION_RETRY_FAILED_PROOF_MISSING' using errcode='23514';
  end if;

  update public.pandora_project_deployments
  set status='ready_for_verification',
      verification_state='ready_for_verification',
      failed_at=null,
      last_provider_check_at=v_now,
      updated_at=v_now
  where id=v_dep.id;

  update public.pandora_runtime_environments
  set verification_state='ready_for_verification',
      last_reconciled_at=v_now,
      updated_at=v_now
  where id=v_env.id;

  update public.projectos_projects
  set config=jsonb_set(
        coalesce(config,'{}'::jsonb),
        '{customerJourney}',
        coalesce(config->'customerJourney','{}'::jsonb) ||
          jsonb_build_object(
            'stage','preview_ready',
            'runtimeStatus','verifying',
            'previewUrl',v_dep.url,
            'previewProvider',v_dep.provider,
            'previewVersionId',v_ver.id::text,
            'previewDeploymentId',v_dep.provider_deployment_id,
            'previewVerificationState','ready_for_verification',
            'runtimeUpdatedAt',v_now
          ),
        true
      ),
      updated_at=v_now
  where id=v_dep.project_id
    and organization_id=v_dep.organization_id;

  begin
    v_result:=private.pandora_worker_e_verify_supabase_preview_v2_20260830(
      v_dep.id,
      coalesce(p_requested_by,v_job.requested_by)
    );
  exception when others then
    update public.pandora_project_deployments
    set status='failed',
        verification_state='failed',
        failed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=v_dep.id;
    raise;
  end;

  if upper(coalesce(v_result->>'status',''))<>'PASS' then
    update public.pandora_project_deployments
    set status='failed',
        verification_state='failed',
        failed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=v_dep.id;
    return jsonb_build_object(
      'state','blocked',
      'stage','verification',
      'deploymentId',v_dep.id,
      'verificationRunId',v_result->>'verificationRunId',
      'previousVerificationRunId',v_previous_run.id
    );
  end if;

  v_run_id:=(v_result->>'verificationRunId')::uuid;
  return private.pandora_recover_verified_static_build_20260830(
    v_job.id,
    v_run_id
  ) || jsonb_build_object(
    'retried',true,
    'previousVerificationRunId',v_previous_run.id
  );
end
$function$;

revoke all on function private.pandora_retry_failed_preview_verification_20260906(uuid,uuid)
from public,anon,authenticated;
grant execute on function private.pandora_retry_failed_preview_verification_20260906(uuid,uuid)
to service_role;

comment on function private.pandora_retry_failed_preview_verification_20260906(uuid,uuid) is
'Reopens only an exact current preview failed by VERIFICATION_FAILED, runs fresh Worker E verification, and recovers the build only on PASS using the existing verified-build recovery finalizer.';

commit;
