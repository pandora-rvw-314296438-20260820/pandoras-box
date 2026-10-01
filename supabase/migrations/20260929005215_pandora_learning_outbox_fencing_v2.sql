begin;

-- Restore the live verified-learning transport shape to canonical migrations.
-- CREATE IF NOT EXISTS is a no-op on the deployed table and makes clean replay
-- independent of the historical live-only bootstrap.
create table if not exists public.pandora_verified_learning_outbox (
  id uuid default gen_random_uuid() not null
    constraint pandora_verified_learning_outbox_pkey primary key,
  organization_id uuid not null,
  activity_job_id uuid not null,
  thread_id uuid,
  idempotency_key text not null
    constraint pandora_verified_learning_outbox_idempotency_key_key unique,
  memory_project_id uuid not null,
  namespace text default 'real_life'::text not null
    constraint pandora_verified_learning_outbox_namespace_check
      check (namespace = any (array['real_life'::text,'au'::text])),
  learning_kind text not null
    constraint pandora_verified_learning_outbox_learning_kind_check
      check (learning_kind = any (
        array['fact'::text,'procedure'::text,'failure_lesson'::text,'outcome'::text]
      )),
  learning_summary text not null
    constraint pandora_verified_learning_outbox_learning_summary_check
      check (char_length(learning_summary) >= 1 and char_length(learning_summary) <= 2000),
  promotion_basis text not null
    constraint pandora_verified_learning_outbox_promotion_basis_check
      check (char_length(promotion_basis) >= 1 and char_length(promotion_basis) <= 4096),
  confidence numeric not null
    constraint pandora_verified_learning_outbox_confidence_check
      check (confidence >= 0::numeric and confidence <= 1::numeric),
  execution jsonb not null
    constraint pandora_verified_learning_outbox_execution_check
      check (jsonb_typeof(execution) = 'object'::text),
  incident_verification_ref text,
  additional_evidence_refs text[] default '{}'::text[] not null,
  state text default 'pending'::text not null
    constraint pandora_verified_learning_outbox_state_check
      check (state = any (
        array['pending'::text,'processing'::text,'accepted'::text,'failed'::text]
      )),
  attempt_count integer default 0 not null
    constraint pandora_verified_learning_outbox_attempt_count_check
      check (attempt_count >= 0),
  lease_until timestamptz,
  memory_candidate_id uuid,
  memory_review_item_id uuid,
  last_error_code text,
  delivered_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint pandora_verified_learning_out_activity_job_id_learning_kind_key
    unique (activity_job_id,learning_kind)
);

create index if not exists pandora_verified_learning_outbox_delivery_idx
  on public.pandora_verified_learning_outbox(state,lease_until,created_at);

alter table public.pandora_verified_learning_outbox enable row level security;
revoke all on table public.pandora_verified_learning_outbox
  from public,anon,authenticated;
grant all on table public.pandora_verified_learning_outbox to service_role;

alter table public.pandora_verified_learning_outbox
  add column if not exists claim_token uuid;

comment on column public.pandora_verified_learning_outbox.claim_token is
  'Single-lease capability minted on each v2 claim. Never evidence of Memory acceptance.';

alter table public.pandora_verified_learning_outbox
  drop constraint if exists pandora_verified_learning_outbox_claim_fence_check;
alter table public.pandora_verified_learning_outbox
  add constraint pandora_verified_learning_outbox_claim_fence_check
  check (
    (
      state = 'processing'
      and lease_until is not null
      and claim_token is not null
    )
    or
    (
      state <> 'processing'
      and lease_until is null
      and claim_token is null
    )
  ) not valid;

create or replace function public.pandora_claim_verified_learning_outbox_v2(
  p_limit integer default 5
)
returns setof public.pandora_verified_learning_outbox
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_now timestamptz := clock_timestamp();
begin
  if p_limit is null or p_limit < 1 or p_limit > 20 then
    raise exception 'PANDORA_LEARNING_OUTBOX_LIMIT_INVALID' using errcode='22023';
  end if;

  -- An expired fifth delivery cannot be reclaimed without exceeding the bounded
  -- attempt count. Close it before picking new work; a live fifth lease remains
  -- owned by its current claimant.
  with exhausted as (
    select o.id
    from public.pandora_verified_learning_outbox o
    where o.attempt_count >= 5
      and (
        o.state = 'pending'
        or (
          o.state = 'processing'
          and (o.lease_until is null or o.lease_until < v_now)
        )
      )
    order by o.created_at,o.id
    for update skip locked
    limit p_limit
  )
  update public.pandora_verified_learning_outbox o
  set state = 'failed',
      memory_candidate_id = null,
      memory_review_item_id = null,
      last_error_code = coalesce(
        nullif(trim(o.last_error_code),''),
        'delivery_attempts_exhausted'
      ),
      claim_token = null,
      lease_until = null,
      updated_at = v_now
  from exhausted
  where o.id = exhausted.id;

  return query
  with picked as (
    select o.id
    from public.pandora_verified_learning_outbox o
    where (
      o.state = 'pending'
      or (
        o.state = 'processing'
        and (o.lease_until is null or o.lease_until < v_now)
      )
    )
      and o.attempt_count < 5
    order by o.created_at, o.id
    for update skip locked
    limit p_limit
  )
  update public.pandora_verified_learning_outbox o
  set state = 'processing',
      attempt_count = o.attempt_count + 1,
      claim_token = gen_random_uuid(),
      lease_until = v_now + interval '5 minutes',
      updated_at = v_now
  from picked
  where o.id = picked.id
  returning o.*;
