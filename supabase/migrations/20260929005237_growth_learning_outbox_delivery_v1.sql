-- PANDORA_SECURITY_ACCESS_PATH: Management-only growth enqueue; existing private signed dispatcher/reconciler remain authoritative. No public caller, grant or transport added.
-- PANDORA_SECURITY_ROLLBACK: Stop new growth ingress; preserve queued rows and strict receipt validation for roll-forward. Never drain or reset old deliveries.
-- CLI generated 20260928195755_growth_learning_outbox_delivery_v1.sql.
-- Authorized version normalization to 20260929040000 orders after PR805.
-- Contract source: Memory126 de1a43c709a097010515b98b018d6d5052681d2a.
begin;

create or replace function private.pandora_canonical_json_v1(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path='pg_catalog','private'
as $function$
declare
  v_result text;
  v_raw text;
  v_digits text;
  v_sign text;
  v_exponent integer;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select '{'||coalesce(string_agg(
        to_json(key)::text||':'||private.pandora_canonical_json_v1(value),
        ',' order by key
      ),'')||'}' into v_result
      from jsonb_each(p_value);
    when 'array' then
      select '['||coalesce(string_agg(
        private.pandora_canonical_json_v1(value),',' order by ordinal
      ),'')||']' into v_result
      from jsonb_array_elements(p_value) with ordinality as e(value,ordinal);
    when 'number' then
      v_raw:=p_value::text;
      if v_raw::numeric=0 then
        v_result:='0';
      elsif abs(v_raw::numeric)<0.000001 then
        v_sign:=case when v_raw::numeric<0 then '-' else '' end;
        v_raw:=ltrim(v_raw,'-');
        v_digits:=regexp_replace(split_part(v_raw,'.',2),'^0+','');
        v_exponent:=length(split_part(v_raw,'.',2))-length(v_digits)+1;
        v_digits:=regexp_replace(v_digits,'0+$','');
        v_result:=v_sign||substr(v_digits,1,1)||
          case when length(v_digits)>1 then '.'||substr(v_digits,2) else '' end||
          'e-'||v_exponent::text;
      else
        v_result:=regexp_replace(
          regexp_replace(v_raw,'([.][0-9]*?)0+$','\1'),
          '[.]$',''
        );
      end if;
    else v_result:=p_value::text;
  end case;
  return v_result;
end;
$function$;
revoke all on function private.pandora_canonical_json_v1(jsonb)
  from public,anon,authenticated;
grant execute on function private.pandora_canonical_json_v1(jsonb) to service_role;

-- Rebuild the exact normalized object serialized by the FB025 producer before
-- it computes candidate.content_hash. The key order here intentionally matches
-- JavaScript JSON.stringify insertion order in projectGrowthLearningCandidate.
create or replace function private.pandora_growth_learning_content_json_v1(
  p_candidate jsonb
) returns text
language plpgsql
immutable
strict
set search_path='pg_catalog','private'
as $function$
declare
  v_evidence text;
  v_supersession text;
begin
  select '['||coalesce(string_agg(
    '{"type":'||to_json(value->>'type')::text||
    ',"ref":'||to_json(btrim(value->>'ref'))::text||
    case when value ? 'sha256'
      then ',"sha256":'||to_json(lower(value->>'sha256'))::text else '' end||
    case when value ? 'artifact_class'
      then ',"artifact_class":'||to_json(value->>'artifact_class')::text else '' end||
    case when value ? 'observed_at'
      then ',"observed_at":'||to_json(value->>'observed_at')::text else '' end||
    '}',',' order by ordinal
  ),'')||']' into v_evidence
  from jsonb_array_elements(p_candidate->'evidence_refs')
    with ordinality as e(value,ordinal);

  v_supersession:=case
    when p_candidate->'supersession'='null'::jsonb then 'null'
    else '{"supersedes_ref":'||
      to_json(p_candidate#>>'{supersession,supersedes_ref}')::text||
      ',"reason":'||to_json(btrim(p_candidate#>>'{supersession,reason}'))::text||'}'
  end;

  return '{"schema_version":"growth-learning-v1"'||
    ',"learning_id":'||to_json(p_candidate->>'source_event_id')::text||
    ',"organization_id":'||to_json(p_candidate->>'organization_id')::text||
    ',"project_id":'||to_json(p_candidate->>'project_id')::text||
    ',"subject_key":'||to_json(p_candidate->>'subject_key')::text||
    ',"claim_kind":'||to_json(p_candidate->>'claim_kind')::text||
    ',"statement":'||to_json(btrim(p_candidate->>'claim'))::text||
    ',"observed_at":'||to_json(p_candidate->>'observed_at')::text||
    ',"validity":{"effective_at":'||to_json(p_candidate->>'effective_at')::text||
      ',"review_due_at":'||to_json(p_candidate->>'review_due_at')::text||
      ',"expires_at":'||private.pandora_canonical_json_v1(p_candidate->'expires_at')||'}'||
    ',"confidence":'||private.pandora_canonical_json_v1(p_candidate->'confidence')||
    ',"confidence_basis":'||to_json(btrim(p_candidate->>'confidence_basis'))::text||
    ',"authority":{"kind":'||to_json(p_candidate->>'authority_kind')::text||
      ',"ref":'||to_json(p_candidate->>'authority_ref')::text||'}'||
    ',"provenance":{"source_type":'||
      to_json(p_candidate#>>'{provenance,source_type}')::text||
      ',"source_locator":'||
      to_json(btrim(p_candidate#>>'{provenance,source_locator}'))::text||
      ',"source_sha":'||case
        when p_candidate#>'{provenance,source_sha}'='null'::jsonb then 'null'
        else to_json(btrim(p_candidate#>>'{provenance,source_sha}'))::text end||
      ',"observed_at":'||
      to_json(p_candidate#>>'{provenance,observed_at}')::text||'}'||
    ',"evidence_refs":'||v_evidence||
    ',"supersession":'||v_supersession||'}';
end;
$function$;
revoke all on function private.pandora_growth_learning_content_json_v1(jsonb)
  from public,anon,authenticated;
grant execute on function private.pandora_growth_learning_content_json_v1(jsonb) to service_role;

create or replace function private.pandora_growth_learning_payload_is_valid_v1(p_payload jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path=''
as $function$
declare
  v_binding jsonb;
  v_source_scope jsonb;
  v_target jsonb;
  v_candidate jsonb;
  v_expected_context_hash text;
  v_expected_content_hash text;
  v_request_hash text;
  v_request_bytes bytea;
  v_expected_request_id text;
  v_key text;
  v_item jsonb;
  v_stamp text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
    or octet_length(p_payload::text)>131072
    or not (p_payload ?& array[
      'schema_version','product_key','source_event_id','source_request_id',
      'organization_id','intake_id','project_id','project_key','tool','risk',
      'outcome_status','duration_ms','completed_at','context_status','context_hash',
      'result_fingerprint','error_fingerprint','privacy_policy','learning_kind',
      'growth_learning'
    ])
    or p_payload - array[
      'schema_version','product_key','source_event_id','source_request_id',
      'organization_id','intake_id','project_id','project_key','tool','risk',
      'outcome_status','duration_ms','completed_at','context_status','context_hash',
      'result_fingerprint','error_fingerprint','privacy_policy','learning_kind',
      'growth_learning'
    ] <> '{}'::jsonb then
    return false;
  end if;

  v_binding:=p_payload->'growth_learning';
  if jsonb_typeof(v_binding) is distinct from 'object'
    or not (v_binding ?& array['schema_version','source_scope','target_memory','candidate'])
    or v_binding-array['schema_version','source_scope','target_memory','candidate']<>'{}'::jsonb then
    return false;
  end if;
  if v_binding::text ~* '(authorization[[:space:]]*[:=][[:space:]]*(bearer|basic)|\\m(github_pat_|gh[pousr]_[a-z0-9_]{16,}|sb_secret_|AIza[a-z0-9_-]{20,}|sk-[a-z0-9_-]{16,})|-----BEGIN [^-]*PRIVATE KEY)' then
    return false;
  end if;
  v_source_scope:=v_binding->'source_scope';
  v_target:=v_binding->'target_memory';
  v_candidate:=v_binding->'candidate';
  if jsonb_typeof(v_source_scope) is distinct from 'object'
    or not (v_source_scope ?& array['organization_id','project_id'])
    or v_source_scope-array['organization_id','project_id']<>'{}'::jsonb
    or jsonb_typeof(v_target) is distinct from 'object'
    or not (v_target ?& array['project_id','project_key','namespace','principal_key','environment'])
    or v_target-array['project_id','project_key','namespace','principal_key','environment']<>'{}'::jsonb
    or jsonb_typeof(v_candidate) is distinct from 'object'
    or not (v_candidate ?& array[
      'schema_version','learning_kind','source_event_id','organization_id','project_id',
      'subject_key','claim_kind','claim','observed_at','effective_at','review_due_at',
      'expires_at','confidence','confidence_basis','authority_kind','authority_ref',
      'provenance','evidence_refs','supersession','content_hash','review_required',
      'canonical_memory_written'
    ])
    or v_candidate-array[
      'schema_version','learning_kind','source_event_id','organization_id','project_id',
      'subject_key','claim_kind','claim','observed_at','effective_at','review_due_at',
      'expires_at','confidence','confidence_basis','authority_kind','authority_ref',
      'provenance','evidence_refs','supersession','content_hash','review_required',
      'canonical_memory_written'
    ]<>'{}'::jsonb then
    return false;
  end if;

  -- JSON text accessors coerce numbers/booleans. Require the original types
  -- before rebuilding the JavaScript producer's normalized content.
  foreach v_key in array array[
    'schema_version','learning_kind','source_event_id','organization_id','project_id',
    'subject_key','claim_kind','claim','observed_at','effective_at','review_due_at',
    'confidence_basis','authority_kind','authority_ref','content_hash'
  ] loop
    if jsonb_typeof(v_candidate->v_key) is distinct from 'string' then return false; end if;
  end loop;
  if jsonb_typeof(v_candidate->'confidence') is distinct from 'number'
    or jsonb_typeof(v_candidate->'evidence_refs') is distinct from 'array'
    or jsonb_typeof(v_candidate->'provenance') is distinct from 'object'
    or not (v_candidate->'expires_at'='null'::jsonb
      or jsonb_typeof(v_candidate->'expires_at')='string') then return false; end if;

  if p_payload->'schema_version' is distinct from '1'::jsonb
    or p_payload->>'product_key' is distinct from 'projectos'
    or p_payload->>'learning_kind' is distinct from 'growth_learning_v1'
    or p_payload->>'tool' is distinct from 'facebook.growth_learning'
    or p_payload->>'risk' is distinct from 'write'
    or p_payload->>'outcome_status' is distinct from 'completed'
    or p_payload->'duration_ms' is distinct from '0'::jsonb
    or p_payload->>'context_status' is distinct from 'available'
    or p_payload->>'privacy_policy' is distinct from 'metadata_only_v1'
    or p_payload->'intake_id' is distinct from 'null'::jsonb
    or p_payload->'error_fingerprint' is distinct from 'null'::jsonb
    or p_payload->>'source_event_id' is distinct from p_payload->>'source_request_id'
    or not coalesce(p_payload->>'source_event_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false)
    or not coalesce(p_payload->>'context_hash' ~ '^[0-9a-f]{64}$',false)
    or not coalesce(p_payload->>'result_fingerprint' ~ '^[0-9a-f]{64}$',false)
    or p_payload->>'completed_at' is distinct from v_candidate->>'observed_at'
    or p_payload->>'result_fingerprint' is distinct from v_candidate->>'content_hash'
    or p_payload->>'organization_id' is distinct from v_candidate->>'organization_id'
    or p_payload->>'project_id' is distinct from '7c686cbd-d968-49d5-86cc-918f5e777bd2'
    or p_payload->>'project_key' is distinct from 'mcpmaster-pandoras-box'
    or v_binding->>'schema_version' is distinct from 'growth-learning-outbox-binding-v1'
    or v_source_scope->>'organization_id' is distinct from v_candidate->>'organization_id'
    or v_source_scope->>'project_id' is distinct from v_candidate->>'project_id'
    or v_target->>'project_id' is distinct from '7c686cbd-d968-49d5-86cc-918f5e777bd2'
    or v_target->>'project_key' is distinct from 'mcpmaster-pandoras-box'
    or v_target->>'namespace' is distinct from 'real_life'
    or v_target->>'principal_key' is distinct from 'projectos-mcpmaster-production'
    or v_target->>'environment' is distinct from 'production'
    or v_candidate->>'schema_version' is distinct from 'growth-learning-candidate-v1'
    or v_candidate->>'learning_kind' is distinct from 'growth_learning_v1'
    or v_candidate->'review_required' is distinct from 'true'::jsonb
    or v_candidate->'canonical_memory_written' is distinct from 'false'::jsonb
    or not coalesce(v_candidate->>'organization_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false)
    or not coalesce(v_candidate->>'project_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false)
    or not coalesce(v_candidate->>'source_event_id' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false)
    or not coalesce(v_candidate->>'subject_key' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false)
    or not coalesce(length(trim(v_candidate->>'claim')) between 1 and 1800,false)
    or v_candidate->>'claim' is distinct from btrim(v_candidate->>'claim')
    or not coalesce(length(trim(v_candidate->>'confidence_basis')) between 1 and 1000,false)
    or v_candidate->>'confidence_basis' is distinct from btrim(v_candidate->>'confidence_basis')
    or not coalesce(v_candidate->>'claim_kind' in ('verified_fact','user_decision','provider_evidence','inference','assumption','superseded'),false)
    or jsonb_typeof(v_candidate->'confidence') is distinct from 'number'
    or (v_candidate->>'confidence')::numeric not between 0 and 1
    or (v_candidate->>'claim_kind'='assumption' and (v_candidate->>'confidence')::numeric>0.5)
    or jsonb_typeof(v_candidate->'provenance') is distinct from 'object'
    or jsonb_typeof(v_candidate->'evidence_refs') is distinct from 'array'
    or jsonb_array_length(v_candidate->'evidence_refs')>32
    or not coalesce(v_candidate->>'content_hash' ~ '^[0-9a-f]{64}$',false) then
    return false;
  end if;

  if not coalesce(v_candidate->>'observed_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false)
    or not coalesce(v_candidate->>'effective_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false)
    or not coalesce(v_candidate->>'review_due_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false)
    or not (
      v_candidate->'expires_at'='null'::jsonb
      or coalesce(v_candidate->>'expires_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false)
    )
    or not coalesce(v_candidate->>'authority_ref' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false)
    or jsonb_typeof(v_candidate->'provenance') is distinct from 'object'
    or not ((v_candidate->'provenance') ?& array['source_type','source_locator','source_sha','observed_at'])
    or (v_candidate->'provenance')-array['source_type','source_locator','source_sha','observed_at']<>'{}'::jsonb
    or not coalesce(v_candidate#>>'{provenance,source_type}' in ('provider','document','repository','owner','verification','model'),false)
    or not coalesce(length(trim(v_candidate#>>'{provenance,source_locator}')) between 1 and 1000,false)
    or v_candidate#>>'{provenance,source_locator}' is distinct from
      btrim(v_candidate#>>'{provenance,source_locator}')
    or not (
      v_candidate#>'{provenance,source_sha}'='null'::jsonb
      or (coalesce(v_candidate#>>'{provenance,source_sha}' ~ '^[0-9a-fA-F]{7,64}$',false)
        and v_candidate#>>'{provenance,source_sha}' is not distinct from
          btrim(v_candidate#>>'{provenance,source_sha}'))
    )
    or not coalesce(v_candidate#>>'{provenance,observed_at}' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false)
    or exists (
      select 1 from jsonb_array_elements(v_candidate->'evidence_refs') e(value)
      where jsonb_typeof(value) is distinct from 'object'
        or not (value ?& array['type','ref'])
        or value-array['type','ref','sha256','artifact_class','observed_at']<>'{}'::jsonb
        or not coalesce(value->>'type' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false)
        or not coalesce(length(trim(value->>'ref')) between 1 and 1000,false)
        or value->>'ref' is distinct from btrim(value->>'ref')
        or (value ? 'sha256' and not coalesce(value->>'sha256' ~ '^[0-9a-fA-F]{64}$',false))
        or (value ? 'sha256' and value->>'sha256' is distinct from lower(value->>'sha256'))
        or (value ? 'artifact_class' and not coalesce(value->>'artifact_class' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false))
        or (value ? 'observed_at' and not coalesce(value->>'observed_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$',false))
    ) then
    return false;
  end if;

  -- Phase A is authorized only for the D004 Pandora source tenant/project.
  -- Reject any other internally consistent source scope before querying durable
  -- project, principal, grant, candidate, or review state.
  if p_payload->>'organization_id' is distinct from '2270b266-59da-4c39-bfd9-9f8d08352af0'
    or v_source_scope->>'organization_id' is distinct from '2270b266-59da-4c39-bfd9-9f8d08352af0'
    or v_candidate->>'organization_id' is distinct from '2270b266-59da-4c39-bfd9-9f8d08352af0'
    or v_source_scope->>'project_id' is distinct from 'ee282126-3f61-4058-8c92-2fedbfcecf1f'
    or v_candidate->>'project_id' is distinct from 'ee282126-3f61-4058-8c92-2fedbfcecf1f' then
    return false;
  end if;

  if not coalesce(case v_candidate->>'claim_kind'
      when 'verified_fact' then v_candidate->>'authority_kind' in ('provider_readback','independent_verification','authoritative_record')
      when 'user_decision' then v_candidate->>'authority_kind' in ('owner_decision','authorized_user_decision')
      when 'provider_evidence' then v_candidate->>'authority_kind'='provider_readback'
      when 'inference' then v_candidate->>'authority_kind'='model_inference'
      when 'assumption' then v_candidate->>'authority_kind'='assumption'
      when 'superseded' then v_candidate->>'authority_kind'='supersession'
      else false
    end,false) then
    return false;
  end if;

  v_expected_context_hash:=encode(extensions.digest(
    convert_to(private.pandora_canonical_json_v1(v_binding),'UTF8'),'sha256'
  ),'hex');
  v_request_hash:=encode(extensions.digest(
    convert_to('growth-learning-request-v1'||chr(10)||v_expected_context_hash,'UTF8'),
    'sha256'
  ),'hex');
  v_request_bytes:=decode(substr(v_request_hash,1,32),'hex');
  v_request_bytes:=set_byte(v_request_bytes,6,(get_byte(v_request_bytes,6)&15)|80);
  v_request_bytes:=set_byte(v_request_bytes,8,(get_byte(v_request_bytes,8)&63)|128);
  v_request_hash:=encode(v_request_bytes,'hex');
  v_expected_request_id:=substr(v_request_hash,1,8)||'-'||substr(v_request_hash,9,4)||'-'||
    substr(v_request_hash,13,4)||'-'||substr(v_request_hash,17,4)||'-'||substr(v_request_hash,21,12);
  if p_payload->>'context_hash' is distinct from v_expected_context_hash
    or p_payload->>'source_event_id' is distinct from v_expected_request_id then
    return false;
  end if;

  begin
    if (v_candidate->>'effective_at')::timestamptz>(v_candidate->>'review_due_at')::timestamptz
      or (v_candidate->'expires_at'<>'null'::jsonb
        and (v_candidate->>'review_due_at')::timestamptz>(v_candidate->>'expires_at')::timestamptz) then
      return false;
    end if;
  exception when invalid_datetime_format then
    return false;
  end;

  if (v_candidate->>'claim_kind' in ('verified_fact','provider_evidence','superseded')
      and jsonb_array_length(v_candidate->'evidence_refs')=0)
    or (v_candidate->>'claim_kind'='assumption' and jsonb_array_length(v_candidate->'evidence_refs')<>0)
    or (v_candidate->>'claim_kind'='provider_evidence' and v_candidate#>>'{provenance,source_type}'<>'provider')
    or (v_candidate->>'claim_kind'='user_decision' and v_candidate#>>'{provenance,source_type}' not in ('owner','document'))
    or (v_candidate->>'claim_kind'='inference' and v_candidate#>>'{provenance,source_type}'<>'model')
    or (v_candidate->>'claim_kind'='superseded' and (
      jsonb_typeof(v_candidate->'supersession') is distinct from 'object'
      or not ((v_candidate->'supersession') ?& array['supersedes_ref','reason'])
      or (v_candidate->'supersession')-array['supersedes_ref','reason']<>'{}'::jsonb
      or not coalesce(v_candidate#>>'{supersession,supersedes_ref}' ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$',false)
      or not coalesce(length(trim(v_candidate#>>'{supersession,reason}')) between 3 and 1000,false)
      or v_candidate#>>'{supersession,reason}' is distinct from
        btrim(v_candidate#>>'{supersession,reason}')
    ))
    or (v_candidate->>'claim_kind'<>'superseded' and v_candidate->'supersession'<>'null'::jsonb) then
    return false;
  end if;

  v_expected_content_hash:=encode(extensions.digest(
    convert_to(private.pandora_growth_learning_content_json_v1(v_candidate),'UTF8'),
    'sha256'
  ),'hex');
  if v_candidate->>'content_hash' is distinct from v_expected_content_hash
    or p_payload->>'result_fingerprint' is distinct from v_expected_content_hash then
    return false;
  end if;

  foreach v_key in array array['source_type','source_locator','observed_at'] loop
    if jsonb_typeof(v_candidate->'provenance'->v_key) is distinct from 'string' then return false; end if;
  end loop;
  if not (v_candidate#>'{provenance,source_sha}'='null'::jsonb
    or jsonb_typeof(v_candidate#>'{provenance,source_sha}')='string') then return false; end if;
  for v_item in select value from jsonb_array_elements(v_candidate->'evidence_refs') loop
    foreach v_key in array array['type','ref','sha256','artifact_class','observed_at'] loop
      if (v_item ? v_key) and jsonb_typeof(v_item->v_key) is distinct from 'string' then return false; end if;
    end loop;
  end loop;
  if v_candidate->>'claim_kind'='superseded' and (
    jsonb_typeof(v_candidate#>'{supersession,supersedes_ref}') is distinct from 'string'
    or jsonb_typeof(v_candidate#>'{supersession,reason}') is distinct from 'string'
  ) then return false; end if;

  -- Reject normalized-by-Postgres invalid calendar inputs, including fields not
  -- used by the validity ordering comparison. The producer requires exact UTC.
  for v_stamp in
    select value from (values
      (v_candidate->>'observed_at'),(v_candidate->>'effective_at'),
      (v_candidate->>'review_due_at'),(v_candidate->>'expires_at'),
      (v_candidate#>>'{provenance,observed_at}')
    ) s(value) where value is not null
    union all
    select value->>'observed_at' from jsonb_array_elements(v_candidate->'evidence_refs')
      where value ? 'observed_at'
  loop
    if to_char(v_stamp::timestamptz at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') is distinct from v_stamp then return false; end if;
  end loop;
  return true;
exception
  when data_exception or program_limit_exceeded then
    -- Invalid JSON shapes, numeric/date casts, or excessively nested payloads
    -- are data failures. Undefined functions/tables and ACL errors still surface.
    return false;
end;
$function$;

revoke all on function private.pandora_growth_learning_payload_is_valid_v1(jsonb)
  from public,anon,authenticated;
-- The existing response validator is invoker-rights and service-callable.
-- Its pure dependency chain must retain that capability without exposing enqueue.
grant execute on function private.pandora_growth_learning_payload_is_valid_v1(jsonb) to service_role;


-- Content-hash event keys are deterministic delivery identities. A separate
-- stable learning identity prevents a changed semantic payload from entering
-- a second row before the Memory intake can reject it.
create unique index if not exists execution_learning_outbox_growth_identity_v1
  on private.execution_learning_outbox(
    organization_id,project_id,(payload#>>'{growth_learning,candidate,source_event_id}')
  )
  where payload->>'learning_kind'='growth_learning_v1';

create or replace function private.enqueue_growth_learning_v1(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_candidate jsonb;
  v_org uuid;
  v_project uuid;
  v_request uuid;
  v_event_key text;
  v_source_identity text;
  v_existing private.execution_learning_outbox%rowtype;
  v_outbox_id uuid;
begin
  if private.pandora_growth_learning_payload_is_valid_v1(p_payload) is not true then
    raise exception 'GROWTH_LEARNING_OUTBOX_PAYLOAD_INVALID' using errcode='22023';
  end if;
  v_candidate:=p_payload#>'{growth_learning,candidate}';
  v_org:=(v_candidate->>'organization_id')::uuid;
  v_project:=(v_candidate->>'project_id')::uuid;
  v_request:=(p_payload->>'source_event_id')::uuid;
  v_event_key:='growth:'||v_org::text||':'||v_project::text||':'||
    (v_candidate->>'source_event_id')||':'||(v_candidate->>'content_hash');
  v_source_identity:=v_org::text||'|'||v_project::text||'|'||
    (v_candidate->>'source_event_id');
  perform pg_advisory_xact_lock(hashtextextended('growth-learning-outbox-v1|'||v_source_identity,0));

  select * into v_existing from private.execution_learning_outbox
  where organization_id=v_org and project_id=v_project
    and payload->>'learning_kind'='growth_learning_v1'
    and payload#>>'{growth_learning,candidate,source_event_id}'=v_candidate->>'source_event_id'
  for update;
  if v_existing.id is not null then
    if v_existing.payload is distinct from p_payload
      or v_existing.event_key is distinct from v_event_key
      or v_existing.request_id is distinct from v_request
      or v_existing.plan_id is not null or v_existing.intake_id is not null
      or v_existing.project_key is distinct from 'mcpmaster-pandoras-box' then
      raise exception 'GROWTH_LEARNING_OUTBOX_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into private.execution_learning_outbox(
    plan_id,event_key,organization_id,request_id,intake_id,project_id,project_key,
    payload,delivery_status,attempt_count,next_attempt_at,created_at,updated_at
  ) values (
    null,v_event_key,v_org,v_request,null,v_project,'mcpmaster-pandoras-box',
    p_payload,'pending',0,now(),now(),now()
  )
  on conflict do nothing
  returning id into v_outbox_id;
  if v_outbox_id is null then
    -- Handles a direct concurrent writer without rewriting either payload.
    select * into v_existing from private.execution_learning_outbox
    where organization_id=v_org and project_id=v_project
      and payload->>'learning_kind'='growth_learning_v1'
      and payload#>>'{growth_learning,candidate,source_event_id}'=v_candidate->>'source_event_id'
    for update;
    if v_existing.id is null or v_existing.payload is distinct from p_payload
      or v_existing.event_key is distinct from v_event_key
      or v_existing.request_id is distinct from v_request
      or v_existing.plan_id is not null or v_existing.intake_id is not null
      or v_existing.project_key is distinct from 'mcpmaster-pandoras-box' then
      raise exception 'GROWTH_LEARNING_OUTBOX_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return v_existing.id;
  end if;
  return v_outbox_id;
end;
$function$;

revoke all on function private.enqueue_growth_learning_v1(jsonb)
  from public,anon,authenticated,service_role;

create or replace function private.execution_learning_response_is_valid(
  p_payload jsonb,
  p_status integer,
  p_content text,
  p_error text,
  p_timed_out boolean
)
returns boolean
language plpgsql
immutable
set search_path=''
as $function$
declare
  v_body jsonb;
  v_key text;
  v_kind text:=coalesce(p_payload->>'learning_kind','');
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
    or (p_payload ? 'learning_kind' and (
      jsonb_typeof(p_payload->'learning_kind') is distinct from 'string'
      or coalesce(p_payload->>'learning_kind','')=''
    )) then return false; end if;
  if p_status is null
     or p_status not in (200,202)
     or coalesce(p_timed_out,false)
     or p_error is not null then
    return false;
  end if;

  -- Signed growth markers must not downgrade to the generic HTTP-success path.
  if v_kind='growth_learning_v1'
    or p_payload->>'tool'='facebook.growth_learning'
    or p_payload ? 'growth_learning' then
    if v_kind<>'growth_learning_v1'
      or private.pandora_growth_learning_payload_is_valid_v1(p_payload) is not true then
      return false;
    end if;
    begin
      v_body:=p_content::jsonb;
    exception when data_exception or program_limit_exceeded then
      return false;
    end;
    if v_body->>'status'='already_reviewed' then
      if p_status<>200
        or jsonb_typeof(v_body) is distinct from 'object'
        or not (v_body ?& array[
          'ok','status','source_event_id','learning_id','content_hash',
          'candidate_id','review_item_id','review_status','deduplicated'
        ])
        or v_body-array[
          'ok','status','source_event_id','learning_id','content_hash',
          'candidate_id','review_item_id','review_status','deduplicated'
        ]<>'{}'::jsonb then return false; end if;
      foreach v_key in array array[
        'status','source_event_id','learning_id','content_hash','candidate_id',
        'review_item_id','review_status'
      ] loop
        if jsonb_typeof(v_body->v_key) is distinct from 'string' then return false; end if;
      end loop;
      return v_body->'ok' is not distinct from 'true'::jsonb
        and v_body->>'source_event_id' is not distinct from p_payload->>'source_event_id'
        and v_body->>'learning_id' is not distinct from p_payload#>>'{growth_learning,candidate,source_event_id}'
        and v_body->>'content_hash' is not distinct from p_payload#>>'{growth_learning,candidate,content_hash}'
        and coalesce(lower(v_body->>'candidate_id') ~ v_uuid_pattern,false)
        and coalesce(lower(v_body->>'review_item_id') ~ v_uuid_pattern,false)
        and v_body->>'review_status' in (
          'needs_clarification','blocked_namespace_mismatch','blocked_sensitive',
          'blocked_policy','approved_for_append','rejected','archived'
        )
        and v_body->'deduplicated' is not distinct from 'true'::jsonb;
    end if;

    if jsonb_typeof(v_body) is distinct from 'object'
      or not (v_body ?& array[
        'ok','status','source_event_id','learning_id','content_hash',
        'candidate_id','review_item_id','review_required','canonical_memory_written',
        'promotion_status','retrieval_status','deduplicated'
      ])
      or v_body-array[
        'ok','status','source_event_id','learning_id','content_hash',
        'candidate_id','review_item_id','review_required','canonical_memory_written',
        'promotion_status','retrieval_status','deduplicated'
      ]<>'{}'::jsonb then return false; end if;
    foreach v_key in array array[
      'status','source_event_id','learning_id','content_hash','candidate_id',
      'review_item_id','promotion_status','retrieval_status'
    ] loop
      if jsonb_typeof(v_body->v_key) is distinct from 'string' then return false; end if;
    end loop;
    return v_body->'ok' is not distinct from 'true'::jsonb
      and v_body->>'status' is not distinct from 'pending_review'
      and v_body->>'source_event_id' is not distinct from p_payload->>'source_event_id'
      and v_body->>'learning_id' is not distinct from p_payload#>>'{growth_learning,candidate,source_event_id}'
      and v_body->>'content_hash' is not distinct from p_payload#>>'{growth_learning,candidate,content_hash}'
      and coalesce(lower(v_body->>'candidate_id') ~ v_uuid_pattern,false)
      and coalesce(lower(v_body->>'review_item_id') ~ v_uuid_pattern,false)
      and v_body->'review_required' is not distinct from 'true'::jsonb
      and v_body->'canonical_memory_written' is not distinct from 'false'::jsonb
      and v_body->>'promotion_status' is not distinct from 'not_promoted'
      and v_body->>'retrieval_status' is not distinct from 'not_retrievable'
      and jsonb_typeof(v_body->'deduplicated')='boolean';
  end if;

  if v_kind='' then return true; end if;
  if v_kind not in (
    'visible_creation_evidence_v1',
    'visible_creation_decision_influence_v1',
    'visible_creation_decision_outcome_v1'
  ) then
    return false;
  end if;
  begin
    v_body:=p_content::jsonb;
  exception when others then
    return false;
  end;

  if v_kind='visible_creation_evidence_v1' then
    return coalesce(v_body->>'ok','')='true'
      and coalesce(v_body->>'review_required','')='true'
      and coalesce(v_body->>'canonical_memory_written','')='false'
      and lower(coalesce(v_body->>'source_event_id',''))=lower(coalesce(p_payload->>'source_event_id',''))
      and lower(coalesce(v_body->>'visible_project_id',''))=lower(coalesce(p_payload->>'visible_project_id',''))
      and coalesce(v_body->>'evidence_kind','')=coalesce(p_payload->>'evidence_kind','')
      and coalesce(v_body->>'proof_stage','')=coalesce(p_payload->>'proof_stage','')
      and lower(coalesce(v_body->>'candidate_id','')) ~ v_uuid_pattern
      and lower(coalesce(v_body->>'review_item_id','')) ~ v_uuid_pattern;
  end if;

  if coalesce(v_body->>'ok','')<>'true'
     or coalesce(v_body->>'canonical_memory_written','')<>'false'
     or lower(coalesce(v_body->>'source_event_id',''))<>lower(coalesce(p_payload->>'source_event_id',''))
     or lower(coalesce(v_body->>'visible_project_id',''))<>lower(coalesce(p_payload->>'visible_project_id',''))
     or lower(coalesce(v_body->>'receipt_id',''))<>lower(coalesce(p_payload->>'receipt_id',''))
     or lower(coalesce(v_body->>'retrieval_log_id',''))<>lower(coalesce(p_payload->>'retrieval_log_id',''))
     or coalesce(v_body->>'decision_type','')<>coalesce(p_payload->>'decision_type','')
     or lower(coalesce(v_body->>'decision_id',''))<>lower(coalesce(p_payload->>'decision_id',''))
     or coalesce(v_body->'approved_memory_item_ids','[]'::jsonb)<>coalesce(p_payload->'approved_memory_item_ids','[]'::jsonb)
     or lower(coalesce(v_body->>'retrieval_log_id','')) !~ v_uuid_pattern
     or lower(coalesce(v_body->>'decision_id','')) !~ v_uuid_pattern then
    return false;
  end if;

  if v_kind='visible_creation_decision_influence_v1' then
    return coalesce(v_body->>'status','')='decision_context_bound'
      and coalesce(v_body->>'decision_run_id','')=coalesce(p_payload->>'decision_run_id','');
  end if;

  return coalesce(v_body->>'status','')='decision_outcome_recorded'
    and lower(coalesce(v_body->>'outcome_run_id',''))=lower(coalesce(p_payload->>'outcome_run_id',''))
    and coalesce(v_body->>'outcome_status','')=coalesce(p_payload->>'outcome_status_detail','')
    and lower(coalesce(v_body->>'outcome_run_id','')) ~ v_uuid_pattern;
end;
$function$;

revoke all on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  from public,anon,authenticated;
grant execute on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  to service_role;

commit;

