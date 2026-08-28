
-- Pandora Worker A: durable orchestration, execution lineage, artifacts, verification, and policy bindings.
-- Provider/model/build/verifier execution remains outside Supabase; this migration persists durable control-plane truth only.

create table if not exists public.pandora_build_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  source_intent_id uuid null references public.pandora_project_intents(id) on delete restrict,
  target_project_version_id uuid null references public.pandora_project_versions(id) on delete restrict,
  workflow_run_id uuid null references public.workflow_runs(id) on delete set null,
  parent_job_id uuid null references public.pandora_build_jobs(id) on delete restrict,
  requested_by uuid null references auth.users(id) on delete set null,
  job_kind text not null,
  status text not null default 'queued',
  current_stage text not null default 'received',
  priority smallint not null default 50,
  idempotency_key text not null,
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  lease_owner text null,
  lease_token_sha256 text null,
  lease_expires_at timestamptz null,
  heartbeat_at timestamptz null,
  deadline_at timestamptz null,
  budget_cents bigint not null default 0,
  spent_cents bigint not null default 0,
  cancel_requested_at timestamptz null,
  cancel_reason text null,
  error_code text null,
  public_error_summary text null,
  worker_identity text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_build_jobs_kind_check check (job_kind in ('build','repair','verify','preview','publish','rollback')),
  constraint pandora_build_jobs_status_check check (status in ('queued','claimed','running','waiting_approval','waiting_verification','succeeded','failed','cancelled')),
  constraint pandora_build_jobs_stage_check check (current_stage in ('received','understanding','planning','designing','building','connecting','testing','repairing','verifying','previewing','preview_ready','awaiting_approval','publishing','live','rolling_back','needs_you','failed','cancelled')),
  constraint pandora_build_jobs_priority_check check (priority between 0 and 100),
  constraint pandora_build_jobs_attempt_check check (attempt_count >= 0 and max_attempts between 1 and 100 and attempt_count <= max_attempts),
  constraint pandora_build_jobs_idempotency_check check (length(trim(idempotency_key)) between 8 and 200),
  constraint pandora_build_jobs_budget_check check (budget_cents >= 0 and spent_cents >= 0),
  constraint pandora_build_jobs_lease_hash_check check (lease_token_sha256 is null or lease_token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_build_jobs_lease_shape_check check ((lease_owner is null and lease_token_sha256 is null and lease_expires_at is null) or (lease_owner is not null and lease_token_sha256 is not null and lease_expires_at is not null)),
  constraint pandora_build_jobs_completion_check check ((status in ('succeeded','failed','cancelled')) = (completed_at is not null)),
  constraint pandora_build_jobs_project_org_check check (private.pandora_control_plane_project_org_matches(organization_id, project_id))
);
create unique index if not exists pandora_build_jobs_idempotency_uidx on public.pandora_build_jobs(organization_id, project_id, idempotency_key);
create index if not exists pandora_build_jobs_project_created_idx on public.pandora_build_jobs(project_id, created_at desc);
create index if not exists pandora_build_jobs_active_idx on public.pandora_build_jobs(organization_id, status, priority desc, created_at) where status in ('queued','claimed','running','waiting_approval','waiting_verification');
create index if not exists pandora_build_jobs_expiring_lease_idx on public.pandora_build_jobs(lease_expires_at) where status in ('claimed','running') and lease_expires_at is not null;
create index if not exists pandora_build_jobs_spec_idx on public.pandora_build_jobs(project_spec_id, created_at desc);

create or replace function private.pandora_validate_build_job_lineage()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid; v_status text;
begin
  select s.organization_id, s.project_id into v_org, v_project from public.pandora_project_specs s where s.id = new.project_spec_id;
  if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'build job ProjectSpec lineage mismatch' using errcode='23514'; end if;
  if new.source_intent_id is not null then
    select i.organization_id, i.project_id into v_org, v_project from public.pandora_project_intents i where i.id = new.source_intent_id;
    if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'build job intent lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.target_project_version_id is not null then
    select v.organization_id, v.project_id into v_org, v_project from public.pandora_project_versions v where v.id = new.target_project_version_id;
    if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'build job target project version lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.workflow_run_id is not null then
    select w.organization_id into v_org from public.workflow_runs w where w.id = new.workflow_run_id;
    if v_org is null or v_org <> new.organization_id then raise exception 'build job workflow lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.parent_job_id is not null then
    select j.organization_id, j.project_id into v_org, v_project from public.pandora_build_jobs j where j.id = new.parent_job_id;
    if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'build job parent lineage mismatch' using errcode='23514'; end if;
  end if;
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    v_status := old.status || '>' || new.status;
    if v_status not in ('queued>claimed','queued>running','queued>failed','queued>cancelled','claimed>queued','claimed>running','claimed>failed','claimed>cancelled','running>queued','running>waiting_approval','running>waiting_verification','running>succeeded','running>failed','running>cancelled','waiting_approval>queued','waiting_approval>running','waiting_approval>failed','waiting_approval>cancelled','waiting_verification>running','waiting_verification>succeeded','waiting_verification>failed','waiting_verification>cancelled') then
      raise exception 'invalid build job state transition %', v_status using errcode='23514';
    end if;
  end if;
  if new.status in ('claimed','running') and (new.lease_owner is null or new.lease_token_sha256 is null or new.lease_expires_at is null) then raise exception 'active build job requires lease identity' using errcode='23514'; end if;
  if tg_op = 'UPDATE' then
    if new.organization_id <> old.organization_id or new.project_id <> old.project_id or new.project_spec_id <> old.project_spec_id or new.source_intent_id is distinct from old.source_intent_id or new.idempotency_key <> old.idempotency_key or new.job_kind <> old.job_kind or new.parent_job_id is distinct from old.parent_job_id or new.workflow_run_id is distinct from old.workflow_run_id then
      raise exception 'build job identity lineage is immutable' using errcode='23514';
    end if;
  end if;
  new.updated_at := now();
  if new.status = 'running' and new.started_at is null then new.started_at := now(); end if;
  if new.status in ('succeeded','failed','cancelled') and new.completed_at is null then new.completed_at := now(); elsif new.status not in ('succeeded','failed','cancelled') then new.completed_at := null; end if;
  return new;
