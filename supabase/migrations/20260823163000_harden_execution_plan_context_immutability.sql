-- Execution-plan context is evidence used by approval, dispatch, and review.
-- Once attached, it must remain bound to the exact plan/request envelope.

-- Canonical context JSON is compact JSON with array order preserved and every
-- object key recursively sorted by bytewise (C-collation) order. Scalar JSON
-- uses PostgreSQL jsonb text encoding. The Node producer implements the same
-- contract before hashing, so object insertion order cannot change the digest.
create or replace function private.projectos_canonical_context_json(
  p_value jsonb
)
returns text
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $$
declare
  canonical text;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select '{' || coalesce(string_agg(
        to_jsonb(entry.key)::text || ':' ||
          private.projectos_canonical_context_json(entry.value),
        ',' order by entry.key collate "C"
      ), '') || '}'
      into canonical
      from jsonb_each(p_value) entry;
      return canonical;
    when 'array' then
      select '[' || coalesce(string_agg(
        private.projectos_canonical_context_json(entry.value),
        ',' order by entry.ordinality
      ), '') || ']'
      into canonical
      from jsonb_array_elements(p_value) with ordinality entry(value, ordinality);
      return canonical;
    else
      return p_value::text;
  end case;
end;
$$;

revoke all on function private.projectos_canonical_context_json(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.attach_execution_plan_context(
  p_organization_id uuid,
  p_plan_id uuid,
  p_request_id uuid,
  p_context_hash text,
  p_context_envelope jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plan private.execution_plans%rowtype;
  context_row private.execution_plan_contexts%rowtype;
  context_status text;
  context_namespace text;
  context_counts jsonb;
  warning_count integer;
  canonical_context text;
  derived_context_hash text;
begin
  perform private.assert_control_service_role();

  if coalesce(p_context_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid context hash' using errcode = '22023';
  end if;
  if jsonb_typeof(p_context_envelope) is distinct from 'object'
     or octet_length(coalesce(p_context_envelope, '{}'::jsonb)::text) > 32768 then
    raise exception 'invalid context envelope' using errcode = '22023';
  end if;
  if not coalesce(p_context_envelope ?& array[
       'schemaVersion', 'status', 'source', 'namespace', 'retrievedAt',
       'queryHash', 'queryBasis', 'counts', 'highlights', 'warnings'
     ]::text[], false)
     or (select count(*) from jsonb_object_keys(p_context_envelope)) not in (10, 11)
     or (
       (select count(*) from jsonb_object_keys(p_context_envelope)) = 11
       and (
         not (p_context_envelope ? 'failure')
         or jsonb_typeof(p_context_envelope -> 'failure') is distinct from 'object'
       )
     )
     or p_context_envelope ->> 'schemaVersion' is distinct from '1.0.0'
     or p_context_envelope ->> 'source' is distinct from 'pandora-memory'
     or jsonb_typeof(p_context_envelope -> 'queryBasis') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'counts') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'highlights') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'warnings') is distinct from 'array'
     or nullif(p_context_envelope ->> 'retrievedAt', '') is null then
    raise exception 'invalid context envelope contract' using errcode = '22023';
  end if;

  canonical_context := private.projectos_canonical_context_json(p_context_envelope);
  derived_context_hash := encode(
    extensions.digest(convert_to(canonical_context, 'UTF8'), 'sha256'),
    'hex'
  );
  if p_context_hash is distinct from derived_context_hash then
    raise exception 'context hash does not match canonical envelope'
      using errcode = '22023';
  end if;
  if not coalesce((p_context_envelope -> 'counts') ?& array[
       'projectContext', 'riskWarnings', 'openLoops', 'recentEvents',
       'semanticMatches'
     ]::text[], false)
     or (select count(*) from jsonb_object_keys(p_context_envelope -> 'counts')) <> 5
     or jsonb_typeof(p_context_envelope #> '{counts,projectContext}')
       is distinct from 'number'
     or jsonb_typeof(p_context_envelope #> '{counts,riskWarnings}')
       is distinct from 'number'
     or jsonb_typeof(p_context_envelope #> '{counts,openLoops}')
       is distinct from 'number'
     or jsonb_typeof(p_context_envelope #> '{counts,recentEvents}')
       is distinct from 'number'
     or jsonb_typeof(p_context_envelope #> '{counts,semanticMatches}')
       is distinct from 'number' then
    raise exception 'invalid context counts' using errcode = '22023';
  end if;

  context_status := p_context_envelope ->> 'status';
  context_namespace := p_context_envelope ->> 'namespace';
  if coalesce(context_status, '') not in ('available', 'empty', 'unavailable') then
    raise exception 'invalid context status' using errcode = '22023';
  end if;
  if context_namespace is distinct from 'real_life' then
    raise exception 'invalid context namespace' using errcode = '22023';
  end if;
  if coalesce(p_context_envelope ->> 'queryHash', '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid context query hash' using errcode = '22023';
  end if;

  context_counts := jsonb_build_object(
    'projectContext', (p_context_envelope #>> '{counts,projectContext}')::integer,
    'riskWarnings', (p_context_envelope #>> '{counts,riskWarnings}')::integer,
    'openLoops', (p_context_envelope #>> '{counts,openLoops}')::integer,
    'recentEvents', (p_context_envelope #>> '{counts,recentEvents}')::integer,
    'semanticMatches', (p_context_envelope #>> '{counts,semanticMatches}')::integer
  );
  if exists (
    select 1
    from jsonb_each_text(context_counts) count_value
    where count_value.value::integer < 0 or count_value.value::integer > 50
  ) then
    raise exception 'invalid context counts' using errcode = '22023';
  end if;
  warning_count := jsonb_array_length(p_context_envelope -> 'warnings');
  if warning_count > 10 then
    raise exception 'invalid context warnings' using errcode = '22023';
  end if;

  -- The plan lock serializes both the absent-context first write and every replay.
  select * into plan
  from private.execution_plans
  where id = p_plan_id
    and organization_id = p_organization_id
    and request_id = p_request_id
  for update;

  if plan.id is null then
    raise exception 'execution plan not found' using errcode = 'P0002';
  end if;

  select * into context_row
  from private.execution_plan_contexts
  where plan_id = plan.id
  for update;

  if context_row.plan_id is not null then
    if context_row.context_hash = p_context_hash
       and context_row.context_envelope = p_context_envelope then
      return jsonb_build_object(
        'planId', context_row.plan_id,
        'requestId', context_row.request_id,
        'contextHash', context_row.context_hash,
        'status', context_row.context_status,
        'namespace', context_row.namespace,
        'recordedAt', context_row.recorded_at
      );
    end if;

    raise exception 'execution plan context is immutable' using errcode = '55000';
  end if;

  -- Context may be introduced only before approval and before the plan expires.
  -- Exact replays above remain safe after either boundary because they do not mutate.
  if plan.status <> 'pending_approval' or plan.expires_at <= now() then
    raise exception 'execution plan context attachment is closed' using errcode = '55000';
  end if;

  insert into private.execution_plan_contexts (
    plan_id,
    organization_id,
    request_id,
    context_hash,
    context_status,
    namespace,
    context_envelope
  ) values (
    plan.id,
    p_organization_id,
    p_request_id,
    p_context_hash,
    context_status,
    context_namespace,
    p_context_envelope
  )
  returning * into context_row;

  perform private.append_execution_audit(
    p_organization_id,
    plan.id,
    plan.request_id,
    'plan_context_attached',
    plan.status,
    plan.tool,
    plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'contextHash', context_row.context_hash,
      'contextStatus', context_row.context_status,
      'namespace', context_row.namespace,
      'retrievedAt', p_context_envelope ->> 'retrievedAt',
      'counts', context_counts,
      'warningCount', warning_count
    )
  );

  return jsonb_build_object(
    'planId', context_row.plan_id,
    'requestId', context_row.request_id,
    'contextHash', context_row.context_hash,
    'status', context_row.context_status,
    'namespace', context_row.namespace,
    'recordedAt', context_row.recorded_at
  );
end;
$$;

revoke all on function public.attach_execution_plan_context(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.attach_execution_plan_context(uuid, uuid, uuid, text, jsonb)
  to service_role;

-- Keep the service credential on the validated RPC boundary. The function
-- owner retains the table access needed by SECURITY DEFINER execution.
revoke all on table private.execution_plan_contexts from service_role;
