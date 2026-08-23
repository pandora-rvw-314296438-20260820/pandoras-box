-- Emergency capability rollback for 20260823155000.
-- Run only after later migrations that depend on projectos_reviewer_ingest
-- have been rolled back. Historical signatures, evidence, audit rows, and
-- completed dispatches are intentionally preserved.

begin;

update private.compute_reviewer_identities
set status = 'disabled', updated_at = now()
where status <> 'disabled';

revoke execute on function public.resolve_compute_reviewer_identity(uuid, text)
  from service_role;
revoke execute on function public.record_governed_worker_review_attestation(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text, text, text, text, text,
  text, text, text
) from projectos_reviewer_ingest;

-- Keep guard_governed_worker_review_attestation installed. New finalization
-- must fail closed instead of falling back to unsigned projectos_evidence.

commit;