end; $$;
drop trigger if exists pandora_build_jobs_lineage_guard on public.pandora_build_jobs;
create trigger pandora_build_jobs_lineage_guard before insert or update on public.pandora_build_jobs for each row execute function private.pandora_validate_build_job_lineage();

create table if not exists public.pandora_build_job_steps (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade, build_job_id uuid not null references public.pandora_build_jobs(id) on delete cascade, workflow_step_id uuid null references public.workflow_steps(id) on delete set null, step_key text not null, sequence integer not null, step_kind text not null, status text not null default 'pending', idempotency_key text null, attempt_count integer not null default 0, max_attempts integer not null default 3, error_code text null, public_error_summary text null, input_sha256 text null, result_sha256 text null, started_at timestamptz null, completed_at timestamptz null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pandora_build_job_steps_status_check check (status in ('pending','running','waiting_approval','succeeded','failed','skipped','cancelled')),
  constraint pandora_build_job_steps_sequence_check check (sequence >= 0),
  constraint pandora_build_job_steps_attempt_check check (attempt_count >= 0 and max_attempts between 1 and 100 and attempt_count <= max_attempts),
  constraint pandora_build_job_steps_hash_check check ((input_sha256 is null or input_sha256 ~ '^[0-9a-f]{64}$') and (result_sha256 is null or result_sha256 ~ '^[0-9a-f]{64}$'))
);
create unique index if not exists pandora_build_job_steps_key_uidx on public.pandora_build_job_steps(build_job_id, step_key);
create unique index if not exists pandora_build_job_steps_sequence_uidx on public.pandora_build_job_steps(build_job_id, sequence);
create index if not exists pandora_build_job_steps_status_idx on public.pandora_build_job_steps(build_job_id, status, sequence);

create or replace function private.pandora_validate_build_job_child()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  select j.organization_id, j.project_id into v_org, v_project from public.pandora_build_jobs j where j.id = new.build_job_id;
  if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then raise exception 'build job child lineage mismatch' using errcode='23514'; end if;
  if (to_jsonb(new)->>'workflow_step_id') is not null then
    select s.organization_id into v_org from public.workflow_steps s where s.id = nullif(to_jsonb(new)->>'workflow_step_id','')::uuid;
    if v_org is null or v_org <> new.organization_id then raise exception 'build step workflow lineage mismatch' using errcode='23514'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists pandora_build_job_steps_lineage_guard on public.pandora_build_job_steps;
create trigger pandora_build_job_steps_lineage_guard before insert or update on public.pandora_build_job_steps for each row execute function private.pandora_validate_build_job_child();

create table if not exists public.pandora_build_job_attempts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade, build_job_id uuid not null references public.pandora_build_jobs(id) on delete cascade, attempt_no integer not null, worker_identity text not null, lease_token_sha256 text not null, status text not null default 'running', failure_class text null, resource_usage_redacted jsonb not null default '{}'::jsonb, started_at timestamptz not null default now(), finished_at timestamptz null,
  constraint pandora_build_job_attempts_no_check check (attempt_no between 1 and 100), constraint pandora_build_job_attempts_status_check check (status in ('running','completed','failed','cancelled','expired')), constraint pandora_build_job_attempts_hash_check check (lease_token_sha256 ~ '^[0-9a-f]{64}$')
);
create unique index if not exists pandora_build_job_attempts_job_no_uidx on public.pandora_build_job_attempts(build_job_id, attempt_no);
create index if not exists pandora_build_job_attempts_worker_idx on public.pandora_build_job_attempts(worker_identity, started_at desc);
drop trigger if exists pandora_build_job_attempts_lineage_guard on public.pandora_build_job_attempts;
create trigger pandora_build_job_attempts_lineage_guard before insert or update on public.pandora_build_job_attempts for each row execute function private.pandora_validate_build_job_child();

create table if not exists public.pandora_build_job_events (
  id bigint generated always as identity primary key, organization_id uuid not null references public.organizations(id) on delete cascade, project_id uuid not null references public.projectos_projects(id) on delete cascade, build_job_id uuid not null references public.pandora_build_jobs(id) on delete cascade, event_type text not null, from_status text null, to_status text null, safe_payload jsonb not null default '{}'::jsonb, actor_type text not null default 'system', actor_id text null, request_id text null, idempotency_key text null, created_at timestamptz not null default now(),
  constraint pandora_build_job_events_type_check check (event_type in ('PROJECT_CREATED','INTENT_RECEIVED','SPEC_COMPILATION_REQUESTED','SPEC_READY','BUILD_REQUESTED','BUILD_STARTED','BUILD_STEP_STARTED','BUILD_STEP_COMPLETED','BUILD_FAILED','REPAIR_REQUESTED','REPAIR_STARTED','VERIFY_REQUESTED','VERIFICATION_STARTED','VERIFICATION_FAILED','VERIFICATION_PASSED','PREVIEW_REQUESTED','PREVIEW_READY','PUBLISH_REQUESTED','PUBLISH_STARTED','PUBLISHED','ROLLBACK_REQUESTED','ROLLED_BACK','CANCELLED','JOB_STATE_CHANGED'))
);
create index if not exists pandora_build_job_events_job_idx on public.pandora_build_job_events(build_job_id, id);
create index if not exists pandora_build_job_events_project_idx on public.pandora_build_job_events(project_id, created_at desc);
drop trigger if exists pandora_build_job_events_lineage_guard on public.pandora_build_job_events;
create trigger pandora_build_job_events_lineage_guard before insert on public.pandora_build_job_events for each row execute function private.pandora_validate_build_job_child();

