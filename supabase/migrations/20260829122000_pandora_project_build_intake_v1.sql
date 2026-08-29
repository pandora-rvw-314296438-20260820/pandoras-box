
-- Governed generated-source intake for the customer Build journey.
-- Source bytes stay in a private content-addressed Storage bucket; the database stores immutable lineage only.

do $bucket$
begin
  if to_regclass('storage.buckets') is not null then
    execute $sql$
      insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      values ('pandora-build-artifacts', 'pandora-build-artifacts', false, 26214400, array['application/json']::text[])
      on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types,
          updated_at = now()
    $sql$;
  end if;
end
$bucket$;

create or replace function private.pandora_commit_generated_build_intake_20260829(
  p_organization_id uuid,
  p_project_id uuid,
  p_project_spec_id uuid,
  p_requested_by uuid,
  p_idempotency_key text,
  p_source_sha256 text,
  p_source_byte_size bigint,
  p_storage_path text,
  p_model_run_id uuid,
  p_build_adapter text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec public.pandora_project_specs%rowtype;
  v_existing public.pandora_build_jobs%rowtype;
  v_artifact_id uuid;
  v_artifact_version_id uuid;
  v_project_version_id uuid := gen_random_uuid();
  v_build_job_id uuid := gen_random_uuid();
  v_sequence bigint;
  v_artifact_version integer;
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
  if not found then
    raise exception 'BUILD_INTAKE_PROJECT_SPEC_STALE' using errcode='23514';
  end if;
  v_source_intent_id := v_spec.source_intent_id;

  if not exists (
    select 1 from public.organization_memberships
    where organization_id = p_organization_id and user_id = p_requested_by and status = 'active'
  ) then
    raise exception 'BUILD_INTAKE_REQUESTER_NOT_MEMBER' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.pandora_model_runs
    where id = p_model_run_id and organization_id = p_organization_id and project_id = p_project_id
      and project_spec_id = p_project_spec_id and status = 'succeeded'
  ) then
    raise exception 'BUILD_INTAKE_MODEL_RUN_INVALID' using errcode='23514';
  end if;

  insert into public.pandora_artifacts (organization_id, project_id, logical_key, artifact_kind)
  values (p_organization_id, p_project_id, 'source:' || p_project_spec_id::text, 'source_snapshot')
  on conflict (project_id, logical_key) do update set logical_key = excluded.logical_key
  returning id into v_artifact_id;

  select id into v_artifact_version_id
  from public.pandora_artifact_versions
  where artifact_id = v_artifact_id and content_sha256 = p_source_sha256
  limit 1;

  if v_artifact_version_id is null then
    select coalesce(max(version), 0) + 1 into v_artifact_version
    from public.pandora_artifact_versions where artifact_id = v_artifact_id;
    v_artifact_version_id := gen_random_uuid();
    insert into public.pandora_artifact_versions (
      id, organization_id, project_id, artifact_id, version, content_sha256, byte_size, media_type,
      storage_provider, storage_bucket, storage_path, produced_by_model_run_id, provenance_redacted
    ) values (
      v_artifact_version_id, p_organization_id, p_project_id, v_artifact_id, v_artifact_version,
      p_source_sha256, p_source_byte_size, 'application/json', 'supabase_storage', 'pandora-build-artifacts', p_storage_path,
      p_model_run_id,
      jsonb_build_object('projectSpecId', p_project_spec_id, 'sourceIntentId', v_source_intent_id, 'buildAdapter', p_build_adapter)
    );
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_sequence
  from public.pandora_project_versions where project_id = p_project_id;

  insert into public.pandora_project_versions (
    id, organization_id, project_id, sequence_no, kind, source_payload, source_sha256, created_by,
    project_spec_id, root_artifact_version_id, lifecycle_status
  ) values (
    v_project_version_id, p_organization_id, p_project_id, v_sequence, 'preview',
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
    'state','working',
    'buildJobId',v_build_job_id,
    'projectVersionId',v_project_version_id,
    'sourceArtifactVersionId',v_artifact_version_id,
    'sourceSha256',p_source_sha256,
    'buildAdapter',p_build_adapter
  );
end;
$$;

revoke all on function private.pandora_commit_generated_build_intake_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) from public, anon, authenticated;
grant execute on function private.pandora_commit_generated_build_intake_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) to service_role;

create or replace function public.pandora_project_build_status_20260829(p_project_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select coalesce((
    select jsonb_build_object(
      'buildJobId', j.id,
      'state', case when j.status = 'succeeded' then 'ready' when j.status = 'failed' then 'blocked' else 'working' end,
      'stage', j.current_stage,
      'projectVersionId', j.target_project_version_id,
      'updatedAt', j.updated_at,
      'errorSummary', j.public_error_summary
    )
    from public.pandora_build_jobs j
    where j.project_id = p_project_id
      and exists (
        select 1 from public.organization_memberships m
        where m.organization_id = j.organization_id and m.user_id = auth.uid() and m.status = 'active'
      )
    order by j.created_at desc
    limit 1
  ), jsonb_build_object('state','not_started'));
$$;

grant execute on function public.pandora_project_build_status_20260829(uuid) to authenticated;
revoke all on function public.pandora_project_build_status_20260829(uuid) from anon;
