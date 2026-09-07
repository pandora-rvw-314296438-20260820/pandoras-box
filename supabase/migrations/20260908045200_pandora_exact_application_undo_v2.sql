-- Pandora exact application Undo v2
-- Keeps application restore distinct from production rollback.
-- The mutation is atomic: exact current version -> exact verified parent preview
-- plus preview runtime pointer and customer journey in one database transaction.

create or replace function private.pandora_apply_application_undo_v2(
  p_organization_id uuid,
  p_project_id uuid,
  p_expected_version_id uuid,
  p_parent_version_id uuid,
  p_parent_preview_deployment_id uuid,
  p_parent_preview_url text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_current public.pandora_project_versions%rowtype;
  v_parent public.pandora_project_versions%rowtype;
  v_parent_preview public.pandora_project_deployments%rowtype;
  v_preview_env public.pandora_runtime_environments%rowtype;
  v_production_env public.pandora_runtime_environments%rowtype;
  v_latest_id uuid;
  v_project public.projectos_projects%rowtype;
  v_parent_is_production boolean := false;
  v_now timestamptz := clock_timestamp();
  v_next_config jsonb;
begin
  if p_organization_id is null
     or p_project_id is null
     or p_expected_version_id is null
     or p_parent_version_id is null
     or p_parent_preview_deployment_id is null
     or nullif(trim(coalesce(p_parent_preview_url,'')),'') is null then
    raise exception 'INVALID_UNDO_REQUEST' using errcode='22023';
  end if;

  select *
    into v_project
  from public.projectos_projects
  where id=p_project_id
    and organization_id=p_organization_id
  for update;
  if not found then
    raise exception 'PROJECT_NOT_FOUND' using errcode='22023';
  end if;

  select *
    into v_current
  from public.pandora_project_versions
  where id=p_expected_version_id
    and organization_id=p_organization_id
    and project_id=p_project_id
  for update;
  if not found then
    raise exception 'EXACT_VERSION_REQUIRED' using errcode='22023';
  end if;

  if v_current.parent_version_id is distinct from p_parent_version_id then
    raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
  end if;

  select v.id
    into v_latest_id
  from public.pandora_project_versions v
  where v.organization_id=p_organization_id
    and v.project_id=p_project_id
    and v.root_artifact_version_id is not null
    and v.artifact_digest_sha256 is not null
    and v.lifecycle_status in ('built','verification_pending','verified','preview_ready','live')
  order by v.created_at desc, v.id desc
  limit 1;

  if v_latest_id is distinct from p_expected_version_id then
    if v_current.lifecycle_status='rolled_back' then
      -- Idempotent replay is accepted only when the exact parent is already current below.
      null;
    else
      raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
    end if;
  end if;

  select *
    into v_production_env
  from public.pandora_runtime_environments
  where organization_id=p_organization_id
    and project_id=p_project_id
    and environment='production'
  for update;

  if v_current.lifecycle_status in ('live','production_candidate')
     or v_production_env.current_version_id=p_expected_version_id then
    raise exception 'UNDO_REQUIRES_ROLLBACK' using errcode='55000';
  end if;

  if v_current.lifecycle_status not in ('built','verification_pending','verified','preview_ready','rolled_back') then
    raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
  end if;

  select *
    into v_parent
  from public.pandora_project_versions
  where id=p_parent_version_id
    and organization_id=p_organization_id
    and project_id=p_project_id
  for share;
  if not found
     or v_parent.lifecycle_status not in ('verified','preview_ready','live') then
    raise exception 'UNDO_PARENT_NOT_VERIFIED' using errcode='55000';
  end if;

  select *
    into v_parent_preview
  from public.pandora_project_deployments
  where id=p_parent_preview_deployment_id
    and organization_id=p_organization_id
    and project_id=p_project_id
    and version_id=p_parent_version_id
    and environment='preview'
  for share;
  if not found
     or v_parent_preview.status<>'ready'
     or v_parent_preview.verification_state<>'live_verified'
     or v_parent_preview.source_sha256 is distinct from v_parent.source_sha256
     or v_parent_preview.artifact_digest is distinct from v_parent.artifact_digest_sha256
     or v_parent_preview.source_commit_sha is distinct from v_parent.source_commit
     or v_parent_preview.url is distinct from p_parent_preview_url then
    raise exception 'UNDO_PARENT_PREVIEW_UNAVAILABLE' using errcode='55000';
  end if;

  select *
    into v_preview_env
  from public.pandora_runtime_environments
  where organization_id=p_organization_id
    and project_id=p_project_id
    and environment='preview'
  for update;

  if found then
    if v_preview_env.current_version_id=p_expected_version_id then
      update public.pandora_runtime_environments
      set current_version_id=p_parent_version_id,
          current_deployment_id=p_parent_preview_deployment_id,
          status='ready',
          verification_state='live_verified',
          last_reconciled_at=v_now,
          updated_at=v_now
      where id=v_preview_env.id
        and current_version_id=p_expected_version_id;
      if not found then
        raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
      end if;
    elsif not (
      v_current.lifecycle_status='rolled_back'
      and v_preview_env.current_version_id=p_parent_version_id
      and v_preview_env.current_deployment_id=p_parent_preview_deployment_id
      and v_preview_env.status='ready'
      and v_preview_env.verification_state='live_verified'
    ) then
      raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
    end if;
  end if;

  if v_current.lifecycle_status<>'rolled_back' then
    update public.pandora_project_versions
    set lifecycle_status='rolled_back'
    where id=p_expected_version_id
      and organization_id=p_organization_id
      and project_id=p_project_id
      and parent_version_id=p_parent_version_id
      and lifecycle_status in ('built','verification_pending','verified','preview_ready');
    if not found then
      raise exception 'UNDO_PRECONDITION_MISMATCH' using errcode='40001';
    end if;
  end if;

  v_parent_is_production := v_production_env.current_version_id=p_parent_version_id;
  v_next_config :=
    coalesce(v_project.config,'{}'::jsonb)
    || jsonb_build_object(
      'customerJourney',
      coalesce(v_project.config->'customerJourney','{}'::jsonb)
      || jsonb_build_object(
        'stage',case when v_parent_is_production then 'live' else 'preview_ready' end,
        'runtimeStatus','ready',
        'previewUrl',p_parent_preview_url,
        'productionCandidateUrl',null,
        'runtimeUpdatedAt',v_now
      )
    );

  update public.projectos_projects
  set config=v_next_config,
      updated_at=v_now
  where id=p_project_id
    and organization_id=p_organization_id;
  if not found then
    raise exception 'BACKEND_WRITE_FAILED' using errcode='55000';
  end if;

  return jsonb_build_object(
    'ok',true,
    'projectId',p_project_id,
    'undoneVersionId',p_expected_version_id,
    'restoredVersionId',p_parent_version_id,
    'restoredPreviewDeploymentId',p_parent_preview_deployment_id,
    'restoredPreviewUrl',p_parent_preview_url,
    'parentIsProduction',v_parent_is_production,
    'completedAt',v_now
  );
end;
$$;

revoke all on function private.pandora_apply_application_undo_v2(
  uuid,uuid,uuid,uuid,uuid,text
) from public, anon, authenticated;
grant execute on function private.pandora_apply_application_undo_v2(
  uuid,uuid,uuid,uuid,uuid,text
) to service_role;

create or replace function private.pandora_project_experience_undo_guard_v2()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_version public.pandora_project_versions%rowtype;
begin
  if new.can_undo then
    if new.current_version_id is null
       or new.current_version_id=new.production_version_id then
      new.can_undo := false;
      return new;
    end if;

    select *
      into v_version
    from public.pandora_project_versions
    where id=new.current_version_id
      and organization_id=new.organization_id
      and project_id=new.project_id;

    if not found
       or v_version.parent_version_id is null
       or v_version.lifecycle_status not in ('built','verification_pending','verified','preview_ready') then
      new.can_undo := false;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pandora_project_experience_undo_guard_v2() from public;

drop trigger if exists pandora_project_experience_undo_guard_v2
  on public.pandora_project_experience_projection;
create trigger pandora_project_experience_undo_guard_v2
before insert or update on public.pandora_project_experience_projection
for each row execute function private.pandora_project_experience_undo_guard_v2();

-- Recompute all rows so the stricter fail-closed can_undo truth is visible immediately.
do $$
declare
  r record;
begin
  for r in
    select id from public.projectos_projects order by created_at,id
  loop
    perform private.pandora_refresh_project_experience_projection_v1(r.id);
  end loop;
end;
$$;

do $$
begin
  if exists (
    select 1
    from public.pandora_project_experience_projection e
    join public.pandora_project_versions v on v.id=e.current_version_id
    where e.can_undo
      and (
        e.current_version_id=e.production_version_id
        or v.parent_version_id is null
        or v.lifecycle_status not in ('built','verification_pending','verified','preview_ready')
      )
  ) then
    raise exception 'Exact Undo v2 invariant failed: can_undo exposes a non-undoable current version';
  end if;
end;
$$;
