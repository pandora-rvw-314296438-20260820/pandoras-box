-- Emergency capability rollback for 20260823163000.
-- Historical context, audit events, approved plans, dispatches, and review
-- evidence are intentionally preserved. Existing attached contexts remain
-- readable; new plans fail closed until the hardened capability is restored.

begin;

revoke execute on function public.attach_execution_plan_context(
  uuid, uuid, uuid, text, jsonb
) from service_role;

commit;
