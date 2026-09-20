-- Phase 0: complete one allowlisted owner read without weakening ProjectOS mutation gates.
create or replace function public.projectos_complete_owner_read_intake(
  p_organization_id uuid,
  p_intake_id uuid,
  p_operation text,
  p_result jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_intake public.projectos_intake_requests%rowtype;
  v_safe_result jsonb;
  v_fingerprint text;
  v_event_id bigint;
begin
  perform private.assert_control_service_role();

  if p_operation <> 'connected_services_health' then
    raise exception 'unsupported_owner_read_operation' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_result, '{}'::jsonb)) <> 'object' then
    raise exception 'owner_read_result_must_be_object' using errcode = '22023';
  end if;

  select * into v_intake
  from public.projectos_intake_requests
  where id = p_intake_id
    and organization_id = p_organization_id
  for update;

  if v_intake.id is null then
    raise exception 'projectos intake not found' using errcode = 'P0002';
  end if;
  if v_intake.source <> 'api' or v_intake.request_type <> 'work' then
    raise exception 'owner_read_intake_scope_mismatch' using errcode = '55000';
  end if;

  if v_intake.status = 'completed'
     and coalesce(v_intake.analysis->>'ownerReadOperation', '') = p_operation then
    return jsonb_build_object(
      'intakeId', v_intake.id,
      'status', v_intake.status,
      'operation', p_operation,
      'auditEventId', v_intake.analysis->'ownerReadAuditEventId',
      'resultFingerprint', v_intake.analysis->>'ownerReadResultFingerprint',
      'idempotentReplay', true
    );
  end if;

  if v_intake.status <> 'accepted' then
    raise exception 'owner_read_intake_not_accepted' using errcode = '55000';
  end if;

  v_safe_result := jsonb_strip_nulls(jsonb_build_object(
    'summary', case
      when nullif(trim(coalesce(p_result->>'summary', '')), '') is null then null
      else left(trim(p_result->>'summary'), 500)
    end,
    'providerCount', p_result->'providerCount',
    'needsAttention', p_result->'needsAttention',
    'notChecked', p_result->'notChecked',
    'safetyState', p_result->'safetyState'
  ));
  v_fingerprint := encode(
    extensions.digest(convert_to(v_safe_result::text, 'UTF8'), 'sha256'),
    'hex'
  );

  v_event_id := public.record_audit_event(
    p_organization_id,
    'projectos.owner_read_completed',
    'system'::public.audit_actor_type,
    v_safe_result || jsonb_build_object('operation', p_operation),
    null,
    null,
    v_intake.requester_id
  );

  update public.projectos_intake_requests
  set status = 'completed',
      analysis = coalesce(analysis, '{}'::jsonb) || jsonb_build_object(
        'nextAction', 'owner_read_completed',
        'ownerReadOperation', p_operation,
        'ownerReadResult', v_safe_result,
        'ownerReadResultFingerprint', v_fingerprint,
        'ownerReadAuditEventId', v_event_id,
        'ownerReadCompletedAt', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      updated_at = now()
  where id = v_intake.id
    and organization_id = p_organization_id
  returning * into v_intake;

  return jsonb_build_object(
    'intakeId', v_intake.id,
    'status', v_intake.status,
    'operation', p_operation,
    'auditEventId', v_event_id,
    'resultFingerprint', v_fingerprint,
    'idempotentReplay', false
  );
end;
$function$;

revoke all on function public.projectos_complete_owner_read_intake(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.projectos_complete_owner_read_intake(uuid, uuid, text, jsonb) to service_role;