create or replace function private.pandora_record_build_job_state_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status or new.current_stage is distinct from old.current_stage then
    insert into public.pandora_build_job_events(organization_id, project_id, build_job_id, event_type, from_status, to_status, safe_payload)
    values (new.organization_id,new.project_id,new.id,case when new.status='cancelled' then 'CANCELLED' when new.status='failed' and new.job_kind='build' then 'BUILD_FAILED' when new.status='succeeded' and new.current_stage='live' then 'PUBLISHED' else 'JOB_STATE_CHANGED' end,case when tg_op='UPDATE' then old.status else null end,new.status,jsonb_build_object('stage',new.current_stage));
  end if;
  return new;
end; $$;
drop trigger if exists pandora_build_jobs_state_event on public.pandora_build_jobs;
create trigger pandora_build_jobs_state_event after insert or update on public.pandora_build_jobs for each row execute function private.pandora_record_build_job_state_event();

create or replace function private.pandora_claim_build_job(p_job_id uuid,p_worker_identity text,p_lease_token_sha256 text,p_lease_seconds integer default 300)
returns public.pandora_build_jobs language plpgsql security definer set search_path = '' as $$
declare v_job public.pandora_build_jobs;
begin
  if nullif(trim(p_worker_identity),'') is null then raise exception 'worker identity is required' using errcode='22023'; end if;
  if p_lease_token_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'lease token digest must be sha256' using errcode='22023'; end if;
  if p_lease_seconds < 30 or p_lease_seconds > 1800 then raise exception 'lease seconds out of range' using errcode='22023'; end if;
  update public.pandora_build_jobs j set status='claimed',attempt_count=j.attempt_count+1,lease_owner=p_worker_identity,lease_token_sha256=p_lease_token_sha256,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),heartbeat_at=now(),worker_identity=p_worker_identity
  where j.id=p_job_id and j.attempt_count<j.max_attempts and j.status='queued' returning * into v_job;
  if v_job.id is null then raise exception 'build job unavailable for claim' using errcode='55000'; end if;
  insert into public.pandora_build_job_attempts(organization_id,project_id,build_job_id,attempt_no,worker_identity,lease_token_sha256) values(v_job.organization_id,v_job.project_id,v_job.id,v_job.attempt_count,p_worker_identity,p_lease_token_sha256);
  return v_job;
end; $$;
revoke all on function private.pandora_claim_build_job(uuid,text,text,integer) from public, anon, authenticated;
grant execute on function private.pandora_claim_build_job(uuid,text,text,integer) to service_role;

create or replace function private.pandora_heartbeat_build_job(p_job_id uuid,p_worker_identity text,p_lease_token_sha256 text,p_lease_seconds integer default 300)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_lease_seconds < 30 or p_lease_seconds > 1800 then raise exception 'lease seconds out of range' using errcode='22023'; end if;
  update public.pandora_build_jobs set heartbeat_at=now(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds)
  where id=p_job_id and status in ('claimed','running') and lease_owner=p_worker_identity and lease_token_sha256=p_lease_token_sha256 and lease_expires_at>now();
  return found;
end; $$;
revoke all on function private.pandora_heartbeat_build_job(uuid,text,text,integer) from public, anon, authenticated;
grant execute on function private.pandora_heartbeat_build_job(uuid,text,text,integer) to service_role;

create or replace function private.pandora_requeue_expired_build_jobs(p_limit integer default 100)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if p_limit<1 or p_limit>1000 then raise exception 'limit out of range' using errcode='22023'; end if;
  with candidates as (select id from public.pandora_build_jobs where status in ('claimed','running') and lease_expires_at<=now() and attempt_count<max_attempts order by lease_expires_at for update skip locked limit p_limit),
  updated as (update public.pandora_build_jobs j set status='queued',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,heartbeat_at=null,current_stage='received' from candidates c where j.id=c.id returning j.id,j.attempt_count)
  update public.pandora_build_job_attempts a set status='expired',finished_at=now() from updated u where a.build_job_id=u.id and a.attempt_no=u.attempt_count and a.status='running';
  get diagnostics v_count = row_count; return v_count;
end; $$;
revoke all on function private.pandora_requeue_expired_build_jobs(integer) from public, anon, authenticated;
grant execute on function private.pandora_requeue_expired_build_jobs(integer) to service_role;

