begin;

create or replace function private.pandora_backfill_missing_publish_receipt_for_reverification_20260906(
  p_deployment_id uuid
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
  v_preview public.pandora_project_deployments%rowtype;
  v_preview_run public.pandora_verification_runs%rowtype;
  v_prev_version uuid;
  v_prev_deployment uuid;
  v_receipt_id uuid;
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
  for update;

  if not found
     or v_dep.environment<>'production'
     or v_dep.provider<>'supabase_static'
     or v_dep.provider_project_id<>'pandora-preview-host'
     or v_dep.provider_state<>'READY'
     or v_dep.status<>'ready_for_verification'
     or v_dep.verification_state<>'ready_for_verification'
     or v_dep.promoted_from_id is null then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  if exists (
    select 1
    from public.pandora_publish_receipts r
    where r.production_deployment_id=v_dep.id
  ) then
    select r.id into v_receipt_id
    from public.pandora_publish_receipts r
    where r.production_deployment_id=v_dep.id
    limit 1;
    return jsonb_build_object(
      'state','ready',
      'deploymentId',v_dep.id,
      'receiptId',v_receipt_id,
      'replayed',true
    );
  end if;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and environment='production'
    and current_deployment_id=v_dep.id
    and current_version_id=v_dep.version_id;
  if not found or v_env.verification_state<>'ready_for_verification' then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_ENVIRONMENT_INVALID' using errcode='40001';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id;
  if not found
     or v_ver.source_sha256 is null
     or v_ver.artifact_digest_sha256 is null
     or v_ver.build_job_id is null
     or v_ver.project_spec_id is null then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_VERSION_INVALID' using errcode='22023';
  end if;

  select * into v_preview
  from public.pandora_project_deployments
  where id=v_dep.promoted_from_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and version_id=v_dep.version_id
    and environment='preview'
    and provider='supabase_preview'
    and provider_state='READY'
    and status='ready'
    and verification_state='live_verified';
  if not found then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_PREVIEW_INVALID' using errcode='23514';
  end if;

  select * into v_preview_run
  from public.pandora_verification_runs
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and project_version_id=v_ver.id
    and build_job_id=v_ver.build_job_id
    and project_spec_id=v_ver.project_spec_id
    and status='PASS'
    and target_environment='preview'
    and required_check_profile='static_site'
    and preview_deployment_id=v_preview.provider_deployment_id
    and source_kind=v_ver.source_kind
    and source_ref=v_ver.source_ref
    and source_commit is not distinct from v_ver.source_commit
    and source_digest=v_ver.source_sha256
    and artifact_digest=v_ver.artifact_digest_sha256
    and migration_set_digest is not distinct from v_ver.migration_set_digest_sha256
    and runtime_target_digest is not distinct from v_ver.runtime_target_digest_sha256
    and completed_at is not null
  order by completed_at desc
  limit 1;
  if not found then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_PREVIEW_PROOF_INVALID' using errcode='23514';
  end if;

  select d.version_id,d.id
  into v_prev_version,v_prev_deployment
  from public.pandora_project_deployments d
  where d.organization_id=v_dep.organization_id
    and d.project_id=v_dep.project_id
    and d.environment='production'
    and d.id<>v_dep.id
  order by d.created_at desc
  limit 1;

  insert into public.pandora_publish_receipts(
    organization_id,
    project_id,
    version_id,
    production_deployment_id,
    provider,
    provider_resource_id,
    source_sha256,
    artifact_digest,
    preview_verification_run_id,
    previous_production_version_id,
    previous_production_deployment_id,
    production_result_url,
    status
  ) values (
    v_dep.organization_id,
    v_dep.project_id,
    v_dep.version_id,
    v_dep.id,
    v_dep.provider,
    v_dep.provider_deployment_id,
    v_dep.source_sha256,
    v_dep.artifact_digest,
    v_preview_run.id::text,
    v_prev_version,
    v_prev_deployment,
    coalesce(v_dep.immutable_url,v_dep.url),
    'awaiting_production_verification'
  )
  on conflict(production_deployment_id) do nothing
  returning id into v_receipt_id;

  if v_receipt_id is null then
    select id into v_receipt_id
    from public.pandora_publish_receipts
    where production_deployment_id=v_dep.id;
  end if;
  if v_receipt_id is null then
    raise exception 'PUBLISH_RECEIPT_BACKFILL_INSERT_FAILED' using errcode='40001';
  end if;

  return jsonb_build_object(
    'state','ready',
    'deploymentId',v_dep.id,
    'receiptId',v_receipt_id,
    'previewVerificationRunId',v_preview_run.id,
    'replayed',false
  );
end
$function$;

revoke all on function private.pandora_backfill_missing_publish_receipt_for_reverification_20260906(uuid)
from public,anon,authenticated;
grant execute on function private.pandora_backfill_missing_publish_receipt_for_reverification_20260906(uuid)
to service_role;

comment on function private.pandora_backfill_missing_publish_receipt_for_reverification_20260906(uuid) is
'Backfills a missing legacy publish receipt only for the exact current Supabase static production deployment, requiring its promoted-from preview and a fresh independent PASS for identical source/artifact lineage.';

commit;
