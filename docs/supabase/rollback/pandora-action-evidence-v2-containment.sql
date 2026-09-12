-- Emergency containment for the exact action-evidence v2 release.
-- Preserve evidence/audit history and fail closed. Never restore vulnerable v1 bodies.
-- Resume by applying the reviewed v2 migration, then run its bounded service backfill.
begin;
drop trigger if exists execution_plan_evidence_v1 on private.execution_plans;
revoke execute on function public.pandora_action_evidence_v1(uuid,integer) from public,anon,authenticated;
revoke execute on function private.pandora_record_execution_plan_evidence_v1(uuid) from public,anon,authenticated,service_role;
revoke execute on function private.pandora_backfill_action_evidence_v2(integer) from public,anon,authenticated,service_role;
commit;
