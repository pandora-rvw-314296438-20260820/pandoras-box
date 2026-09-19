-- PLP verified-learning outbox.
-- Captures only bounded, already-verified execution lessons. Delivery to Pandora
-- Memory is asynchronous and review-governed.

create table if not exists public.pandora_verified_learning_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  activity_job_id uuid not null,
  thread_id uuid,
  idempotency_key text not null unique,
  memory_project_id uuid not null,
  namespace text not null default 'real_life'
    check (namespace in ('real_life','au')),
  learning_kind text not null
    check (learning_kind in ('fact','procedure','failure_lesson','outcome')),
  learning_summary text not null check (char_length(learning_summary) between 1 and 2000),
  promotion_basis text not null check (char_length(promotion_basis) between 1 and 4096),
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  execution jsonb not null check (jsonb_typeof(execution)='object'),
  incident_verification_ref text,
  additional_evidence_refs text[] not null default '{}'::text[],
  state text not null default 'pending'
    check (state in ('pending','processing','accepted','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  lease_until timestamptz,
  memory_candidate_id uuid,
  memory_review_item_id uuid,
  last_error_code text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(activity_job_id, learning_kind)
);

alter table public.pandora_verified_learning_outbox enable row level security;
revoke all on table public.pandora_verified_learning_outbox from anon, authenticated;

create index if not exists pandora_verified_learning_outbox_delivery_idx
  on public.pandora_verified_learning_outbox(state, lease_until, created_at);

create or replace function public.pandora_claim_verified_learning_outbox(
  p_limit integer default 5
)
returns setof public.pandora_verified_learning_outbox
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if p_limit < 1 or p_limit > 20 then
    raise exception 'invalid outbox claim limit' using errcode='22023';
  end if;

  return query
  with picked as (
    select o.id
    from public.pandora_verified_learning_outbox o
    where (
      o.state = 'pending'
      or (
        o.state = 'processing'
        and o.lease_until is not null
        and o.lease_until < now()
      )
    )
      and o.attempt_count < 5
    order by o.created_at, o.id
    for update skip locked
    limit p_limit
  )
  update public.pandora_verified_learning_outbox o
  set state='processing',
      attempt_count=o.attempt_count+1,
      lease_until=now()+interval '5 minutes',
      updated_at=now()
  from picked
  where o.id=picked.id
  returning o.*;
end;
$$;

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
set search_path = public, pg_catalog
as $$
declare
  v_row public.pandora_verified_learning_outbox%rowtype;
begin
  if p_outbox_id is null then
    raise exception 'outbox id required' using errcode='22023';
  end if;

  update public.pandora_verified_learning_outbox o
  set state = case
        when p_success then 'accepted'
        when p_retryable and o.attempt_count < 5 then 'pending'
        else 'failed'
      end,
      memory_candidate_id = case when p_success then p_candidate_id else o.memory_candidate_id end,
      memory_review_item_id = case when p_success then p_review_item_id else o.memory_review_item_id end,
      last_error_code = case
        when p_success then null
        else left(coalesce(nullif(trim(p_error_code),''),'delivery_failed'),120)
      end,
      lease_until = null,
      delivered_at = case when p_success then now() else o.delivered_at end,
      updated_at = now()
  where o.id=p_outbox_id
    and o.state='processing'
  returning o.* into v_row;

  if not found then
    raise exception 'outbox item is not in processing state' using errcode='55000';
  end if;

  return jsonb_build_object(
    'id',v_row.id,
    'state',v_row.state,
    'attemptCount',v_row.attempt_count,
    'memoryCandidateId',v_row.memory_candidate_id,
    'memoryReviewItemId',v_row.memory_review_item_id
  );
end;
$$;

revoke all on function public.pandora_claim_verified_learning_outbox(integer) from public, anon, authenticated;
revoke all on function public.pandora_ack_verified_learning_outbox(uuid,boolean,uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.pandora_claim_verified_learning_outbox(integer) to service_role;
grant execute on function public.pandora_ack_verified_learning_outbox(uuid,boolean,uuid,uuid,boolean,text) to service_role;
