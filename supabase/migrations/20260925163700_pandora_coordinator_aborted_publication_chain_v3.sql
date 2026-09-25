-- Recover coordinator decision chaining after an ambiguous provider write was
-- explicitly aborted before the provider check ID could be recorded.
--
-- The previous generation may have reached GitHub even though the database has
-- current_check_run_id = null. In that exact audited state, the next envelope
-- may name the provider check as prior-chain evidence. The Edge publisher still
-- validates the check's App identity, name, external generation metadata, and
-- exact prior ID before publishing. The NEW generation keeps its own check ID
-- null until provider readback succeeds.
create or replace function public.pandora_coordinator_gate_begin_decision_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_prior_generation bigint,
  p_prior_check_run_id bigint,
  p_head_sha text,
  p_base_sha text,
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
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_existing private.pandora_coordinator_gate_decisions%rowtype;
  v_prior private.pandora_coordinator_gate_decisions%rowtype;
  v_id uuid;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_pull_request_number < 1 or p_decision_generation < 1
     or p_head_sha !~ '^[0-9a-f]{40}$' or p_base_sha !~ '^[0-9a-f]{40}$'
     or p_authoritative_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     or p_envelope_hash !~ '^[0-9a-f]{64}$' or p_idempotency_key !~ '^[0-9a-f]{64}$'
     or p_decision not in ('PASS','HOLD') or p_expires_at <= now() then
    raise exception 'pandora_coordinator_gate_decision_invalid' using errcode='22023';
  end if;

  select * into v_existing
  from private.pandora_coordinator_gate_decisions
  where repository=p_repository and pull_request_number=p_pull_request_number
    and decision_generation=p_decision_generation;
  if found then
    if v_existing.head_sha<>p_head_sha or v_existing.base_sha<>p_base_sha
       or v_existing.authoritative_snapshot_revision<>p_authoritative_snapshot_revision
       or v_existing.authoritative_snapshot_sha256<>p_authoritative_snapshot_sha256
       or v_existing.envelope_hash<>p_envelope_hash
       or v_existing.idempotency_key<>p_idempotency_key
       or v_existing.decision_nonce<>p_decision_nonce
       or v_existing.decision<>p_decision then
      raise exception 'pandora_coordinator_gate_generation_conflict' using errcode='23505';
    end if;
    return jsonb_build_object(
      'mode','replay','decisionId',v_existing.id,
      'generation',v_existing.decision_generation,
      'checkRunId',v_existing.check_run_id,
      'providerState',v_existing.provider_state
    );
  end if;

  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;

  if found then
    if p_decision_generation<>v_state.current_generation+1
       or p_prior_generation is distinct from v_state.current_generation then
      raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
    end if;

    if p_prior_check_run_id is distinct from v_state.current_check_run_id then
      if v_state.current_check_run_id is not null or p_prior_check_run_id is null then
        raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
      end if;
      select * into v_prior
      from private.pandora_coordinator_gate_decisions
      where id=v_state.current_decision_id
      for share;
      if not found
         or v_prior.decision_generation<>v_state.current_generation
         or v_prior.provider_state<>'publication_aborted'
         or v_prior.check_run_id is not null
         or v_prior.provider_status is not null
         or v_prior.provider_conclusion is not null then
        raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
      end if;
    end if;
  else
    if p_decision_generation<>1 or p_prior_generation is not null or p_prior_check_run_id is not null then
      raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
    end if;
  end if;

  insert into private.pandora_coordinator_gate_decisions(
    repository,pull_request_number,decision_generation,head_sha,base_sha,
    authoritative_snapshot_revision,authoritative_snapshot_sha256,
    envelope_hash,idempotency_key,decision_nonce,decision,expires_at,
    check_run_id,provider_state
  ) values (
    p_repository,p_pull_request_number,p_decision_generation,p_head_sha,p_base_sha,
    p_authoritative_snapshot_revision,p_authoritative_snapshot_sha256,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_decision,p_expires_at,
    null,'pending_publish'
  ) returning id into v_id;

  insert into private.pandora_coordinator_gate_state(
    repository,pull_request_number,current_decision_id,current_generation,
    head_sha,base_sha,authoritative_snapshot_revision,authoritative_snapshot_sha256,
    envelope_hash,idempotency_key,decision_nonce,decision,expires_at,
    current_check_run_id,provider_status,provider_conclusion,
    merge_claim_id,merge_claimed_at,merged_sha,consumed_at,updated_at
  ) values (
    p_repository,p_pull_request_number,v_id,p_decision_generation,
    p_head_sha,p_base_sha,p_authoritative_snapshot_revision,p_authoritative_snapshot_sha256,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_decision,p_expires_at,
    null,null,null,null,null,null,null,now()
  ) on conflict(repository,pull_request_number) do update set
    current_decision_id=excluded.current_decision_id,
    current_generation=excluded.current_generation,
    head_sha=excluded.head_sha,base_sha=excluded.base_sha,
    authoritative_snapshot_revision=excluded.authoritative_snapshot_revision,
    authoritative_snapshot_sha256=excluded.authoritative_snapshot_sha256,
    envelope_hash=excluded.envelope_hash,idempotency_key=excluded.idempotency_key,
    decision_nonce=excluded.decision_nonce,decision=excluded.decision,
    expires_at=excluded.expires_at,current_check_run_id=null,
    provider_status=null,provider_conclusion=null,merge_claim_id=null,
    merge_claimed_at=null,merged_sha=null,consumed_at=null,updated_at=now();

  return jsonb_build_object(
    'mode','new','decisionId',v_id,'generation',p_decision_generation,
    'priorCheckRunId',p_prior_check_run_id
  );
end;
$body$;

revoke all on function public.pandora_coordinator_gate_begin_decision_v1(
  text,text,integer,bigint,bigint,bigint,text,text,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_begin_decision_v1(
  text,text,integer,bigint,bigint,bigint,text,text,text,text,text,text,text,text,timestamptz
) to service_role;
