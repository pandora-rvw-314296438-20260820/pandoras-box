-- Recoverable capability rollback for 20260823143000.
-- Historical plan, dispatch, result, and audit evidence is intentionally retained.
-- New intake/claim/delivery is frozen. Authenticated late-result reporting and
-- reviewer finalization remain available so signed work is not orphaned.
-- The plan guard is retained so legacy claim/finish callers cannot bypass the outbox.

begin;

update private.compute_worker_identities
set status = 'draining', updated_at = now()
where status = 'active';

update public.projectos_agent_runtime_proofs proof
set active_leases = greatest(
      proof.active_leases - active_dispatch.active_count,
      0
    ),
    updated_at = now()
from (
  select runtime_proof_id, count(*)::integer as active_count
  from private.execution_dispatch_outbox
  where status in ('claimed', 'envelope_ready')
    and runtime_proof_id is not null
  group by runtime_proof_id
) active_dispatch
where proof.id = active_dispatch.runtime_proof_id;

do $$
declare
  item record;
begin
  -- Queued and unsigned claimed work provably has no runnable control envelope.
  -- Finalize those plans as failed before removing the new-work RPCs.
  for item in
    select dispatch.id as dispatch_id,
           dispatch.organization_id,
           dispatch.plan_id
    from private.execution_dispatch_outbox dispatch
    join private.execution_plans plan on plan.id = dispatch.plan_id
    where dispatch.status in ('queued', 'claimed')
      and dispatch.job_digest is null
      and plan.status = 'executing'
    order by dispatch.created_at
    for update of dispatch, plan
  loop
    update private.execution_dispatch_outbox
    set status = 'finalizing',
        verified_outcome = 'failed',
        verified_at = now(),
        verification_summary = jsonb_build_object(
          'schemaVersion', 1,
          'decision', 'failed',
          'reason', 'capability_rollback_before_delivery'
        ),
        error_code = 'ROLLBACK_DISABLED_BEFORE_WORKER_START',
        updated_at = now()
    where id = item.dispatch_id;

    perform public.finish_execution_plan(
      item.organization_id,
      item.plan_id,
      'failed',
      0,
      'worker capability rollback before signed delivery',
      '{}'::jsonb
    );

    update private.execution_dispatch_outbox
    set status = 'failed', completed_at = now(), updated_at = now()
    where id = item.dispatch_id and status = 'finalizing';
  end loop;
end;
$$;

update private.execution_plans plan
set status = 'denied',
    completed_at = now(),
    error = 'worker capability rollback before execution claim',
    updated_at = now()
from private.execution_dispatch_outbox dispatch
where dispatch.plan_id = plan.id
  and dispatch.status = 'staged'
  and plan.status in ('pending_approval', 'approved');

update private.execution_dispatch_outbox
set status = 'failed',
    error_code = 'ROLLBACK_DISABLED_BEFORE_WORKER_START',
    completed_at = now(),
    updated_at = now()
where status in ('staged', 'queued', 'claimed');

-- A signed envelope may already have reached the worker. Preserve ambiguity;
-- never retry or force-fail it without exact provider/worker readback.
update private.execution_dispatch_outbox
set status = 'ambiguous',
    error_code = 'ROLLBACK_OUTCOME_REQUIRES_RECONCILIATION',
    completed_at = now(),
    updated_at = now()
where status = 'envelope_ready';

revoke all on function public.register_compute_worker_identity(
  uuid, uuid, text, text, text[], text[]
) from service_role;
revoke all on function public.projectos_accept_governed_worker_intake(
  uuid, uuid, text, text, text, text
) from service_role;
revoke all on function public.projectos_create_or_get_worker_plan(
  uuid, uuid, jsonb, text, timestamptz
) from service_role;
revoke all on function public.decide_governed_worker_execution_plan(
  uuid, uuid, text, text
) from service_role;
revoke all on function public.claim_governed_worker_dispatch(uuid, text)
  from service_role;
revoke all on function public.record_governed_worker_job_envelope(
  uuid, uuid, uuid, text, text, jsonb, text
) from service_role;
drop function if exists public.record_governed_worker_job_envelope(
  uuid, uuid, uuid, text, text, jsonb, text
);
drop function if exists public.claim_governed_worker_dispatch(uuid, text);
drop function if exists public.decide_governed_worker_execution_plan(
  uuid, uuid, text, text
);
drop function if exists public.register_compute_worker_identity(
  uuid, uuid, text, text, text[], text[]
);
drop function if exists public.projectos_create_or_get_worker_plan(
  uuid, uuid, jsonb, text, timestamptz
);
drop function if exists public.projectos_accept_governed_worker_intake(
  uuid, uuid, text, text, text, text
);

commit;
