begin;

create or replace function private.pandora_rotate_expiring_supabase_preview_capability_20260906(
  p_deployment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','extensions'
as $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_facts jsonb;
  v_old_expires timestamptz;
  v_new_expires timestamptz:=clock_timestamp()+interval '7 days';
  v_token text;
  v_token_hash text;
  v_url text;
  v_now timestamptz:=clock_timestamp();
  v_current boolean:=false;
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
  for update;

  if not found
     or v_dep.provider<>'supabase_preview'
     or v_dep.environment<>'preview'
     or v_dep.provider_project_id<>'pandora-preview-host'
     or v_dep.provider_state<>'READY'
     or v_dep.provider_deployment_id !~ '^spv_[0-9a-f]{32}$'
     or v_dep.url !~ '^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$' then
    raise exception 'PREVIEW_CAPABILITY_ROTATION_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id;
  if not found
     or v_ver.root_artifact_version_id is null
     or v_ver.artifact_digest_sha256 is null
     or v_ver.source_sha256 is null then
    raise exception 'PREVIEW_CAPABILITY_ROTATION_VERSION_INVALID' using errcode='22023';
  end if;

  select * into v_op
  from public.pandora_runtime_operations
  where project_id=v_dep.project_id
    and project_version_id=v_dep.version_id
    and action='create_preview'
    and idempotency_key=v_dep.idempotency_key
    and status='succeeded'
    and provider_resource_id=v_dep.provider_deployment_id
  order by created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'PREVIEW_CAPABILITY_ROTATION_OPERATION_INVALID' using errcode='22023';
  end if;

  v_facts:=coalesce(v_op.result_facts,'{}'::jsonb);
  if v_facts->>'previewProvider'<>'supabase_preview'
     or v_facts->>'providerDeploymentId'<>v_dep.provider_deployment_id
     or lower(coalesce(v_facts->>'artifactDigest',''))<>v_ver.artifact_digest_sha256 then
    raise exception 'PREVIEW_CAPABILITY_ROTATION_FACTS_INVALID' using errcode='23514';
  end if;

  begin
    v_old_expires:=(v_facts->>'previewCapabilityExpiresAt')::timestamptz;
  exception when others then
    v_old_expires:=null;
  end;
  if v_old_expires is null then
    raise exception 'PREVIEW_CAPABILITY_ROTATION_EXPIRY_INVALID' using errcode='23514';
  end if;

  if v_old_expires > v_now + interval '1 day' then
    return jsonb_build_object(
      'state','ready',
      'deploymentId',v_dep.id,
      'rotated',false,
      'expiresAt',v_old_expires
    );
  end if;

  v_token:=encode(
    extensions.digest(
      convert_to(
        gen_random_uuid()::text||'|'||clock_timestamp()::text||'|'||
        v_dep.id::text||'|'||v_ver.artifact_digest_sha256,
        'utf8'
      ),
      'sha256'
    ),
    'hex'
  );
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  v_url:='https://mcpmaster.vercel.app/preview/'||v_token||'/index.html';

  update public.pandora_runtime_operations
  set result_facts=v_facts || jsonb_build_object(
        'previewCapabilityHash',v_token_hash,
        'previewCapabilityExpiresAt',v_new_expires,
        'verificationState','ready_for_verification',
        'capabilityRotatedAt',v_now
      ),
      last_reconciled_at=v_now,
      updated_at=v_now
  where id=v_op.id;

  update public.pandora_project_deployments
  set url=v_url,
      immutable_url=v_url,
      stable_url=v_url,
      expires_at=v_new_expires,
      status='ready_for_verification',
      verification_state='ready_for_verification',
      last_provider_check_at=v_now,
      updated_at=v_now
  where id=v_dep.id;

  update public.pandora_runtime_environments
  set verification_state='ready_for_verification',
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
              'runtimeStatus','verifying',
              'previewUrl',v_url,
              'previewProvider','supabase_preview',
              'previewVersionId',v_dep.version_id::text,
              'previewDeploymentId',v_dep.provider_deployment_id,
              'previewVerificationState','ready_for_verification',
              'runtimeUpdatedAt',v_now
            ),
          true
        ),
        updated_at=v_now
    where id=v_dep.project_id
      and organization_id=v_dep.organization_id;
  end if;

  return jsonb_build_object(
    'state','working',
    'stage','preview_reverification',
    'deploymentId',v_dep.id,
    'rotated',true,
    'currentPreview',v_current,
    'expiresAt',v_new_expires
  );
end
$function$;

revoke all on function private.pandora_rotate_expiring_supabase_preview_capability_20260906(uuid)
from public,anon,authenticated;
grant execute on function private.pandora_rotate_expiring_supabase_preview_capability_20260906(uuid)
to service_role;

comment on function private.pandora_rotate_expiring_supabase_preview_capability_20260906(uuid) is
'Rotates only expired or near-expiry Supabase preview capabilities while preserving exact deployment, version, artifact, and runtime-operation lineage. Forces fresh independent verification after rotation.';

commit;
