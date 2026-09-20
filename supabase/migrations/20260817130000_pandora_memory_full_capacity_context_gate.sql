begin;

create or replace function private.enforce_execution_plan_memory_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context private.execution_plan_contexts%rowtype;
  v_retrieved_at timestamptz;
  v_schema_version text;
  v_required_sections jsonb;
  v_observed_sections jsonb;
  v_missing_sections jsonb;
  v_count_key text;
  v_highlight_key text;
  v_count_value numeric;
  v_approved_record_count numeric;
  v_expected_sections constant jsonb := '[
    "adaptive_profile",
    "style_profile",
    "project_context",
    "people_context",
    "risk_warnings",
    "open_loops",
    "latest_context_pack",
    "daily_context_pack",
    "recent_events",
    "semantic_matches",
    "canonical_records",
    "approved_record_count",
    "requested_canon_statuses",
    "retrieval_mode",
    "retrieval_reasoning_summary",
    "warnings"
  ]'::jsonb;
  v_count_keys constant text[] := array[
    'adaptiveProfile',
    'styleProfile',
    'projectContext',
    'peopleContext',
    'riskWarnings',
    'openLoops',
    'latestContextPack',
    'dailyContextPack',
    'recentEvents',
    'semanticMatches',
    'canonicalRecords',
    'approvedRecords'
  ];
  v_highlight_keys constant text[] := array[
    'adaptive',
    'style',
    'project',
    'people',
    'risks',
    'openLoops',
    'latestContextPack',
    'dailyContextPack',
    'recent',
    'semantic',
    'canonical'
  ];
