
create or replace function public.pandora_create_execution_plan(
  p_organization_id uuid,
  p_request_id uuid,
  p_tool text,
  p_risk text,
  p_args jsonb,
  p_payload_hash text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  created private.execution_plans%rowtype;
  initial_status text;
begin
  perform private.assert_control_service_role();
  if p_risk not in ('read','write','destructive') then
    raise exception 'invalid risk' using errcode='22023';
  end if;
  if p_payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid payload hash' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_args,'{}'::jsonb)) <> 'object' then
    raise exception 'args must be an object' using errcode='22023';
  end if;
  if p_expires_at <= now() or p_expires_at > now()+interval '30 minutes' then
    raise exception 'invalid plan expiry' using errcode='22023';
  end if;

  initial_status := case when p_risk='read' then 'approved' else 'pending_approval' end;

  insert into private.execution_plans(
    organization_id,request_id,intake_id,tool,risk,args,payload_hash,status,
    expires_at,approved_at,approved_by
  ) values(
    p_organization_id,p_request_id,null,p_tool,p_risk,coalesce(p_args,'{}'::jsonb),
    p_payload_hash,initial_status,p_expires_at,
    case when p_risk='read' then now() else null end,
    case when p_risk='read' then 'system:auto-read' else null end
  )
  returning * into created;

  perform private.append_execution_audit(
    p_organization_id,created.id,created.request_id,'plan_created',created.status,
    created.tool,created.risk,created.payload_hash,
    jsonb_build_object(
      'authority','pandora-native-execution-v1',
      'intakeRequired',false
    )
  );

  return jsonb_build_object(
    'planId',created.id,'requestId',created.request_id,'tool',created.tool,
    'risk',created.risk,'payloadHash',created.payload_hash,'status',created.status,
    'expiresAt',created.expires_at,'createdAt',created.created_at
  );
end;
$fn$;

create or replace function public.pandora_approve_execution_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_approved_by text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  plan private.execution_plans%rowtype;
begin
  perform private.assert_control_service_role();
  select * into plan
  from private.execution_plans
  where id=p_plan_id and organization_id=p_organization_id
  for update;
  if plan.id is null then
    raise exception 'execution plan not found' using errcode='P0002';
  end if;
  if plan.intake_id is not null then
    return public.approve_execution_plan(p_organization_id,p_plan_id,p_approved_by);
  end if;
  if plan.expires_at <= now() and plan.status in ('pending_approval','approved') then
    update private.execution_plans
      set status='expired',updated_at=now()
      where id=plan.id returning * into plan;
    perform private.append_execution_audit(
      p_organization_id,plan.id,plan.request_id,'plan_expired',plan.status,
      plan.tool,plan.risk,plan.payload_hash,
      jsonb_build_object('authority','pandora-native-execution-v1')
    );
    return jsonb_build_object(
      'planId',plan.id,'requestId',plan.request_id,'status',plan.status,
      'expiresAt',plan.expires_at
    );
  end if;
  if plan.risk='read' or plan.status='approved' then
    return jsonb_build_object(
      'planId',plan.id,'requestId',plan.request_id,'status',plan.status,
      'approvedAt',plan.approved_at,'expiresAt',plan.expires_at
    );
  end if;
  if plan.status<>'pending_approval' then
    raise exception 'execution plan cannot be approved from status %',plan.status using errcode='55000';
  end if;
  update private.execution_plans
    set status='approved',approved_at=now(),
        approved_by=left(coalesce(p_approved_by,'admin'),200),updated_at=now()
    where id=plan.id returning * into plan;
  perform private.append_execution_audit(
    p_organization_id,plan.id,plan.request_id,'plan_approved',plan.status,
    plan.tool,plan.risk,plan.payload_hash,
    jsonb_build_object('approvedBy',plan.approved_by,'authority','pandora-native-execution-v1')
  );
  return jsonb_build_object(
    'planId',plan.id,'requestId',plan.request_id,'status',plan.status,
    'approvedAt',plan.approved_at,'expiresAt',plan.expires_at
  );
end;
$fn$;

create or replace function public.pandora_claim_execution_plan(
  p_organization_id uuid,
  p_plan_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  plan private.execution_plans%rowtype;
begin
  perform private.assert_control_service_role();
  select * into plan
  from private.execution_plans
  where id=p_plan_id and organization_id=p_organization_id
  for update;
  if plan.id is null then
    raise exception 'execution plan not found' using errcode='P0002';
  end if;
  if plan.intake_id is not null then
    return public.claim_execution_plan(p_organization_id,p_plan_id);
  end if;
  if plan.expires_at <= now() and plan.status in ('pending_approval','approved') then
    raise exception 'execution plan expired' using errcode='55000';
  end if;
  if plan.status<>'approved' then
    raise exception 'execution plan is not claimable from status %',plan.status using errcode='55000';
  end if;
  update private.execution_plans
    set status='executing',claimed_at=now(),updated_at=now()
    where id=plan.id returning * into plan;
  perform private.append_execution_audit(
    p_organization_id,plan.id,plan.request_id,'plan_claimed',plan.status,
    plan.tool,plan.risk,plan.payload_hash,
    jsonb_build_object('authority','pandora-native-execution-v1')
  );
  return jsonb_build_object(
    'planId',plan.id,'requestId',plan.request_id,'tool',plan.tool,'risk',plan.risk,
    'args',plan.args,'payloadHash',plan.payload_hash,'status',plan.status,
    'expiresAt',plan.expires_at,'claimedAt',plan.claimed_at
  );
end;
$fn$;

create or replace function public.pandora_finish_execution_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_status text,
  p_duration_ms integer,
  p_error text,
  p_result_summary jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  plan private.execution_plans%rowtype;
begin
  perform private.assert_control_service_role();
  if p_status not in ('completed','failed') then
    raise exception 'invalid final status' using errcode='22023';
  end if;
  select * into plan
  from private.execution_plans
  where id=p_plan_id and organization_id=p_organization_id
  for update;
  if plan.id is null then
    raise exception 'execution plan not found' using errcode='P0002';
  end if;
  if plan.intake_id is not null then
    return public.finish_execution_plan(
      p_organization_id,p_plan_id,p_status,p_duration_ms,p_error,p_result_summary
    );
  end if;
  if plan.status<>'executing' then
    raise exception 'execution plan cannot finish from status %',plan.status using errcode='55000';
  end if;
  update private.execution_plans
    set status=p_status,completed_at=now(),
        duration_ms=greatest(coalesce(p_duration_ms,0),0),
        error=case when p_status='failed' then left(coalesce(p_error,'execution failed'),2000) else null end,
        result_summary=case when p_status='completed' then coalesce(p_result_summary,'{}'::jsonb) else null end,
        updated_at=now()
    where id=plan.id returning * into plan;
  perform private.append_execution_audit(
    p_organization_id,plan.id,plan.request_id,'plan_finished',plan.status,
    plan.tool,plan.risk,plan.payload_hash,
    jsonb_strip_nulls(jsonb_build_object(
      'durationMs',plan.duration_ms,'error',plan.error,'resultSummary',plan.result_summary,
      'authority','pandora-native-execution-v1'
    ))
  );
  return jsonb_build_object(
    'planId',plan.id,'requestId',plan.request_id,'status',plan.status,
    'completedAt',plan.completed_at,'durationMs',plan.duration_ms
  );
end;
$fn$;

revoke all on function public.pandora_create_execution_plan(uuid,uuid,text,text,jsonb,text,timestamptz) from public,anon,authenticated;
revoke all on function public.pandora_approve_execution_plan(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.pandora_claim_execution_plan(uuid,uuid) from public,anon,authenticated;
revoke all on function public.pandora_finish_execution_plan(uuid,uuid,text,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_create_execution_plan(uuid,uuid,text,text,jsonb,text,timestamptz) to service_role;
grant execute on function public.pandora_approve_execution_plan(uuid,uuid,text) to service_role;
grant execute on function public.pandora_claim_execution_plan(uuid,uuid) to service_role;
grant execute on function public.pandora_finish_execution_plan(uuid,uuid,text,integer,text,jsonb) to service_role;

comment on function public.pandora_create_execution_plan(uuid,uuid,text,text,jsonb,text,timestamptz)
is 'Pandora-native execution plan creation with no retired ProjectOS intake dependency.';
