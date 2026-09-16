-- R-058 recovery for an expired publication that never created a provider Check Run.
create or replace function public.pandora_coordinator_gate_abort_unpublished_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint
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
  where repository=p_repository and pull_request_number=p_pull_request_number for update;
  if v_fence.repository is null or v_state.repository is null
     or v_fence.fence_state<>'publishing'
     or v_fence.active_publication_decision_id<>v_state.current_decision_id
     or v_state.current_generation<>p_decision_generation
     or v_state.current_check_run_id is not null
     or v_state.provider_status is not null
     or v_state.provider_conclusion is not null
     or v_state.expires_at>now()
     or v_state.consumed_at is not null
     or v_state.merge_claim_id is not null then
    raise exception 'pandora_coordinator_unpublished_abort_not_authorized' using errcode='42501';
  end if;
  update private.pandora_coordinator_gate_decisions
  set provider_state='expired_unpublished',updated_at=now()
  where id=v_state.current_decision_id and check_run_id is null;
  if not found then
    raise exception 'pandora_coordinator_unpublished_abort_state_mismatch' using errcode='23505';
  end if;
  update private.pandora_coordinator_repository_fence
  set fence_state='idle',active_publication_decision_id=null,updated_at=now()
  where repository=p_repository and fence_state='publishing'
    and active_publication_decision_id=v_state.current_decision_id;
  if not found then
    raise exception 'pandora_coordinator_unpublished_abort_release_failed' using errcode='23505';
  end if;
  return jsonb_build_object('ok',true,'state','expired_unpublished','generation',v_state.current_generation);
end;
$body$;
revoke all on function public.pandora_coordinator_gate_abort_unpublished_v1(text,text,integer,bigint)
  from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_abort_unpublished_v1(text,text,integer,bigint)
  to service_role;
