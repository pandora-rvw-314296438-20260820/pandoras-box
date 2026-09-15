-- Pandora M1-007 durable Universal Chat recovery/reconciliation v1.
-- A repeated delivery observes or reconciles the original execution; it never starts a second writer.

alter table public.pandora_activity_jobs
  add column if not exists request_fingerprint text,
  add column if not exists execution_state text not null default 'ready',
  add column if not exists execution_claim_id uuid,
  add column if not exists execution_generation bigint not null default 0,
  add column if not exists execution_checkpoint text,
  add column if not exists execution_checkpoint_ref text,
  add column if not exists execution_effect_state text not null default 'none',
  add column if not exists execution_result jsonb,
  add column if not exists execution_error_code text,
  add column if not exists execution_started_at timestamptz,
  add column if not exists execution_updated_at timestamptz;

alter table public.pandora_activity_jobs drop constraint if exists pandora_activity_jobs_request_fingerprint_check;
alter table public.pandora_activity_jobs add constraint pandora_activity_jobs_request_fingerprint_check
  check (request_fingerprint is null or request_fingerprint ~ '^[0-9a-f]{64}$');
alter table public.pandora_activity_jobs drop constraint if exists pandora_activity_jobs_execution_state_check;
alter table public.pandora_activity_jobs add constraint pandora_activity_jobs_execution_state_check
  check (execution_state in ('ready','running','complete','failed','cancelled'));
alter table public.pandora_activity_jobs drop constraint if exists pandora_activity_jobs_execution_effect_state_check;
alter table public.pandora_activity_jobs add constraint pandora_activity_jobs_execution_effect_state_check
  check (execution_effect_state in ('none','ambiguous','verified'));
alter table public.pandora_activity_jobs drop constraint if exists pandora_activity_jobs_execution_generation_check;
alter table public.pandora_activity_jobs add constraint pandora_activity_jobs_execution_generation_check
  check (execution_generation >= 0);