create table if not exists public.pandora_model_runs (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,build_job_step_id uuid null references public.pandora_build_job_steps(id) on delete set null,request_id text not null,task text not null,output_mode text not null default 'structured',status text not null default 'queued',provider text null,model text null,model_revision text null,request_sha256 text not null,context_sha256 text null,schema_sha256 text null,response_sha256 text null,input_tokens bigint not null default 0,output_tokens bigint not null default 0,total_tokens bigint not null default 0,estimated_cost_micros bigint not null default 0,billed_cost_micros bigint not null default 0,attempt integer not null default 1,max_attempts integer not null default 1,error_code text null,error_public_summary text null,started_at timestamptz null,completed_at timestamptz null,created_at timestamptz not null default now(),
  constraint pandora_model_runs_task_check check (task in ('understand_intent','compile_project_spec','classify_task','plan_build','design_experience','plan_architecture','generate_code','repair_code','inspect_error','inspect_visual','write_copy','summarize_context','extract_structure','derive_acceptance_tests')),
  constraint pandora_model_runs_output_mode_check check (output_mode in ('text','json','structured','tool_proposals')),
  constraint pandora_model_runs_status_check check (status in ('queued','running','succeeded','failed','cancelled')),
  constraint pandora_model_runs_error_check check (error_code is null or error_code in ('provider_unavailable','timeout','rate_limited','authentication_failed','invalid_request','context_too_large','structured_output_invalid','unsupported_capability','budget_exhausted','provider_error')),
  constraint pandora_model_runs_hash_check check (request_sha256 ~ '^[0-9a-f]{64}$' and (context_sha256 is null or context_sha256 ~ '^[0-9a-f]{64}$') and (schema_sha256 is null or schema_sha256 ~ '^[0-9a-f]{64}$') and (response_sha256 is null or response_sha256 ~ '^[0-9a-f]{64}$')),
  constraint pandora_model_runs_usage_check check (input_tokens>=0 and output_tokens>=0 and total_tokens>=0 and estimated_cost_micros>=0 and billed_cost_micros>=0),constraint pandora_model_runs_attempt_check check (attempt between 1 and 100 and max_attempts between 1 and 100 and attempt<=max_attempts)
);
create unique index if not exists pandora_model_runs_request_uidx on public.pandora_model_runs(organization_id,request_id);
create index if not exists pandora_model_runs_job_idx on public.pandora_model_runs(build_job_id,created_at desc);
create index if not exists pandora_model_runs_project_idx on public.pandora_model_runs(project_id,created_at desc);

create table if not exists public.pandora_tool_calls (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,build_job_step_id uuid null references public.pandora_build_job_steps(id) on delete set null,model_run_id uuid null references public.pandora_model_runs(id) on delete set null,workflow_run_id uuid null references public.workflow_runs(id) on delete set null,workflow_step_id uuid null references public.workflow_steps(id) on delete set null,project_version_id uuid null references public.pandora_project_versions(id) on delete restrict,tool_name text not null,tool_version text not null,action_name text not null,environment text not null,target_resource_ref text null,policy_version text not null,action_hash text not null,arguments_sha256 text not null,risk_level text not null,decision text not null,side_effect text not null,retry_mode text not null,idempotency_mode text not null,idempotency_key text null,approval_required boolean not null default false,approval_id uuid null references public.approvals(id) on delete set null,status text not null default 'proposed',error_class text null,requested_at timestamptz not null default now(),started_at timestamptz null,completed_at timestamptz null,
  constraint pandora_tool_calls_environment_check check (environment in ('development','sandbox','test','preview','production')),constraint pandora_tool_calls_hash_check check (action_hash ~ '^[0-9a-f]{64}$' and arguments_sha256 ~ '^[0-9a-f]{64}$'),constraint pandora_tool_calls_risk_check check (risk_level in ('LOW','MEDIUM','HIGH','CRITICAL')),constraint pandora_tool_calls_decision_check check (decision in ('ALLOW','DENY','REQUIRE_APPROVAL','DEFER')),constraint pandora_tool_calls_side_effect_check check (side_effect in ('NONE','READ','PROJECT_MUTATION','EXTERNAL_MUTATION','PRODUCTION_MUTATION')),constraint pandora_tool_calls_retry_check check (retry_mode in ('SAFE_RETRY','IDEMPOTENT_RETRY','NO_AUTOMATIC_RETRY')),constraint pandora_tool_calls_idempotency_mode_check check (idempotency_mode in ('NONE','OPTIONAL','REQUIRED')),constraint pandora_tool_calls_status_check check (status in ('proposed','authorized','executing','succeeded','failed','denied','cancelled')),constraint pandora_tool_calls_error_class_check check (error_class is null or error_class in ('authorization','rate_limit','timeout','network','conflict','invalid_request','provider_unavailable','resource_missing','budget','policy_denied','approval_required','verification_required','ambiguous_mutation','internal'))
);
create unique index if not exists pandora_tool_calls_action_uidx on public.pandora_tool_calls(organization_id,action_hash);
create unique index if not exists pandora_tool_calls_idempotency_uidx on public.pandora_tool_calls(organization_id,project_id,idempotency_key) where idempotency_key is not null;
create index if not exists pandora_tool_calls_job_idx on public.pandora_tool_calls(build_job_id,requested_at desc);
create index if not exists pandora_tool_calls_model_idx on public.pandora_tool_calls(model_run_id,requested_at desc);

create table if not exists public.pandora_tool_results (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,tool_call_id uuid not null references public.pandora_tool_calls(id) on delete cascade,status text not null,result_sha256 text not null,public_summary text null,metadata_redacted jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),constraint pandora_tool_results_status_check check (status in ('success','failure','ambiguous')),constraint pandora_tool_results_hash_check check (result_sha256 ~ '^[0-9a-f]{64}$')
);
create unique index if not exists pandora_tool_results_call_uidx on public.pandora_tool_results(tool_call_id);

create table if not exists public.pandora_artifacts (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,logical_key text not null,artifact_kind text not null,created_at timestamptz not null default now(),constraint pandora_artifacts_kind_check check (artifact_kind in ('source_snapshot','build_output','log','test_report','verification_evidence','migration_bundle','runtime_bundle','document','other'))
);
create unique index if not exists pandora_artifacts_project_key_uidx on public.pandora_artifacts(project_id,logical_key);

