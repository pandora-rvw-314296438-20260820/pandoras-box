-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_accept_fxpass_product_intake(
  p_source_submission_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_org_id uuid;
  v_requester_id uuid;
  v_run_id uuid;
  v_existing_run_id uuid;
  v_idempotency_key text := 'fxpass-product-discovery:' || p_source_submission_id::text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload';
  end if;

  select id into v_org_id
  from public.organizations
  where slug = 'mcpmaster-staging'
  limit 1;

  if v_org_id is null then
    raise exception 'projectos_organization_missing';
  end if;

  select user_id into v_requester_id
  from public.memberships
  where organization_id = v_org_id
    and role = 'owner'
    and status = 'active'
  order by created_at asc
  limit 1;

  if v_requester_id is null then
    raise exception 'projectos_owner_missing';
  end if;

  select workflow_run_id into v_existing_run_id
  from private.product_intake_payloads
  where source_system = 'fxpass'
    and source_submission_id = p_source_submission_id;

  if v_existing_run_id is not null then
    return jsonb_build_object('accepted', true, 'run_id', v_existing_run_id, 'duplicate', true);
  end if;

  select id into v_existing_run_id
  from public.workflow_runs
  where organization_id = v_org_id
    and idempotency_key = v_idempotency_key
  limit 1;

  if v_existing_run_id is not null then
    insert into private.product_intake_payloads(
      source_system, source_submission_id, organization_id, requester_id, workflow_run_id, payload
    ) values (
      'fxpass', p_source_submission_id, v_org_id, v_requester_id, v_existing_run_id, p_payload
    ) on conflict (source_system, source_submission_id)
      do update set workflow_run_id = excluded.workflow_run_id, payload = excluded.payload;
    return jsonb_build_object('accepted', true, 'run_id', v_existing_run_id, 'duplicate', true);
  end if;

  insert into public.workflow_runs(
    organization_id,
    workflow_key,
    workflow_version,
    status,
    requester_id,
    risk_ceiling,
    input_redacted,
    idempotency_key,
    budget_cents,
    started_at
  ) values (
    v_org_id,
    'fxpass.product-discovery-to-execution-plan',
    '1.0.0',
    'planning',
    v_requester_id,
    'R2',
    jsonb_build_object(
      'source', 'fxpass',
      'submission_id', p_source_submission_id,
      'product', 'FXPass',
      'summary', coalesce(p_payload #> '{analysis,executive_summary}', '"Product direction submitted for reconciliation"'::jsonb),
      'requires_owner_action', false
    ),
    v_idempotency_key,
    0,
    timezone('utc', now())
  ) returning id into v_run_id;

  insert into private.product_intake_payloads(
    source_system, source_submission_id, organization_id, requester_id, workflow_run_id, payload
  ) values (
    'fxpass', p_source_submission_id, v_org_id, v_requester_id, v_run_id, p_payload
  );

  insert into public.workflow_steps(
    organization_id, run_id, step_key, sequence, tool_name, status, risk, approval_required, idempotency_key, input_redacted, result_redacted, started_at, completed_at
  ) values
  (
    v_org_id, v_run_id, 'intake.capture', 1, 'projectos.product_intake', 'succeeded', 'R0', false,
    v_idempotency_key || ':capture',
    jsonb_build_object('source', 'fxpass', 'submission_id', p_source_submission_id),
    jsonb_build_object('captured', true, 'analysis_supplied', true, 'plan_supplied', true),
    timezone('utc', now()), timezone('utc', now())
  ),
  (
    v_org_id, v_run_id, 'product.plan.reconcile', 2, 'projectos.plan_reconciler', 'pending', 'R1', false,
    v_idempotency_key || ':reconcile',
    jsonb_build_object('repository', 'mbanatao/fong', 'canonical_plan', 'CANONICAL_MASTER_PLAN.md'), null, null, null
  ),
  (
    v_org_id, v_run_id, 'roadmap.decompose', 3, 'projectos.task_planner', 'pending', 'R1', false,
    v_idempotency_key || ':decompose',
    jsonb_build_object('dependency_aware', true, 'preserve_current_state', true), null, null, null
  ),
  (
    v_org_id, v_run_id, 'independent.review', 4, 'projectos.review_router', 'pending', 'R1', false,
    v_idempotency_key || ':review',
    jsonb_build_object('builder_must_not_self_approve', true, 'exact_version_required', true), null, null, null
  ),
  (
    v_org_id, v_run_id, 'execution.queue', 5, 'projectos.execution_router', 'pending', 'R2', true,
    v_idempotency_key || ':queue',
    jsonb_build_object('target_repository', 'mbanatao/fong', 'production_release_not_authorized', true), null, null, null
  );

  return jsonb_build_object('accepted', true, 'run_id', v_run_id, 'duplicate', false, 'status', 'planning');
end;
$$;

revoke all on function public.projectos_accept_fxpass_product_intake(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.projectos_accept_fxpass_product_intake(uuid, jsonb) to service_role;
