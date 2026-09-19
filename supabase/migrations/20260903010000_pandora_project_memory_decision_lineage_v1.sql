
begin;

-- Non-authoritative evidence receipt for the exact approved Memory context
-- consulted before a ProjectSpec or build decision. ProjectSpec/BuildJob remain
-- the lifecycle authorities; this table only preserves retrieval provenance.
create table if not exists private.pandora_project_memory_context_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  source_intent_id uuid not null references public.pandora_project_intents(id) on delete cascade,
  decision_type text not null check (decision_type in ('project_spec','build','repair')),
  memory_project_id uuid,
  memory_project_key text not null,
  context_status text not null check (context_status in ('available','empty','unavailable')),
  context_hash text not null check (context_hash ~ '^[0-9a-f]{64}$'),
  retrieval_log_id uuid,
  approved_memory_item_ids uuid[] not null default '{}'::uuid[],
  context_envelope jsonb not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint pandora_project_memory_context_receipts_shape check (
    jsonb_typeof(context_envelope)='object'
    and context_envelope->>'schemaVersion'='1.0.0'
    and context_envelope->>'source'='pandora-memory'
    and context_envelope->>'namespace'='real_life'
    and context_envelope->>'status'=context_status
    and jsonb_typeof(context_envelope->'queryBasis')='object'
    and jsonb_typeof(context_envelope#>'{queryBasis,identifiers}')='object'
    and cardinality(approved_memory_item_ids) <= 50
    and (
      (context_status='available' and memory_project_id is not null and retrieval_log_id is not null and cardinality(approved_memory_item_ids) >= 1)
      or (context_status='empty' and memory_project_id is not null and retrieval_log_id is not null and cardinality(approved_memory_item_ids)=0)
      or (context_status='unavailable' and retrieval_log_id is null and cardinality(approved_memory_item_ids)=0)
    )
  ),
  constraint pandora_project_memory_context_receipts_exact unique (source_intent_id,decision_type,context_hash)
);

create index if not exists pandora_project_memory_context_receipts_lookup_idx
  on private.pandora_project_memory_context_receipts(source_intent_id,decision_type,created_at desc);

revoke all on private.pandora_project_memory_context_receipts from public,anon,authenticated;
grant select,insert on private.pandora_project_memory_context_receipts to service_role;

create or replace function private.pandora_project_memory_receipt_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'PANDORA_MEMORY_CONTEXT_RECEIPT_IMMUTABLE' using errcode='55000';
end;
$$;

drop trigger if exists pandora_project_memory_receipt_immutable_v1 on private.pandora_project_memory_context_receipts;
create trigger pandora_project_memory_receipt_immutable_v1
before update or delete on private.pandora_project_memory_context_receipts
for each row execute function private.pandora_project_memory_receipt_immutable_v1();