create table if not exists public.pandora_artifact_versions (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,artifact_id uuid not null references public.pandora_artifacts(id) on delete cascade,version integer not null,parent_version_id uuid null references public.pandora_artifact_versions(id) on delete restrict,content_sha256 text not null,byte_size bigint not null,media_type text not null,storage_provider text not null,storage_bucket text null,storage_path text not null,produced_by_model_run_id uuid null references public.pandora_model_runs(id) on delete set null,produced_by_tool_call_id uuid null references public.pandora_tool_calls(id) on delete set null,produced_by_build_step_id uuid null references public.pandora_build_job_steps(id) on delete set null,provenance_redacted jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),constraint pandora_artifact_versions_version_check check (version>0),constraint pandora_artifact_versions_hash_check check (content_sha256 ~ '^[0-9a-f]{64}$'),constraint pandora_artifact_versions_size_check check (byte_size>=0)
);
create unique index if not exists pandora_artifact_versions_version_uidx on public.pandora_artifact_versions(artifact_id,version);
create unique index if not exists pandora_artifact_versions_content_uidx on public.pandora_artifact_versions(artifact_id,content_sha256);
create index if not exists pandora_artifact_versions_project_idx on public.pandora_artifact_versions(project_id,created_at desc);

create table if not exists public.pandora_verification_runs (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,project_version_id uuid not null references public.pandora_project_versions(id) on delete restrict,build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,source_commit text not null,source_digest text not null,artifact_digest text not null,migration_set_digest text null,runtime_target_digest text null,preview_deployment_id text null,target_environment text not null,required_check_profile text not null,requested_by uuid null references auth.users(id) on delete set null,builder_identity text null,verifier_identity text not null,identity_sha256 text not null,status text not null default 'PENDING',started_at timestamptz null,completed_at timestamptz null,created_at timestamptz not null default now(),
  constraint pandora_verification_runs_source_commit_check check (source_commit ~ '^[0-9a-f]{40}$'),constraint pandora_verification_runs_digest_check check (source_digest ~ '^[0-9a-f]{64}$' and artifact_digest ~ '^[0-9a-f]{64}$' and identity_sha256 ~ '^[0-9a-f]{64}$' and (migration_set_digest is null or migration_set_digest ~ '^[0-9a-f]{64}$') and (runtime_target_digest is null or runtime_target_digest ~ '^[0-9a-f]{64}$')),constraint pandora_verification_runs_environment_check check (target_environment in ('development','test','preview','production')),constraint pandora_verification_runs_status_check check (status in ('PENDING','RUNNING','PASS','FAIL','BLOCKED','INCONCLUSIVE','STALE')),constraint pandora_verification_runs_independence_check check (builder_identity is null or builder_identity <> verifier_identity)
);
create unique index if not exists pandora_verification_runs_identity_uidx on public.pandora_verification_runs(project_version_id,identity_sha256);
create index if not exists pandora_verification_runs_project_idx on public.pandora_verification_runs(project_id,created_at desc);
create index if not exists pandora_verification_runs_status_idx on public.pandora_verification_runs(status,created_at) where status in ('PENDING','RUNNING','BLOCKED');

create table if not exists public.pandora_verification_checks (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,verification_run_id uuid not null references public.pandora_verification_runs(id) on delete cascade,requirement_id uuid null references public.pandora_project_requirements(id) on delete set null,check_key text not null,status text not null,failure_class text null,security_severity text null,summary text null,details_redacted jsonb not null default '{}'::jsonb,started_at timestamptz null,completed_at timestamptz null,created_at timestamptz not null default now(),constraint pandora_verification_checks_status_check check (status in ('PASS','FAIL','BLOCKED','INCONCLUSIVE','SKIPPED')),constraint pandora_verification_checks_failure_check check (failure_class is null or failure_class in ('source','build','unit_test','integration','browser','visual','accessibility','security','dependency','migration','runtime','domain','acceptance','business_acceptance','provider','environment','verification_infrastructure','unknown')),constraint pandora_verification_checks_severity_check check (security_severity is null or security_severity in ('INFO','LOW','MEDIUM','HIGH','CRITICAL'))
);
create unique index if not exists pandora_verification_checks_key_uidx on public.pandora_verification_checks(verification_run_id,check_key);
create index if not exists pandora_verification_checks_requirement_idx on public.pandora_verification_checks(requirement_id,status) where requirement_id is not null;

create table if not exists public.pandora_verification_evidence (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,verification_run_id uuid not null references public.pandora_verification_runs(id) on delete cascade,verification_check_id uuid null references public.pandora_verification_checks(id) on delete cascade,artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete set null,evidence_type text not null,media_type text not null default 'application/json',content_sha256 text not null,storage_provider text null,storage_path text null,created_at timestamptz not null default now(),constraint pandora_verification_evidence_hash_check check (content_sha256 ~ '^[0-9a-f]{64}$')
);
create index if not exists pandora_verification_evidence_run_idx on public.pandora_verification_evidence(verification_run_id,created_at);

alter table public.pandora_project_versions
  add column if not exists parent_version_id uuid null references public.pandora_project_versions(id) on delete restrict,
  add column if not exists project_spec_id uuid null references public.pandora_project_specs(id) on delete restrict,
  add column if not exists build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,
  add column if not exists root_artifact_version_id uuid null references public.pandora_artifact_versions(id) on delete set null,
  add column if not exists source_commit text null,
  add column if not exists artifact_digest_sha256 text null,
  add column if not exists migration_set_digest_sha256 text null,
  add column if not exists runtime_target_digest_sha256 text null,
  add column if not exists lifecycle_status text not null default 'draft',
  add column if not exists rollback_of_version_id uuid null references public.pandora_project_versions(id) on delete restrict,
  add column if not exists rollback_eligible boolean not null default false,
  add column if not exists promoted_at timestamptz null,
  add column if not exists verification_run_id uuid null references public.pandora_verification_runs(id) on delete restrict;
