-- R-058 recovery for an ambiguous coordinator publication before any GitHub check write.
-- Preserves the aborted decision for audit and releases only the exact held publication fence.

create or replace function public.pandora_coordinator_gate_abort_publication_v2(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_decision_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_pull_request_number < 1 or p_decision_generation < 1 or p_decision_id is null
     or v_reason is null or length(v_reason) > 240 then
    raise exception 'pandora_coordinator_publication_abort_invalid' using errcode='22023';
  end if;

  select * into v_fence
  from private.pandora_coordinator_repository_fence
  where repository=p_repository for update;
  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;

  if not found or v_fence.fence_state <> 'publishing'
     or v_fence.active_publication_decision_id <> p_decision_id
     or v_state.current_decision_id <> p_decision_id
     or v_state.current_generation <> p_decision_generation
     or v_state.current_check_run_id is not null
     or v_state.provider_status is not null
     or v_state.provider_conclusion is not null
     or v_state.merge_claim_id is not null
     or v_state.consumed_at is not null then
    raise exception 'pandora_coordinator_publication_abort_mismatch' using errcode='23505';
  end if;

  update private.pandora_coordinator_gate_decisions
  set provider_state='publication_aborted', updated_at=now()
  where id=p_decision_id and check_run_id is null
    and provider_status is null and provider_conclusion is null;
  if not found then
    raise exception 'pandora_coordinator_publication_abort_decision_mismatch' using errcode='23505';
  end if;

  update private.pandora_coordinator_repository_fence
  set fence_state='idle', active_publication_decision_id=null, updated_at=now()
  where repository=p_repository and fence_state='publishing'
    and active_publication_decision_id=p_decision_id;
  if not found then
    raise exception 'pandora_coordinator_publication_abort_release_failed' using errcode='23505';
  end if;

  return jsonb_build_object(
    'ok',true,'state','publication_aborted','decisionId',p_decision_id,
    'generation',p_decision_generation,'reason',v_reason,'publicationFence','released'
  );
end;
$body$;

revoke all on function public.pandora_coordinator_gate_abort_publication_v2(
  text,text,integer,bigint,uuid,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_abort_publication_v2(
  text,text,integer,bigint,uuid,text
) to service_role;
