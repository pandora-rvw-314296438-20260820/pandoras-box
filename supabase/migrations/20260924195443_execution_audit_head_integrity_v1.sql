-- Pandora execution audit hot-path verifier v1
--
-- The full verify_execution_audit_chain(uuid) function intentionally remains
-- available for explicit deep audits. Runtime owner safety reads use this
-- constant-time head verifier instead so audit history growth cannot turn
-- ordinary reads into O(n) scans.

create or replace function public.verify_execution_audit_head_v1(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  chain private.execution_audit_chain_state%rowtype;
  tail private.execution_audit_events%rowtype;
  canonical text;
  expected_hash text;
  zero_hash constant text := repeat('0', 64);
begin
  perform private.assert_control_service_role();

  select *
  into chain
  from private.execution_audit_chain_state
  where organization_id = p_organization_id;

  if not found then
    if exists (
      select 1
      from private.execution_audit_events
      where organization_id = p_organization_id
      limit 1
    ) then
      return jsonb_build_object(
        'valid', false,
        'reason', 'missing_chain_state',
        'verificationScope', 'head'
      );
    end if;

    return jsonb_build_object(
      'valid', true,
      'eventCount', 0,
      'lastHash', zero_hash,
      'verificationScope', 'head'
    );
  end if;

  if chain.last_sequence = 0 then
    if chain.last_hash <> zero_hash then
      return jsonb_build_object(
        'valid', false,
        'reason', 'zero_sequence_hash_mismatch',
        'verificationScope', 'head'
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
        'reason', 'zero_sequence_with_events',
        'verificationScope', 'head'
      );
    end if;

    return jsonb_build_object(
      'valid', true,
      'eventCount', 0,
      'lastHash', zero_hash,
      'verificationScope', 'head'
    );
  end if;

  select *
  into tail
  from private.execution_audit_events
  where organization_id = p_organization_id
  order by sequence desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'valid', false,
      'reason', 'missing_tail_event',
      'verificationScope', 'head'
    );
  end if;

  if tail.sequence <> chain.last_sequence
     or tail.event_hash <> chain.last_hash then
    return jsonb_build_object(
      'valid', false,
      'reason', 'chain_head_mismatch',
      'stateSequence', chain.last_sequence,
      'tailSequence', tail.sequence,
      'verificationScope', 'head'
    );
  end if;

  canonical := concat_ws(
    '|',
    tail.organization_id::text,
    tail.sequence::text,
    coalesce(tail.plan_id::text, ''),
    coalesce(tail.request_id::text, ''),
    tail.event_type,
    tail.status,
    coalesce(tail.tool, ''),
    coalesce(tail.risk, ''),
    coalesce(tail.payload_hash, ''),
    tail.details::text,
    tail.occurred_at::text,
    tail.previous_hash
  );
  expected_hash := encode(
    extensions.digest(convert_to(canonical, 'UTF8'), 'sha256'),
    'hex'
  );

  if expected_hash <> tail.event_hash then
    return jsonb_build_object(
      'valid', false,
      'failedSequence', tail.sequence,
      'reason', 'tail_event_hash_mismatch',
      'verificationScope', 'head'
    );
  end if;

  return jsonb_build_object(
    'valid', true,
    'eventCount', chain.last_sequence,
    'lastHash', chain.last_hash,
    'verificationScope', 'head'
  );
end;
$$;

revoke all on function public.verify_execution_audit_head_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.verify_execution_audit_head_v1(uuid)
  to service_role;

comment on function public.verify_execution_audit_head_v1(uuid) is
  'Constant-time execution-audit head consistency check for runtime safety reads. The full historical verify_execution_audit_chain(uuid) verifier remains authoritative for explicit deep audits.';