alter table public.pandora_project_versions drop constraint if exists pandora_project_versions_source_commit_worker_a_check;
alter table public.pandora_project_versions add constraint pandora_project_versions_source_commit_worker_a_check check (source_commit is null or source_commit ~ '^[0-9a-f]{40}$');
alter table public.pandora_project_versions drop constraint if exists pandora_project_versions_worker_a_digest_check;
alter table public.pandora_project_versions add constraint pandora_project_versions_worker_a_digest_check check ((artifact_digest_sha256 is null or artifact_digest_sha256 ~ '^[0-9a-f]{64}$') and (migration_set_digest_sha256 is null or migration_set_digest_sha256 ~ '^[0-9a-f]{64}$') and (runtime_target_digest_sha256 is null or runtime_target_digest_sha256 ~ '^[0-9a-f]{64}$'));
alter table public.pandora_project_versions drop constraint if exists pandora_project_versions_lifecycle_status_check;
alter table public.pandora_project_versions add constraint pandora_project_versions_lifecycle_status_check check (lifecycle_status in ('draft','built','verification_pending','verified','preview_ready','production_candidate','live','rolled_back','rejected'));
create index if not exists pandora_project_versions_spec_idx on public.pandora_project_versions(project_spec_id,created_at desc) where project_spec_id is not null;
create index if not exists pandora_project_versions_lifecycle_idx on public.pandora_project_versions(project_id,lifecycle_status,created_at desc);
create index if not exists pandora_project_versions_parent_idx on public.pandora_project_versions(parent_version_id) where parent_version_id is not null;

create or replace function private.pandora_validate_project_version_control_plane()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid;v_project uuid;v_spec uuid;v_status text;v_source_commit text;v_source_digest text;v_artifact_digest text;v_migration_digest text;v_runtime_digest text;
begin
  if new.project_spec_id is not null then select s.organization_id,s.project_id into v_org,v_project from public.pandora_project_specs s where s.id=new.project_spec_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project version ProjectSpec lineage mismatch' using errcode='23514'; end if; end if;
  if new.parent_version_id is not null then select v.organization_id,v.project_id into v_org,v_project from public.pandora_project_versions v where v.id=new.parent_version_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project version parent lineage mismatch' using errcode='23514'; end if; end if;
  if new.build_job_id is not null then select j.organization_id,j.project_id into v_org,v_project from public.pandora_build_jobs j where j.id=new.build_job_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project version build job lineage mismatch' using errcode='23514'; end if; end if;
  if new.verification_run_id is not null then
    select r.organization_id,r.project_id,r.project_spec_id,r.status,r.source_commit,r.source_digest,r.artifact_digest,r.migration_set_digest,r.runtime_target_digest into v_org,v_project,v_spec,v_status,v_source_commit,v_source_digest,v_artifact_digest,v_migration_digest,v_runtime_digest from public.pandora_verification_runs r where r.id=new.verification_run_id;
    if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project version verification lineage mismatch' using errcode='23514'; end if;
    if new.project_spec_id is not null and v_spec<>new.project_spec_id then raise exception 'project version verification ProjectSpec mismatch' using errcode='23514'; end if;
    if new.lifecycle_status in ('verified','production_candidate','live') then
      if v_status<>'PASS' then raise exception 'verified project version requires PASS verification' using errcode='23514'; end if;
      if v_source_digest<>new.source_sha256 then raise exception 'project version source digest verification mismatch' using errcode='23514'; end if;
      if new.source_commit is not null and v_source_commit<>new.source_commit then raise exception 'project version source commit verification mismatch' using errcode='23514'; end if;
      if new.artifact_digest_sha256 is null or v_artifact_digest<>new.artifact_digest_sha256 then raise exception 'project version artifact digest verification mismatch' using errcode='23514'; end if;
      if new.migration_set_digest_sha256 is distinct from v_migration_digest then raise exception 'project version migration digest verification mismatch' using errcode='23514'; end if;
      if new.runtime_target_digest_sha256 is distinct from v_runtime_digest then raise exception 'project version runtime digest verification mismatch' using errcode='23514'; end if;
    end if;
  elsif new.lifecycle_status in ('verified','production_candidate','live') then raise exception 'verified project version requires verification_run_id' using errcode='23514'; end if;
  if new.lifecycle_status='live' and new.promoted_at is null then new.promoted_at:=now(); end if; return new;
end; $$;
drop trigger if exists pandora_project_versions_control_plane_guard on public.pandora_project_versions;
create trigger pandora_project_versions_control_plane_guard before insert or update on public.pandora_project_versions for each row execute function private.pandora_validate_project_version_control_plane();

create table if not exists public.pandora_artifact_links (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,artifact_version_id uuid not null references public.pandora_artifact_versions(id) on delete cascade,project_spec_id uuid null references public.pandora_project_specs(id) on delete cascade,requirement_id uuid null references public.pandora_project_requirements(id) on delete cascade,project_version_id uuid null references public.pandora_project_versions(id) on delete cascade,verification_run_id uuid null references public.pandora_verification_runs(id) on delete cascade,link_kind text not null,created_at timestamptz not null default now(),constraint pandora_artifact_links_target_check check (num_nonnulls(project_spec_id,requirement_id,project_version_id,verification_run_id)=1)
);
create index if not exists pandora_artifact_links_artifact_idx on public.pandora_artifact_links(artifact_version_id,link_kind);
create index if not exists pandora_artifact_links_project_version_idx on public.pandora_artifact_links(project_version_id) where project_version_id is not null;

