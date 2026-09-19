-- Expose only a bounded, allowlisted terminal outcome for durable plan readback.
-- Raw provider errors and result payloads remain private.

create or replace function private.execution_terminal_outcome(
  p_status text,
  p_error text,
  p_result_summary jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  source jsonb := '{}'::jsonb;
  classification text;
  provider_outcome text;
  mutation_state text;
  downstream_outcome text;
  safe_error_code text;
  retry_contract text;
  retryable boolean := false;
  reconciliation_required boolean := false;
  provider_idempotency_supported boolean := false;
  payload_hash text;
  idempotency_identity_hash text;
begin
  if p_status = 'completed' then
    source := coalesce(p_result_summary, '{}'::jsonb);
    classification := 'succeeded';
    provider_outcome := 'succeeded';
  elsif p_status = 'failed' then
    begin
      source := coalesce(nullif(p_error, ''), '{}')::jsonb;
      if jsonb_typeof(source) <> 'object' then
        source := '{}'::jsonb;
      end if;
    exception when others then
      source := '{}'::jsonb;
    end;

    classification := case source ->> 'terminalClassification'
      when 'reconciliation_required' then 'reconciliation_required'
      when 'failed_without_side_effect' then 'failed_without_side_effect'
      else 'failed_unknown'
    end;

    provider_outcome := case source ->> 'providerOutcome'
      when 'not_executed' then 'not_executed'
      when 'failed_before_side_effects' then 'failed_before_side_effects'
      when 'ambiguous' then 'ambiguous'
      when 'succeeded' then 'succeeded'
      else 'ambiguous'
    end;

    if classification = 'failed_without_side_effect'
       and provider_outcome not in ('not_executed', 'failed_before_side_effects') then
      classification := 'failed_unknown';
      provider_outcome := 'ambiguous';
    elsif classification = 'reconciliation_required'
       and provider_outcome not in ('ambiguous', 'succeeded') then
      classification := 'failed_unknown';
      provider_outcome := 'ambiguous';
    end if;
  else
    return null;
  end if;

  provider_idempotency_supported := case
    when jsonb_typeof(source -> 'providerIdempotencySupported') = 'boolean'
      then (source ->> 'providerIdempotencySupported')::boolean
    else false
  end;

  payload_hash := case
    when source ->> 'payloadHash' ~ '^[0-9a-f]{64}$'
      then source ->> 'payloadHash'
    else null
  end;
  idempotency_identity_hash := case
    when source ->> 'idempotencyIdentityHash' ~ '^[0-9a-f]{64}$'
      then source ->> 'idempotencyIdentityHash'
    else null
  end;

  if classification = 'succeeded' then
    mutation_state := 'PROVIDER_SUCCEEDED';
    downstream_outcome := 'succeeded';
    safe_error_code := null;
    retry_contract := 'do_not_repeat_provider_mutation';
    retryable := false;
    reconciliation_required := false;
  elsif classification = 'reconciliation_required' then
    mutation_state := case provider_outcome
      when 'succeeded' then 'PROVIDER_SUCCEEDED_LOCAL_FINALIZATION_FAILED'
      else 'OUTCOME_AMBIGUOUS_AFTER_DISPATCH'
    end;
    downstream_outcome := case
      when source ->> 'downstreamProcessingOutcome' ~ '^[a-z0-9][a-z0-9._:-]{0,79}$'
        then source ->> 'downstreamProcessingOutcome'
      else 'local_processing_failed'
    end;
    safe_error_code := case
      when source ->> 'safeErrorCode' ~ '^[a-z0-9][a-z0-9._:-]{0,79}$'
        then source ->> 'safeErrorCode'
      else 'provider_execution_outcome_ambiguous'
    end;
    if provider_outcome = 'succeeded' then
      retry_contract := 'do_not_repeat_provider_mutation';
    elsif provider_idempotency_supported
       and idempotency_identity_hash is not null
       and source ->> 'retryContract' = 'same_immutable_idempotency_identity_only' then
      retry_contract := 'same_immutable_idempotency_identity_only';
      retryable := true;
    else
      retry_contract := 'reconcile_before_retry';
    end if;
    reconciliation_required := true;
  elsif classification = 'failed_without_side_effect' then
    mutation_state := case provider_outcome
      when 'not_executed' then 'DEFINITELY_NOT_DISPATCHED'
      else 'PROVIDER_REJECTED_WITH_NO_SIDE_EFFECT'
    end;
    downstream_outcome := 'not_started';
    safe_error_code := case
      when source ->> 'safeErrorCode' ~ '^[a-z0-9][a-z0-9._:-]{0,79}$'
        then source ->> 'safeErrorCode'
      else 'provider_execution_failed'
    end;
    retry_contract := case source ->> 'retryContract'
      when 'normal_retry_policy' then 'normal_retry_policy'
      else 'not_retryable'
    end;
    retryable := case
      when retry_contract = 'normal_retry_policy'
       and jsonb_typeof(source -> 'retryable') = 'boolean'
        then (source ->> 'retryable')::boolean
      else false
    end;
    reconciliation_required := false;
  else
    mutation_state := 'OUTCOME_UNKNOWN';
    downstream_outcome := 'durable_failure_unknown';
    safe_error_code := 'execution_failed_unknown';
    retry_contract := 'reconcile_before_retry';
    retryable := false;
    reconciliation_required := true;
    provider_idempotency_supported := false;
    idempotency_identity_hash := null;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'schemaVersion', '1.0.0',
    'terminalClassification', classification,
    'providerOutcome', provider_outcome,
    'mutationState', mutation_state,
    'downstreamProcessingOutcome', downstream_outcome,
    'safeErrorCode', safe_error_code,
    'retryable', retryable,
    'automaticRetryAllowed', false,
    'retryContract', retry_contract,
    'reconciliationRequired', reconciliation_required,
    'providerIdempotencySupported', provider_idempotency_supported,
    'payloadHash', payload_hash,
    'idempotencyIdentityHash', idempotency_identity_hash,
    'evidencePolicy', 'privacy_safe_summary_only_v1'
  ));
end;
$$;

revoke all on function private.execution_terminal_outcome(text, text, jsonb)
  from public, anon, authenticated, service_role;

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
        'terminalOutcome', private.execution_terminal_outcome(
          plan.status,
          plan.error,
          plan.result_summary
        ),
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