create or replace function public.pandora_record_project_memory_context_v1(
  p_source_intent_id uuid,
  p_decision_type text,
  p_memory_project_id uuid,
  p_memory_project_key text,
  p_context_status text,
  p_context_hash text,
  p_retrieval_log_id uuid,
  p_approved_memory_item_ids uuid[],
  p_context_envelope jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,private,public,auth,extensions
as $$
declare
  v_user uuid:=auth.uid();
  v_intent public.pandora_project_intents%rowtype;
  v_project public.projectos_projects%rowtype;
  v_expected_memory_key text;
  v_hash text;
  v_retrieved_at timestamptz;
  v_receipt_id uuid;
begin
  if v_user is null then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  if p_source_intent_id is null or p_decision_type not in ('project_spec','build','repair') then
    raise exception 'MEMORY_CONTEXT_REQUEST_INVALID' using errcode='22023';
  end if;

  select * into v_intent from public.pandora_project_intents where id=p_source_intent_id;
  if v_intent.id is null then raise exception 'INTENT_NOT_AVAILABLE' using errcode='P0002'; end if;
  select * into v_project from public.projectos_projects
    where id=v_intent.project_id and organization_id=v_intent.organization_id;
  if v_project.id is null or not private.is_org_member(v_project.organization_id) then
    raise exception 'PROJECT_ACCESS_REQUIRED' using errcode='42501';
  end if;

  v_expected_memory_key:=case when v_project.project_key='mcpmaster' then 'mcpmaster-pandoras-box' else v_project.project_key end;
  if p_memory_project_key is null or p_memory_project_key<>v_expected_memory_key
     or p_context_status not in ('available','empty','unavailable')
     or p_context_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_context_envelope) is distinct from 'object'
     or p_context_envelope->>'schemaVersion'<>'1.0.0'
     or p_context_envelope->>'source'<>'pandora-memory'
     or p_context_envelope->>'namespace'<>'real_life'
     or p_context_envelope->>'status'<>p_context_status
     or p_context_envelope#>>'{queryBasis,identifiers,projectKey}'<>p_memory_project_key
     or p_context_envelope#>>'{queryBasis,identifiers,projectId}'<>v_project.id::text
     or p_context_envelope#>>'{queryBasis,tool}'<>('visible_creation.'||p_decision_type)
     or coalesce(cardinality(p_approved_memory_item_ids),0)>50 then
    raise exception 'MEMORY_CONTEXT_RECEIPT_INVALID' using errcode='22023';
  end if;

  v_hash:=private.projectos_context_json_sha256(private.projectos_canonical_context_json(p_context_envelope));
  if v_hash<>p_context_hash then raise exception 'MEMORY_CONTEXT_HASH_MISMATCH' using errcode='22023'; end if;
  begin v_retrieved_at:=(p_context_envelope->>'retrievedAt')::timestamptz;
  exception when others then raise exception 'MEMORY_CONTEXT_TIMESTAMP_INVALID' using errcode='22023'; end;
  if v_retrieved_at is null or v_retrieved_at < clock_timestamp()-interval '10 minutes'
     or v_retrieved_at > clock_timestamp()+interval '1 minute' then
    raise exception 'MEMORY_CONTEXT_STALE' using errcode='22023';
  end if;

  if p_context_status='available' then
    if p_memory_project_id is null or p_retrieval_log_id is null or coalesce(cardinality(p_approved_memory_item_ids),0)<1 then
      raise exception 'MEMORY_CONTEXT_LINEAGE_REQUIRED' using errcode='22023';
    end if;
  elsif p_context_status='empty' then
    if p_memory_project_id is null or p_retrieval_log_id is null or coalesce(cardinality(p_approved_memory_item_ids),0)<>0 then
      raise exception 'MEMORY_CONTEXT_EMPTY_INVALID' using errcode='22023';
    end if;
  else
    if p_retrieval_log_id is not null or coalesce(cardinality(p_approved_memory_item_ids),0)<>0 then
      raise exception 'MEMORY_CONTEXT_UNAVAILABLE_INVALID' using errcode='22023';
    end if;
  end if;

  insert into private.pandora_project_memory_context_receipts(
    organization_id,project_id,source_intent_id,decision_type,memory_project_id,memory_project_key,
    context_status,context_hash,retrieval_log_id,approved_memory_item_ids,context_envelope,created_by
  ) values (
    v_project.organization_id,v_project.id,v_intent.id,p_decision_type,p_memory_project_id,p_memory_project_key,
    p_context_status,p_context_hash,p_retrieval_log_id,coalesce(p_approved_memory_item_ids,'{}'::uuid[]),p_context_envelope,v_user
  ) on conflict (source_intent_id,decision_type,context_hash) do nothing
  returning id into v_receipt_id;

  if v_receipt_id is null then
    select id into v_receipt_id from private.pandora_project_memory_context_receipts
    where source_intent_id=v_intent.id and decision_type=p_decision_type and context_hash=p_context_hash;
  end if;

  return jsonb_build_object(
    'receiptId',v_receipt_id,'organizationId',v_project.organization_id,'projectId',v_project.id,
    'sourceIntentId',v_intent.id,'decisionType',p_decision_type,'memoryProjectId',p_memory_project_id,
    'memoryProjectKey',p_memory_project_key,'contextStatus',p_context_status,'contextHash',p_context_hash,
    'retrievalLogId',p_retrieval_log_id,'approvedMemoryItemIds',to_jsonb(coalesce(p_approved_memory_item_ids,'{}'::uuid[]))
  );