create table if not exists public.pandora_policy_actions (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,project_id uuid not null references public.projectos_projects(id) on delete cascade,project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,tool_call_id uuid null references public.pandora_tool_calls(id) on delete set null,project_version_id uuid null references public.pandora_project_versions(id) on delete restrict,tool_name text not null,tool_version text not null,action_name text not null,action_hash text not null,arguments_sha256 text not null,policy_version text not null,environment text not null,target_resource_ref text null,risk_level text not null,disposition text not null,side_effect text not null,approval_required boolean not null default false,approval_id uuid null references public.approvals(id) on delete restrict,status text not null default 'proposed',expires_at timestamptz null,authorized_at timestamptz null,executed_at timestamptz null,created_at timestamptz not null default now(),constraint pandora_policy_actions_hash_check check (action_hash ~ '^[0-9a-f]{64}$' and arguments_sha256 ~ '^[0-9a-f]{64}$'),constraint pandora_policy_actions_environment_check check (environment in ('development','sandbox','test','preview','production')),constraint pandora_policy_actions_risk_check check (risk_level in ('LOW','MEDIUM','HIGH','CRITICAL')),constraint pandora_policy_actions_disposition_check check (disposition in ('ALLOW','DENY','REQUIRE_APPROVAL','DEFER')),constraint pandora_policy_actions_side_effect_check check (side_effect in ('NONE','READ','PROJECT_MUTATION','EXTERNAL_MUTATION','PRODUCTION_MUTATION')),constraint pandora_policy_actions_status_check check (status in ('proposed','authorized','denied','revoked','expired','executed'))
);
create unique index if not exists pandora_policy_actions_hash_uidx on public.pandora_policy_actions(organization_id,action_hash);
create index if not exists pandora_policy_actions_pending_idx on public.pandora_policy_actions(organization_id,status,created_at) where status in ('proposed','authorized');
create index if not exists pandora_policy_actions_project_idx on public.pandora_policy_actions(project_id,created_at desc);

create or replace function private.pandora_validate_policy_action()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid;v_hash text;v_decision text;v_expires timestamptz;
begin
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id or new.project_version_id is distinct from old.project_version_id or new.tool_name<>old.tool_name or new.tool_version<>old.tool_version or new.action_name<>old.action_name or new.action_hash<>old.action_hash or new.arguments_sha256<>old.arguments_sha256 or new.policy_version<>old.policy_version or new.environment<>old.environment or new.target_resource_ref is distinct from old.target_resource_ref) then raise exception 'policy action identity is immutable' using errcode='23514'; end if;
  if new.approval_id is not null then
    select a.organization_id,a.action_hash,a.decision::text,a.expires_at into v_org,v_hash,v_decision,v_expires from public.approvals a where a.id=new.approval_id;
    if v_org is null or v_org<>new.organization_id or v_hash<>new.action_hash then raise exception 'approval action hash binding mismatch' using errcode='23514'; end if;
    if new.status in ('authorized','executed') and new.approval_required then
      if v_decision<>'approved' then raise exception 'authorized action requires approved approval' using errcode='23514'; end if;
      if v_expires<=now() then raise exception 'approval is expired' using errcode='23514'; end if;
    end if;
  elsif new.status in ('authorized','executed') and new.approval_required then raise exception 'authorized action requires bound approval' using errcode='23514'; end if;
  if new.expires_at is not null and new.expires_at<=now() and new.status='authorized' then raise exception 'cannot authorize expired policy action' using errcode='23514'; end if;
  if new.status='authorized' and new.authorized_at is null then new.authorized_at:=now(); end if;
  if new.status='executed' and new.executed_at is null then new.executed_at:=now(); end if; return new;
end; $$;
drop trigger if exists pandora_policy_actions_guard on public.pandora_policy_actions;
create trigger pandora_policy_actions_guard before insert or update on public.pandora_policy_actions for each row execute function private.pandora_validate_policy_action();

create or replace function private.pandora_validate_control_plane_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v jsonb:=to_jsonb(new);v_id uuid;v_org uuid;v_project uuid;
begin
  v_id:=nullif(v->>'project_spec_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_specs where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'ProjectSpec scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'build_job_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_build_jobs where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build job scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'build_job_step_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_build_job_steps where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build step scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'model_run_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_model_runs where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'model run scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'tool_call_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_tool_calls where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'tool call scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'artifact_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifacts where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'artifact scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'artifact_version_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_artifact_versions where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'artifact version scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'project_version_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_versions where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'project version scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'verification_run_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_verification_runs where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'verification run scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'verification_check_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_verification_checks where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'verification check scope mismatch' using errcode='23514'; end if; end if;
  v_id:=nullif(v->>'requirement_id','')::uuid; if v_id is not null then select organization_id,project_id into v_org,v_project from public.pandora_project_requirements where id=v_id; if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'requirement scope mismatch' using errcode='23514'; end if; end if;
  return new;
end; $$;
do $scope_triggers$ declare v_table text; begin foreach v_table in array array['pandora_model_runs','pandora_tool_calls','pandora_tool_results','pandora_artifacts','pandora_artifact_versions','pandora_artifact_links','pandora_verification_runs','pandora_verification_checks','pandora_verification_evidence','pandora_policy_actions'] loop execute format('drop trigger if exists %I on public.%I',v_table||'_scope_guard',v_table);execute format('create trigger %I before insert or update on public.%I for each row execute function private.pandora_validate_control_plane_scope()',v_table||'_scope_guard',v_table);end loop;end; $scope_triggers$;

create or replace function private.pandora_validate_artifact_version_lineage()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_artifact uuid;v_version integer;
begin
  if new.version=1 then if new.parent_version_id is not null then raise exception 'artifact version 1 cannot have a parent' using errcode='23514'; end if;
  else if new.parent_version_id is null then raise exception 'artifact version > 1 requires parent_version_id' using errcode='23514'; end if;select artifact_id,version into v_artifact,v_version from public.pandora_artifact_versions where id=new.parent_version_id;if v_artifact is null or v_artifact<>new.artifact_id or v_version<>new.version-1 then raise exception 'artifact version parent must be previous version of same artifact' using errcode='23514'; end if;end if;return new;
end; $$;
drop trigger if exists pandora_artifact_versions_lineage_guard on public.pandora_artifact_versions;
create trigger pandora_artifact_versions_lineage_guard before insert on public.pandora_artifact_versions for each row execute function private.pandora_validate_artifact_version_lineage();

create or replace function private.pandora_validate_verification_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_spec uuid;v_source_sha text;v_source_commit text;v_artifact_sha text;
begin
  select v.project_spec_id,v.source_sha256,v.source_commit,v.artifact_digest_sha256 into v_spec,v_source_sha,v_source_commit,v_artifact_sha from public.pandora_project_versions v where v.id=new.project_version_id;
  if v_spec is not null and v_spec<>new.project_spec_id then raise exception 'verification ProjectSpec does not match project version' using errcode='23514'; end if;
  if v_source_sha<>new.source_digest then raise exception 'verification source digest does not match project version' using errcode='23514'; end if;
  if v_source_commit is not null and v_source_commit<>new.source_commit then raise exception 'verification source commit does not match project version' using errcode='23514'; end if;
  if v_artifact_sha is not null and v_artifact_sha<>new.artifact_digest then raise exception 'verification artifact digest does not match project version' using errcode='23514'; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id or new.project_version_id<>old.project_version_id or new.source_commit<>old.source_commit or new.source_digest<>old.source_digest or new.artifact_digest<>old.artifact_digest or new.migration_set_digest is distinct from old.migration_set_digest or new.runtime_target_digest is distinct from old.runtime_target_digest or new.target_environment<>old.target_environment or new.required_check_profile<>old.required_check_profile or new.identity_sha256<>old.identity_sha256 or new.verifier_identity<>old.verifier_identity or new.builder_identity is distinct from old.builder_identity) then raise exception 'verification identity is immutable' using errcode='23514'; end if;return new;
