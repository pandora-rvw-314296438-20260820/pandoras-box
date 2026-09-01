begin;

-- Visible Creation lifecycle evidence reuses the existing bounded, HMAC-signed
-- execution_learning_outbox transport. Existing execution-plan rows retain their
-- plan_id identity; lifecycle rows use an explicit immutable event_key instead.
alter table private.execution_learning_outbox
  add column if not exists event_key text;

alter table private.execution_learning_outbox
  alter column plan_id drop not null;

alter table private.execution_learning_outbox
  drop constraint if exists execution_learning_outbox_identity_check;

alter table private.execution_learning_outbox
  add constraint execution_learning_outbox_identity_check
  check (plan_id is not null or nullif(btrim(event_key), '') is not null);

create unique index if not exists execution_learning_outbox_event_key_key
  on private.execution_learning_outbox(event_key)
  where event_key is not null;

create or replace function private.visible_creation_evidence_basis(
  p_evidence_kind text,
  p_proof_stage text,
  p_visible_project_id uuid,
  p_project_version_id uuid,
  p_build_job_id uuid,
  p_verification_run_id uuid,
  p_deployment_id uuid,
  p_publish_receipt_id uuid,
  p_source_sha256 text,
  p_artifact_sha256 text,
  p_failure_fingerprint text,
  p_recurrence_count integer,
  p_repair_action_hash text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select array_to_string(array[
    'visible-creation-evidence-v1',
    coalesce(p_evidence_kind, ''),
    coalesce(p_proof_stage, ''),
    coalesce(p_visible_project_id::text, ''),
    coalesce(p_project_version_id::text, ''),
    coalesce(p_build_job_id::text, ''),
    coalesce(p_verification_run_id::text, ''),
    coalesce(p_deployment_id::text, ''),
    coalesce(p_publish_receipt_id::text, ''),
    coalesce(lower(p_source_sha256), ''),
    coalesce(lower(p_artifact_sha256), ''),
    coalesce(lower(p_failure_fingerprint), ''),
    coalesce(p_recurrence_count::text, ''),
    coalesce(lower(p_repair_action_hash), '')
  ], E'\n')
$$;

create or replace function private.enqueue_visible_creation_memory_evidence(
  p_source_event_id uuid,
  p_organization_id uuid,
  p_visible_project_id uuid,
  p_evidence_kind text,
  p_proof_stage text,
  p_completed_at timestamptz,
  p_project_version_id uuid default null,
  p_build_job_id uuid default null,
  p_verification_run_id uuid default null,
  p_deployment_id uuid default null,
  p_publish_receipt_id uuid default null,
  p_source_sha256 text default null,
  p_artifact_sha256 text default null,
  p_failure_fingerprint text default null,
  p_recurrence_count integer default null,
  p_repair_action_hash text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_memory_project_id constant uuid := '7c686cbd-d968-49d5-86cc-918f5e777bd2'::uuid;
  v_memory_project_key constant text := 'mcpmaster-pandoras-box';
  v_context_hash text;
  v_payload jsonb;
  v_event_key text;
  v_outbox_id uuid;
  v_existing_payload jsonb;
begin
  if p_source_event_id is null or p_organization_id is null or p_visible_project_id is null then
    raise exception 'VISIBLE_MEMORY_EVIDENCE_IDENTITY_REQUIRED' using errcode='22023';
  end if;
  if p_evidence_kind not in ('verified_build','verified_preview','verified_publish','verified_repair','repeated_failure') then
    raise exception 'VISIBLE_MEMORY_EVIDENCE_KIND_INVALID' using errcode='22023';
  end if;
  if p_proof_stage not in ('tested','deployed','production_verified') then
    raise exception 'VISIBLE_MEMORY_EVIDENCE_STAGE_INVALID' using errcode='22023';
  end if;
  if p_evidence_kind='verified_preview' and p_proof_stage not in ('deployed','production_verified') then
    raise exception 'VISIBLE_MEMORY_EVIDENCE_STAGE_INVALID' using errcode='22023';
  end if;
  if p_evidence_kind='verified_publish' and p_proof_stage <> 'production_verified' then
    raise exception 'VISIBLE_MEMORY_EVIDENCE_STAGE_INVALID' using errcode='22023';
  end if;
  if p_evidence_kind='verified_build'
     and (p_build_job_id is null or p_project_version_id is null or p_verification_run_id is null
          or p_source_sha256 !~ '^[0-9a-f]{64}$' or p_artifact_sha256 !~ '^[0-9a-f]{64}$') then
    raise exception 'VISIBLE_MEMORY_BUILD_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;
  if p_evidence_kind='verified_preview'
     and (p_project_version_id is null or p_verification_run_id is null or p_deployment_id is null
          or p_source_sha256 !~ '^[0-9a-f]{64}$' or p_artifact_sha256 !~ '^[0-9a-f]{64}$') then
    raise exception 'VISIBLE_MEMORY_PREVIEW_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;
  if p_evidence_kind='verified_publish'
     and (p_project_version_id is null or p_verification_run_id is null or p_deployment_id is null or p_publish_receipt_id is null
          or p_source_sha256 !~ '^[0-9a-f]{64}$' or p_artifact_sha256 !~ '^[0-9a-f]{64}$') then
    raise exception 'VISIBLE_MEMORY_PUBLISH_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;
  if p_evidence_kind='verified_repair'
     and (p_build_job_id is null or p_project_version_id is null or p_verification_run_id is null
          or p_source_sha256 !~ '^[0-9a-f]{64}$' or p_artifact_sha256 !~ '^[0-9a-f]{64}$'
          or p_failure_fingerprint !~ '^[0-9a-f]{64}$' or p_repair_action_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'VISIBLE_MEMORY_REPAIR_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;
  if p_evidence_kind='repeated_failure'
     and (p_build_job_id is null or p_failure_fingerprint !~ '^[0-9a-f]{64}$' or coalesce(p_recurrence_count,0) < 2) then
    raise exception 'VISIBLE_MEMORY_FAILURE_EVIDENCE_INCOMPLETE' using errcode='22023';
  end if;

  v_context_hash := encode(extensions.digest(private.visible_creation_evidence_basis(
    p_evidence_kind,p_proof_stage,p_visible_project_id,p_project_version_id,p_build_job_id,
    p_verification_run_id,p_deployment_id,p_publish_receipt_id,lower(p_source_sha256),
    lower(p_artifact_sha256),lower(p_failure_fingerprint),p_recurrence_count,lower(p_repair_action_hash)
  ),'sha256'),'hex');

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'schema_version',1,
    'product_key','projectos',
    'source_event_id',p_source_event_id,
    'source_request_id',p_source_event_id,
    'organization_id',p_organization_id,
    'intake_id',null,
    'project_id',v_memory_project_id,
    'project_key',v_memory_project_key,
    'tool','visible_creation.'||p_evidence_kind,
    'risk','write',
    'outcome_status',case when p_evidence_kind='repeated_failure' then 'failed' else 'completed' end,
    'duration_ms',0,
    'completed_at',to_char(coalesce(p_completed_at,clock_timestamp()) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'context_status','available',
    'context_hash',v_context_hash,
    'result_fingerprint',case when p_evidence_kind='repeated_failure' then null else lower(p_source_sha256) end,
    'error_fingerprint',case when p_evidence_kind='repeated_failure' then lower(p_failure_fingerprint) else null end,
    'privacy_policy','metadata_only_v1',
    'learning_kind','visible_creation_evidence_v1',
    'evidence_kind',p_evidence_kind,
    'proof_stage',p_proof_stage,
    'visible_project_id',p_visible_project_id,
    'project_version_id',p_project_version_id,
    'build_job_id',p_build_job_id,
    'verification_run_id',p_verification_run_id,
    'deployment_id',p_deployment_id,
    'publish_receipt_id',p_publish_receipt_id,
    'source_sha256',lower(p_source_sha256),
    'artifact_sha256',lower(p_artifact_sha256),
    'failure_fingerprint',lower(p_failure_fingerprint),
    'recurrence_count',p_recurrence_count,
    'repair_action_hash',lower(p_repair_action_hash)
  ));
  v_event_key := 'visible:'||p_evidence_kind||':'||p_source_event_id::text;

  select payload,id into v_existing_payload,v_outbox_id
  from private.execution_learning_outbox
  where event_key=v_event_key;
  if v_outbox_id is not null then
    if v_existing_payload is distinct from v_payload then
      raise exception 'VISIBLE_MEMORY_EVIDENCE_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return v_outbox_id;
  end if;

  insert into private.execution_learning_outbox(
    plan_id,event_key,organization_id,request_id,intake_id,project_id,project_key,payload,
    delivery_status,next_attempt_at,created_at,updated_at
  ) values (
    null,v_event_key,p_organization_id,p_source_event_id,null,p_visible_project_id,v_memory_project_key,v_payload,
    'pending',now(),now(),now()
  )
  on conflict (event_key) where event_key is not null do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select payload,id into v_existing_payload,v_outbox_id
    from private.execution_learning_outbox where event_key=v_event_key;
    if v_outbox_id is null or v_existing_payload is distinct from v_payload then
      raise exception 'VISIBLE_MEMORY_EVIDENCE_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return v_outbox_id;
  end if;

  begin
    perform private.dispatch_execution_learning(v_outbox_id);
  exception when others then
    update private.execution_learning_outbox
      set delivery_status='pending',last_error=left(sqlerrm,1000),next_attempt_at=now(),updated_at=now()
    where id=v_outbox_id and delivery_status <> 'delivered';
  end;
  return v_outbox_id;
end;
$$;

create or replace function private.enqueue_visible_build_failure_memory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_fingerprint text;
begin
  if new.status <> 'failed' or new.error_code is null
     or (tg_op='UPDATE' and old.status is not distinct from new.status) then
    return new;
  end if;
  if new.error_code !~ '^[A-Z0-9_:-]{2,96}$' then return new; end if;
  select count(*)::integer into v_count
  from public.pandora_build_jobs j
  where j.project_id=new.project_id and j.status='failed' and j.error_code=new.error_code
    and coalesce(j.completed_at,j.updated_at) >= coalesce(new.completed_at,new.updated_at)-interval '7 days'
    and coalesce(j.completed_at,j.updated_at) <= coalesce(new.completed_at,new.updated_at);
  if v_count <> 2 then return new; end if;
  v_fingerprint := encode(extensions.digest(
    'visible-build-failure-v1'||E'\n'||new.project_id::text||E'\n'||new.error_code,'sha256'),'hex');
  perform private.enqueue_visible_creation_memory_evidence(
    new.id,new.organization_id,new.project_id,'repeated_failure','tested',coalesce(new.completed_at,new.updated_at),
    null,new.id,null,null,null,null,null,v_fingerprint,v_count,null
  );
  return new;
end;
$$;

drop trigger if exists pandora_visible_build_failure_memory on public.pandora_build_jobs;
create trigger pandora_visible_build_failure_memory
after insert or update of status on public.pandora_build_jobs
for each row execute function private.enqueue_visible_build_failure_memory();

create or replace function private.enqueue_visible_verification_memory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.pandora_build_jobs%rowtype;
  v_failure_code text;
  v_failure_count integer;
  v_failure_fingerprint text;
  v_repair_hash text;
begin
  if new.status <> 'PASS' or new.build_job_id is null
     or (tg_op='UPDATE' and old.status is not distinct from new.status) then
    return new;
  end if;
  select * into v_job from public.pandora_build_jobs
  where id=new.build_job_id and organization_id=new.organization_id and project_id=new.project_id;
  if v_job.id is null or v_job.status <> 'succeeded' then return new; end if;
  if new.source_digest !~ '^[0-9a-f]{64}$' or new.artifact_digest !~ '^[0-9a-f]{64}$' then return new; end if;

  perform private.enqueue_visible_creation_memory_evidence(
    new.id,new.organization_id,new.project_id,'verified_build','tested',coalesce(new.completed_at,new.created_at),
    new.project_version_id,new.build_job_id,new.id,null,null,new.source_digest,new.artifact_digest,null,null,null
  );

  select j.error_code,count(*)::integer
    into v_failure_code,v_failure_count
  from public.pandora_build_jobs j
  where j.project_id=new.project_id and j.status='failed' and j.error_code ~ '^[A-Z0-9_:-]{2,96}$'
    and coalesce(j.completed_at,j.updated_at) >= v_job.created_at-interval '7 days'
    and coalesce(j.completed_at,j.updated_at) < v_job.created_at
  group by j.error_code
  having count(*) >= 2
  order by max(coalesce(j.completed_at,j.updated_at)) desc
  limit 1;

  if v_failure_code is not null then
    v_failure_fingerprint := encode(extensions.digest(
      'visible-build-failure-v1'||E'\n'||new.project_id::text||E'\n'||v_failure_code,'sha256'),'hex');
    v_repair_hash := encode(extensions.digest(
      'visible-repair-action-v1'||E'\n'||new.build_job_id::text||E'\n'||new.project_version_id::text||E'\n'||new.source_digest||E'\n'||new.artifact_digest,
      'sha256'),'hex');
    perform private.enqueue_visible_creation_memory_evidence(
      new.id,new.organization_id,new.project_id,'verified_repair','tested',coalesce(new.completed_at,new.created_at),
      new.project_version_id,new.build_job_id,new.id,null,null,new.source_digest,new.artifact_digest,
      v_failure_fingerprint,v_failure_count,v_repair_hash
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_visible_verification_memory on public.pandora_verification_runs;
create trigger pandora_visible_verification_memory
after insert or update of status on public.pandora_verification_runs
for each row execute function private.enqueue_visible_verification_memory();

create or replace function private.enqueue_visible_preview_memory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.pandora_project_versions%rowtype;
  v_verification public.pandora_verification_runs%rowtype;
begin
  if new.environment <> 'preview' or new.verification_state <> 'live_verified'
     or (tg_op='UPDATE' and old.verification_state is not distinct from new.verification_state) then
    return new;
  end if;
  if new.source_sha256 !~ '^[0-9a-f]{64}$' or new.artifact_digest !~ '^[0-9a-f]{64}$' then return new; end if;
  select * into v_version from public.pandora_project_versions
    where id=new.version_id and organization_id=new.organization_id and project_id=new.project_id;
  if v_version.id is null or v_version.verification_run_id is null then return new; end if;
  select * into v_verification from public.pandora_verification_runs
    where id=v_version.verification_run_id and organization_id=new.organization_id and project_id=new.project_id
      and project_version_id=new.version_id and status='PASS';
  if v_verification.id is null or v_verification.source_digest <> new.source_sha256
     or v_verification.artifact_digest <> new.artifact_digest then return new; end if;
  perform private.enqueue_visible_creation_memory_evidence(
    new.id,new.organization_id,new.project_id,'verified_preview','deployed',coalesce(new.ready_at,new.updated_at),
    new.version_id,null,v_verification.id,new.id,null,new.source_sha256,new.artifact_digest,null,null,null
  );
  return new;
end;
$$;

drop trigger if exists pandora_visible_preview_memory on public.pandora_project_deployments;
create trigger pandora_visible_preview_memory
after insert or update of verification_state on public.pandora_project_deployments
for each row execute function private.enqueue_visible_preview_memory();

create or replace function private.enqueue_visible_publish_memory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deployment public.pandora_project_deployments%rowtype;
  v_verification public.pandora_verification_runs%rowtype;
  v_verification_id uuid;
begin
  if new.status <> 'live_verified'
     or (tg_op='UPDATE' and old.status is not distinct from new.status) then return new; end if;
  if new.source_sha256 !~ '^[0-9a-f]{64}$' or new.artifact_digest !~ '^[0-9a-f]{64}$'
     or new.production_verification_run_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return new;
  end if;
  v_verification_id := new.production_verification_run_id::uuid;
  select * into v_deployment from public.pandora_project_deployments
    where id=new.production_deployment_id and organization_id=new.organization_id and project_id=new.project_id
      and version_id=new.version_id and environment='production' and verification_state='live_verified';
  if v_deployment.id is null or v_deployment.source_sha256 <> new.source_sha256
     or v_deployment.artifact_digest <> new.artifact_digest then return new; end if;
  select * into v_verification from public.pandora_verification_runs
    where id=v_verification_id and organization_id=new.organization_id and project_id=new.project_id
      and project_version_id=new.version_id and status='PASS'
      and source_digest=new.source_sha256 and artifact_digest=new.artifact_digest;
  if v_verification.id is null then return new; end if;
  perform private.enqueue_visible_creation_memory_evidence(
    new.id,new.organization_id,new.project_id,'verified_publish','production_verified',coalesce(new.published_at,new.updated_at),
    new.version_id,null,v_verification.id,new.production_deployment_id,new.id,new.source_sha256,new.artifact_digest,null,null,null
  );
  return new;
end;
$$;

drop trigger if exists pandora_visible_publish_memory on public.pandora_publish_receipts;
create trigger pandora_visible_publish_memory
after insert or update of status on public.pandora_publish_receipts
for each row execute function private.enqueue_visible_publish_memory();

revoke all on function private.visible_creation_evidence_basis(text,text,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,text) from public,anon,authenticated;
revoke all on function private.enqueue_visible_creation_memory_evidence(uuid,uuid,uuid,text,text,timestamptz,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,text) from public,anon,authenticated;
revoke all on function private.enqueue_visible_build_failure_memory() from public,anon,authenticated;
revoke all on function private.enqueue_visible_verification_memory() from public,anon,authenticated;
revoke all on function private.enqueue_visible_preview_memory() from public,anon,authenticated;
revoke all on function private.enqueue_visible_publish_memory() from public,anon,authenticated;

comment on function private.enqueue_visible_creation_memory_evidence(uuid,uuid,uuid,text,text,timestamptz,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,text)
is 'Queues metadata-only Visible Creation lifecycle evidence through the existing bounded HMAC Memory learning outbox. Never carries raw prompts, source, env values, credentials, or provider error text.';

commit;
