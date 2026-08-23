-- Roll back the safe terminal-outcome readback surface while preserving plan rows.
-- This restores the exact pre-20260823150000 list response shape.

create or replace function public.list_execution_plans(
  p_organization_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_control_service_role();

  return coalesce((
    select jsonb_agg(plan_row order by (plan_row ->> 'createdAt')::timestamptz desc)
    from (
      select jsonb_strip_nulls(jsonb_build_object(
        'planId', plan.id,
        'requestId', plan.request_id,
        'tool', plan.tool,
        'risk', plan.risk,
        'args', plan.args,
        'payloadHash', plan.payload_hash,
        'status', case
          when plan.status in ('pending_approval', 'approved') and plan.expires_at <= now()
            then 'expired'
          else plan.status
        end,
        'expiresAt', plan.expires_at,
        'createdAt', plan.created_at,
        'approvedAt', plan.approved_at,
        'claimedAt', plan.claimed_at,
        'completedAt', plan.completed_at,
        'durationMs', plan.duration_ms,
        'intakeId', intake.id,
        'projectId', project.id,
        'projectKey', project.project_key,
        'intakeStatus', intake.status,
        'memoryContext', context.context_envelope,
        'memoryContextHash', context.context_hash,
        'memoryContextRecorded', case when context.plan_id is null then null else true end
      )) as plan_row
      from private.execution_plans plan
      left join public.projectos_intake_requests intake
        on intake.id = plan.intake_id and intake.organization_id = plan.organization_id
      left join public.projectos_projects project
        on project.id = intake.project_id and project.organization_id = plan.organization_id
      left join private.execution_plan_contexts context on context.plan_id = plan.id
      where plan.organization_id = p_organization_id
      order by plan.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) listed
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_execution_plans(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.list_execution_plans(uuid, integer) to service_role;

drop function if exists private.execution_terminal_outcome(text, text, jsonb);
