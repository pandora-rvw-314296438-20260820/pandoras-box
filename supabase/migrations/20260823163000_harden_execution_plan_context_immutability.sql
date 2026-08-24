-- Execution-plan context is evidence used by approval, dispatch, and review.
-- Once attached, it must remain bound to the exact plan/request envelope.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';
-- Hold back concurrent attachments until classification, the direct-insert
-- guard, and the canonical-only RPC all become visible together at commit.
-- Reads remain available while this SHARE ROW EXCLUSIVE lock is held.
lock table private.execution_plan_contexts in share row exclusive mode;

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

-- BEGIN EXECUTION PLAN CONTEXT HASH CONTRACT
-- Historical rows are immutable evidence. Their original context_hash bytes
-- must not be rewritten merely because the producer now uses a canonical JSON
-- serializer. Record the serializer that produced each durable hash instead.
create or replace function private.projectos_legacy_node_context_json(
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
  identifiers_json text;
  failure_json text;
begin
  -- The original Node producer used this exact top-level insertion order.
  if jsonb_typeof(p_value) is distinct from 'object'
     or not (p_value ?& array[
       'schemaVersion', 'status', 'source', 'namespace', 'retrievedAt',
       'queryHash', 'queryBasis', 'counts', 'highlights', 'warnings'
     ]::text[])
     or (select count(*) from jsonb_object_keys(p_value)) not in (10, 11)
     or (
       (select count(*) from jsonb_object_keys(p_value)) = 11
       and not (p_value ? 'failure')
     )
     or jsonb_typeof(p_value -> 'queryBasis') is distinct from 'object'
     or not ((p_value -> 'queryBasis') ?& array['tool', 'identifiers']::text[])
     or (select count(*) from jsonb_object_keys(p_value -> 'queryBasis')) <> 2
     or jsonb_typeof(p_value #> '{queryBasis,tool}') is distinct from 'string'
     or nullif(btrim(p_value #>> '{queryBasis,tool}'), '') is null
     or char_length(p_value #>> '{queryBasis,tool}') > 200
     or jsonb_typeof(p_value #> '{queryBasis,identifiers}') is distinct from 'object'
     or jsonb_typeof(p_value -> 'counts') is distinct from 'object'
     or not ((p_value -> 'counts') ?& array[
       'projectContext', 'riskWarnings', 'openLoops', 'recentEvents',
       'semanticMatches'
     ]::text[])
     or (select count(*) from jsonb_object_keys(p_value -> 'counts')) <> 5
     or jsonb_typeof(p_value -> 'highlights') is distinct from 'object'
     or not ((p_value -> 'highlights') ?& array[
       'project', 'risks', 'openLoops', 'recent', 'semantic'
     ]::text[])
     or (select count(*) from jsonb_object_keys(p_value -> 'highlights')) <> 5
     or jsonb_typeof(p_value -> 'warnings') is distinct from 'array' then
    return null;
  end if;

  if exists (
    select 1
    from jsonb_each(p_value #> '{queryBasis,identifiers}') identifier
    where identifier.key <> all(array[
      'owner', 'org', 'organization', 'repo', 'repository',
      'repository_full_name', 'projectId', 'project_id', 'projectRef',
      'project_ref', 'branch', 'issue_number', 'pr_number', 'deploymentId',
      'deployment_id', 'teamId', 'team_id', 'domain'
    ]::text[])
       or jsonb_typeof(identifier.value) is distinct from 'string'
       or nullif(btrim(identifier.value #>> '{}'), '') is null
       or char_length(identifier.value #>> '{}') > 240
  ) or exists (
    select 1
    from jsonb_each(p_value -> 'counts') count_value
    where jsonb_typeof(count_value.value) is distinct from 'number'
  ) or exists (
    select 1
    from jsonb_each(p_value -> 'highlights') highlight
    where jsonb_typeof(highlight.value) is distinct from 'array'
       or exists (
         select 1
         from jsonb_array_elements(highlight.value) item
         where jsonb_typeof(item) is distinct from 'string'
            or nullif(btrim(item #>> '{}'), '') is null
            or char_length(item #>> '{}') > 1000
       )
  ) or exists (
    select 1
    from jsonb_array_elements(p_value -> 'warnings') warning
    where jsonb_typeof(warning) is distinct from 'string'
       or nullif(btrim(warning #>> '{}'), '') is null
       or char_length(warning #>> '{}') > 300
  ) then
    return null;
  end if;

  select coalesce(string_agg(
    to_jsonb(identifier.key)::text || ':' || identifier.value::text,
    ',' order by identifier.key collate "C"
  ), '')
  into identifiers_json
  from jsonb_each(p_value #> '{queryBasis,identifiers}') identifier;

  if p_value ? 'failure' then
    if jsonb_typeof(p_value -> 'failure') is distinct from 'object'
       or not ((p_value -> 'failure') ? 'type')
       or (select count(*) from jsonb_object_keys(p_value -> 'failure')) not in (1, 2)
       or (
         (select count(*) from jsonb_object_keys(p_value -> 'failure')) = 2
         and not ((p_value -> 'failure') ? 'status')
       )
       or jsonb_typeof(p_value #> '{failure,type}') is distinct from 'string'
       or nullif(btrim(p_value #>> '{failure,type}'), '') is null
       or (
         (p_value -> 'failure') ? 'status'
         and jsonb_typeof(p_value #> '{failure,status}') is distinct from 'number'
       ) then
      return null;
    end if;

    if (p_value -> 'failure') ? 'status'
       and (
         p_value #>> '{failure,type}' is distinct from 'PandoraMemoryError'
         or (p_value #>> '{failure,status}')::numeric
           <> trunc((p_value #>> '{failure,status}')::numeric)
         or (p_value #>> '{failure,status}')::numeric not between 100 and 599
       ) then
      return null;
    end if;

    failure_json := ',"failure":{"type":' ||
      (p_value #> '{failure,type}')::text ||
      case when (p_value -> 'failure') ? 'status'
        then ',"status":' || (p_value #> '{failure,status}')::text
        else ''
      end || '}';
  else
    failure_json := '';
  end if;

  return '{' ||
    '"schemaVersion":' || (p_value -> 'schemaVersion')::text ||
    ',"status":' || (p_value -> 'status')::text ||
    ',"source":' || (p_value -> 'source')::text ||
    ',"namespace":' || (p_value -> 'namespace')::text ||
    ',"retrievedAt":' || (p_value -> 'retrievedAt')::text ||
    ',"queryHash":' || (p_value -> 'queryHash')::text ||
    ',"queryBasis":{"tool":' || (p_value #> '{queryBasis,tool}')::text ||
      ',"identifiers":{' || identifiers_json || '}}' ||
    ',"counts":{"projectContext":' ||
      (p_value #> '{counts,projectContext}')::text ||
      ',"riskWarnings":' || (p_value #> '{counts,riskWarnings}')::text ||
      ',"openLoops":' || (p_value #> '{counts,openLoops}')::text ||
      ',"recentEvents":' || (p_value #> '{counts,recentEvents}')::text ||
      ',"semanticMatches":' || (p_value #> '{counts,semanticMatches}')::text ||
    '}' ||
    ',"highlights":{"project":' ||
      private.projectos_canonical_context_json(p_value #> '{highlights,project}') ||
      ',"risks":' ||
      private.projectos_canonical_context_json(p_value #> '{highlights,risks}') ||
      ',"openLoops":' ||
      private.projectos_canonical_context_json(p_value #> '{highlights,openLoops}') ||
      ',"recent":' ||
      private.projectos_canonical_context_json(p_value #> '{highlights,recent}') ||
      ',"semantic":' ||
      private.projectos_canonical_context_json(p_value #> '{highlights,semantic}') ||
    '}' ||
    ',"warnings":' ||
      private.projectos_canonical_context_json(p_value -> 'warnings') ||
    failure_json ||
  '}';
end;
$$;

create or replace function private.projectos_context_json_sha256(
  p_serialized text
)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $$
  select encode(
    extensions.digest(convert_to(p_serialized, 'UTF8'), 'sha256'),
    'hex'
  )
$$;

create or replace function private.projectos_context_hash_matches_contract(
  p_context_hash text,
  p_context_envelope jsonb,
  p_hash_contract text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(case p_hash_contract
    when 'canonical-json-c-utf8-sha256-v1' then
      p_context_hash = private.projectos_context_json_sha256(
        private.projectos_canonical_context_json(p_context_envelope)
      )
    when 'legacy-js-json-stringify-envelope-v1' then
      p_context_hash = private.projectos_context_json_sha256(
        private.projectos_legacy_node_context_json(p_context_envelope)
      )
    when 'legacy-postgres-jsonb-text-sha256-v1' then
      p_context_hash = private.projectos_context_json_sha256(
        p_context_envelope::text
      )
    else false
  end, false)
$$;

revoke all on function private.projectos_legacy_node_context_json(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_context_json_sha256(text)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_context_hash_matches_contract(text, jsonb, text)
  from public, anon, authenticated, service_role;

alter table private.execution_plan_contexts
  add column hash_contract text,
  add column canonical_context_hash text;

-- Classify only from the original envelope and immutable hash. The order is
-- intentional: current production evidence was emitted by the Node producer,
-- with one provider-text fallback row; canonical rows are a forward case.
do $$
declare
  evidence_before text;
  evidence_after text;
  evidence_row_count_before bigint;
  evidence_row_count_after bigint;
  unclassified_count bigint;
begin
  select count(*), private.projectos_context_json_sha256(coalesce(string_agg(
    evidence.row_hash, E'\n' order by evidence.plan_id
  ), '')) into evidence_row_count_before, evidence_before
  from (
    select
      plan_id,
      private.projectos_context_json_sha256(
        plan_id::text || ':' || context_hash || ':' || context_envelope::text
      ) as row_hash
    from private.execution_plan_contexts
  ) evidence;

  update private.execution_plan_contexts
  set
    hash_contract = case
      when context_hash = private.projectos_context_json_sha256(
        private.projectos_legacy_node_context_json(context_envelope)
      ) then 'legacy-js-json-stringify-envelope-v1'
      when context_hash = private.projectos_context_json_sha256(
        context_envelope::text
      ) then 'legacy-postgres-jsonb-text-sha256-v1'
      when context_hash = private.projectos_context_json_sha256(
        private.projectos_canonical_context_json(context_envelope)
      ) then 'canonical-json-c-utf8-sha256-v1'
      else null
    end,
    canonical_context_hash = private.projectos_context_json_sha256(
      private.projectos_canonical_context_json(context_envelope)
    );

  select count(*), private.projectos_context_json_sha256(coalesce(string_agg(
    evidence.row_hash, E'\n' order by evidence.plan_id
  ), '')) into evidence_row_count_after, evidence_after
  from (
    select
      plan_id,
      private.projectos_context_json_sha256(
        plan_id::text || ':' || context_hash || ':' || context_envelope::text
      ) as row_hash
    from private.execution_plan_contexts
  ) evidence;

  if evidence_row_count_before is distinct from evidence_row_count_after
     or evidence_before is distinct from evidence_after then
    raise exception 'execution plan context evidence changed during hash classification'
      using errcode = '23514';
  end if;

  select count(*) into unclassified_count
  from private.execution_plan_contexts
  where hash_contract is null
     or canonical_context_hash is distinct from private.projectos_context_json_sha256(
       private.projectos_canonical_context_json(context_envelope)
     )
     or private.projectos_context_hash_matches_contract(
       context_hash,
       context_envelope,
       hash_contract
     ) is not true;

  if unclassified_count <> 0 then
    raise exception 'execution plan context hash provenance is unclassified (% rows)',
      unclassified_count
      using errcode = '23514';
  end if;
end;
$$;

alter table private.execution_plan_contexts
  alter column hash_contract set default 'canonical-json-c-utf8-sha256-v1',
  alter column hash_contract set not null,
  alter column canonical_context_hash set not null;

alter table private.execution_plan_contexts
  add constraint execution_plan_contexts_hash_contract_allowed
  check (hash_contract in (
    'canonical-json-c-utf8-sha256-v1',
    'legacy-js-json-stringify-envelope-v1',
    'legacy-postgres-jsonb-text-sha256-v1'
  )) not valid;

alter table private.execution_plan_contexts
  validate constraint execution_plan_contexts_hash_contract_allowed;

create or replace function private.enforce_execution_plan_context_hash_contract_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  expected_canonical_hash text;
begin
  expected_canonical_hash := private.projectos_context_json_sha256(
    private.projectos_canonical_context_json(new.context_envelope)
  );
  if new.hash_contract is distinct from 'canonical-json-c-utf8-sha256-v1'
     or new.context_hash is distinct from expected_canonical_hash
     or new.canonical_context_hash is distinct from expected_canonical_hash then
    raise exception 'new execution plan contexts require the canonical hash contract'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.reject_execution_plan_context_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'execution plan context evidence is immutable'
    using errcode = '55000';
end;
$$;

revoke all on function private.enforce_execution_plan_context_hash_contract_insert()
  from public, anon, authenticated, service_role;
revoke all on function private.reject_execution_plan_context_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists execution_plan_contexts_canonical_insert
  on private.execution_plan_contexts;
create trigger execution_plan_contexts_canonical_insert
before insert on private.execution_plan_contexts
for each row execute function
  private.enforce_execution_plan_context_hash_contract_insert();

drop trigger if exists execution_plan_contexts_immutable
  on private.execution_plan_contexts;
create trigger execution_plan_contexts_immutable
before update or delete on private.execution_plan_contexts
for each row execute function
  private.reject_execution_plan_context_mutation();
-- END EXECUTION PLAN CONTEXT HASH CONTRACT

-- Schema 2.0.0 is the full-capacity Memory envelope already governed by
-- 20260817130000. Keep its validation explicit here so hardening the hash
-- boundary cannot make the previously accepted contract unreachable.
create or replace function private.projectos_full_capacity_context_is_valid(
  p_value jsonb
)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  required_sections jsonb;
  observed_sections jsonb;
  missing_sections jsonb;
  count_key text;
  highlight_key text;
  count_value numeric;
  approved_record_count numeric;
  failure_status numeric;
  retrieved_timestamp timestamptz;
  expected_sections constant jsonb := '[
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
  count_keys constant text[] := array[
    'adaptiveProfile', 'styleProfile', 'projectContext', 'peopleContext',
    'riskWarnings', 'openLoops', 'latestContextPack', 'dailyContextPack',
    'recentEvents', 'semanticMatches', 'canonicalRecords', 'approvedRecords'
  ];
  highlight_keys constant text[] := array[
    'adaptive', 'style', 'project', 'people', 'risks', 'openLoops',
    'latestContextPack', 'dailyContextPack', 'recent', 'semantic', 'canonical'
  ];
begin
  if jsonb_typeof(p_value) is distinct from 'object'
     or not coalesce(p_value ?& array[
       'schemaVersion', 'status', 'source', 'namespace', 'retrievedAt',
       'queryHash', 'queryBasis', 'counts', 'highlights', 'warnings',
       'capabilityContract', 'retrieval', 'fallbackRequired'
     ]::text[], false)
     or p_value ->> 'schemaVersion' is distinct from '2.0.0'
     or p_value ->> 'source' is distinct from 'pandora-memory'
     or p_value ->> 'namespace' is distinct from 'real_life'
     or coalesce(p_value ->> 'status', '') not in ('available', 'empty', 'unavailable')
     or jsonb_typeof(p_value -> 'retrievedAt') is distinct from 'string'
     or coalesce(p_value ->> 'retrievedAt', '')
       !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
     or jsonb_typeof(p_value -> 'queryHash') is distinct from 'string'
     or coalesce(p_value ->> 'queryHash', '') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_value -> 'queryBasis') is distinct from 'object'
     or (select count(*) from jsonb_object_keys(p_value -> 'queryBasis')) <> 2
     or not ((p_value -> 'queryBasis') ?& array['tool', 'identifiers']::text[])
     or jsonb_typeof(p_value #> '{queryBasis,tool}') is distinct from 'string'
     or nullif(btrim(p_value #>> '{queryBasis,tool}'), '') is null
     or char_length(p_value #>> '{queryBasis,tool}') > 200
     or jsonb_typeof(p_value #> '{queryBasis,identifiers}') is distinct from 'object'
     or jsonb_typeof(p_value -> 'counts') is distinct from 'object'
     or (select count(*) from jsonb_object_keys(p_value -> 'counts')) <> 12
     or not ((p_value -> 'counts') ?& count_keys)
     or jsonb_typeof(p_value -> 'highlights') is distinct from 'object'
     or (select count(*) from jsonb_object_keys(p_value -> 'highlights')) <> 11
     or not ((p_value -> 'highlights') ?& highlight_keys)
     or jsonb_typeof(p_value -> 'warnings') is distinct from 'array'
     or jsonb_typeof(p_value -> 'capabilityContract') is distinct from 'object'
     or jsonb_typeof(p_value -> 'retrieval') is distinct from 'object'
     or jsonb_array_length(p_value -> 'warnings') > 10 then
    return false;
  end if;

  retrieved_timestamp := (p_value ->> 'retrievedAt')::timestamptz;

  if exists (
    select 1
    from jsonb_each(p_value #> '{queryBasis,identifiers}') identifier
    where identifier.key <> all(array[
      'owner', 'org', 'organization', 'repo', 'repository',
      'repository_full_name', 'projectId', 'project_id', 'projectRef',
      'project_ref', 'branch', 'issue_number', 'pr_number', 'deploymentId',
      'deployment_id', 'teamId', 'team_id', 'domain'
    ]::text[])
       or jsonb_typeof(identifier.value) is distinct from 'string'
       or nullif(btrim(identifier.value #>> '{}'), '') is null
       or char_length(identifier.value #>> '{}') > 240
  ) or exists (
    select 1
    from jsonb_array_elements(p_value -> 'warnings') warning
    where jsonb_typeof(warning) is distinct from 'string'
       or nullif(btrim(warning #>> '{}'), '') is null
       or char_length(warning #>> '{}') > 300
  ) then
    return false;
  end if;

  required_sections := p_value #> '{capabilityContract,requiredSections}';
  observed_sections := p_value #> '{capabilityContract,observedSections}';
  missing_sections := p_value #> '{capabilityContract,missingRequiredSections}';
  if jsonb_typeof(required_sections) is distinct from 'array'
     or jsonb_typeof(observed_sections) is distinct from 'array'
     or jsonb_typeof(missing_sections) is distinct from 'array'
     or required_sections is distinct from expected_sections then
    return false;
  end if;

  foreach count_key in array count_keys loop
    if jsonb_typeof(p_value -> 'counts' -> count_key) is distinct from 'number' then
      return false;
    end if;
    count_value := (p_value -> 'counts' ->> count_key)::numeric;
    if count_value < 0
       or trunc(count_value) <> count_value
       or (
         count_key in ('latestContextPack', 'dailyContextPack')
         and count_value not in (0, 1)
       )
       or (
         count_key not in (
           'latestContextPack', 'dailyContextPack', 'approvedRecords'
         )
         and count_value > 50
       ) then
      return false;
    end if;
  end loop;

  foreach highlight_key in array highlight_keys loop
    if jsonb_typeof(p_value -> 'highlights' -> highlight_key) is distinct from 'array'
       or jsonb_array_length(p_value -> 'highlights' -> highlight_key) > 3
       or exists (
         select 1
         from jsonb_array_elements(p_value -> 'highlights' -> highlight_key) item
         where jsonb_typeof(item) is distinct from 'string'
            or nullif(btrim(item #>> '{}'), '') is null
            or char_length(item #>> '{}') > 1000
       ) then
      return false;
    end if;
  end loop;

  if p_value ->> 'status' in ('available', 'empty') then
    if (select count(*) from jsonb_object_keys(p_value)) <> 13
       or p_value ? 'failure'
       or p_value -> 'fallbackRequired' is distinct from 'false'::jsonb
       or (select count(*) from jsonb_object_keys(p_value -> 'capabilityContract')) <> 13
       or not ((p_value -> 'capabilityContract') ?& array[
         'status', 'id', 'version', 'schemaVersion', 'semanticHash',
         'authorityRepository', 'authorityOrigin', 'path', 'compatible',
         'requiredSections', 'observedSections', 'missingRequiredSections',
         'utilizationPercentage'
       ]::text[])
       or p_value #>> '{capabilityContract,status}' is distinct from 'verified'
       or p_value #>> '{capabilityContract,id}' is distinct from 'pandora-projectos-memory-puzzle'
       or p_value #>> '{capabilityContract,version}' is distinct from '1.0.0'
       or p_value #>> '{capabilityContract,schemaVersion}' is distinct from '1.0.0'
       or p_value #>> '{capabilityContract,path}' is distinct from '/.well-known/pandora-projectos-memory-contract-v1.json'
       or p_value #>> '{capabilityContract,authorityRepository}' is distinct from 'banataosystems/pandoras-box-memory'
       or p_value #>> '{capabilityContract,authorityOrigin}' is distinct from 'https://pandorasbox-memory.vercel.app'
       or p_value #> '{capabilityContract,compatible}' is distinct from 'true'::jsonb
       or p_value #> '{capabilityContract,utilizationPercentage}' is distinct from '100'::jsonb
       or jsonb_typeof(p_value #> '{capabilityContract,semanticHash}') is distinct from 'string'
       -- Governed implementation 33445e126456af732b420a4c5e47047596ad70ed
       -- defines the exact v1 authority contract. A different semantic hash
       -- requires a separately reviewed migration; arbitrary 64-hex values do
       -- not prove that the trusted contract was actually verified.
       or p_value #>> '{capabilityContract,semanticHash}' is distinct from
         '69cd91cb776249d22fa5050fa6826318748ea3b4d4fa68c96c509d9b51242dbd'
       or observed_sections is distinct from expected_sections
       or missing_sections is distinct from '[]'::jsonb
       or (select count(*) from jsonb_object_keys(p_value -> 'retrieval')) <> 4
       or not ((p_value -> 'retrieval') ?& array[
         'mode', 'reasoningSummary', 'requestedCanonStatuses',
         'approvedRecordCount'
       ]::text[])
       or jsonb_typeof(p_value #> '{retrieval,mode}') is distinct from 'string'
       or jsonb_typeof(p_value #> '{retrieval,reasoningSummary}') is distinct from 'string'
       or nullif(btrim(p_value #>> '{retrieval,mode}'), '') is null
       or char_length(p_value #>> '{retrieval,mode}') > 80
       or nullif(btrim(p_value #>> '{retrieval,reasoningSummary}'), '') is null
       or char_length(p_value #>> '{retrieval,reasoningSummary}') > 1000
       or p_value #> '{retrieval,requestedCanonStatuses}' is distinct from '["approved"]'::jsonb
       or jsonb_typeof(p_value #> '{retrieval,approvedRecordCount}') is distinct from 'number' then
      return false;
    end if;

    if (
      p_value ->> 'status' = 'empty'
      and (
        exists (
          select 1 from unnest(count_keys) key(name)
          where p_value -> 'counts' -> key.name is distinct from '0'::jsonb
        )
        or exists (
          select 1 from unnest(highlight_keys) key(name)
          where p_value -> 'highlights' -> key.name is distinct from '[]'::jsonb
        )
      )
    ) or (
      p_value ->> 'status' = 'available'
      and not (
        exists (
          select 1 from unnest(count_keys) key(name)
          where (p_value -> 'counts' ->> key.name)::numeric > 0
        )
        or exists (
          select 1 from unnest(highlight_keys) key(name)
          where jsonb_array_length(p_value -> 'highlights' -> key.name) > 0
        )
      )
    ) then
      return false;
    end if;

    approved_record_count := (p_value #>> '{retrieval,approvedRecordCount}')::numeric;
    return approved_record_count >= 0
      and trunc(approved_record_count) = approved_record_count
      and p_value #>> '{retrieval,approvedRecordCount}'
        is not distinct from p_value #>> '{counts,approvedRecords}';
  end if;

  if (select count(*) from jsonb_object_keys(p_value)) <> 14
     or not (p_value ? 'failure')
     or p_value -> 'fallbackRequired' is distinct from 'true'::jsonb
     or (select count(*) from jsonb_object_keys(p_value -> 'capabilityContract')) <> 8
     or not ((p_value -> 'capabilityContract') ?& array[
       'status', 'id', 'path', 'compatible', 'requiredSections',
       'observedSections', 'missingRequiredSections', 'utilizationPercentage'
     ]::text[])
     or p_value #>> '{capabilityContract,status}' is distinct from 'unavailable'
     or p_value #>> '{capabilityContract,id}' is distinct from 'pandora-projectos-memory-puzzle'
     or p_value #>> '{capabilityContract,path}' is distinct from '/.well-known/pandora-projectos-memory-contract-v1.json'
     or p_value #> '{capabilityContract,compatible}' is distinct from 'false'::jsonb
     or observed_sections is distinct from '[]'::jsonb
     or missing_sections is distinct from expected_sections
     or p_value #> '{capabilityContract,utilizationPercentage}' is distinct from '0'::jsonb
     or (select count(*) from jsonb_object_keys(p_value -> 'retrieval')) <> 2
     or not ((p_value -> 'retrieval') ?& array[
       'requestedCanonStatuses', 'approvedRecordCount'
     ]::text[])
     or p_value #> '{retrieval,requestedCanonStatuses}' is distinct from '[]'::jsonb
     or p_value #> '{retrieval,approvedRecordCount}' is distinct from '0'::jsonb
     or jsonb_typeof(p_value -> 'failure') is distinct from 'object'
     or not ((p_value -> 'failure') ? 'type')
     or jsonb_typeof(p_value #> '{failure,type}') is distinct from 'string'
     or nullif(btrim(p_value #>> '{failure,type}'), '') is null
     or (select count(*) from jsonb_object_keys(p_value -> 'failure')) not in (1, 2)
     or (
       (select count(*) from jsonb_object_keys(p_value -> 'failure')) = 2
       and (
         ((p_value -> 'failure') ? 'status') = ((p_value -> 'failure') ? 'code')
         or (
           (p_value -> 'failure') ? 'status'
           and jsonb_typeof(p_value #> '{failure,status}') is distinct from 'number'
         )
         or (
           (p_value -> 'failure') ? 'code'
           and jsonb_typeof(p_value #> '{failure,code}') is distinct from 'string'
         )
       )
     )
     or (
       (p_value -> 'failure') ? 'status'
       and p_value #>> '{failure,type}' is distinct from 'PandoraMemoryError'
     )
     or (
       (p_value -> 'failure') ? 'code'
       and p_value #>> '{failure,type}' is distinct from 'MemoryCapabilityContractError'
     )
     or p_value -> 'warnings'
       is distinct from '["memory_context_unavailable"]'::jsonb
     or exists (
       select 1 from unnest(count_keys) key(name)
       where p_value -> 'counts' -> key.name is distinct from '0'::jsonb
     )
     or exists (
       select 1 from unnest(highlight_keys) key(name)
       where p_value -> 'highlights' -> key.name is distinct from '[]'::jsonb
     ) then
    return false;
  end if;

  if (p_value -> 'failure') ? 'status' then
    failure_status := (p_value #>> '{failure,status}')::numeric;
    if trunc(failure_status) <> failure_status
       or failure_status < 100
       or failure_status > 599 then
      return false;
    end if;
  elsif (p_value -> 'failure') ? 'code' then
    if nullif(btrim(p_value #>> '{failure,code}'), '') is null
       or char_length(p_value #>> '{failure,code}') > 160 then
      return false;
    end if;
  end if;

  return true;
exception when others then
  return false;
end;
$$;

revoke all on function private.projectos_full_capacity_context_is_valid(jsonb)
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
  context_schema_version text;
  context_counts jsonb;
  count_key text;
  count_value numeric;
  warning_count integer;
  retrieved_timestamp timestamptz;
  canonical_context text;
  derived_context_hash text;
  v1_count_keys constant text[] := array[
    'projectContext', 'riskWarnings', 'openLoops', 'recentEvents',
    'semanticMatches'
  ];
  v1_highlight_keys constant text[] := array[
    'project', 'risks', 'openLoops', 'recent', 'semantic'
  ];
begin
  perform private.assert_control_service_role();

  if coalesce(p_context_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid context hash' using errcode = '22023';
  end if;
  if jsonb_typeof(p_context_envelope) is distinct from 'object'
     or octet_length(coalesce(p_context_envelope, '{}'::jsonb)::text) > 32768 then
    raise exception 'invalid context envelope' using errcode = '22023';
  end if;

  -- Lock and resolve an exact historical replay before applying today's deep
  -- schema rules. Stored provenance and the separately derived canonical hash
  -- still have to verify, but validator evolution cannot rewrite old evidence.
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
       and context_row.context_envelope = p_context_envelope
       and context_row.canonical_context_hash = private.projectos_context_json_sha256(
         private.projectos_canonical_context_json(context_row.context_envelope)
       )
       and private.projectos_context_hash_matches_contract(
         context_row.context_hash,
         context_row.context_envelope,
         context_row.hash_contract
       ) is true then
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

  if not coalesce(p_context_envelope ?& array[
       'schemaVersion', 'status', 'source', 'namespace', 'retrievedAt',
       'queryHash', 'queryBasis', 'counts', 'highlights', 'warnings'
     ]::text[], false)
     or jsonb_typeof(p_context_envelope -> 'schemaVersion') is distinct from 'string'
     or jsonb_typeof(p_context_envelope -> 'status') is distinct from 'string'
     or jsonb_typeof(p_context_envelope -> 'source') is distinct from 'string'
     or jsonb_typeof(p_context_envelope -> 'namespace') is distinct from 'string'
     or jsonb_typeof(p_context_envelope -> 'retrievedAt') is distinct from 'string'
     or jsonb_typeof(p_context_envelope -> 'queryHash') is distinct from 'string'
     or coalesce(p_context_envelope ->> 'schemaVersion', '') not in ('1.0.0', '2.0.0')
     or p_context_envelope ->> 'source' is distinct from 'pandora-memory'
     or jsonb_typeof(p_context_envelope -> 'queryBasis') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'counts') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'highlights') is distinct from 'object'
     or jsonb_typeof(p_context_envelope -> 'warnings') is distinct from 'array'
     or coalesce(p_context_envelope ->> 'retrievedAt', '')
       !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$' then
    raise exception 'invalid context envelope contract' using errcode = '22023';
  end if;

  begin
    retrieved_timestamp := (p_context_envelope ->> 'retrievedAt')::timestamptz;
  exception when others then
    raise exception 'invalid context envelope contract' using errcode = '22023';
  end;

  context_schema_version := p_context_envelope ->> 'schemaVersion';
  if context_schema_version = '1.0.0' then
    if private.projectos_legacy_node_context_json(p_context_envelope) is null
       or (
         (p_context_envelope ->> 'status' = 'unavailable')
         <> (p_context_envelope ? 'failure')
       ) then
      raise exception 'invalid context envelope contract' using errcode = '22023';
    end if;

    if exists (
      select 1
      from unnest(v1_highlight_keys) key(name)
      where jsonb_array_length(
        p_context_envelope -> 'highlights' -> key.name
      ) > 3
    ) then
      raise exception 'invalid context envelope contract' using errcode = '22023';
    end if;

    if not coalesce((p_context_envelope -> 'counts') ?& v1_count_keys, false)
       or (select count(*) from jsonb_object_keys(p_context_envelope -> 'counts')) <> 5 then
      raise exception 'invalid context counts' using errcode = '22023';
    end if;

    foreach count_key in array v1_count_keys loop
      if jsonb_typeof(p_context_envelope -> 'counts' -> count_key)
           is distinct from 'number' then
        raise exception 'invalid context counts' using errcode = '22023';
      end if;
      count_value := (p_context_envelope -> 'counts' ->> count_key)::numeric;
      if count_value < 0 or count_value > 50 or trunc(count_value) <> count_value then
        raise exception 'invalid context counts' using errcode = '22023';
      end if;
    end loop;

    if p_context_envelope ->> 'status' = 'available' then
      if not (
        exists (
          select 1
          from unnest(v1_count_keys) key(name)
          where (p_context_envelope -> 'counts' ->> key.name)::numeric > 0
        )
        or exists (
          select 1
          from unnest(v1_highlight_keys) key(name)
          where jsonb_array_length(
            p_context_envelope -> 'highlights' -> key.name
          ) > 0
        )
      ) then
        raise exception 'invalid context envelope contract'
          using errcode = '22023';
      end if;
    elsif p_context_envelope ->> 'status' in ('empty', 'unavailable') then
      if exists (
        select 1
        from unnest(v1_count_keys) key(name)
        where (p_context_envelope -> 'counts' ->> key.name)::numeric > 0
      ) or exists (
        select 1
        from unnest(v1_highlight_keys) key(name)
        where jsonb_array_length(
          p_context_envelope -> 'highlights' -> key.name
        ) > 0
      ) then
        raise exception 'invalid context envelope contract'
          using errcode = '22023';
      end if;
    end if;

    if p_context_envelope ->> 'status' = 'unavailable'
       and p_context_envelope -> 'warnings'
         is distinct from '["memory_context_unavailable"]'::jsonb then
      raise exception 'invalid context envelope contract'
        using errcode = '22023';
    end if;
  elsif private.projectos_full_capacity_context_is_valid(p_context_envelope)
      is not true then
    raise exception 'invalid full-capacity context envelope' using errcode = '22023';
  end if;

  if p_context_envelope #>> '{queryBasis,tool}' is distinct from plan.tool then
    raise exception 'context tool does not match execution plan'
      using errcode = '22023';
  end if;

  canonical_context := private.projectos_canonical_context_json(p_context_envelope);
  derived_context_hash := private.projectos_context_json_sha256(canonical_context);

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
    'projectContext', p_context_envelope #> '{counts,projectContext}',
    'riskWarnings', p_context_envelope #> '{counts,riskWarnings}',
    'openLoops', p_context_envelope #> '{counts,openLoops}',
    'recentEvents', p_context_envelope #> '{counts,recentEvents}',
    'semanticMatches', p_context_envelope #> '{counts,semanticMatches}'
  );
  warning_count := jsonb_array_length(p_context_envelope -> 'warnings');
  if warning_count > 10 then
    raise exception 'invalid context warnings' using errcode = '22023';
  end if;

  if p_context_hash is distinct from derived_context_hash then
    raise exception 'context hash does not match canonical envelope'
      using errcode = '22023';
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
    hash_contract,
    canonical_context_hash,
    context_status,
    namespace,
    context_envelope
  ) values (
    plan.id,
    p_organization_id,
    p_request_id,
    p_context_hash,
    'canonical-json-c-utf8-sha256-v1',
    derived_context_hash,
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

commit;
