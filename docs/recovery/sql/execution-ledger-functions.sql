-- Read-only recovery of the active MCPMaster execution-ledger function definitions.
-- Supabase project: jcyqixttuebxqqfkjonq
-- Recovered: 2026-08-12
-- This evidence file is not an automatically applied migration.

-- approve_execution_plan
CREATE OR REPLACE FUNCTION public.approve_execution_plan(p_organization_id uuid, p_plan_id uuid, p_approved_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  plan private.execution_plans%rowtype;
  intake public.pandora_intake_requests%rowtype;
  project public.pandora_projects%rowtype;
begin
  perform private.assert_control_service_role();

  select * into plan
  from private.execution_plans
  where id = p_plan_id and organization_id = p_organization_id
  for update;

  if plan.id is null then
    raise exception 'execution plan not found' using errcode = 'P0002';
  end if;
  if plan.intake_id is null then
    raise exception 'mandatory pandora intake missing' using errcode = '55000';
  end if;

  select * into intake
  from public.pandora_intake_requests
  where id = plan.intake_id and organization_id = p_organization_id
  for update;

  if intake.id is null then
    raise exception 'pandora intake not found' using errcode = 'P0002';
  end if;
  if intake.status not in ('accepted', 'analyzing', 'planned', 'executing') then
    raise exception 'pandora intake is not approvable from status %', intake.status using errcode = '55000';
  end if;

  select * into project
  from public.pandora_projects
  where id = intake.project_id and organization_id = p_organization_id;

  if plan.expires_at <= now() and plan.status in ('pending_approval', 'approved') then
    update private.execution_plans
    set status = 'expired', updated_at = now()
    where id = plan.id
    returning * into plan;

    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id, 'plan_expired', plan.status,
      plan.tool, plan.risk, plan.payload_hash,
      jsonb_build_object('intakeId', intake.id, 'projectKey', project.project_key)
    );
    return jsonb_build_object(
      'planId', plan.id,
      'requestId', plan.request_id,
      'status', plan.status,
      'expiresAt', plan.expires_at,
      'intakeId', intake.id,
      'projectId', project.id,
      'projectKey', project.project_key,
      'intakeStatus', intake.status
    );
  end if;

  if plan.risk = 'read' or plan.status = 'approved' then
    return jsonb_build_object(
      'planId', plan.id,
      'requestId', plan.request_id,
      'status', plan.status,
      'approvedAt', plan.approved_at,
      'expiresAt', plan.expires_at,
      'intakeId', intake.id,
      'projectId', project.id,
      'projectKey', project.project_key,
      'intakeStatus', intake.status
    );
  end if;

  if plan.status <> 'pending_approval' then
    raise exception 'execution plan cannot be approved from status %', plan.status using errcode = '55000';
  end if;

  update private.execution_plans
  set status = 'approved',
      approved_at = now(),
      approved_by = left(coalesce(p_approved_by, 'admin'), 200),
      updated_at = now()
  where id = plan.id
  returning * into plan;

  perform private.append_execution_audit(
    p_organization_id, plan.id, plan.request_id, 'plan_approved', plan.status,
    plan.tool, plan.risk, plan.payload_hash,
    jsonb_build_object(
      'approvedBy', plan.approved_by,
      'intakeId', intake.id,
      'projectKey', project.project_key
    )
  );

  return jsonb_build_object(
    'planId', plan.id,
    'requestId', plan.request_id,
    'status', plan.status,
    'approvedAt', plan.approved_at,
    'expiresAt', plan.expires_at,
    'intakeId', intake.id,
    'projectId', project.id,
    'projectKey', project.project_key,
    'intakeStatus', intake.status
  );