end; $$;
drop trigger if exists pandora_verification_runs_identity_guard on public.pandora_verification_runs;
create trigger pandora_verification_runs_identity_guard before insert or update on public.pandora_verification_runs for each row execute function private.pandora_validate_verification_identity();

drop trigger if exists pandora_build_job_events_update_guard on public.pandora_build_job_events;create trigger pandora_build_job_events_update_guard before update or delete on public.pandora_build_job_events for each row execute function private.pandora_reject_immutable_control_plane_mutation();
drop trigger if exists pandora_tool_results_update_guard on public.pandora_tool_results;create trigger pandora_tool_results_update_guard before update or delete on public.pandora_tool_results for each row execute function private.pandora_reject_immutable_control_plane_mutation();
drop trigger if exists pandora_artifact_versions_update_guard on public.pandora_artifact_versions;create trigger pandora_artifact_versions_update_guard before update or delete on public.pandora_artifact_versions for each row execute function private.pandora_reject_immutable_control_plane_mutation();
drop trigger if exists pandora_verification_evidence_update_guard on public.pandora_verification_evidence;create trigger pandora_verification_evidence_update_guard before update or delete on public.pandora_verification_evidence for each row execute function private.pandora_reject_immutable_control_plane_mutation();

alter table public.pandora_build_jobs enable row level security;alter table public.pandora_build_job_steps enable row level security;alter table public.pandora_build_job_attempts enable row level security;alter table public.pandora_build_job_events enable row level security;alter table public.pandora_model_runs enable row level security;alter table public.pandora_tool_calls enable row level security;alter table public.pandora_tool_results enable row level security;alter table public.pandora_artifacts enable row level security;alter table public.pandora_artifact_versions enable row level security;alter table public.pandora_artifact_links enable row level security;alter table public.pandora_verification_runs enable row level security;alter table public.pandora_verification_checks enable row level security;alter table public.pandora_verification_evidence enable row level security;alter table public.pandora_policy_actions enable row level security;
do $policies$ declare v_table text;v_policy text;begin foreach v_table in array array['pandora_build_jobs','pandora_build_job_steps','pandora_build_job_attempts','pandora_build_job_events','pandora_model_runs','pandora_tool_calls','pandora_tool_results','pandora_artifacts','pandora_artifact_versions','pandora_artifact_links','pandora_verification_runs','pandora_verification_checks','pandora_verification_evidence','pandora_policy_actions'] loop v_policy:=v_table||'_member_read';execute format('drop policy if exists %I on public.%I',v_policy,v_table);execute format('create policy %I on public.%I for select to authenticated using (private.is_org_member(organization_id))',v_policy,v_table);execute format('revoke all on public.%I from anon, authenticated',v_table);execute format('grant select on public.%I to authenticated',v_table);execute format('grant select, insert, update, delete on public.%I to service_role',v_table);end loop;end; $policies$;
grant usage,select on sequence public.pandora_build_job_events_id_seq to service_role;
comment on table public.pandora_build_jobs is 'Durable customer build lifecycle orchestration. Provider execution remains in governed worker dispatch.';
comment on table public.pandora_model_runs is 'Provider-independent model run lineage; stores hashes and usage, not raw prompts or provider secrets.';
comment on table public.pandora_tool_calls is 'Durable Tool Gateway proposal/execution lineage bound to exact action hashes and policy versions.';
comment on table public.pandora_artifact_versions is 'Immutable artifact metadata/version lineage. Artifact bytes remain in governed storage.';
comment on table public.pandora_verification_runs is 'Independent verification contract bound to exact ProjectSpec, project version, source and artifact digests.';
comment on table public.pandora_policy_actions is 'Exact immutable policy action binding used to reject stale approvals and changed targets.';