begin
  if new.status <> 'executing' or old.status is not distinct from new.status then
    return new;
  end if;

  select *
  into v_context
  from private.execution_plan_contexts
  where plan_id = new.id
    and organization_id = new.organization_id
    and request_id = new.request_id;

  if v_context.plan_id is null then
    raise exception 'projectos_memory_context_missing'
      using errcode = '55000';
  end if;

  v_schema_version := v_context.context_envelope->>'schemaVersion';

  if v_context.namespace is distinct from 'real_life'
     or v_context.context_envelope->>'namespace' is distinct from 'real_life'
     or v_context.context_envelope->>'source' is distinct from 'pandora-memory'
     or v_schema_version is null
     or v_schema_version not in ('1.0.0', '2.0.0')
     or v_context.context_envelope->>'status' is distinct from v_context.context_status
     or v_context.context_envelope#>>'{queryBasis,tool}' is distinct from new.tool
     or lower(coalesce(v_context.context_hash, '')) !~ '^[0-9a-f]{64}$' then
    raise exception 'projectos_memory_context_invalid'
      using errcode = '55000';
  end if;

  if v_schema_version = '2.0.0' then
    v_required_sections := v_context.context_envelope#>'{capabilityContract,requiredSections}';
    v_observed_sections := v_context.context_envelope#>'{capabilityContract,observedSections}';
    v_missing_sections := v_context.context_envelope#>'{capabilityContract,missingRequiredSections}';

    if v_context.context_envelope#>>'{capabilityContract,status}' is distinct from 'verified'
       or v_context.context_envelope#>>'{capabilityContract,id}' is distinct from 'pandora-projectos-memory-puzzle'
       or v_context.context_envelope#>>'{capabilityContract,version}' is distinct from '1.0.0'
       or v_context.context_envelope#>>'{capabilityContract,schemaVersion}' is distinct from '1.0.0'
       or v_context.context_envelope#>>'{capabilityContract,path}' is distinct from '/.well-known/pandora-projectos-memory-contract-v1.json'
       or v_context.context_envelope#>>'{capabilityContract,authorityRepository}' is distinct from 'banataosystems/pandoras-box-memory'
       or v_context.context_envelope#>>'{capabilityContract,authorityOrigin}' is distinct from 'https://pandorasbox-memory.vercel.app'
       or v_context.context_envelope#>>'{capabilityContract,compatible}' is distinct from 'true'
       or v_context.context_envelope#>>'{capabilityContract,utilizationPercentage}' is distinct from '100'
       or lower(coalesce(v_context.context_envelope#>>'{capabilityContract,semanticHash}', '')) !~ '^[0-9a-f]{64}$'
       or v_context.context_envelope->>'fallbackRequired' is distinct from 'false' then
      raise exception 'projectos_memory_full_capacity_contract_invalid'
        using errcode = '55000';
    end if;

    if jsonb_typeof(v_required_sections) is distinct from 'array'
       or jsonb_typeof(v_observed_sections) is distinct from 'array'
       or jsonb_typeof(v_missing_sections) is distinct from 'array' then
      raise exception 'projectos_memory_full_capacity_sections_invalid'
        using errcode = '55000';
    end if;

    if jsonb_array_length(v_required_sections) <> jsonb_array_length(v_expected_sections)
       or not (v_required_sections @> v_expected_sections and v_expected_sections @> v_required_sections)
       or jsonb_array_length(v_observed_sections) <> jsonb_array_length(v_expected_sections)
       or not (v_observed_sections @> v_expected_sections and v_expected_sections @> v_observed_sections)
       or jsonb_array_length(v_missing_sections) <> 0 then
      raise exception 'projectos_memory_full_capacity_sections_invalid'
        using errcode = '55000';
    end if;

    if jsonb_typeof(v_context.context_envelope->'counts') is distinct from 'object'
       or jsonb_typeof(v_context.context_envelope->'highlights') is distinct from 'object'
       or jsonb_typeof(v_context.context_envelope->'retrieval') is distinct from 'object'
       or jsonb_typeof(v_context.context_envelope->'warnings') is distinct from 'array' then
      raise exception 'projectos_memory_full_capacity_envelope_invalid'
        using errcode = '55000';
    end if;

    if not ((v_context.context_envelope->'counts') ?& v_count_keys)
       or not ((v_context.context_envelope->'highlights') ?& v_highlight_keys)
       or jsonb_array_length(v_context.context_envelope->'warnings') > 10 then
      raise exception 'projectos_memory_full_capacity_envelope_invalid'
        using errcode = '55000';
    end if;

    foreach v_count_key in array v_count_keys loop
      if jsonb_typeof(v_context.context_envelope->'counts'->v_count_key) is distinct from 'number' then
        raise exception 'projectos_memory_full_capacity_count_invalid'
          using errcode = '55000';
      end if;

      v_count_value := (v_context.context_envelope->'counts'->>v_count_key)::numeric;
      if v_count_value < 0 or trunc(v_count_value) <> v_count_value then
        raise exception 'projectos_memory_full_capacity_count_invalid'
          using errcode = '55000';
      end if;
    end loop;

    foreach v_highlight_key in array v_highlight_keys loop
      if jsonb_typeof(v_context.context_envelope->'highlights'->v_highlight_key) is distinct from 'array' then
        raise exception 'projectos_memory_full_capacity_highlights_invalid'
          using errcode = '55000';
      end if;

      if jsonb_array_length(v_context.context_envelope->'highlights'->v_highlight_key) > 3 then
        raise exception 'projectos_memory_full_capacity_highlights_invalid'
          using errcode = '55000';
      end if;
    end loop;

    if nullif(btrim(v_context.context_envelope#>>'{retrieval,mode}'), '') is null
       or nullif(btrim(v_context.context_envelope#>>'{retrieval,reasoningSummary}'), '') is null
       or v_context.context_envelope#>'{retrieval,requestedCanonStatuses}' is distinct from '["approved"]'::jsonb
       or jsonb_typeof(v_context.context_envelope#>'{retrieval,approvedRecordCount}') is distinct from 'number' then
      raise exception 'projectos_memory_full_capacity_retrieval_invalid'
        using errcode = '55000';
    end if;

    v_approved_record_count := (v_context.context_envelope#>>'{retrieval,approvedRecordCount}')::numeric;
    if v_approved_record_count < 0
       or trunc(v_approved_record_count) <> v_approved_record_count
       or v_context.context_envelope#>>'{retrieval,approvedRecordCount}'
          is distinct from v_context.context_envelope#>>'{counts,approvedRecords}' then
      raise exception 'projectos_memory_full_capacity_retrieval_invalid'
        using errcode = '55000';
    end if;
  end if;

  if new.risk = 'read' then
    if v_context.context_status is null
       or v_context.context_status not in ('available', 'empty') then
      raise exception 'projectos_memory_context_unavailable'
        using errcode = '55000';
    end if;
  elsif v_context.context_status is distinct from 'available' then
    raise exception 'projectos_memory_context_unavailable_for_stateful_action'
      using errcode = '55000';
  end if;

  begin
    v_retrieved_at := nullif(v_context.context_envelope->>'retrievedAt', '')::timestamptz;
  exception when others then
    raise exception 'projectos_memory_context_timestamp_invalid'
      using errcode = '55000';
  end;

  if v_retrieved_at is null
     or v_retrieved_at < new.created_at - interval '10 minutes'
     or v_retrieved_at > clock_timestamp() + interval '1 minute'
     or v_context.recorded_at < new.created_at - interval '2 seconds'
     or v_context.recorded_at > clock_timestamp() + interval '1 minute' then
    raise exception 'projectos_memory_context_stale'
      using errcode = '55000';
  end if;

  return new;
end;
$function$;

comment on function private.enforce_execution_plan_memory_context() is
  'Requires fresh real_life Pandora Memory context before execution. Legacy 1.0.0 envelopes remain accepted; 2.0.0 envelopes must prove the exact full-capacity capability contract, complete section utilization, approved-only canonical retrieval, bounded summaries, and no provider fallback.';

commit;