end;
$$;
revoke all on function public.pandora_record_project_memory_context_v1(uuid,text,uuid,text,text,text,uuid,uuid[],jsonb) from public,anon;
grant execute on function public.pandora_record_project_memory_context_v1(uuid,text,uuid,text,text,text,uuid,uuid[],jsonb) to authenticated,service_role;

create or replace function private.pandora_memory_decision_influence_basis_v1(
  p_memory_project_id uuid,p_memory_project_key text,p_retrieval_log_id uuid,p_receipt_id uuid,
  p_decision_type text,p_decision_id uuid,p_decision_run_id uuid,p_approved_memory_item_ids uuid[]
) returns text language sql immutable set search_path='' as $$
  select array_to_string(array[
    'visible-creation-decision-influence-v1',coalesce(p_memory_project_id::text,''),coalesce(p_memory_project_key,''),
    coalesce(p_retrieval_log_id::text,''),coalesce(p_receipt_id::text,''),coalesce(p_decision_type,''),
    coalesce(p_decision_id::text,''),coalesce(p_decision_run_id::text,''),
    coalesce(array_to_string(p_approved_memory_item_ids::text[],','),'')
  ],E'\n')
$$;

create or replace function private.pandora_memory_decision_outcome_basis_v1(
  p_memory_project_id uuid,p_memory_project_key text,p_retrieval_log_id uuid,p_receipt_id uuid,
  p_decision_type text,p_decision_id uuid,p_outcome_run_id uuid,p_outcome_status text,
  p_usefulness_delta numeric,p_evidence_ref text,p_approved_memory_item_ids uuid[]
) returns text language sql immutable set search_path='' as $$
  select array_to_string(array[
    'visible-creation-decision-outcome-v1',coalesce(p_memory_project_id::text,''),coalesce(p_memory_project_key,''),
    coalesce(p_retrieval_log_id::text,''),coalesce(p_receipt_id::text,''),coalesce(p_decision_type,''),
    coalesce(p_decision_id::text,''),coalesce(p_outcome_run_id::text,''),coalesce(p_outcome_status,''),
    coalesce(p_usefulness_delta::text,''),coalesce(p_evidence_ref,''),
    coalesce(array_to_string(p_approved_memory_item_ids::text[],','),'')
  ],E'\n')
$$;

