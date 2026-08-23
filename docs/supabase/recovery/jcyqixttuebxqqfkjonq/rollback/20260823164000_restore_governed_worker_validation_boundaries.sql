-- Emergency capability rollback for 20260823164000.
-- Validation, canonical-hash constraints, safe search paths, and immutable
-- evidence remain installed. The affected mutation capabilities are disabled
-- rather than restoring fail-open SQL semantics.

begin;

revoke execute on function public.projectos_create_or_get_worker_plan(
  uuid, uuid, jsonb, text, timestamptz
) from service_role;

revoke execute on function public.record_governed_worker_job_envelope(
  uuid, uuid, uuid, text, text, jsonb, text
) from service_role;

revoke execute on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, text, integer, text, text, jsonb
) from service_role;

revoke execute on function public.attach_execution_plan_context(
  uuid, uuid, uuid, text, jsonb
) from service_role;

revoke execute on function public.record_governed_worker_review_attestation(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text, text, text, text, text,
  text, text, text
) from projectos_reviewer_ingest;

commit;