create or replace function public.pandora_activity_execution_claim_v1(
  p_job_id uuid,
  p_request_fingerprint text,
  p_claim_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_fingerprint text := lower(trim(coalesce(p_request_fingerprint,'')));
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'pandora_activity_service_role_required' using errcode='42501';
  end if;
  if p_claim_id is null or v_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'pandora_activity_execution_claim_invalid' using errcode='22023';
  end if;
  select * into v_job from public.pandora_activity_jobs where id=p_job_id for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;
  if v_job.request_fingerprint is not null and v_job.request_fingerprint <> v_fingerprint then
    raise exception 'pandora_activity_execution_idempotency_conflict' using errcode='23505';
  end if;

  if v_job.execution_result is not null or v_job.terminal_state is not null
     or v_job.execution_state in ('complete','failed','cancelled') then
    return jsonb_build_object(
      'mode','reconcile','jobId',v_job.id,'claimId',v_job.execution_claim_id,
      'generation',v_job.execution_generation,'executionState',v_job.execution_state,'checkpoint',v_job.execution_checkpoint,
      'effectState',v_job.execution_effect_state,'terminalState',v_job.terminal_state,
      'result',v_job.execution_result,'errorCode',v_job.execution_error_code
    );
  end if;

  if v_job.execution_state='running' then
    if v_job.execution_claim_id=p_claim_id then
      return jsonb_build_object(
        'mode','execute','jobId',v_job.id,'claimId',v_job.execution_claim_id,
        'generation',v_job.execution_generation,'executionState',v_job.execution_state,'checkpoint',v_job.execution_checkpoint,
        'effectState',v_job.execution_effect_state,'terminalState',v_job.terminal_state
      );
    end if;
    return jsonb_build_object(
      'mode','observe','jobId',v_job.id,'claimId',v_job.execution_claim_id,
      'generation',v_job.execution_generation,'executionState',v_job.execution_state,'checkpoint',v_job.execution_checkpoint,
      'effectState',v_job.execution_effect_state,'terminalState',v_job.terminal_state
    );
  end if;

  update public.pandora_activity_jobs
  set request_fingerprint=coalesce(request_fingerprint,v_fingerprint),
      execution_state='running',execution_claim_id=p_claim_id,
      execution_generation=execution_generation+1,
      execution_checkpoint='claimed',execution_checkpoint_ref=null,
      execution_effect_state='none',execution_result=null,execution_error_code=null,
      execution_started_at=coalesce(execution_started_at,now()),execution_updated_at=now(),
      updated_at=now()
  where id=v_job.id returning * into v_job;

  return jsonb_build_object(
    'mode','execute','jobId',v_job.id,'claimId',v_job.execution_claim_id,
    'generation',v_job.execution_generation,'executionState',v_job.execution_state,'checkpoint',v_job.execution_checkpoint,
    'effectState',v_job.execution_effect_state,'terminalState',v_job.terminal_state
  );
end;
$body$;

revoke all on function public.pandora_activity_execution_claim_v1(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_activity_execution_claim_v1(uuid,text,uuid) to service_role;

create or replace function public.pandora_activity_execution_checkpoint_v1(
  p_job_id uuid,
  p_claim_id uuid,
  p_checkpoint text,
  p_checkpoint_ref text default null,
  p_effect_state text default 'none',
  p_result jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_checkpoint text := lower(trim(coalesce(p_checkpoint,'')));
  v_effect text := lower(trim(coalesce(p_effect_state,'')));
  v_ref text := nullif(trim(coalesce(p_checkpoint_ref,'')),'');
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  if p_claim_id is null or v_checkpoint not in ('claimed','capability_dispatching','request_persisted','provider_running','result_persisted','terminal')
     or v_effect not in ('none','ambiguous','verified') or (v_ref is not null and length(v_ref)>500)
     or (p_result is not null and octet_length(p_result::text)>131072) then
    raise exception 'pandora_activity_execution_checkpoint_invalid' using errcode='22023';
  end if;
  select * into v_job from public.pandora_activity_jobs where id=p_job_id for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;
  if v_job.execution_claim_id is distinct from p_claim_id then raise exception 'pandora_activity_execution_claim_stale' using errcode='55000'; end if;
  if v_job.execution_state <> 'running' and v_job.terminal_state is null then raise exception 'pandora_activity_execution_not_running' using errcode='55000'; end if;

  update public.pandora_activity_jobs
  set execution_checkpoint=v_checkpoint,execution_checkpoint_ref=v_ref,
      execution_effect_state=v_effect,execution_result=coalesce(p_result,execution_result),
      execution_updated_at=now(),updated_at=now()
  where id=v_job.id returning * into v_job;
  return jsonb_build_object(
    'jobId',v_job.id,'claimId',v_job.execution_claim_id,'generation',v_job.execution_generation,
    'checkpoint',v_job.execution_checkpoint,'effectState',v_job.execution_effect_state,
    'terminalState',v_job.terminal_state,'resultPersisted',v_job.execution_result is not null
  );
end;
$body$;

revoke all on function public.pandora_activity_execution_checkpoint_v1(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_activity_execution_checkpoint_v1(uuid,uuid,text,text,text,jsonb) to service_role;

create or replace function public.pandora_activity_execution_finish_v1(
  p_job_id uuid,
  p_claim_id uuid,
  p_state text,
  p_result jsonb default null,
  p_error_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_state text := lower(trim(coalesce(p_state,'')));
  v_error text := nullif(trim(coalesce(p_error_code,'')),'');
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  if p_claim_id is null or v_state not in ('complete','failed','cancelled')
     or (p_result is not null and octet_length(p_result::text)>131072)
     or (v_error is not null and length(v_error)>160) then
    raise exception 'pandora_activity_execution_finish_invalid' using errcode='22023';
  end if;
  select * into v_job from public.pandora_activity_jobs where id=p_job_id for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;
  if v_job.execution_claim_id is distinct from p_claim_id then raise exception 'pandora_activity_execution_claim_stale' using errcode='55000'; end if;

  update public.pandora_activity_jobs
  set execution_state=v_state,execution_checkpoint='terminal',
      execution_effect_state=case when v_state='complete' then 'verified' else execution_effect_state end,
      execution_result=coalesce(p_result,execution_result),execution_error_code=v_error,
      execution_updated_at=now(),updated_at=now()
  where id=v_job.id returning * into v_job;
  return jsonb_build_object(
    'jobId',v_job.id,'state',v_job.execution_state,'terminalState',v_job.terminal_state,
    'result',v_job.execution_result,'errorCode',v_job.execution_error_code
  );
end;
$body$;

revoke all on function public.pandora_activity_execution_finish_v1(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.pandora_activity_execution_finish_v1(uuid,uuid,text,jsonb,text) to service_role;

create or replace function public.pandora_activity_execution_readback_v1(
  p_job_id uuid,
  p_request_fingerprint text
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_fingerprint text := lower(trim(coalesce(p_request_fingerprint,'')));
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  if v_fingerprint !~ '^[0-9a-f]{64}$' then raise exception 'pandora_activity_execution_readback_invalid' using errcode='22023'; end if;
  select * into v_job from public.pandora_activity_jobs where id=p_job_id;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;
  if v_job.request_fingerprint is not null and v_job.request_fingerprint <> v_fingerprint then
    raise exception 'pandora_activity_execution_idempotency_conflict' using errcode='23505';
  end if;
  return jsonb_build_object(
    'mode',case when v_job.execution_result is not null or v_job.terminal_state is not null then 'reconcile' else 'observe' end,
    'jobId',v_job.id,'claimId',v_job.execution_claim_id,'generation',v_job.execution_generation,
    'checkpoint',v_job.execution_checkpoint,'checkpointRef',v_job.execution_checkpoint_ref,
    'effectState',v_job.execution_effect_state,'executionState',v_job.execution_state,
    'terminalState',v_job.terminal_state,'result',v_job.execution_result,'errorCode',v_job.execution_error_code,
    'updatedAt',v_job.execution_updated_at
  );
end;
$body$;

revoke all on function public.pandora_activity_execution_readback_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_activity_execution_readback_v1(uuid,text) to service_role;
