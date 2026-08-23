-- FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK.
--
-- This rollback stops owner decisions and worker mutation without restoring the
-- candidate service-role gateway. It intentionally preserves the authority JTI
-- ledger, signed claim/completion fields, reviewer/physical bindings, immutable
-- triggers, and historical rows so an incident cannot erase release evidence.

-- Disable both the caller-bound owner entrypoint and the legacy entrypoint that
-- accepted caller-supplied decision attribution. Nothing is granted here.
revoke all on function public.decide_governed_worker_execution_plan(
  uuid,uuid,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.decide_governed_worker_execution_plan(
  uuid,uuid,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;

-- Keep every legacy candidate/service-role worker mutation path disabled.
revoke all on function public.consume_compute_worker_nonce(
  uuid,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.consume_compute_worker_nonce(
  uuid,text,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.claim_governed_worker_dispatch(
  uuid,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.claim_governed_worker_dispatch(
  uuid,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.record_governed_worker_job_envelope(
  uuid,uuid,uuid,text,text,jsonb,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch(
  uuid,uuid,uuid,text,text,integer,text,text,jsonb
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch(
  uuid,uuid,uuid,text,text,text,integer,text,text,jsonb
) from public, anon, authenticated, service_role, projectos_worker_ingest;

-- Disable the externally authorized worker entrypoints while preserving their
-- definitions and all receipts required to audit or reconcile work in flight.
revoke all on function public.claim_governed_worker_dispatch_authorized(
  uuid,text,text,uuid,text,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.record_governed_worker_job_envelope_authorized(
  uuid,uuid,uuid,text,text,text,jsonb,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch_authorized(
  uuid,uuid,uuid,text,text,text,integer,text,text,jsonb,uuid,text,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;

-- Stop new gateway sessions from assuming the ingest role. Keep the nologin
-- role itself so privilege and evidence audits can still name it deterministically.
revoke usage on schema public from projectos_worker_ingest;
revoke projectos_worker_ingest from authenticator;
alter role projectos_worker_ingest nologin noinherit;

-- Prevent already-enrolled workers from claiming new work. Existing dispatch,
-- JTI, signature, reviewer, and physical receipt rows remain immutable and must
-- be reconciled before an explicitly reviewed re-enable migration is applied.
update private.compute_worker_identities
set status = 'draining',
    updated_at = now()
where status = 'active';
