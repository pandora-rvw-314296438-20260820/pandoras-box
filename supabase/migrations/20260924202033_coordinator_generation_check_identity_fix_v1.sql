
-- Coordinator generation check identity fix v1.
--
-- A new decision generation must bind the prior check run only as chain evidence.
-- It must not pre-populate the new generation's current check identity, because
-- GitHub will publish a distinct trusted check run for the new generation.
--
-- record_publish_v1 also recognizes the one legacy pending state created by the
-- old behavior: current_check_run_id equals the immediately-prior generation's
-- trusted check, while the current generation has not recorded provider status.
-- In that case only, a new trusted provider check may replace the inherited ID.

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
       or p_prior_generation is distinct from v_state.current_generation
       or p_prior_check_run_id is distinct from v_state.current_check_run_id then
      raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
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

create or replace function public.pandora_coordinator_gate_record_publish_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_envelope_hash text,
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
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_current private.pandora_coordinator_gate_decisions%rowtype;
  v_prior private.pandora_coordinator_gate_decisions%rowtype;
  v_expected_conclusion text;
  v_legacy_inherited_prior boolean := false;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_provider_app_id<>4785021 or p_check_run_id<1 or p_provider_status<>'completed' then
    raise exception 'pandora_coordinator_gate_provider_identity_invalid' using errcode='22023';
  end if;

  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found
     or v_state.current_generation<>p_decision_generation
     or v_state.envelope_hash<>p_envelope_hash
     or v_state.idempotency_key<>p_idempotency_key then
    raise exception 'pandora_coordinator_gate_state_mismatch' using errcode='23505';
  end if;

  v_expected_conclusion := case when v_state.decision='PASS' then 'success' else 'action_required' end;
  if p_provider_conclusion<>v_expected_conclusion then
    raise exception 'pandora_coordinator_gate_provider_state_invalid' using errcode='22023';
  end if;

  select * into v_current
  from private.pandora_coordinator_gate_decisions
  where id=v_state.current_decision_id
  for update;
  if not found
     or v_current.decision_generation<>p_decision_generation
     or v_current.provider_status is not null
     or v_current.provider_conclusion is not null then
    raise exception 'pandora_coordinator_gate_current_decision_mismatch' using errcode='23505';
  end if;

  if v_state.current_check_run_id is not null and v_state.current_check_run_id<>p_check_run_id then
    if p_decision_generation > 1 then
      select * into v_prior
      from private.pandora_coordinator_gate_decisions
      where repository=p_repository
        and pull_request_number=p_pull_request_number
        and decision_generation=p_decision_generation-1;

      v_legacy_inherited_prior :=
        found
        and v_prior.check_run_id is not null
        and v_state.current_check_run_id=v_prior.check_run_id
        and v_current.check_run_id=v_prior.check_run_id
        and v_current.provider_state='pending_publish';
    end if;

    if not v_legacy_inherited_prior then
      raise exception 'pandora_coordinator_gate_check_identity_conflict' using errcode='23505';
    end if;
  end if;

  update private.pandora_coordinator_gate_decisions
  set check_run_id=p_check_run_id,
      provider_status=p_provider_status,
      provider_conclusion=p_provider_conclusion,
      provider_state=case when v_state.decision='PASS' then 'completed_success' else 'completed_hold' end,
      updated_at=now()
  where id=v_state.current_decision_id;

  update private.pandora_coordinator_gate_state
  set current_check_run_id=p_check_run_id,
      provider_status=p_provider_status,
      provider_conclusion=p_provider_conclusion,
      updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;

  return jsonb_build_object(
    'ok',true,
    'checkRunId',p_check_run_id,
    'decision',v_state.decision,
    'legacyInheritedPriorRecovered',v_legacy_inherited_prior
  );
end;
$body$;

revoke all on function public.pandora_coordinator_gate_record_publish_v1(
  text,text,integer,bigint,text,text,bigint,bigint,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_record_publish_v1(
  text,text,integer,bigint,text,text,bigint,bigint,text,text
) to service_role;
;
