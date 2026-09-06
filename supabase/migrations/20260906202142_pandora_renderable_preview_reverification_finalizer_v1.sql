begin;

create or replace function private.pandora_finalize_renderable_preview_reverification_20260906(
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
  v_ver public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_run public.pandora_verification_runs%rowtype;
  v_verification jsonb;
  v_current boolean:=false;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
  for update;

  if not found
     or v_dep.provider<>'supabase_preview'
     or v_dep.environment<>'preview'
     or v_dep.provider_state<>'READY'
     or v_dep.status not in ('ready_for_verification','ready')
     or v_dep.verification_state not in ('ready_for_verification','live_verified')
     or v_dep.url !~ '^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$' then
    raise exception 'RENDERABLE_PREVIEW_REVERIFY_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id;
  if not found or v_ver.build_job_id is null then
    raise exception 'RENDERABLE_PREVIEW_REVERIFY_VERSION_INVALID' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_build_jobs
  where id=v_ver.build_job_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id;
  if not found then
    raise exception 'RENDERABLE_PREVIEW_REVERIFY_BUILD_INVALID' using errcode='22023';
  end if;

  v_verification:=private.pandora_worker_e_verify_supabase_preview_v2_20260830(
    v_dep.id,
    coalesce(p_requested_by,v_job.requested_by)
  );
  if upper(coalesce(v_verification->>'status',''))<>'PASS' then
    raise exception 'RENDERABLE_PREVIEW_REVERIFY_FAILED' using errcode='23514';
  end if;

  select * into v_run
  from public.pandora_verification_runs
  where id=(v_verification->>'verificationRunId')::uuid;
  if not found
     or upper(v_run.status)<>'PASS'
     or v_run.project_id<>v_dep.project_id
     or v_run.project_version_id<>v_ver.id
     or v_run.build_job_id<>v_ver.build_job_id
     or v_run.preview_deployment_id<>v_dep.provider_deployment_id
     or v_run.source_digest is distinct from v_ver.source_sha256
     or v_run.artifact_digest is distinct from v_ver.artifact_digest_sha256
     or v_run.builder_identity is not distinct from v_run.verifier_identity then
    raise exception 'RENDERABLE_PREVIEW_REVERIFY_PROOF_INVALID' using errcode='23514';
  end if;

  update public.pandora_project_deployments
  set status='ready',
      verification_state='live_verified',
      failed_at=null,
      ready_at=coalesce(ready_at,v_now),
      last_provider_check_at=v_now,
      updated_at=v_now
  where id=v_dep.id;

  update public.pandora_runtime_environments
  set status='ready',
      verification_state='live_verified',
      last_reconciled_at=v_now,
      updated_at=v_now
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and environment='preview'
    and current_deployment_id=v_dep.id;
  v_current:=found;

  if v_current then
    update public.projectos_projects
    set config=jsonb_set(
          coalesce(config,'{}'::jsonb),
          '{customerJourney}',
          coalesce(config->'customerJourney','{}'::jsonb) ||
            jsonb_build_object(
              'stage','preview_ready',
              'runtimeStatus','ready',
              'previewUrl',v_dep.url,
              'previewProvider','supabase_preview',
              'previewVersionId',v_ver.id::text,
              'previewDeploymentId',v_dep.provider_deployment_id,
              'previewVerificationState','verified',
              'runtimeUpdatedAt',v_now
            ),
          true
        ),
        updated_at=v_now
    where id=v_dep.project_id
      and organization_id=v_dep.organization_id;
  end if;

  return jsonb_build_object(
    'state','ready',
    'deploymentId',v_dep.id,
    'projectVersionId',v_ver.id,
    'verificationRunId',v_run.id,
    'currentPreview',v_current
  );
end
$function$;

comment on function private.pandora_finalize_renderable_preview_reverification_20260906(uuid,uuid) is
'Finalizes a fresh transport-bound PASS for a Supabase preview. Historical previews are re-certified without moving the current preview pointer or visible project URL.';

commit;
