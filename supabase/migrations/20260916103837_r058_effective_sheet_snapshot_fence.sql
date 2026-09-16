-- R-058 effective Sheet snapshot promotion fence.
-- Raw Google Sheet edits are proposed data only. A snapshot becomes authoritative
-- only after every prior trusted PASS is provider-revoked and read back.

alter table private.pandora_coordinator_gate_decisions
  add column if not exists authoritative_snapshot_generation bigint;
alter table private.pandora_coordinator_gate_state
  add column if not exists authoritative_snapshot_generation bigint;

alter table private.pandora_coordinator_gate_decisions
  drop constraint if exists pandora_coordinator_gate_decisions_snapshot_generation_check;
alter table private.pandora_coordinator_gate_decisions
  add constraint pandora_coordinator_gate_decisions_snapshot_generation_check
  check (authoritative_snapshot_generation is null or authoritative_snapshot_generation > 0);
alter table private.pandora_coordinator_gate_state
  drop constraint if exists pandora_coordinator_gate_state_snapshot_generation_check;
alter table private.pandora_coordinator_gate_state
  add constraint pandora_coordinator_gate_state_snapshot_generation_check
  check (authoritative_snapshot_generation is null or authoritative_snapshot_generation > 0);

create table if not exists private.pandora_coordinator_repository_fence (
  repository text primary key,
  spreadsheet_id text not null,
  fence_state text not null default 'idle' check (fence_state in ('idle','promoting')),
  effective_snapshot_generation bigint not null default 0 check (effective_snapshot_generation >= 0),
  effective_snapshot_revision text,
  effective_snapshot_sha256 text,
  active_promotion_id uuid,
  updated_at timestamptz not null default now()
);alter table private.pandora_coordinator_repository_fence
  drop constraint if exists pandora_coordinator_repository_fence_effective_identity_check;
alter table private.pandora_coordinator_repository_fence
  add constraint pandora_coordinator_repository_fence_effective_identity_check check (
    (effective_snapshot_generation = 0 and effective_snapshot_revision is null and effective_snapshot_sha256 is null)
    or
    (effective_snapshot_generation > 0 and effective_snapshot_revision is not null
      and effective_snapshot_sha256 ~ '^[0-9a-f]{64}$')
  );