create or replace function private.pandora_enqueue_memory_decision_influence_v1(
  p_receipt_id uuid,p_decision_type text,p_decision_id uuid,p_decision_run_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_receipt private.pandora_project_memory_context_receipts%rowtype;
  v_context_hash text; v_payload jsonb; v_event_key text; v_outbox_id uuid; v_existing jsonb;
begin
  select * into v_receipt from private.pandora_project_memory_context_receipts where id=p_receipt_id;
  if v_receipt.id is null or v_receipt.context_status<>'available' or v_receipt.retrieval_log_id is null
     or cardinality(v_receipt.approved_memory_item_ids)<1 then return null; end if;
  if p_decision_type not in ('project_spec','build','repair') or p_decision_id is null then
    raise exception 'MEMORY_DECISION_IDENTITY_INVALID' using errcode='22023';
  end if;
  v_context_hash:=encode(extensions.digest(convert_to(private.pandora_memory_decision_influence_basis_v1(
    v_receipt.memory_project_id,v_receipt.memory_project_key,v_receipt.retrieval_log_id,v_receipt.id,
    p_decision_type,p_decision_id,p_decision_run_id,v_receipt.approved_memory_item_ids
  ),'utf8'),'sha256'),'hex');
  v_payload:=jsonb_build_object(
    'schema_version',1,'product_key','projectos','source_event_id',p_decision_id,'source_request_id',v_receipt.id,
    'organization_id',v_receipt.organization_id,'intake_id',null,'project_id',v_receipt.memory_project_id,
    'project_key',v_receipt.memory_project_key,'tool','visible_creation.memory_decision_influence','risk','write',
    'outcome_status','completed','duration_ms',0,'completed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'context_status','available','context_hash',v_context_hash,'result_fingerprint',v_receipt.context_hash,'error_fingerprint',null,
    'privacy_policy','metadata_only_v1','learning_kind','visible_creation_decision_influence_v1',
    'visible_project_id',v_receipt.project_id,'receipt_id',v_receipt.id,'retrieval_log_id',v_receipt.retrieval_log_id,
    'approved_memory_item_ids',to_jsonb(v_receipt.approved_memory_item_ids),'decision_type',p_decision_type,
    'decision_id',p_decision_id,'decision_run_id',p_decision_run_id
  );
  v_event_key:='memory-influence:'||p_decision_type||':'||p_decision_id::text||':'||v_receipt.id::text;
  select payload,id into v_existing,v_outbox_id from private.execution_learning_outbox where event_key=v_event_key;
  if v_outbox_id is not null then
    if v_existing is distinct from v_payload then raise exception 'MEMORY_DECISION_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
    return v_outbox_id;
  end if;
  insert into private.execution_learning_outbox(plan_id,event_key,organization_id,request_id,intake_id,project_id,project_key,payload,delivery_status,next_attempt_at,created_at,updated_at)
  values(null,v_event_key,v_receipt.organization_id,p_decision_id,null,v_receipt.project_id,v_receipt.memory_project_key,v_payload,'pending',now(),now(),now())
  on conflict (event_key) where event_key is not null do nothing returning id into v_outbox_id;
  if v_outbox_id is not null then perform private.dispatch_execution_learning(v_outbox_id); end if;
  return v_outbox_id;
end;
$$;

create or replace function private.pandora_enqueue_memory_decision_outcome_v1(
  p_receipt_id uuid,p_decision_type text,p_decision_id uuid,p_outcome_run_id uuid,
  p_outcome_status text,p_usefulness_delta numeric,p_evidence_ref text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_receipt private.pandora_project_memory_context_receipts%rowtype;
  v_context_hash text; v_payload jsonb; v_event_key text; v_outbox_id uuid; v_existing jsonb;
begin
  select * into v_receipt from private.pandora_project_memory_context_receipts where id=p_receipt_id;
  if v_receipt.id is null or v_receipt.context_status<>'available' or v_receipt.retrieval_log_id is null
     or cardinality(v_receipt.approved_memory_item_ids)<1 then return null; end if;
  if p_decision_type not in ('project_spec','build','repair') or p_decision_id is null or p_outcome_run_id is null
     or p_outcome_status not in ('succeeded','failed','accepted','rejected','regressed','unknown')
     or p_usefulness_delta < -1 or p_usefulness_delta > 1
     or p_evidence_ref is null or length(p_evidence_ref)>500 then
    raise exception 'MEMORY_DECISION_OUTCOME_INVALID' using errcode='22023';
  end if;
  v_context_hash:=encode(extensions.digest(convert_to(private.pandora_memory_decision_outcome_basis_v1(
    v_receipt.memory_project_id,v_receipt.memory_project_key,v_receipt.retrieval_log_id,v_receipt.id,
    p_decision_type,p_decision_id,p_outcome_run_id,p_outcome_status,p_usefulness_delta,p_evidence_ref,
    v_receipt.approved_memory_item_ids
  ),'utf8'),'sha256'),'hex');
  v_payload:=jsonb_build_object(
    'schema_version',1,'product_key','projectos','source_event_id',p_outcome_run_id,'source_request_id',v_receipt.id,
    'organization_id',v_receipt.organization_id,'intake_id',null,'project_id',v_receipt.memory_project_id,
    'project_key',v_receipt.memory_project_key,'tool','visible_creation.memory_decision_outcome','risk','write',
    'outcome_status','completed','duration_ms',0,'completed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'context_status','available','context_hash',v_context_hash,'result_fingerprint',v_receipt.context_hash,'error_fingerprint',null,
    'privacy_policy','metadata_only_v1','learning_kind','visible_creation_decision_outcome_v1',
    'visible_project_id',v_receipt.project_id,'receipt_id',v_receipt.id,'retrieval_log_id',v_receipt.retrieval_log_id,
    'approved_memory_item_ids',to_jsonb(v_receipt.approved_memory_item_ids),'decision_type',p_decision_type,
    'decision_id',p_decision_id,'outcome_run_id',p_outcome_run_id,'outcome_status_detail',p_outcome_status,
    'usefulness_delta',p_usefulness_delta,'evidence_ref',p_evidence_ref
  );
  v_event_key:='memory-outcome:'||p_decision_type||':'||p_decision_id::text||':'||p_outcome_run_id::text;
  select payload,id into v_existing,v_outbox_id from private.execution_learning_outbox where event_key=v_event_key;
  if v_outbox_id is not null then
    if v_existing is distinct from v_payload then raise exception 'MEMORY_DECISION_OUTCOME_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
    return v_outbox_id;
  end if;
  insert into private.execution_learning_outbox(plan_id,event_key,organization_id,request_id,intake_id,project_id,project_key,payload,delivery_status,next_attempt_at,created_at,updated_at)
  values(null,v_event_key,v_receipt.organization_id,p_outcome_run_id,null,v_receipt.project_id,v_receipt.memory_project_key,v_payload,'pending',now(),now(),now())
  on conflict (event_key) where event_key is not null do nothing returning id into v_outbox_id;
  if v_outbox_id is not null then perform private.dispatch_execution_learning(v_outbox_id); end if;
  return v_outbox_id;
end;
$$;

create or replace function private.pandora_project_spec_memory_influence_trigger_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_receipt_id uuid;
begin
  if new.status<>'active' then return new; end if;
  select id into v_receipt_id from private.pandora_project_memory_context_receipts
  where source_intent_id=new.source_intent_id and decision_type='project_spec' and context_status='available'
    and created_at between new.created_at-interval '10 minutes' and new.created_at+interval '1 minute'
  order by created_at desc limit 1;
  if v_receipt_id is not null then perform private.pandora_enqueue_memory_decision_influence_v1(v_receipt_id,'project_spec',new.id,null); end if;
  return new;
end;
$$;
drop trigger if exists pandora_project_spec_memory_influence_v1 on public.pandora_project_specs;
create trigger pandora_project_spec_memory_influence_v1 after insert on public.pandora_project_specs
for each row execute function private.pandora_project_spec_memory_influence_trigger_v1();

create or replace function private.pandora_build_memory_influence_trigger_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_receipt_id uuid;
begin
  if new.source_intent_id is null then return new; end if;
  select id into v_receipt_id from private.pandora_project_memory_context_receipts
  where source_intent_id=new.source_intent_id and decision_type='build' and context_status='available'
    and created_at between new.created_at-interval '10 minutes' and new.created_at+interval '1 minute'
  order by created_at desc limit 1;
  if v_receipt_id is not null then perform private.pandora_enqueue_memory_decision_influence_v1(v_receipt_id,'build',new.id,null); end if;
  return new;
end;
$$;
drop trigger if exists pandora_build_memory_influence_v1 on public.pandora_build_jobs;
create trigger pandora_build_memory_influence_v1 after insert on public.pandora_build_jobs
for each row execute function private.pandora_build_memory_influence_trigger_v1();

create or replace function private.pandora_verification_memory_outcome_trigger_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_receipt_id uuid; v_spec_id uuid; v_outcome text; v_delta numeric; v_evidence text;
begin
  if new.status not in ('PASS','FAIL','BLOCKED') or (tg_op='UPDATE' and old.status is not distinct from new.status) then return new; end if;
  v_outcome:=case new.status when 'PASS' then 'succeeded' when 'FAIL' then 'failed' else 'unknown' end;
  v_delta:=case new.status when 'PASS' then 1 when 'FAIL' then -1 else 0 end;
  v_evidence:='verification_run:'||new.id::text;

  if new.build_job_id is not null then
    select (payload->>'receipt_id')::uuid into v_receipt_id from private.execution_learning_outbox
    where payload->>'learning_kind'='visible_creation_decision_influence_v1'
      and payload->>'decision_type'='build' and payload->>'decision_id'=new.build_job_id::text
    order by created_at desc limit 1;
    if v_receipt_id is not null then
      perform private.pandora_enqueue_memory_decision_outcome_v1(v_receipt_id,'build',new.build_job_id,new.id,v_outcome,v_delta,v_evidence);
    end if;
  end if;

  v_spec_id:=new.project_spec_id;
  if v_spec_id is not null then
    v_receipt_id:=null;
    select (payload->>'receipt_id')::uuid into v_receipt_id from private.execution_learning_outbox
    where payload->>'learning_kind'='visible_creation_decision_influence_v1'
      and payload->>'decision_type'='project_spec' and payload->>'decision_id'=v_spec_id::text
    order by created_at desc limit 1;
    if v_receipt_id is not null then
      perform private.pandora_enqueue_memory_decision_outcome_v1(v_receipt_id,'project_spec',v_spec_id,new.id,v_outcome,v_delta,v_evidence);
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists pandora_verification_memory_outcome_v1 on public.pandora_verification_runs;
create trigger pandora_verification_memory_outcome_v1 after insert or update of status on public.pandora_verification_runs
for each row execute function private.pandora_verification_memory_outcome_trigger_v1();

revoke all on function private.pandora_enqueue_memory_decision_influence_v1(uuid,text,uuid,uuid) from public,anon,authenticated;
revoke all on function private.pandora_enqueue_memory_decision_outcome_v1(uuid,text,uuid,uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function private.pandora_enqueue_memory_decision_influence_v1(uuid,text,uuid,uuid) to service_role;
grant execute on function private.pandora_enqueue_memory_decision_outcome_v1(uuid,text,uuid,uuid,text,numeric,text) to service_role;


-- Actual-use hardening: retrieval alone is never counted as influence.
-- A ProjectSpec decision is bound atomically to the exact model run that consumed
-- the validated Memory context. Build influence is emitted only after a
-- successful source-generation model run carries the same context hash.
drop trigger if exists pandora_project_spec_memory_influence_v1 on public.pandora_project_specs;
drop trigger if exists pandora_build_memory_influence_v1 on public.pandora_build_jobs;

create or replace function public.pandora_commit_compiled_project_spec_memory_v1(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_candidate jsonb,
  p_compiler_provider text,
  p_compiler_model text,
  p_compiler_version text,
  p_compiler_provenance jsonb,
  p_content_sha256 text,
  p_model_request_id text,
  p_model_request_sha256 text,
  p_model_response_sha256 text,
  p_model_input_tokens bigint,
  p_model_output_tokens bigint,
  p_model_total_tokens bigint,
  p_model_revision text,
  p_memory_context_hash text,
  p_memory_receipt_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,private,public
as $$
declare
  v_receipt private.pandora_project_memory_context_receipts%rowtype;
  v_result jsonb;
  v_spec_id uuid;
  v_model_run_id uuid;
begin
  if p_memory_context_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'MEMORY_CONTEXT_BIND_INVALID' using errcode='22023';
  end if;

  if p_memory_receipt_id is not null then
    select * into v_receipt
    from private.pandora_project_memory_context_receipts
    where id=p_memory_receipt_id
      and source_intent_id=p_source_intent_id
      and decision_type='project_spec'
      and context_hash=p_memory_context_hash;
    if v_receipt.id is null then
      raise exception 'MEMORY_CONTEXT_RECEIPT_MISMATCH' using errcode='22023';
    end if;
  elsif coalesce(p_compiler_provenance->>'memory_context_status','')<>'unavailable' then
    raise exception 'MEMORY_CONTEXT_RECEIPT_REQUIRED' using errcode='22023';
  end if;

  v_result:=private.pandora_commit_compiled_project_spec_v2_20260901(
    p_source_intent_id,p_claim_token,p_candidate,p_compiler_provider,p_compiler_model,
    p_compiler_version,p_compiler_provenance,p_content_sha256,p_model_request_id,
    p_model_request_sha256,p_model_response_sha256,p_model_input_tokens,
    p_model_output_tokens,p_model_total_tokens,p_model_revision
  );
  if coalesce(v_result->>'state','')<>'succeeded' then return v_result; end if;

  begin
    v_spec_id:=(v_result->>'projectSpecId')::uuid;
  exception when others then
    raise exception 'MEMORY_CONTEXT_SPEC_ID_INVALID' using errcode='55000';
  end;

  update public.pandora_model_runs
  set context_sha256=p_memory_context_hash
  where project_spec_id=v_spec_id
    and request_id=p_model_request_id
    and task='compile_project_spec'
    and status='succeeded'
    and (context_sha256 is null or context_sha256=p_memory_context_hash)
  returning id into v_model_run_id;
  if v_model_run_id is null then
    raise exception 'MEMORY_CONTEXT_MODEL_RUN_BIND_FAILED' using errcode='55000';
  end if;

  return v_result || jsonb_build_object(
    'memoryContextHash',p_memory_context_hash,
    'memoryReceiptId',p_memory_receipt_id,
    'modelRunId',v_model_run_id
  );
end;
$$;
revoke all on function public.pandora_commit_compiled_project_spec_memory_v1(
  uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text,text,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_commit_compiled_project_spec_memory_v1(
  uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text,text,uuid
) to service_role;

create or replace function private.pandora_model_run_memory_influence_trigger_v2()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source_intent_id uuid;
  v_decision_type text;
  v_decision_id uuid;
  v_receipt_id uuid;
  v_reference_time timestamptz;
begin
  if new.status<>'succeeded' or new.context_sha256 is null
     or new.context_sha256 !~ '^[0-9a-f]{64}$' then
    return new;
  end if;
  if tg_op='UPDATE' then
    if old.context_sha256 is not distinct from new.context_sha256 then return new; end if;
  end if;

  if new.task='compile_project_spec' and new.project_spec_id is not null then
    v_decision_type:='project_spec';
    v_decision_id:=new.project_spec_id;
    select source_intent_id into v_source_intent_id
    from public.pandora_project_specs where id=new.project_spec_id;
  elsif new.task='generate_project_source' and new.build_job_id is not null then
    v_decision_type:='build';
    v_decision_id:=new.build_job_id;
    select source_intent_id into v_source_intent_id
    from public.pandora_build_jobs where id=new.build_job_id;
  else
    return new;
  end if;
  if v_source_intent_id is null or v_decision_id is null then return new; end if;

  v_reference_time:=coalesce(new.started_at,new.created_at,clock_timestamp());
  select id into v_receipt_id
  from private.pandora_project_memory_context_receipts
  where source_intent_id=v_source_intent_id
    and decision_type=v_decision_type
    and context_status='available'
    and context_hash=new.context_sha256
    and created_at between v_reference_time-interval '10 minutes'
                       and coalesce(new.completed_at,v_reference_time)+interval '1 minute'
  order by created_at desc
  limit 1;

  if v_receipt_id is not null then
    perform private.pandora_enqueue_memory_decision_influence_v1(
      v_receipt_id,v_decision_type,v_decision_id,new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_model_run_memory_influence_v2 on public.pandora_model_runs;
create trigger pandora_model_run_memory_influence_v2
after insert or update on public.pandora_model_runs
for each row execute function private.pandora_model_run_memory_influence_trigger_v2();

commit;
