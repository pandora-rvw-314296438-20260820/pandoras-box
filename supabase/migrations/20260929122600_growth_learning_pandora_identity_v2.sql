-- Normalize FB026/G3 payload identity to the canonical Pandora Memory principal.
-- Existing historical migration remains immutable; no outbox growth rows existed at activation.
begin;

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
    or p_payload->>'product_key' is distinct from 'pandora'
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
    or v_target->>'principal_key' is distinct from 'pandora-mcpmaster-production'
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



comment on function private.pandora_growth_learning_payload_is_valid_v1(jsonb) is
  'Validates Pandora-native growth_learning_v1 payloads bound to pandora-mcpmaster-production.';

commit;
