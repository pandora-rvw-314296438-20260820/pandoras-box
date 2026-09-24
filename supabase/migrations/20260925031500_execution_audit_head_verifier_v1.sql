-- Keep routine owner-safety reads constant-time while preserving the full
-- verify_execution_audit_chain() forensic verifier for explicit deep audits.
create or replace function public.verify_execution_audit_head(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  chain private.execution_audit_chain_state%rowtype;
  head_event private.execution_audit_events%rowtype;
  previous_hash text;
  expected_previous text;
  canonical text;
  expected_hash text;
  zero_hash text := repeat('0', 64);
begin
  perform private.assert_control_service_role();

  select *
  into chain
  from private.execution_audit_chain_state
  where organization_id = p_organization_id;

  if chain.organization_id is null then
    if exists (
      select 1
      from private.execution_audit_events
      where organization_id = p_organization_id
      limit 1
    ) then
      return jsonb_build_object(
        'valid', false,
        'reason', 'missing_chain_state',
        'scope', 'head'
      );
    end if;

    return jsonb_build_object(
      'valid', true,
      'eventCount', 0,
      'lastHash', zero_hash,
      'checkedSequence', 0,
      'scope', 'head'
    );
  end if;

  if chain.last_sequence < 0 then
    return jsonb_build_object(
      'valid', false,
      'reason', 'invalid_chain_sequence',
      'scope', 'head'
    );
  end if;

  if chain.last_sequence = 0 then
    if chain.last_hash <> zero_hash then
      return jsonb_build_object(
        'valid', false,
        'reason', 'empty_chain_hash_mismatch',
        'scope', 'head'
      );
    end if;

    if exists (
      select 1
      from private.execution_audit_events
      where organization_id = p_organization_id
      limit 1
    ) then
      return jsonb_build_object(
        'valid', false,
        'reason', 'unexpected_events_for_empty_chain',
        'scope', 'head'
      );
    end if;

    return jsonb_build_object(
      'valid', true,
      'eventCount', 0,
      'lastHash', zero_hash,
      'checkedSequence', 0,
      'scope', 'head'
    );
  end if;

  select *
  into head_event
  from private.execution_audit_events
  where organization_id = p_organization_id
    and sequence = chain.last_sequence;

  if head_event.id is null then
    return jsonb_build_object(
      'valid', false,
      'failedSequence', chain.last_sequence,
      'reason', 'missing_head_event',
      'scope', 'head'
    );
  end if;

  if head_event.event_hash <> chain.last_hash then
    return jsonb_build_object(
      'valid', false,
      'failedSequence', chain.last_sequence,
      'reason', 'head_state_hash_mismatch',
      'scope', 'head'
    );
  end if;

  if chain.last_sequence = 1 then
    expected_previous := zero_hash;
  else
    select event_hash
    into previous_hash
    from private.execution_audit_events
    where organization_id = p_organization_id
      and sequence = chain.last_sequence - 1;

    if previous_hash is null then
      return jsonb_build_object(
        'valid', false,
        'failedSequence', chain.last_sequence - 1,
        'reason', 'missing_previous_event',
        'scope', 'head'
      );
    end if;
    expected_previous := previous_hash;
  end if;

  if head_event.previous_hash <> expected_previous then
    return jsonb_build_object(
      'valid', false,
      'failedSequence', chain.last_sequence,
      'reason', 'head_previous_hash_mismatch',
      'scope', 'head'
    );
  end if;

  canonical := concat_ws(
    '|',
    head_event.organization_id::text,
    head_event.sequence::text,
    coalesce(head_event.plan_id::text, ''),
    coalesce(head_event.request_id::text, ''),
    head_event.event_type,
    head_event.status,
    coalesce(head_event.tool, ''),
    coalesce(head_event.risk, ''),
    coalesce(head_event.payload_hash, ''),
    head_event.details::text,
    head_event.occurred_at::text,
    head_event.previous_hash
  );
  expected_hash := encode(
    extensions.digest(convert_to(canonical, 'UTF8'), 'sha256'),
    'hex'
  );

  if expected_hash <> head_event.event_hash then
    return jsonb_build_object(
      'valid', false,
      'failedSequence', chain.last_sequence,
      'reason', 'head_event_hash_mismatch',
      'scope', 'head'
    );
  end if;

  return jsonb_build_object(
    'valid', true,
    'eventCount', chain.last_sequence,
    'lastHash', chain.last_hash,
    'checkedSequence', chain.last_sequence,
    'scope', 'head'
  );
end;
$function$;

revoke all on function public.verify_execution_audit_head(uuid)
  from public, anon, authenticated;
grant execute on function public.verify_execution_audit_head(uuid)
  to service_role;

comment on function public.verify_execution_audit_head(uuid) is
  'Constant-time hot-path integrity check for the execution audit chain head. The full verify_execution_audit_chain(uuid) forensic verifier remains unchanged for explicit deep audits.';
