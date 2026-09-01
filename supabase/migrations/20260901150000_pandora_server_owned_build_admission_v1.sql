-- Pandora Visible Creation — Server-Owned Build Admission v1
begin;

create or replace function private.pandora_admit_authorized_build_v1(
  p_authorization_id uuid,
  p_stream_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
  v_auth public.pandora_build_authorization_receipts%rowtype;
  v_spec public.pandora_project_specs%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_stream public.pandora_build_stream_sessions%rowtype;
  v_queue public.pandora_source_generation_queue%rowtype;
  v_base_version_id uuid;
  v_key text;
begin
  if p_authorization_id is null or p_stream_idempotency_key is null
     or length(trim(p_stream_idempotency_key)) not between 8 and 200 then
    raise exception 'BUILD_ADMISSION_REQUEST_INVALID' using errcode='22023';
  end if;
  select * into v_auth from public.pandora_build_authorization_receipts
   where id=p_authorization_id for update;
  if not found then raise exception 'BUILD_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;
  if trim(v_auth.idempotency_key)<>trim(p_stream_idempotency_key) then
    raise exception 'BUILD_ADMISSION_IDEMPOTENCY_MISMATCH' using errcode='23514';
  end if;
  select * into v_spec from public.pandora_project_specs
   where id=v_auth.project_spec_id and organization_id=v_auth.organization_id
     and project_id=v_auth.project_id and source_intent_id=v_auth.source_intent_id
     and content_sha256=v_auth.approved_spec_sha256 and status='active' for share;
  if not found then raise exception 'BUILD_ADMISSION_PROJECT_SPEC_STALE' using errcode='23514'; end if;
  if not exists(select 1 from public.memberships m where m.organization_id=v_auth.organization_id
      and m.user_id=v_auth.authorized_by and m.status::text='active') then
    raise exception 'BUILD_ADMISSION_REQUESTER_NOT_MEMBER' using errcode='42501';
  end if;

  v_key:='pandora-admission:'||v_auth.id::text;
  perform pg_advisory_xact_lock(hashtextextended(v_auth.organization_id::text||':'||v_auth.project_id::text||':'||v_key,0));
  select * into v_job from public.pandora_build_jobs
   where organization_id=v_auth.organization_id and project_id=v_auth.project_id and idempotency_key=v_key
   limit 1 for update;
  if found then
    if v_job.project_spec_id<>v_auth.project_spec_id or v_job.source_intent_id is distinct from v_auth.source_intent_id
       or v_job.requested_by is distinct from v_auth.authorized_by or v_job.job_kind<>'build' then
      raise exception 'BUILD_ADMISSION_COLLISION' using errcode='23505';
    end if;
    select * into v_stream from public.pandora_build_stream_sessions
     where organization_id=v_auth.organization_id and project_id=v_auth.project_id and build_job_id=v_job.id
     order by created_at limit 1;
    select * into v_queue from public.pandora_source_generation_queue
     where build_job_id=v_job.id order by created_at limit 1;
    if v_stream.id is null or v_queue.id is null then
      raise exception 'BUILD_ADMISSION_PARTIAL_STATE' using errcode='55000';
    end if;
    return jsonb_build_object('state',case when v_job.status='succeeded' then 'ready'
      when v_job.status in ('failed','cancelled') then 'blocked' else 'working' end,
      'authorizationId',v_auth.id,'buildJobId',v_job.id,'streamId',v_stream.id,
      'sourceQueueId',v_queue.id,'projectSpecId',v_auth.project_spec_id,
      'projectVersionId',v_job.target_project_version_id,'admittedAt',v_auth.admitted_at,'replayed',true);
  end if;

  select pv.id into v_base_version_id from public.pandora_project_versions pv
   where pv.organization_id=v_auth.organization_id and pv.project_id=v_auth.project_id
     and pv.lifecycle_status in ('verified','preview_ready','live') order by pv.created_at desc limit 1;
  insert into public.pandora_build_jobs(
    organization_id,project_id,project_spec_id,source_intent_id,requested_by,job_kind,status,
    current_stage,idempotency_key,max_attempts,deadline_at
  ) values (
    v_auth.organization_id,v_auth.project_id,v_auth.project_spec_id,v_auth.source_intent_id,v_auth.authorized_by,
    'build','queued','building',v_key,3,clock_timestamp()+interval '30 minutes'
  ) returning * into v_job;
  perform private.pandora_bind_build_authorization_v1(v_auth.id,v_job.id);
  select * into v_auth from public.pandora_build_authorization_receipts where id=v_auth.id;
  insert into public.pandora_source_generation_queue(
    organization_id,project_id,project_spec_id,requested_by,reason,base_version_id,attempt_no,status,idempotency_key,build_job_id
  ) values (
    v_auth.organization_id,v_auth.project_id,v_auth.project_spec_id,v_auth.authorized_by,'active_spec',
    v_base_version_id,0,'queued',v_key,v_job.id
  ) returning * into v_queue;
  insert into public.pandora_build_stream_sessions(
    organization_id,project_id,requested_by,idempotency_key,status,build_job_id
  ) values (
    v_auth.organization_id,v_auth.project_id,v_auth.authorized_by,trim(p_stream_idempotency_key),'queued',v_job.id
  ) returning * into v_stream;
  insert into public.pandora_build_job_events(
    organization_id,project_id,build_job_id,event_type,to_status,safe_payload,actor_type,actor_id,idempotency_key
  ) values (
    v_auth.organization_id,v_auth.project_id,v_job.id,'BUILD_REQUESTED','queued',
    jsonb_build_object('authorizationId',v_auth.id,'projectSpecId',v_auth.project_spec_id,'streamId',v_stream.id,'sourceQueueId',v_queue.id),
    'user',v_auth.authorized_by::text,v_key||':admitted'
  );
  insert into public.pandora_build_stream_events(
    stream_id,organization_id,project_id,build_job_id,event_type,safe_payload
  ) values (
    v_stream.id,v_auth.organization_id,v_auth.project_id,v_job.id,'build_admitted',
    jsonb_build_object('authorizationId',v_auth.id,'buildJobId',v_job.id,'projectSpecId',v_auth.project_spec_id,
      'sourceQueueId',v_queue.id,'admittedAt',v_auth.admitted_at)
  );
  return jsonb_build_object('state','working','authorizationId',v_auth.id,'buildJobId',v_job.id,
    'streamId',v_stream.id,'sourceQueueId',v_queue.id,'projectSpecId',v_auth.project_spec_id,
    'projectVersionId',null,'admittedAt',v_auth.admitted_at,'replayed',false);
end;$fn$;

create or replace function public.pandora_admit_authorized_build_service_v1(
  p_authorization_id uuid,p_stream_idempotency_key text
) returns jsonb language sql security definer set search_path='' as $fn$
  select private.pandora_admit_authorized_build_v1(p_authorization_id,p_stream_idempotency_key)
$fn$;
revoke all on function public.pandora_admit_authorized_build_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_admit_authorized_build_service_v1(uuid,text) to service_role;

create or replace function private.pandora_claim_source_fastpath_v1(p_queue_id uuid,p_build_job_id uuid)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare v_claimed boolean:=false;
begin
  update public.pandora_source_generation_queue q set status='dispatching',dispatch_count=dispatch_count+1,
    dispatched_at=clock_timestamp(),request_id=null,last_error_code=null,updated_at=clock_timestamp()
  where q.id=p_queue_id and q.build_job_id=p_build_job_id and q.status='queued' and q.dispatch_count<5
    and exists(select 1 from public.pandora_build_jobs j where j.id=p_build_job_id
      and j.organization_id=q.organization_id and j.project_id=q.project_id and j.project_spec_id=q.project_spec_id
      and j.status='queued' and j.target_project_version_id is null and j.cancel_requested_at is null);
  v_claimed:=found; return v_claimed;
end;$fn$;
create or replace function public.pandora_claim_source_fastpath_service_v1(p_queue_id uuid,p_build_job_id uuid)
returns boolean language sql security definer set search_path='' as $fn$
  select private.pandora_claim_source_fastpath_v1(p_queue_id,p_build_job_id)
$fn$;
revoke all on function public.pandora_claim_source_fastpath_service_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.pandora_claim_source_fastpath_service_v1(uuid,uuid) to service_role;

create or replace function private.pandora_commit_generated_build_intake_v3_20260901(
  p_organization_id uuid,p_project_id uuid,p_project_spec_id uuid,p_requested_by uuid,p_idempotency_key text,
  p_source_sha256 text,p_source_byte_size bigint,p_storage_path text,p_model_run_id uuid,p_build_adapter text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
  v_job public.pandora_build_jobs%rowtype; v_spec public.pandora_project_specs%rowtype;
  v_artifact_id uuid; v_artifact_version_id uuid; v_parent_artifact_version_id uuid;
  v_project_version_id uuid:=gen_random_uuid(); v_artifact_version integer; v_parent_artifact_version integer;
  v_parent_project_version_id uuid; v_authz jsonb;
begin
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
  if v_job.target_project_version_id is not null then
    select jsonb_build_object('buildJobId',t.build_job_id,'projectVersionId',t.project_version_id,'toolCallId',t.id,
      'tool','request_build@1','capability','build.execute','actionHash',t.action_hash,'argumentsSha256',t.arguments_sha256,
      'decision',t.decision,'environment',t.environment) into v_authz
    from public.pandora_tool_calls t where t.build_job_id=v_job.id and t.tool_name='request_build' and t.tool_version='1'
      and t.decision='ALLOW' and t.status='authorized' limit 1;
    return jsonb_build_object('state',case when v_job.status='succeeded' then 'ready'
      when v_job.status in ('failed','cancelled') then 'blocked' else 'working' end,
      'buildJobId',v_job.id,'projectVersionId',v_job.target_project_version_id,'authorization',v_authz,'replayed',true);
  end if;
  if v_job.status<>'queued' or v_job.cancel_requested_at is not null then
    raise exception 'BUILD_INTAKE_ADMITTED_JOB_NOT_ATTACHABLE' using errcode='55000';
  end if;
  if p_source_sha256 !~ '^[0-9a-f]{64}$' or p_source_byte_size<=0 or p_source_byte_size>26214400 then
    raise exception 'BUILD_INTAKE_SOURCE_INVALID' using errcode='22023';
  end if;
  if p_storage_path is null or length(p_storage_path)>1024 or p_storage_path ~ '(^/|\.\.|\\|\x00)' then
    raise exception 'BUILD_INTAKE_STORAGE_PATH_INVALID' using errcode='22023';
  end if;
  if p_build_adapter not in ('static-web','node-vite-web','node-next-web','flutter-web','flutter-android-apk') then
    raise exception 'BUILD_INTAKE_ADAPTER_INVALID' using errcode='22023';
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
  if not exists(select 1 from public.pandora_model_runs where id=p_model_run_id and organization_id=p_organization_id
    and project_id=p_project_id and project_spec_id=p_project_spec_id and status='succeeded') then
    raise exception 'BUILD_INTAKE_MODEL_RUN_INVALID' using errcode='23514';
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
    jsonb_build_object('kind','artifact_snapshot','artifactVersionId',v_artifact_version_id,'buildAdapter',p_build_adapter),
    p_source_sha256,p_requested_by,p_project_spec_id,v_parent_project_version_id,v_artifact_version_id,'draft');
  update public.pandora_build_jobs set target_project_version_id=v_project_version_id,current_stage='building',updated_at=clock_timestamp()
    where id=v_job.id and target_project_version_id is null and status='queued';
  if not found then raise exception 'BUILD_INTAKE_ATTACH_RACE' using errcode='55000'; end if;
  update public.pandora_project_versions set build_job_id=v_job.id where id=v_project_version_id;
  update public.pandora_model_runs set build_job_id=v_job.id where id=p_model_run_id and build_job_id is null;
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

create or replace function public.pandora_commit_generated_build_intake_service_20260830(
  p_organization_id uuid,p_project_id uuid,p_project_spec_id uuid,p_requested_by uuid,p_idempotency_key text,
  p_source_sha256 text,p_source_byte_size bigint,p_storage_path text,p_model_run_id uuid,p_build_adapter text
) returns jsonb language sql security definer set search_path='' as $fn$
  select private.pandora_commit_generated_build_intake_v3_20260901(
    p_organization_id,p_project_id,p_project_spec_id,p_requested_by,p_idempotency_key,p_source_sha256,
    p_source_byte_size,p_storage_path,p_model_run_id,p_build_adapter)
$fn$;
revoke all on function public.pandora_commit_generated_build_intake_service_20260830(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_commit_generated_build_intake_service_20260830(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text)
  to service_role;

create index if not exists pandora_source_generation_queue_build_job_idx
  on public.pandora_source_generation_queue(build_job_id,status,updated_at) where build_job_id is not null;
commit;
