begin;

create or replace function private.pandora_commit_generated_build_intake_v3_20260901(
  p_organization_id uuid,p_project_id uuid,p_project_spec_id uuid,p_requested_by uuid,p_idempotency_key text,
  p_source_sha256 text,p_source_byte_size bigint,p_storage_path text,p_model_run_id uuid,p_build_adapter text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
  v_job public.pandora_build_jobs%rowtype; v_spec public.pandora_project_specs%rowtype;
  v_model_run public.pandora_model_runs%rowtype; v_existing_version public.pandora_project_versions%rowtype;
  v_existing_artifact public.pandora_artifact_versions%rowtype;
  v_artifact_id uuid; v_artifact_version_id uuid; v_parent_artifact_version_id uuid;
  v_project_version_id uuid:=gen_random_uuid(); v_artifact_version integer; v_parent_artifact_version integer;
  v_parent_project_version_id uuid; v_authz jsonb;
begin
  if p_source_sha256 !~ '^[0-9a-f]{64}$' or p_source_byte_size<=0 or p_source_byte_size>26214400 then
    raise exception 'BUILD_INTAKE_SOURCE_INVALID' using errcode='22023';
  end if;
  if p_storage_path is null or length(p_storage_path)>1024 or p_storage_path ~ '(^/|\.\.|\\|\x00)' then
    raise exception 'BUILD_INTAKE_STORAGE_PATH_INVALID' using errcode='22023';
  end if;
  if p_build_adapter not in ('static-web','node-vite-web','node-next-web','flutter-web','flutter-android-apk') then
    raise exception 'BUILD_INTAKE_ADAPTER_INVALID' using errcode='22023';
  end if;

  select * into v_job from public.pandora_build_jobs where organization_id=p_organization_id and project_id=p_project_id
    and idempotency_key=trim(p_idempotency_key) limit 1 for update;
  if not found then
    return private.pandora_commit_generated_build_intake_v2_20260829(
      p_organization_id,p_project_id,p_project_spec_id,p_requested_by,p_idempotency_key,p_source_sha256,
      p_source_byte_size,p_storage_path,p_model_run_id,p_build_adapter);
  end if;
  if v_job.project_spec_id<>p_project_spec_id or v_job.requested_by is distinct from p_requested_by or v_job.job_kind<>'build' then
    raise exception 'BUILD_INTAKE_ADMITTED_JOB_MISMATCH' using errcode='23514';
  end if;

  select * into v_model_run from public.pandora_model_runs where id=p_model_run_id and organization_id=p_organization_id
    and project_id=p_project_id and project_spec_id=p_project_spec_id and status='succeeded' for update;
  if not found then raise exception 'BUILD_INTAKE_MODEL_RUN_INVALID' using errcode='23514'; end if;
  if v_model_run.build_job_id is not null and v_model_run.build_job_id<>v_job.id then
    raise exception 'BUILD_INTAKE_MODEL_RUN_COLLISION' using errcode='23514';
  end if;

  if v_job.target_project_version_id is not null then
    select * into v_existing_version from public.pandora_project_versions pv
      where pv.id=v_job.target_project_version_id and pv.organization_id=p_organization_id and pv.project_id=p_project_id
        and pv.project_spec_id=p_project_spec_id and pv.build_job_id=v_job.id and pv.created_by is not distinct from p_requested_by
      for share;
    if not found or v_existing_version.root_artifact_version_id is null then
      raise exception 'BUILD_INTAKE_REPLAY_PROVENANCE_UNVERIFIABLE' using errcode='23514';
    end if;
    select * into v_existing_artifact from public.pandora_artifact_versions av
      where av.id=v_existing_version.root_artifact_version_id and av.organization_id=p_organization_id and av.project_id=p_project_id
      for share;
    if not found then raise exception 'BUILD_INTAKE_REPLAY_PROVENANCE_UNVERIFIABLE' using errcode='23514'; end if;

    if v_existing_version.source_sha256 is distinct from p_source_sha256
      or v_existing_artifact.content_sha256 is distinct from p_source_sha256
      or v_existing_artifact.byte_size is distinct from p_source_byte_size
      or coalesce(v_existing_version.source_payload->>'buildAdapter','')<>p_build_adapter
      or coalesce(v_existing_artifact.provenance_redacted->>'buildAdapter','')<>p_build_adapter then
      raise exception 'BUILD_INTAKE_REPLAY_COLLISION' using errcode='23514';
    end if;

    if v_existing_version.source_payload ? 'generatedModelRunId' then
      if v_existing_version.source_payload->>'generatedModelRunId'<>p_model_run_id::text
        or v_existing_version.source_payload->>'generatedStoragePath'<>p_storage_path
        or (v_existing_version.source_payload->>'generatedSourceByteSize')::bigint<>p_source_byte_size then
        raise exception 'BUILD_INTAKE_REPLAY_COLLISION' using errcode='23514';
      end if;
    else
      if v_model_run.build_job_id is distinct from v_job.id
        or v_existing_artifact.produced_by_model_run_id is distinct from p_model_run_id
        or v_existing_artifact.storage_provider<>'supabase_storage'
        or v_existing_artifact.storage_bucket<>'pandora-build-artifacts'
        or v_existing_artifact.storage_path is distinct from p_storage_path then
        raise exception 'BUILD_INTAKE_REPLAY_PROVENANCE_UNVERIFIABLE' using errcode='23514';
      end if;
    end if;

    select jsonb_build_object('buildJobId',t.build_job_id,'projectVersionId',t.project_version_id,'toolCallId',t.id,
      'tool','request_build@1','capability','build.execute','actionHash',t.action_hash,'argumentsSha256',t.arguments_sha256,
      'decision',t.decision,'environment',t.environment) into v_authz
    from public.pandora_tool_calls t where t.build_job_id=v_job.id and t.tool_name='request_build' and t.tool_version='1'
      and t.decision='ALLOW' and t.status='authorized' limit 1;
    return jsonb_build_object('state',case when v_job.status='succeeded' then 'ready'
      when v_job.status in ('failed','cancelled') then 'blocked' else 'working' end,
      'buildJobId',v_job.id,'projectVersionId',v_job.target_project_version_id,
      'sourceArtifactVersionId',v_existing_artifact.id,'sourceSha256',p_source_sha256,'buildAdapter',p_build_adapter,
      'authorization',v_authz,'replayed',true);
  end if;

  if v_job.status<>'queued' or v_job.cancel_requested_at is not null then
    raise exception 'BUILD_INTAKE_ADMITTED_JOB_NOT_ATTACHABLE' using errcode='55000';
  end if;
  select * into v_spec from public.pandora_project_specs where id=p_project_spec_id and organization_id=p_organization_id
    and project_id=p_project_id and source_intent_id=v_job.source_intent_id and status='active' for share;
  if not found then raise exception 'BUILD_INTAKE_PROJECT_SPEC_STALE' using errcode='23514'; end if;
  select q.base_version_id into v_parent_project_version_id from public.pandora_source_generation_queue q
    where q.organization_id=p_organization_id and q.project_id=p_project_id and q.project_spec_id=p_project_spec_id
      and q.idempotency_key=trim(p_idempotency_key) and q.build_job_id=v_job.id order by q.created_at desc limit 1;
  if v_parent_project_version_id is not null and not exists(select 1 from public.pandora_project_versions pv
    where pv.id=v_parent_project_version_id and pv.organization_id=p_organization_id and pv.project_id=p_project_id) then
    raise exception 'BUILD_INTAKE_PARENT_VERSION_INVALID' using errcode='23514';
  end if;

  insert into public.pandora_artifacts(organization_id,project_id,logical_key,artifact_kind)
    values(p_organization_id,p_project_id,'source:'||p_project_spec_id::text,'source_snapshot')
    on conflict(project_id,logical_key) do update set logical_key=excluded.logical_key returning id into v_artifact_id;
  select id into v_artifact_version_id from public.pandora_artifact_versions
    where artifact_id=v_artifact_id and content_sha256=p_source_sha256 limit 1;
  if v_artifact_version_id is null then
    select id,version into v_parent_artifact_version_id,v_parent_artifact_version from public.pandora_artifact_versions
      where artifact_id=v_artifact_id order by version desc limit 1 for share;
    if found then v_artifact_version:=v_parent_artifact_version+1; else v_artifact_version:=1; v_parent_artifact_version_id:=null; end if;
    v_artifact_version_id:=gen_random_uuid();
    insert into public.pandora_artifact_versions(id,organization_id,project_id,artifact_id,version,parent_version_id,
      content_sha256,byte_size,media_type,storage_provider,storage_bucket,storage_path,produced_by_model_run_id,provenance_redacted)
    values(v_artifact_version_id,p_organization_id,p_project_id,v_artifact_id,v_artifact_version,v_parent_artifact_version_id,
      p_source_sha256,p_source_byte_size,'application/json','supabase_storage','pandora-build-artifacts',p_storage_path,p_model_run_id,
      jsonb_build_object('projectSpecId',p_project_spec_id,'sourceIntentId',v_job.source_intent_id,'buildAdapter',p_build_adapter,
        'parentArtifactVersionId',v_parent_artifact_version_id));
  end if;
  insert into public.pandora_project_versions(id,organization_id,project_id,kind,source_payload,source_sha256,created_by,
    project_spec_id,parent_version_id,root_artifact_version_id,lifecycle_status)
  values(v_project_version_id,p_organization_id,p_project_id,'preview',
    jsonb_build_object('kind','artifact_snapshot','artifactVersionId',v_artifact_version_id,'buildAdapter',p_build_adapter,
      'generatedModelRunId',p_model_run_id,'generatedStoragePath',p_storage_path,'generatedSourceByteSize',p_source_byte_size),
    p_source_sha256,p_requested_by,p_project_spec_id,v_parent_project_version_id,v_artifact_version_id,'draft');
  update public.pandora_build_jobs set target_project_version_id=v_project_version_id,current_stage='building',updated_at=clock_timestamp()
    where id=v_job.id and target_project_version_id is null and status='queued';
  if not found then raise exception 'BUILD_INTAKE_ATTACH_RACE' using errcode='55000'; end if;
  update public.pandora_project_versions set build_job_id=v_job.id where id=v_project_version_id;
  update public.pandora_model_runs set build_job_id=v_job.id where id=p_model_run_id and build_job_id is null;
  if not found and v_model_run.build_job_id is distinct from v_job.id then
    raise exception 'BUILD_INTAKE_MODEL_RUN_BIND_RACE' using errcode='55000';
  end if;
  insert into public.pandora_build_job_steps(organization_id,project_id,build_job_id,step_key,sequence,step_kind,status,
    idempotency_key,attempt_count,max_attempts,input_sha256,result_sha256,started_at,completed_at)
  values(p_organization_id,p_project_id,v_job.id,'source_snapshot',0,'source_generation','succeeded',trim(p_idempotency_key)||':source',
    1,1,v_spec.content_sha256,p_source_sha256,now(),now()) on conflict do nothing;
  v_authz:=private.pandora_authorize_generated_build_20260829(v_job.id);
  update public.pandora_build_stream_sessions set status='building',project_version_id=v_project_version_id,updated_at=clock_timestamp()
    where build_job_id=v_job.id and organization_id=p_organization_id and project_id=p_project_id;
  insert into public.pandora_build_job_events(organization_id,project_id,build_job_id,event_type,from_status,to_status,
    safe_payload,actor_type,idempotency_key)
  values(p_organization_id,p_project_id,v_job.id,'JOB_STATE_CHANGED','queued','queued',
    jsonb_build_object('stage','source_ready','projectVersionId',v_project_version_id,'sourceSha256',p_source_sha256),
    'system',trim(p_idempotency_key)||':source-ready');
  return jsonb_build_object('state','working','buildJobId',v_job.id,'projectVersionId',v_project_version_id,
    'sourceArtifactVersionId',v_artifact_version_id,'sourceSha256',p_source_sha256,'buildAdapter',p_build_adapter,
    'authorization',v_authz,'replayed',false);
end;$fn$;

commit;
