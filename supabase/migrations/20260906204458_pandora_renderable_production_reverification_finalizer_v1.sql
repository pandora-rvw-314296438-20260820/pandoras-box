begin;

create or replace function private.pandora_finalize_renderable_production_reverification_20260906(
  p_deployment_id uuid,
  p_requested_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_run public.pandora_verification_runs%rowtype;
  v_project public.projectos_projects%rowtype;
  v_verification jsonb;
  v_live_url text;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
    and environment='production'
  for update;

  if not found
     or v_dep.provider<>'supabase_static'
     or v_dep.provider_project_id<>'pandora-preview-host'
     or v_dep.provider_state<>'READY'
     or v_dep.status<>'ready_for_verification'
     or v_dep.verification_state<>'ready_for_verification'
     or v_dep.url !~ '^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$' then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and environment='production'
    and current_deployment_id=v_dep.id
    and current_version_id=v_dep.version_id
  for update;
  if not found or v_env.verification_state<>'ready_for_verification' then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_ENVIRONMENT_INVALID' using errcode='40001';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
  for update;
  if not found or v_ver.lifecycle_status<>'live' or v_ver.build_job_id is null then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_VERSION_INVALID' using errcode='40001';
  end if;

  select * into v_job
  from public.pandora_build_jobs
  where id=v_ver.build_job_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id;
  if not found then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_BUILD_INVALID' using errcode='22023';
  end if;

  v_verification:=private.pandora_worker_e_verify_supabase_production_20260831(
    v_dep.id,
    coalesce(p_requested_by,v_job.requested_by)
  );
  if upper(coalesce(v_verification->>'status',''))<>'PASS' then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_FAILED' using errcode='23514';
  end if;

  select * into v_run
  from public.pandora_verification_runs
  where id=(v_verification->>'verificationRunId')::uuid;
  if not found
     or upper(v_run.status)<>'PASS'
     or v_run.target_environment<>'production'
     or v_run.required_check_profile<>'production_release'
     or v_run.project_id<>v_dep.project_id
     or v_run.project_version_id<>v_ver.id
     or v_run.build_job_id<>v_ver.build_job_id
     or v_run.project_spec_id<>v_ver.project_spec_id
     or v_run.source_kind<>v_ver.source_kind
     or v_run.source_ref<>v_ver.source_ref
     or v_run.source_commit is distinct from v_ver.source_commit
     or v_run.source_digest<>v_ver.source_sha256
     or v_run.artifact_digest<>v_ver.artifact_digest_sha256
     or v_run.migration_set_digest is distinct from v_ver.migration_set_digest_sha256
     or v_run.runtime_target_digest is distinct from v_ver.runtime_target_digest_sha256
     or v_run.preview_deployment_id<>v_dep.provider_deployment_id
     or v_run.completed_at is null
     or v_run.completed_at<v_dep.created_at
     or v_run.builder_identity is not distinct from v_run.verifier_identity then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_PROOF_INVALID' using errcode='23514';
  end if;

  update public.pandora_project_deployments
  set verification_state='live_verified',
      verification_ref=v_run.id::text,
      status='ready',
      last_provider_check_at=v_now,
      updated_at=v_now
  where id=v_dep.id
    and verification_state='ready_for_verification';
  if not found then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_DEPLOYMENT_RACE' using errcode='40001';
  end if;

  update public.pandora_runtime_environments
  set verification_state='live_verified',
      status='ready',
      last_reconciled_at=v_now,
      updated_at=v_now
  where id=v_env.id
    and current_deployment_id=v_dep.id
    and current_version_id=v_ver.id
    and verification_state='ready_for_verification';
  if not found then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_ENVIRONMENT_RACE' using errcode='40001';
  end if;

  update public.pandora_project_versions
  set verification_run_id=v_run.id,
      rollback_eligible=true
  where id=v_ver.id
    and lifecycle_status='live';

  select * into v_project
  from public.projectos_projects
  where id=v_dep.project_id
    and organization_id=v_dep.organization_id
  for update;
  if not found then
    raise exception 'RENDERABLE_PRODUCTION_REVERIFY_PROJECT_INVALID' using errcode='22023';
  end if;

  v_live_url:=coalesce(
    nullif(v_project.config #>> '{customerJourney,liveUrl}',''),
    v_dep.url
  );

  update public.projectos_projects
  set config=jsonb_set(
        coalesce(v_project.config,'{}'::jsonb),
        '{customerJourney}',
        coalesce(v_project.config->'customerJourney','{}'::jsonb) ||
          jsonb_build_object(
            'stage','live',
            'runtimeStatus','ready',
            'liveUrl',v_live_url,
            'productionCandidateUrl',null,
            'productionVerificationState','live_verified',
            'productionVerificationRunId',v_run.id::text,
            'publishedVersionId',v_ver.id::text,
            'runtimeUpdatedAt',v_now
          ),
        true
      ),
      updated_at=v_now
  where id=v_dep.project_id
    and organization_id=v_dep.organization_id;

  return jsonb_build_object(
    'state','live',
    'deploymentId',v_dep.id,
    'projectVersionId',v_ver.id,
    'verificationRunId',v_run.id,
    'reverified',true
  );
end
$function$;

revoke all on function private.pandora_finalize_renderable_production_reverification_20260906(uuid,uuid)
from public,anon,authenticated;
grant execute on function private.pandora_finalize_renderable_production_reverification_20260906(uuid,uuid)
to service_role;

comment on function private.pandora_finalize_renderable_production_reverification_20260906(uuid,uuid) is
'Re-certifies an already-live exact current Supabase static production deployment after render-transport migration. Requires a fresh independent production PASS and never repromotes or rebuilds the version.';

commit;
