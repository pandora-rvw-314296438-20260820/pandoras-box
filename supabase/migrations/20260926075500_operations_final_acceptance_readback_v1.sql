-- Operations Room final acceptance readback v1.
-- OIDC-authenticated Vercel release workers receive only bounded canonical Operations evidence.

create or replace function public.pandora_ops_final_acceptance_readback_v1(
  p_organization_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_tasks constant text[] := array[
    'OPS-SESSION-SHEETS-BRIDGE-V2',
    'OPS-WAKE-RECOVERY-V3',
    'OPS-INTELLIGENCE-ROUTER-SERVICE-V1',
    'OPS-MEMORY-CALLER-ADOPTION-V1',
    'OPS-THEATRE-LIVE-EVENTS-V1',
    'OPS-SERIALIZATION-CANARY-A-V1',
    'OPS-SERIALIZATION-CANARY-B-V1',
    'OPS-WHOLE-SHEET-ACCEPTANCE-V3'
  ]::text[];
begin
  perform 1
  from private.pandora_ops_project_bindings
  where organization_id=p_organization_id
    and project_id=p_project_id
    and state='active';
  if not found then
    raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501';
  end if;

  return jsonb_build_object(
    'tasks',
    coalesce((
      select jsonb_object_agg(
        t.task_key,
        jsonb_build_object(
          'status',t.status,
          'generation',t.generation,
          'revision',t.revision,
          'headSha',t.head_sha,
          'specDigest',t.spec_digest,
          'builderWorkerKey',t.builder_worker_key,
          'builderPrincipalKey',t.builder_principal_key,
          'handoff',t.handoff,
          'verification',t.verification
        )
        order by t.task_key
      )
      from private.pandora_ops_tasks t
      where t.organization_id=p_organization_id
        and t.project_id=p_project_id
        and t.task_key=any(v_tasks)
    ),'{}'::jsonb),
    'events',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',e.id,
          'taskId',e.task_key,
          'eventType',e.event_type,
          'receiptRef',e.receipt_ref,
          'occurredAt',e.occurred_at
        )
        order by e.id
      )
      from private.pandora_ops_events e
      where e.organization_id=p_organization_id
        and e.project_id=p_project_id
        and e.task_key=any(v_tasks)
    ),'[]'::jsonb)
  );
end;
$body$;

revoke all on function public.pandora_ops_final_acceptance_readback_v1(uuid,uuid)
from public,anon,authenticated;

grant execute on function public.pandora_ops_final_acceptance_readback_v1(uuid,uuid)
to service_role;