end;
$function$;

create or replace function public.pandora_ack_verified_learning_outbox_v2(
  p_outbox_id uuid,
  p_claim_token uuid,
  p_attempt_count integer,
  p_success boolean,
  p_candidate_id uuid default null,
  p_review_item_id uuid default null,
  p_retryable boolean default false,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row public.pandora_verified_learning_outbox%rowtype;
  v_now timestamptz;
begin
  if p_outbox_id is null
     or p_claim_token is null
     or p_attempt_count is null
     or p_attempt_count < 1
     or p_success is null then
    raise exception 'PANDORA_LEARNING_OUTBOX_ACK_INPUT_INVALID' using errcode='22023';
  end if;

  if p_success and (p_candidate_id is null or p_review_item_id is null) then
    raise exception 'PANDORA_LEARNING_OUTBOX_RECEIPTS_REQUIRED' using errcode='22023';
  end if;

  if p_success and (
       coalesce(p_retryable,false)
       or nullif(trim(coalesce(p_error_code,'')),'') is not null
     ) then
    raise exception 'PANDORA_LEARNING_OUTBOX_SUCCESS_FIELDS_INVALID' using errcode='22023';
  end if;

  if not p_success and (p_candidate_id is not null or p_review_item_id is not null) then
    raise exception 'PANDORA_LEARNING_OUTBOX_FAILURE_RECEIPTS_INVALID' using errcode='22023';
  end if;

  -- Lock first, then read the wall clock. A blocked acknowledgement must not
  -- validate an expired lease against a timestamp captured before lock wait.
  select *
  into v_row
  from public.pandora_verified_learning_outbox
  where id = p_outbox_id
  for update;

  v_now := clock_timestamp();
  if v_row.id is null
     or v_row.state <> 'processing'
     or v_row.claim_token is distinct from p_claim_token
     or v_row.attempt_count is distinct from p_attempt_count
     or v_row.lease_until is null
     or v_row.lease_until < v_now then
    raise exception 'PANDORA_LEARNING_OUTBOX_CLAIM_STALE' using errcode='55000';
  end if;

  update public.pandora_verified_learning_outbox o
  set state = case
        when p_success then 'accepted'
        when coalesce(p_retryable,false) and o.attempt_count < 5 then 'pending'
        else 'failed'
      end,
      memory_candidate_id = case when p_success then p_candidate_id else null end,
      memory_review_item_id = case when p_success then p_review_item_id else null end,
      last_error_code = case
        when p_success then null
        else left(coalesce(nullif(trim(p_error_code),''),'delivery_failed'),120)
      end,
      claim_token = null,
      lease_until = null,
      delivered_at = case when p_success then v_now else o.delivered_at end,
      updated_at = v_now
  where o.id = p_outbox_id
  returning o.* into v_row;

  return jsonb_build_object(
    'id',v_row.id,
    'state',v_row.state,
    'attemptCount',v_row.attempt_count,
    'memoryCandidateId',v_row.memory_candidate_id,
    'memoryReviewItemId',v_row.memory_review_item_id
  );
end;
$function$;

-- The v1 acknowledgement has no per-claim capability and cannot be made safe
-- after a lease is reclaimed. Disable both legacy entry points before they can
-- mutate or lease work; callers must move to the v2 pair atomically.
create or replace function public.pandora_claim_verified_learning_outbox(
  p_limit integer default 5
)
returns setof public.pandora_verified_learning_outbox
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'PANDORA_LEARNING_OUTBOX_V1_DISABLED' using errcode='0A000';
end;
$function$;

create or replace function public.pandora_ack_verified_learning_outbox(
  p_outbox_id uuid,
  p_success boolean,
  p_candidate_id uuid default null,
  p_review_item_id uuid default null,
  p_retryable boolean default false,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'PANDORA_LEARNING_OUTBOX_V1_DISABLED' using errcode='0A000';
end;
$function$;

-- Preserve the latest typed Memory response contract and close SQL three-valued
-- logic: a NULL transport status is never a successful HTTP response.
create or replace function private.execution_learning_response_is_valid(
  p_payload jsonb,
  p_status integer,
  p_content text,
  p_error text,
  p_timed_out boolean
)
returns boolean
language plpgsql
immutable
set search_path=''
as $function$
declare
  v_body jsonb;
  v_kind text:=coalesce(p_payload->>'learning_kind','');
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
begin
  if p_status is null
     or p_status not in (200,202)
     or coalesce(p_timed_out,false)
     or p_error is not null then
    return false;
  end if;
  if v_kind='' then return true; end if;
  if v_kind not in (
    'visible_creation_evidence_v1',
    'visible_creation_decision_influence_v1',
    'visible_creation_decision_outcome_v1'
  ) then
    return true;
  end if;
  begin
    v_body:=p_content::jsonb;
  exception when others then
    return false;
  end;

  if v_kind='visible_creation_evidence_v1' then
    return coalesce(v_body->>'ok','')='true'
      and coalesce(v_body->>'review_required','')='true'
      and coalesce(v_body->>'canonical_memory_written','')='false'
      and lower(coalesce(v_body->>'source_event_id',''))=lower(coalesce(p_payload->>'source_event_id',''))
      and lower(coalesce(v_body->>'visible_project_id',''))=lower(coalesce(p_payload->>'visible_project_id',''))
      and coalesce(v_body->>'evidence_kind','')=coalesce(p_payload->>'evidence_kind','')
      and coalesce(v_body->>'proof_stage','')=coalesce(p_payload->>'proof_stage','')
      and lower(coalesce(v_body->>'candidate_id','')) ~ v_uuid_pattern
      and lower(coalesce(v_body->>'review_item_id','')) ~ v_uuid_pattern;
  end if;

  if coalesce(v_body->>'ok','')<>'true'
     or coalesce(v_body->>'canonical_memory_written','')<>'false'
     or lower(coalesce(v_body->>'source_event_id',''))<>lower(coalesce(p_payload->>'source_event_id',''))
     or lower(coalesce(v_body->>'visible_project_id',''))<>lower(coalesce(p_payload->>'visible_project_id',''))
     or lower(coalesce(v_body->>'receipt_id',''))<>lower(coalesce(p_payload->>'receipt_id',''))
     or lower(coalesce(v_body->>'retrieval_log_id',''))<>lower(coalesce(p_payload->>'retrieval_log_id',''))
     or coalesce(v_body->>'decision_type','')<>coalesce(p_payload->>'decision_type','')
     or lower(coalesce(v_body->>'decision_id',''))<>lower(coalesce(p_payload->>'decision_id',''))
     or coalesce(v_body->'approved_memory_item_ids','[]'::jsonb)<>coalesce(p_payload->'approved_memory_item_ids','[]'::jsonb)
     or lower(coalesce(v_body->>'retrieval_log_id','')) !~ v_uuid_pattern
     or lower(coalesce(v_body->>'decision_id','')) !~ v_uuid_pattern then
    return false;
  end if;

  if v_kind='visible_creation_decision_influence_v1' then
    return coalesce(v_body->>'status','')='decision_context_bound'
      and coalesce(v_body->>'decision_run_id','')=coalesce(p_payload->>'decision_run_id','');
  end if;

  return coalesce(v_body->>'status','')='decision_outcome_recorded'
    and lower(coalesce(v_body->>'outcome_run_id',''))=lower(coalesce(p_payload->>'outcome_run_id',''))
    and coalesce(v_body->>'outcome_status','')=coalesce(p_payload->>'outcome_status_detail','')
    and lower(coalesce(v_body->>'outcome_run_id','')) ~ v_uuid_pattern;
end;
$function$;

revoke all on function public.pandora_claim_verified_learning_outbox_v2(integer)
  from public,anon,authenticated;
grant execute on function public.pandora_claim_verified_learning_outbox_v2(integer)
  to service_role;
revoke all on function public.pandora_ack_verified_learning_outbox_v2(uuid,uuid,integer,boolean,uuid,uuid,boolean,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ack_verified_learning_outbox_v2(uuid,uuid,integer,boolean,uuid,uuid,boolean,text)
  to service_role;

revoke all on function public.pandora_claim_verified_learning_outbox(integer)
  from public,anon,authenticated;
grant execute on function public.pandora_claim_verified_learning_outbox(integer)
  to service_role;
revoke all on function public.pandora_ack_verified_learning_outbox(uuid,boolean,uuid,uuid,boolean,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ack_verified_learning_outbox(uuid,boolean,uuid,uuid,boolean,text)
  to service_role;

revoke all on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  from public,anon,authenticated;
grant execute on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  to service_role;

commit;