end;
$function$;
-- claim_execution_plan
CREATE OR REPLACE FUNCTION public.claim_execution_plan(p_organization_id uuid, p_plan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  plan private.execution_plans%rowtype;
  intake public.pandora_intake_requests%rowtype;
  project public.pandora_projects%rowtype;
begin
  perform private.assert_control_service_role();

  select * into plan
  from private.execution_plans
  where id = p_plan_id and organization_id = p_organization_id
  for update;

  if plan.id is null then
    raise exception 'execution plan not found' using errcode = 'P0002';
  end if;
  if plan.intake_id is null then
    raise exception 'mandatory pandora intake missing' using errcode = '55000';
  end if;

  select * into intake
  from public.pandora_intake_requests
  where id = plan.intake_id and organization_id = p_organization_id
  for update;

  if intake.id is null then
    raise exception 'pandora intake not found' using errcode = 'P0002';
  end if;
  if intake.status not in ('accepted', 'analyzing', 'planned', 'executing') then
    raise exception 'pandora intake is not claimable from status %', intake.status using errcode = '55000';
  end if;

  select * into project
  from public.pandora_projects
  where id = intake.project_id and organization_id = p_organization_id;

  if plan.expires_at <= now() and plan.status in ('pending_approval', 'approved') then
    raise exception 'execution plan expired' using errcode = '55000';
  end if;
  if plan.status <> 'approved' then
    raise exception 'execution plan is not claimable from status %', plan.status using errcode = '55000';
  end if;

  update private.execution_plans
  set status = 'executing', claimed_at = now(), updated_at = now()
  where id = plan.id
  returning * into plan;

  update public.pandora_intake_requests
  set status = 'executing',
      analysis = coalesce(analysis, '{}'::jsonb) || jsonb_build_object(
        'activeExecutionPlanId', plan.id,
        'activeExecutionRequestId', plan.request_id
      ),
      updated_at = now()
  where id = intake.id
  returning * into intake;

  perform private.append_execution_audit(
    p_organization_id, plan.id, plan.request_id, 'plan_claimed', plan.status,
    plan.tool, plan.risk, plan.payload_hash,
    jsonb_build_object(
      'intakeId', intake.id,
      'projectId', project.id,
      'projectKey', project.project_key,
      'intakeStatus', intake.status
    )
  );

  return jsonb_build_object(
    'planId', plan.id,
    'requestId', plan.request_id,
    'tool', plan.tool,
    'risk', plan.risk,
    'args', plan.args,
    'payloadHash', plan.payload_hash,
    'status', plan.status,
    'expiresAt', plan.expires_at,
    'claimedAt', plan.claimed_at,
    'intakeId', intake.id,
    'projectId', project.id,
    'projectKey', project.project_key,
    'intakeStatus', intake.status
  );
end;
$function$;

-- create_execution_plan
CREATE OR REPLACE FUNCTION public.create_execution_plan(p_organization_id uuid, p_request_id uuid, p_intake_id uuid, p_tool text, p_risk text, p_args jsonb, p_payload_hash text, p_expires_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  created private.execution_plans%rowtype;
  intake public.pandora_intake_requests%rowtype;
  project public.pandora_projects%rowtype;
  initial_status text;
begin
  perform private.assert_control_service_role();

  if p_risk not in ('read', 'write', 'destructive') then
    raise exception 'invalid risk' using errcode = '22023';
  end if;
  if p_payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid payload hash' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_args, '{}'::jsonb)) <> 'object' then
    raise exception 'args must be an object' using errcode = '22023';
  end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '30 minutes' then
    raise exception 'invalid plan expiry' using errcode = '22023';
  end if;

  select * into intake
  from public.pandora_intake_requests
  where id = p_intake_id
    and organization_id = p_organization_id
  for update;

  if intake.id is null then
    raise exception 'pandora intake not found' using errcode = 'P0002';
  end if;
  if intake.status not in ('accepted', 'analyzing', 'planned', 'executing') then
    raise exception 'pandora intake is not executable from status %', intake.status using errcode = '55000';
  end if;

  select * into project
  from public.pandora_projects
  where id = intake.project_id
    and organization_id = p_organization_id;

  if project.id is null then
    raise exception 'pandora project not found' using errcode = 'P0002';
  end if;

  initial_status := case when p_risk = 'read' then 'approved' else 'pending_approval' end;

  insert into private.execution_plans (
    organization_id,
    request_id,
    intake_id,
    tool,
    risk,
    args,
    payload_hash,
    status,
    expires_at,
    approved_at,
    approved_by
  )
  values (
    p_organization_id,
    p_request_id,
    intake.id,
    p_tool,
    p_risk,
    coalesce(p_args, '{}'::jsonb),
    p_payload_hash,
    initial_status,
    p_expires_at,
    case when p_risk = 'read' then now() else null end,
    case when p_risk = 'read' then 'system:auto-read' else null end
  )
  returning * into created;

  update public.pandora_intake_requests
  set status = case when status in ('accepted', 'analyzing') then 'planned' else status end,
      analysis = coalesce(analysis, '{}'::jsonb) || jsonb_build_object(
        'latestExecutionPlanId', created.id,
        'latestExecutionRequestId', created.request_id,
        'latestExecutionTool', created.tool
      ),
      updated_at = now()
  where id = intake.id
  returning * into intake;

  perform private.append_execution_audit(
    p_organization_id,
    created.id,
    created.request_id,
    'plan_created',
    created.status,
    created.tool,
    created.risk,
    created.payload_hash,
    jsonb_build_object(
      'expiresAt', created.expires_at,
      'intakeId', intake.id,
      'projectId', project.id,
      'projectKey', project.project_key,
      'intakeStatus', intake.status
    )
  );

  return jsonb_build_object(
    'planId', created.id,
    'requestId', created.request_id,
    'tool', created.tool,
    'risk', created.risk,
    'payloadHash', created.payload_hash,
    'status', created.status,
    'expiresAt', created.expires_at,
    'createdAt', created.created_at,
    'intakeId', intake.id,
    'projectId', project.id,
    'projectKey', project.project_key,
    'intakeStatus', intake.status
  );
end;
$function$;

-- finish_execution_plan
CREATE OR REPLACE FUNCTION public.finish_execution_plan(p_organization_id uuid, p_plan_id uuid, p_status text, p_duration_ms integer, p_error text, p_result_summary jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  plan private.execution_plans%rowtype;
  intake public.pandora_intake_requests%rowtype;
  project public.pandora_projects%rowtype;
  final_status text;
  next_intake_status text;
begin
  perform private.assert_control_service_role();

  if p_status not in ('completed', 'failed') then
    raise exception 'invalid final status' using errcode = '22023';
  end if;

  select * into plan
  from private.execution_plans
  where id = p_plan_id and organization_id = p_organization_id
  for update;

  if plan.id is null then
    raise exception 'execution plan not found' using errcode = 'P0002';
  end if;
  if plan.intake_id is null then
    raise exception 'mandatory pandora intake missing' using errcode = '55000';
  end if;
  if plan.status <> 'executing' then
    raise exception 'execution plan cannot finish from status %', plan.status using errcode = '55000';
  end if;

  select * into intake
  from public.pandora_intake_requests
  where id = plan.intake_id and organization_id = p_organization_id
  for update;

  if intake.id is null then
    raise exception 'pandora intake not found' using errcode = 'P0002';
  end if;

  select * into project
  from public.pandora_projects
  where id = intake.project_id and organization_id = p_organization_id;

  final_status := p_status;

  update private.execution_plans
  set status = final_status,
      completed_at = now(),
      duration_ms = greatest(coalesce(p_duration_ms, 0), 0),
      error = case when final_status = 'failed' then left(coalesce(p_error, 'execution failed'), 2000) else null end,
      result_summary = case when final_status = 'completed' then coalesce(p_result_summary, '{}'::jsonb) else null end,
      updated_at = now()
  where id = plan.id
  returning * into plan;

  if final_status = 'failed' or exists (
    select 1 from private.execution_plans sibling
    where sibling.intake_id = intake.id and sibling.status = 'failed'
  ) then
    next_intake_status := 'blocked';
  elsif exists (
    select 1 from private.execution_plans sibling
    where sibling.intake_id = intake.id and sibling.status = 'executing'
  ) then
    next_intake_status := 'executing';
  elsif exists (
    select 1 from private.execution_plans sibling
    where sibling.intake_id = intake.id and sibling.status in ('pending_approval', 'approved')
  ) then
    next_intake_status := 'planned';
  else
    next_intake_status := 'completed';
  end if;

  update public.pandora_intake_requests
  set status = case
        when status in ('blocked', 'rejected') then status
        else next_intake_status
      end,
      analysis = coalesce(analysis, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
        'latestExecutionPlanId', plan.id,
        'latestExecutionRequestId', plan.request_id,
        'latestExecutionStatus', plan.status,
        'latestExecutionCompletedAt', plan.completed_at,
        'latestExecutionDurationMs', plan.duration_ms
      )),
      updated_at = now()
  where id = intake.id
  returning * into intake;

  perform private.append_execution_audit(
    p_organization_id, plan.id, plan.request_id, 'plan_finished', plan.status,
    plan.tool, plan.risk, plan.payload_hash,
    jsonb_strip_nulls(jsonb_build_object(
      'durationMs', plan.duration_ms,
      'error', plan.error,
      'resultSummary', plan.result_summary,
      'intakeId', intake.id,
      'projectId', project.id,
      'projectKey', project.project_key,
      'intakeStatus', intake.status
    ))
  );

  return jsonb_build_object(
    'planId', plan.id,
    'requestId', plan.request_id,
    'status', plan.status,
    'completedAt', plan.completed_at,
    'durationMs', plan.duration_ms,
    'intakeId', intake.id,
    'projectId', project.id,
    'projectKey', project.project_key,
    'intakeStatus', intake.status
  );
end;
$function$;

-- list_execution_audit
CREATE OR REPLACE FUNCTION public.list_execution_audit(p_organization_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.assert_control_service_role();

  return coalesce((
    select jsonb_agg(event_row order by (event_row ->> 'sequence')::bigint desc)
    from (
      select jsonb_build_object(
        'sequence', event.sequence,
        'planId', event.plan_id,
        'requestId', event.request_id,
        'eventType', event.event_type,
        'status', event.status,
        'tool', event.tool,
        'risk', event.risk,
        'payloadHash', event.payload_hash,
        'details', event.details,
        'previousHash', event.previous_hash,
        'eventHash', event.event_hash,
        'occurredAt', event.occurred_at
      ) as event_row
      from private.execution_audit_events event
      where event.organization_id = p_organization_id
      order by event.sequence desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) listed
  ), '[]'::jsonb);
end;
$function$;

-- list_execution_plans
CREATE OR REPLACE FUNCTION public.list_execution_plans(p_organization_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      left join public.pandora_intake_requests intake
        on intake.id = plan.intake_id and intake.organization_id = plan.organization_id
      left join public.pandora_projects project
        on project.id = intake.project_id and project.organization_id = plan.organization_id
      left join private.execution_plan_contexts context on context.plan_id = plan.id
      where plan.organization_id = p_organization_id
      order by plan.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) listed
  ), '[]'::jsonb);
end;
$function$;

-- verify_execution_audit_chain
CREATE OR REPLACE FUNCTION public.verify_execution_audit_chain(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  event private.execution_audit_events%rowtype;
  expected_previous text := repeat('0', 64);
  expected_sequence bigint := 1;
  canonical text;
  expected_hash text;
begin
  perform private.assert_control_service_role();

  for event in
    select *
    from private.execution_audit_events
    where organization_id = p_organization_id
    order by sequence asc
  loop
    if event.sequence <> expected_sequence or event.previous_hash <> expected_previous then
      return jsonb_build_object(
        'valid', false,
        'failedSequence', event.sequence,
        'reason', 'sequence_or_previous_hash_mismatch'
      );
    end if;

    canonical := concat_ws(
      '|',
      event.organization_id::text,
      event.sequence::text,
      coalesce(event.plan_id::text, ''),
      coalesce(event.request_id::text, ''),
      event.event_type,
      event.status,
      coalesce(event.tool, ''),
      coalesce(event.risk, ''),
      coalesce(event.payload_hash, ''),
      event.details::text,
      event.occurred_at::text,
      event.previous_hash
    );
    expected_hash := encode(extensions.digest(convert_to(canonical, 'UTF8'), 'sha256'), 'hex');

    if expected_hash <> event.event_hash then
      return jsonb_build_object(
        'valid', false,
        'failedSequence', event.sequence,
        'reason', 'event_hash_mismatch'
      );
    end if;

    expected_previous := event.event_hash;
    expected_sequence := expected_sequence + 1;
  end loop;

  return jsonb_build_object(
    'valid', true,
    'eventCount', expected_sequence - 1,
    'lastHash', expected_previous
  );
end;
$function$;