create table if not exists private.pandora_coordinator_snapshot_promotions (
  id uuid primary key default extensions.gen_random_uuid(),
  repository text not null,
  spreadsheet_id text not null,
  snapshot_generation bigint not null check (snapshot_generation > 0),
  candidate_revision text not null,
  candidate_sha256 text not null check (candidate_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_ref text not null,
  provider_read_at timestamptz not null,
  promotion_nonce text not null,
  state text not null default 'revoking' check (state in ('revoking','effective','aborted')),
  required_revocations integer not null default 0 check (required_revocations >= 0),
  completed_revocations integer not null default 0 check (completed_revocations >= 0),
  created_at timestamptz not null default now(),
  effective_at timestamptz,
  aborted_at timestamptz,
  unique(repository,snapshot_generation),
  unique(promotion_nonce)
);create table if not exists private.pandora_coordinator_snapshot_revocations (
  promotion_id uuid not null references private.pandora_coordinator_snapshot_promotions(id) on delete cascade,
  pull_request_number integer not null check (pull_request_number > 0),
  check_run_id bigint not null check (check_run_id > 0),
  head_sha text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  provider_app_id bigint,
  provider_status text,
  provider_conclusion text,
  revoked_at timestamptz,
  primary key(promotion_id,pull_request_number)
);

create or replace function public.pandora_coordinator_snapshot_prepare_v1(
  p_internal_key text,
  p_repository text,
  p_spreadsheet_id text,
  p_candidate_revision text,
  p_candidate_sha256 text,
  p_evidence_ref text,
  p_provider_read_at timestamptz,
  p_promotion_nonce text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_existing private.pandora_coordinator_snapshot_promotions%rowtype;
  v_id uuid;
  v_generation bigint;
  v_required integer;
  v_targets jsonb;begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_spreadsheet_id <> '1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0'
     or nullif(trim(p_candidate_revision),'') is null
     or length(p_candidate_revision) > 192
     or p_candidate_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(trim(p_evidence_ref),'') is null or length(p_evidence_ref) > 240
     or nullif(trim(p_promotion_nonce),'') is null or length(p_promotion_nonce) > 240
     or p_provider_read_at < now() - interval '5 minutes'
     or p_provider_read_at > now() + interval '1 minute' then
    raise exception 'pandora_coordinator_snapshot_identity_invalid' using errcode='22023';
  end if;

  insert into private.pandora_coordinator_repository_fence(repository,spreadsheet_id)
  values (p_repository,p_spreadsheet_id)
  on conflict(repository) do nothing;
  select * into v_fence
  from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if v_fence.spreadsheet_id<>p_spreadsheet_id then
    raise exception 'pandora_coordinator_snapshot_spreadsheet_mismatch' using errcode='23505';
  end if;

  select * into v_existing
  from private.pandora_coordinator_snapshot_promotions
  where promotion_nonce=p_promotion_nonce;
  if found then
    if v_existing.repository<>p_repository or v_existing.spreadsheet_id<>p_spreadsheet_id
       or v_existing.candidate_revision<>p_candidate_revision
       or v_existing.candidate_sha256<>p_candidate_sha256 then
      raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';
    end if;
    if v_existing.state='effective' then
      return jsonb_build_object(
        'mode','effective_replay','promotionId',v_existing.id,
        'snapshotGeneration',v_existing.snapshot_generation,
        'requiredRevocations',v_existing.required_revocations,
        'completedRevocations',v_existing.completed_revocations,'revocations','[]'::jsonb
      );
    end if;
    if v_existing.state='revoking' and v_fence.fence_state='promoting'
       and v_fence.active_promotion_id=v_existing.id then
      select coalesce(jsonb_agg(jsonb_build_object(
        'pullRequestNumber',pull_request_number,'checkRunId',check_run_id,'headSha',head_sha
      ) order by pull_request_number),'[]'::jsonb) into v_targets
      from private.pandora_coordinator_snapshot_revocations where promotion_id=v_existing.id;
      return jsonb_build_object(
        'mode','replay','promotionId',v_existing.id,'snapshotGeneration',v_existing.snapshot_generation,
        'requiredRevocations',v_existing.required_revocations,'completedRevocations',v_existing.completed_revocations,
        'revocations',v_targets
      );
    end if;
    raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';
  end if;
  if v_fence.fence_state<>'idle' then
    raise exception 'pandora_coordinator_repository_fence_busy' using errcode='55000';
  end if;

  v_generation:=v_fence.effective_snapshot_generation+1;
  insert into private.pandora_coordinator_snapshot_promotions(
    repository,spreadsheet_id,snapshot_generation,candidate_revision,candidate_sha256,
    evidence_ref,provider_read_at,promotion_nonce,state
  ) values (
    p_repository,p_spreadsheet_id,v_generation,p_candidate_revision,p_candidate_sha256,
    p_evidence_ref,p_provider_read_at,p_promotion_nonce,'revoking'
  ) returning id into v_id;

  insert into private.pandora_coordinator_snapshot_revocations(
    promotion_id,pull_request_number,check_run_id,head_sha
  )
  select v_id,pull_request_number,current_check_run_id,head_sha
  from private.pandora_coordinator_gate_state
  where repository=p_repository and decision='PASS'
    and provider_status='completed' and provider_conclusion='success'
    and consumed_at is null and current_check_run_id is not null;
  get diagnostics v_required=row_count;  update private.pandora_coordinator_snapshot_promotions
  set required_revocations=v_required where id=v_id;
  update private.pandora_coordinator_repository_fence
  set fence_state='promoting',active_promotion_id=v_id,updated_at=now()
  where repository=p_repository;
  select coalesce(jsonb_agg(jsonb_build_object(
    'pullRequestNumber',pull_request_number,'checkRunId',check_run_id,'headSha',head_sha
  ) order by pull_request_number),'[]'::jsonb) into v_targets
  from private.pandora_coordinator_snapshot_revocations where promotion_id=v_id;
  return jsonb_build_object(
    'mode','new','promotionId',v_id,'snapshotGeneration',v_generation,
    'requiredRevocations',v_required,'completedRevocations',0,'revocations',v_targets
  );
end;
$body$;
revoke all on function public.pandora_coordinator_snapshot_prepare_v1(
  text,text,text,text,text,text,timestamptz,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_snapshot_prepare_v1(
  text,text,text,text,text,text,timestamptz,text
) to service_role;

create or replace function public.pandora_coordinator_snapshot_record_revocation_v1(
  p_internal_key text,
  p_repository text,
  p_promotion_id uuid,
  p_pull_request_number integer,
  p_check_run_id bigint,
  p_provider_app_id bigint,
  p_provider_status text,
  p_provider_conclusion text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_target private.pandora_coordinator_snapshot_revocations%rowtype;
  v_completed integer;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_provider_app_id<>4785021 or p_provider_status<>'completed'
     or p_provider_conclusion<>'action_required' then
    raise exception 'pandora_coordinator_snapshot_revocation_provider_invalid' using errcode='22023';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if not found or v_fence.fence_state<>'promoting' or v_fence.active_promotion_id<>p_promotion_id then
    raise exception 'pandora_coordinator_snapshot_promotion_not_active' using errcode='23505';
  end if;
  select * into v_target from private.pandora_coordinator_snapshot_revocations
  where promotion_id=p_promotion_id and pull_request_number=p_pull_request_number for update;
  if not found or v_target.check_run_id<>p_check_run_id then
    raise exception 'pandora_coordinator_snapshot_revocation_target_mismatch' using errcode='23505';
  end if;
  if v_target.revoked_at is not null then
    return jsonb_build_object('ok',true,'mode','replay','pullRequestNumber',p_pull_request_number);
  end if;
  update private.pandora_coordinator_snapshot_revocations
  set provider_app_id=p_provider_app_id,provider_status=p_provider_status,
      provider_conclusion=p_provider_conclusion,revoked_at=now()
  where promotion_id=p_promotion_id and pull_request_number=p_pull_request_number;

  update private.pandora_coordinator_gate_decisions d
  set provider_status='completed',provider_conclusion='action_required',
      provider_state='snapshot_revoked',updated_at=now()
  from private.pandora_coordinator_gate_state s  where s.repository=p_repository and s.pull_request_number=p_pull_request_number
    and s.current_decision_id=d.id and s.current_check_run_id=p_check_run_id;
  update private.pandora_coordinator_gate_state
  set provider_status='completed',provider_conclusion='action_required',updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number
    and current_check_run_id=p_check_run_id;
  if not found then
    raise exception 'pandora_coordinator_snapshot_gate_state_mismatch' using errcode='23505';
  end if;
  select count(*)::integer into v_completed
  from private.pandora_coordinator_snapshot_revocations
  where promotion_id=p_promotion_id and revoked_at is not null;
  update private.pandora_coordinator_snapshot_promotions
  set completed_revocations=v_completed where id=p_promotion_id and state='revoking';
  return jsonb_build_object('ok',true,'mode','recorded','pullRequestNumber',p_pull_request_number);
end;
$body$;
revoke all on function public.pandora_coordinator_snapshot_record_revocation_v1(
  text,text,uuid,integer,bigint,bigint,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_snapshot_record_revocation_v1(
  text,text,uuid,integer,bigint,bigint,text,text
) to service_role;

create or replace function public.pandora_coordinator_snapshot_commit_v1(
  p_internal_key text,
  p_repository text,
  p_promotion_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_promotion private.pandora_coordinator_snapshot_promotions%rowtype;
begin  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if not found or v_fence.fence_state<>'promoting' or v_fence.active_promotion_id<>p_promotion_id then
    raise exception 'pandora_coordinator_snapshot_promotion_not_active' using errcode='23505';
  end if;
  select * into v_promotion from private.pandora_coordinator_snapshot_promotions
  where id=p_promotion_id for update;
  if not found or v_promotion.state<>'revoking'
     or v_promotion.required_revocations<>v_promotion.completed_revocations then
    raise exception 'pandora_coordinator_snapshot_revocations_incomplete' using errcode='23505';
  end if;
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',effective_snapshot_generation=v_promotion.snapshot_generation,
      effective_snapshot_revision=v_promotion.candidate_revision,
      effective_snapshot_sha256=v_promotion.candidate_sha256,
      active_promotion_id=null,updated_at=now()
  where repository=p_repository;
  update private.pandora_coordinator_snapshot_promotions
  set state='effective',effective_at=now() where id=p_promotion_id;
  return jsonb_build_object(
    'ok',true,'snapshotGeneration',v_promotion.snapshot_generation,
    'snapshotRevision',v_promotion.candidate_revision,
    'snapshotSha256',v_promotion.candidate_sha256
  );
end;
$body$;
revoke all on function public.pandora_coordinator_snapshot_commit_v1(text,text,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_coordinator_snapshot_commit_v1(text,text,uuid)
  to service_role;

create or replace function public.pandora_coordinator_snapshot_abort_v1(
  p_internal_key text,
  p_repository text,
  p_promotion_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if not found or v_fence.fence_state<>'promoting' or v_fence.active_promotion_id<>p_promotion_id then
    raise exception 'pandora_coordinator_snapshot_promotion_not_active' using errcode='23505';
  end if;
  update private.pandora_coordinator_snapshot_promotions
  set state='aborted',aborted_at=now() where id=p_promotion_id and state='revoking';
  if not found then
    raise exception 'pandora_coordinator_snapshot_promotion_not_abortable' using errcode='23505';
  end if;
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_promotion_id=null,updated_at=now()
  where repository=p_repository;
  return jsonb_build_object('ok',true,'state','aborted');
end;
$body$;
revoke all on function public.pandora_coordinator_snapshot_abort_v1(text,text,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_coordinator_snapshot_abort_v1(text,text,uuid)
  to service_role;

create or replace function public.pandora_coordinator_snapshot_read_effective_v1(
  p_internal_key text,
  p_repository text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository;
  if not found then return null; end if;
  return jsonb_build_object(
    'repository',v_fence.repository,'spreadsheetId',v_fence.spreadsheet_id,
    'fenceState',v_fence.fence_state,'snapshotGeneration',v_fence.effective_snapshot_generation,
    'snapshotRevision',v_fence.effective_snapshot_revision,
    'snapshotSha256',v_fence.effective_snapshot_sha256,
    'activePromotionId',v_fence.active_promotion_id
  );
end;
$body$;
revoke all on function public.pandora_coordinator_snapshot_read_effective_v1(text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_coordinator_snapshot_read_effective_v1(text,text)
  to service_role;

alter table private.pandora_coordinator_repository_fence
  drop constraint if exists pandora_coordinator_repository_fence_fence_state_check;
alter table private.pandora_coordinator_repository_fence
  add constraint pandora_coordinator_repository_fence_fence_state_check
  check (fence_state in ('idle','promoting','publishing','merging'));
alter table private.pandora_coordinator_repository_fence
  add column if not exists active_publication_decision_id uuid references private.pandora_coordinator_gate_decisions(id),
  add column if not exists active_merge_claim_id uuid,
  add column if not exists active_merge_pull_request_number integer;

create or replace function public.pandora_coordinator_gate_begin_decision_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_prior_generation bigint,
  p_prior_check_run_id bigint,
  p_head_sha text,
  p_base_sha text,
  p_authoritative_snapshot_generation bigint,
  p_authoritative_snapshot_revision text,
  p_authoritative_snapshot_sha256 text,
  p_envelope_hash text,
  p_idempotency_key text,
  p_decision_nonce text,
  p_decision text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_decision private.pandora_coordinator_gate_decisions%rowtype;
  v_result jsonb;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if not found or v_fence.fence_state<>'idle'
     or v_fence.effective_snapshot_generation<1
     or v_fence.effective_snapshot_generation<>p_authoritative_snapshot_generation
     or v_fence.effective_snapshot_revision<>p_authoritative_snapshot_revision
     or v_fence.effective_snapshot_sha256<>p_authoritative_snapshot_sha256 then
    raise exception 'pandora_coordinator_gate_effective_snapshot_mismatch' using errcode='23505';
  end if;
  v_result:=public.pandora_coordinator_gate_begin_decision_v1(
    p_internal_key,p_repository,p_pull_request_number,p_decision_generation,
    p_prior_generation,p_prior_check_run_id,p_head_sha,p_base_sha,
    p_authoritative_snapshot_revision,p_authoritative_snapshot_sha256,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_decision,p_expires_at
  );  select * into v_decision
  from private.pandora_coordinator_gate_decisions
  where id=(v_result->>'decisionId')::uuid
  for update;
  if not found then
    raise exception 'pandora_coordinator_gate_decision_missing' using errcode='23505';
  end if;
  if v_decision.authoritative_snapshot_generation is not null
     and v_decision.authoritative_snapshot_generation<>p_authoritative_snapshot_generation then
    raise exception 'pandora_coordinator_gate_snapshot_generation_conflict' using errcode='23505';
  end if;
  update private.pandora_coordinator_gate_decisions
  set authoritative_snapshot_generation=p_authoritative_snapshot_generation,
      updated_at=now()
  where id=v_decision.id;
  update private.pandora_coordinator_gate_state
  set authoritative_snapshot_generation=p_authoritative_snapshot_generation,
      updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number
    and current_decision_id=v_decision.id;
  if not found then
    raise exception 'pandora_coordinator_gate_state_mismatch' using errcode='23505';
  end if;  update private.pandora_coordinator_repository_fence
  set fence_state='publishing',active_publication_decision_id=v_decision.id,
      active_promotion_id=null,active_merge_claim_id=null,
      active_merge_pull_request_number=null,updated_at=now()
  where repository=p_repository and fence_state='idle';
  if not found then
    raise exception 'pandora_coordinator_repository_fence_busy' using errcode='55000';
  end if;
  return v_result || jsonb_build_object(
    'snapshotGeneration',p_authoritative_snapshot_generation,
    'publicationFence','publishing'
  );
end;
$body$;
revoke all on function public.pandora_coordinator_gate_begin_decision_v2(
  text,text,integer,bigint,bigint,bigint,text,text,bigint,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_begin_decision_v2(
  text,text,integer,bigint,bigint,bigint,text,text,bigint,text,text,text,text,text,text,timestamptz
) to service_role;

create or replace function public.pandora_coordinator_gate_record_publish_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_authoritative_snapshot_generation bigint,  p_envelope_hash text,
  p_idempotency_key text,
  p_check_run_id bigint,
  p_provider_app_id bigint,
  p_provider_status text,
  p_provider_conclusion text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_result jsonb;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_fence.fence_state<>'publishing'
     or v_fence.active_publication_decision_id<>v_state.current_decision_id then
    raise exception 'pandora_coordinator_publication_fence_mismatch' using errcode='23505';
  end if;  if v_fence.effective_snapshot_generation<>p_authoritative_snapshot_generation
     or v_state.authoritative_snapshot_generation<>p_authoritative_snapshot_generation
     or v_state.current_generation<>p_decision_generation then
    raise exception 'pandora_coordinator_publication_snapshot_mismatch' using errcode='23505';
  end if;
  v_result:=public.pandora_coordinator_gate_record_publish_v1(
    p_internal_key,p_repository,p_pull_request_number,p_decision_generation,
    p_envelope_hash,p_idempotency_key,p_check_run_id,p_provider_app_id,
    p_provider_status,p_provider_conclusion
  );
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_publication_decision_id=null,updated_at=now()
  where repository=p_repository and fence_state='publishing'
    and active_publication_decision_id=v_state.current_decision_id;
  if not found then
    raise exception 'pandora_coordinator_publication_release_failed' using errcode='23505';
  end if;
  return v_result || jsonb_build_object('publicationFence','released');
end;
$body$;
revoke all on function public.pandora_coordinator_gate_record_publish_v2(
  text,text,integer,bigint,bigint,text,text,bigint,bigint,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_record_publish_v2(
  text,text,integer,bigint,bigint,text,text,bigint,bigint,text,text
) to service_role;
create or replace function public.pandora_coordinator_gate_claim_merge_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_authoritative_snapshot_generation bigint,
  p_authoritative_snapshot_revision text,
  p_authoritative_snapshot_sha256 text,
  p_envelope_hash text,
  p_idempotency_key text,
  p_decision_nonce text,
  p_check_run_id bigint,
  p_head_sha text,
  p_base_sha text,
  p_claim_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_result jsonb;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_fence.fence_state<>'idle'
     or v_fence.effective_snapshot_generation<>p_authoritative_snapshot_generation
     or v_fence.effective_snapshot_revision<>p_authoritative_snapshot_revision
     or v_fence.effective_snapshot_sha256<>p_authoritative_snapshot_sha256
     or v_state.authoritative_snapshot_generation<>p_authoritative_snapshot_generation
     or v_state.authoritative_snapshot_revision<>p_authoritative_snapshot_revision
     or v_state.authoritative_snapshot_sha256<>p_authoritative_snapshot_sha256 then
    raise exception 'pandora_coordinator_merge_snapshot_fence_mismatch' using errcode='23505';
  end if;
  v_result:=public.pandora_coordinator_gate_claim_merge_v1(
    p_internal_key,p_repository,p_pull_request_number,p_decision_generation,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_check_run_id,
    p_head_sha,p_base_sha,p_claim_id
  );
  update private.pandora_coordinator_repository_fence
  set fence_state='merging',active_merge_claim_id=p_claim_id,
      active_merge_pull_request_number=p_pull_request_number,updated_at=now()
  where repository=p_repository and fence_state='idle';
  if not found then
    raise exception 'pandora_coordinator_merge_fence_claim_failed' using errcode='55000';
  end if;
  return v_result || jsonb_build_object(
    'snapshotGeneration',p_authoritative_snapshot_generation,'mergeFence','held'
  );
end;
$body$;revoke all on function public.pandora_coordinator_gate_claim_merge_v2(
  text,text,integer,bigint,bigint,text,text,text,text,text,bigint,text,text,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_claim_merge_v2(
  text,text,integer,bigint,bigint,text,text,text,text,text,bigint,text,text,uuid
) to service_role;

create or replace function public.pandora_coordinator_gate_complete_merge_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_claim_id uuid,
  p_merge_sha text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_result jsonb;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  if not found or v_fence.fence_state<>'merging'
     or v_fence.active_merge_claim_id<>p_claim_id
     or v_fence.active_merge_pull_request_number<>p_pull_request_number then
    raise exception 'pandora_coordinator_merge_fence_mismatch' using errcode='23505';
  end if;  v_result:=public.pandora_coordinator_gate_complete_merge_v1(
    p_internal_key,p_repository,p_pull_request_number,p_decision_generation,
    p_claim_id,p_merge_sha
  );
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_merge_claim_id=null,
      active_merge_pull_request_number=null,updated_at=now()
  where repository=p_repository and fence_state='merging'
    and active_merge_claim_id=p_claim_id;
  if not found then
    raise exception 'pandora_coordinator_merge_fence_release_failed' using errcode='23505';
  end if;
  return v_result || jsonb_build_object('mergeFence','released');
end;
$body$;
revoke all on function public.pandora_coordinator_gate_complete_merge_v2(
  text,text,integer,bigint,uuid,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_complete_merge_v2(
  text,text,integer,bigint,uuid,text
) to service_role;

create or replace function public.pandora_coordinator_gate_abort_merge_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_claim_id uuid,
  p_check_run_id bigint,
  p_provider_app_id bigint,
  p_provider_status text,
  p_provider_conclusion text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_provider_app_id<>4785021 or p_provider_status<>'completed'
     or p_provider_conclusion<>'action_required' then
    raise exception 'pandora_coordinator_merge_abort_provider_invalid' using errcode='22023';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_fence.fence_state<>'merging'
     or v_fence.active_merge_claim_id<>p_claim_id
     or v_fence.active_merge_pull_request_number<>p_pull_request_number
     or v_state.current_generation<>p_decision_generation
     or v_state.merge_claim_id<>p_claim_id
     or v_state.current_check_run_id<>p_check_run_id
     or v_state.consumed_at is not null then
    raise exception 'pandora_coordinator_merge_abort_fence_mismatch' using errcode='23505';
  end if;  update private.pandora_coordinator_gate_decisions
  set provider_status='completed',provider_conclusion='action_required',
      provider_state='merge_aborted',merge_claim_id=null,merge_claimed_at=null,
      updated_at=now()
  where id=v_state.current_decision_id;
  update private.pandora_coordinator_gate_state
  set provider_status='completed',provider_conclusion='action_required',
      merge_claim_id=null,merge_claimed_at=null,updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_merge_claim_id=null,
      active_merge_pull_request_number=null,updated_at=now()
  where repository=p_repository and fence_state='merging'
    and active_merge_claim_id=p_claim_id;
  if not found then
    raise exception 'pandora_coordinator_merge_abort_release_failed' using errcode='23505';
  end if;
  return jsonb_build_object('ok',true,'mergeFence','released','state','aborted');
end;
$body$;
revoke all on function public.pandora_coordinator_gate_abort_merge_v2(
  text,text,integer,bigint,uuid,bigint,bigint,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_abort_merge_v2(
  text,text,integer,bigint,uuid,bigint,bigint,text,text
) to service_role;

revoke all on table private.pandora_coordinator_repository_fence from public,anon,authenticated;
revoke all on table private.pandora_coordinator_snapshot_promotions from public,anon,authenticated;
revoke all on table private.pandora_coordinator_snapshot_revocations from public,anon,authenticated;
grant select,insert,update on table private.pandora_coordinator_repository_fence to service_role;
grant select,insert,update on table private.pandora_coordinator_snapshot_promotions to service_role;
grant select,insert,update on table private.pandora_coordinator_snapshot_revocations to service_role;
create or replace function public.pandora_coordinator_gate_begin_expiry_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_check_run_id bigint
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_fence.fence_state<>'idle'
     or v_state.current_generation<>p_decision_generation
     or v_state.current_check_run_id<>p_check_run_id
     or v_state.expires_at>now() then
    raise exception 'pandora_coordinator_expiry_fence_mismatch' using errcode='23505';
  end if;  update private.pandora_coordinator_repository_fence
  set fence_state='publishing',active_publication_decision_id=v_state.current_decision_id,
      updated_at=now()
  where repository=p_repository and fence_state='idle';
  if not found then
    raise exception 'pandora_coordinator_expiry_fence_claim_failed' using errcode='55000';
  end if;
  return jsonb_build_object(
    'ok',true,'decisionId',v_state.current_decision_id,
    'generation',v_state.current_generation,'checkRunId',v_state.current_check_run_id,
    'headSha',v_state.head_sha,'expiresAt',v_state.expires_at
  );
end;
$body$;
revoke all on function public.pandora_coordinator_gate_begin_expiry_v2(
  text,text,integer,bigint,bigint
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_begin_expiry_v2(
  text,text,integer,bigint,bigint
) to service_role;

create or replace function public.pandora_coordinator_gate_mark_expired_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_check_run_id bigint
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_result jsonb;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_fence from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_fence.fence_state<>'publishing'
     or v_fence.active_publication_decision_id<>v_state.current_decision_id
     or v_state.current_generation<>p_decision_generation
     or v_state.current_check_run_id<>p_check_run_id then
    raise exception 'pandora_coordinator_expiry_fence_mismatch' using errcode='23505';
  end if;
  v_result:=public.pandora_coordinator_gate_mark_expired_v1(
    p_internal_key,p_repository,p_pull_request_number,p_decision_generation,p_check_run_id
  );
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_publication_decision_id=null,updated_at=now()
  where repository=p_repository and fence_state='publishing'
    and active_publication_decision_id=v_state.current_decision_id;
  if not found then
    raise exception 'pandora_coordinator_expiry_fence_release_failed' using errcode='23505';
  end if;
  return v_result || jsonb_build_object('publicationFence','released');
end;
$body$;revoke all on function public.pandora_coordinator_gate_mark_expired_v2(
  text,text,integer,bigint,bigint
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_mark_expired_v2(
  text,text,integer,bigint,bigint
) to service_role;
