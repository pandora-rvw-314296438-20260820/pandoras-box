-- Generic owner decision path for consequential ProjectOS execution plans.
-- Approval records permission only; it never claims or executes the plan.

create or replace function public.decide_execution_plan_v1(
  p_organization_id uuid,
  p_plan_id uuid,
  p_decision text,
  p_decided_by text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plan private.execution_plans%rowtype;
  intake public.projectos_intake_requests%rowtype;
  project public.projectos_projects%rowtype;
  transition jsonb;
begin
  perform private.assert_control_service_role();
  p_decision := lower(trim(coalesce(p_decision, '')));
  if p_decision not in ('approve', 'deny') then
    raise exception 'invalid execution plan decision' using errcode = '22023';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = p_plan_id
  for update;

  -- Specialized worker plans retain their exact dispatch protocol.
  if plan.id is null or plan.tool = 'projectos.worker.verify' then
    return null;
  end if;

  if plan.risk = 'read' then
    raise exception 'read execution plan does not require owner approval'
      using errcode = '55000';
  end if;

  select * into intake
  from public.projectos_intake_requests
  where organization_id = p_organization_id and id = plan.intake_id
  for update;
  if intake.id is null then
    raise exception 'execution plan intake missing' using errcode = '55000';
  end if;

  select * into project
  from public.projectos_projects
  where organization_id = p_organization_id and id = intake.project_id;

  if plan.status in ('pending_approval', 'approved') and plan.expires_at <= now() then
    update private.execution_plans
    set status = 'expired', updated_at = now()
    where id = plan.id
    returning * into plan;
    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id, 'plan_expired', plan.status,
      plan.tool, plan.risk, plan.payload_hash,
      jsonb_build_object(
        'intakeId', intake.id,
        'projectId', project.id,
        'decisionAttempt', p_decision
      )
    );
    return jsonb_build_object(
      'kind', 'execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'projectId', project.id,
      'tool', plan.tool,
      'risk', plan.risk,
      'idempotentReplay', false
    );
  end if;

  if p_decision = 'deny' then
    if plan.status = 'denied' then
      return jsonb_build_object(
        'kind', 'execution_plan',
        'planId', plan.id,
        'status', plan.status,
        'intakeId', intake.id,
        'projectId', project.id,
        'tool', plan.tool,
        'risk', plan.risk,
        'idempotentReplay', true
      );
    end if;
    if plan.status not in ('pending_approval', 'approved') then
      raise exception 'execution plan cannot be denied from status %', plan.status
        using errcode = '55000';
    end if;

    update private.execution_plans
    set status = 'denied',
        completed_at = now(),
        error = 'owner denied execution',
        updated_at = now()
    where id = plan.id
    returning * into plan;

    update public.projectos_intake_requests
    set analysis = coalesce(analysis, '{}'::jsonb) || jsonb_build_object(
          'latestExecutionPlanId', plan.id,
          'latestExecutionStatus', plan.status
        ),
        updated_at = now()
    where id = intake.id and organization_id = p_organization_id;

    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id, 'plan_denied', plan.status,
      plan.tool, plan.risk, plan.payload_hash,
      jsonb_build_object(
        'intakeId', intake.id,
        'projectId', project.id,
        'decidedBy', left(coalesce(p_decided_by, 'owner'), 200)
      )
    );
    return jsonb_build_object(
      'kind', 'execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'projectId', project.id,
      'tool', plan.tool,
      'risk', plan.risk,
      'idempotentReplay', false
    );
  end if;

  if plan.status = 'approved' then
    return jsonb_build_object(
      'kind', 'execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'projectId', project.id,
      'tool', plan.tool,
      'risk', plan.risk,
      'idempotentReplay', true
    );
  end if;
  if plan.status <> 'pending_approval' then
    raise exception 'execution plan cannot be approved from status %', plan.status
      using errcode = '55000';
  end if;

  transition := public.approve_execution_plan(
    p_organization_id,
    plan.id,
    left(coalesce(p_decided_by, 'owner'), 200)
  );

  return jsonb_build_object(
    'kind', 'execution_plan',
    'planId', plan.id,
    'status', transition ->> 'status',
    'intakeId', intake.id,
    'projectId', project.id,
    'tool', plan.tool,
    'risk', plan.risk,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.decide_execution_plan_v1(
  p_organization_id uuid,
  p_plan_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_user_id uuid;
  prior_claims text;
  result_payload jsonb;
begin
  owner_user_id := private.assert_live_plan_approver(p_organization_id);
  prior_claims := coalesce(current_setting('request.jwt.claims', true), '{}');
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, ''), '{}')::jsonb
      || jsonb_build_object('role', 'service_role'))::text,
    true
  );
  result_payload := public.decide_execution_plan_v1(
    p_organization_id,
    p_plan_id,
    p_decision,
    'owner:' || owner_user_id::text
  );
  perform set_config('request.jwt.claims', prior_claims, true);
  return result_payload;
exception when others then
  perform set_config('request.jwt.claims', prior_claims, true);
  raise;
end;
$$;

revoke all on function public.decide_execution_plan_v1(uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.decide_execution_plan_v1(uuid,uuid,text,text)
  to service_role;

revoke all on function public.decide_execution_plan_v1(uuid,uuid,text)
  from public, anon;
grant execute on function public.decide_execution_plan_v1(uuid,uuid,text)
  to authenticated;
