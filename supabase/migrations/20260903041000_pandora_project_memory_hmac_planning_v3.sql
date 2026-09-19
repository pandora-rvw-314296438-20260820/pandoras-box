begin;

-- Task93 production authority: sign bounded planning retrievals inside Primary.
-- Customer bearer tokens never leave Primary; only exact metadata is HMAC-bound.
create or replace function public.pandora_sign_project_memory_planning_request_v2(
  p_source_intent_id uuid,
  p_decision_type text,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,private,public,extensions
as $$
declare
  v_intent public.pandora_project_intents%rowtype;
  v_project public.projectos_projects%rowtype;
  v_memory_project_key text;
  v_secret text;
  v_query_basis text;
  v_query_hash text;
  v_request_basis text;
  v_timestamp text;
  v_signature text;
begin
  if p_source_intent_id is null or p_request_id is null
     or p_decision_type not in ('project_spec','build','repair') then
    raise exception 'MEMORY_PLANNING_REQUEST_INVALID' using errcode='22023';
  end if;
  select * into v_intent from public.pandora_project_intents where id=p_source_intent_id;
  if v_intent.id is null then raise exception 'INTENT_NOT_AVAILABLE' using errcode='P0002'; end if;
  select * into v_project from public.projectos_projects
    where id=v_intent.project_id and organization_id=v_intent.organization_id;
  if v_project.id is null or v_project.status='archived' then
    raise exception 'PROJECT_NOT_AVAILABLE' using errcode='P0002';
  end if;
  v_memory_project_key:=case when v_project.project_key='mcpmaster' then 'mcpmaster-pandoras-box' else v_project.project_key end;
  if v_memory_project_key is null or v_memory_project_key !~ '^[a-z0-9][a-z0-9._-]{1,95}$' then
    raise exception 'MEMORY_PROJECT_KEY_INVALID' using errcode='22023';
  end if;
  v_query_basis:=array_to_string(array[
    'projectos-planning-query-v1',v_intent.organization_id::text,v_project.id::text,v_memory_project_key,p_decision_type
  ],E'\n');
  v_query_hash:=encode(extensions.digest(convert_to(v_query_basis,'utf8'),'sha256'),'hex');
  v_request_basis:=array_to_string(array[
    'projectos-planning-context-v1',p_request_id::text,v_intent.organization_id::text,v_project.id::text,
    v_memory_project_key,p_decision_type,v_query_hash
  ],E'\n');
  select secret_value into v_secret from private.integration_secrets
    where secret_name='projectos_memory_learning_hmac';
  if coalesce(v_secret,'')='' then raise exception 'MEMORY_PLANNING_SECRET_UNAVAILABLE' using errcode='55000'; end if;
  v_timestamp:=floor(extract(epoch from clock_timestamp())*1000)::bigint::text;
  v_signature:=encode(extensions.hmac(v_timestamp||'.'||v_request_basis,v_secret,'sha256'),'hex');
  return jsonb_build_object(
    'body',jsonb_build_object(
      'schema_version',1,'purpose','projectos-planning-context-v1','request_id',p_request_id,
      'organization_id',v_intent.organization_id,'visible_project_id',v_project.id,
      'project_key',v_memory_project_key,'decision_type',p_decision_type,'query_hash',v_query_hash
    ),
    'timestamp',v_timestamp,
    'signature',v_signature
  );
end;
$$;
revoke all on function public.pandora_sign_project_memory_planning_request_v2(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_sign_project_memory_planning_request_v2(uuid,text,uuid) to service_role;

-- Persist only immutable lineage refs/hash. Bounded Memory summaries remain transient
-- in the model request and are never copied into the Primary receipt.
create or replace function public.pandora_record_project_memory_context_v2(
  p_source_intent_id uuid,
  p_decision_type text,
  p_request_id uuid,
  p_memory_project_id uuid,
  p_memory_project_key text,
  p_context_status text,
  p_context_hash text,
  p_query_hash text,
  p_retrieval_log_id uuid,
  p_approved_memory_item_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,private,public
as $$
declare
  v_intent public.pandora_project_intents%rowtype;
  v_project public.projectos_projects%rowtype;
  v_expected_key text;
  v_expected_query_hash text;
  v_envelope jsonb;
  v_receipt_id uuid;
begin
  if p_source_intent_id is null or p_request_id is null or p_memory_project_id is null
     or p_retrieval_log_id is null or p_decision_type not in ('project_spec','build','repair')
     or p_context_status not in ('available','empty') or p_context_hash !~ '^[0-9a-f]{64}$'
     or p_query_hash !~ '^[0-9a-f]{64}$' or coalesce(cardinality(p_approved_memory_item_ids),0)>50 then
    raise exception 'MEMORY_CONTEXT_RECEIPT_INVALID' using errcode='22023';
  end if;
  select * into v_intent from public.pandora_project_intents where id=p_source_intent_id;
  if v_intent.id is null then raise exception 'INTENT_NOT_AVAILABLE' using errcode='P0002'; end if;
  select * into v_project from public.projectos_projects where id=v_intent.project_id and organization_id=v_intent.organization_id;
  if v_project.id is null then raise exception 'PROJECT_NOT_AVAILABLE' using errcode='P0002'; end if;
  v_expected_key:=case when v_project.project_key='mcpmaster' then 'mcpmaster-pandoras-box' else v_project.project_key end;
  if p_memory_project_key<>v_expected_key then raise exception 'MEMORY_CONTEXT_PROJECT_MISMATCH' using errcode='22023'; end if;
  v_expected_query_hash:=encode(extensions.digest(convert_to(array_to_string(array[
    'projectos-planning-query-v1',v_intent.organization_id::text,v_project.id::text,v_expected_key,p_decision_type
  ],E'\n'),'utf8'),'sha256'),'hex');
  if p_query_hash<>v_expected_query_hash then raise exception 'MEMORY_CONTEXT_QUERY_HASH_MISMATCH' using errcode='22023'; end if;
  if (p_context_status='available' and coalesce(cardinality(p_approved_memory_item_ids),0)<1)
     or (p_context_status='empty' and coalesce(cardinality(p_approved_memory_item_ids),0)<>0) then
    raise exception 'MEMORY_CONTEXT_LINEAGE_INVALID' using errcode='22023';
  end if;
  v_envelope:=jsonb_build_object(
    'schemaVersion','1.0.0','source','pandora-memory','namespace','real_life','status',p_context_status,
    'queryBasis',jsonb_build_object('tool','visible_creation.'||p_decision_type,'identifiers',jsonb_build_object(
      'projectKey',p_memory_project_key,'projectId',v_project.id::text,'requestId',p_request_id::text,'queryHash',p_query_hash)),
    'metadataOnly',true
  );
  insert into private.pandora_project_memory_context_receipts(
    organization_id,project_id,source_intent_id,decision_type,memory_project_id,memory_project_key,
    context_status,context_hash,retrieval_log_id,approved_memory_item_ids,context_envelope,created_by
  ) values (
    v_intent.organization_id,v_project.id,v_intent.id,p_decision_type,p_memory_project_id,p_memory_project_key,
    p_context_status,p_context_hash,p_retrieval_log_id,coalesce(p_approved_memory_item_ids,'{}'::uuid[]),v_envelope,v_intent.requester_id
  ) on conflict (source_intent_id,decision_type,context_hash) do nothing returning id into v_receipt_id;
  if v_receipt_id is null then
    select id into v_receipt_id from private.pandora_project_memory_context_receipts
    where source_intent_id=v_intent.id and decision_type=p_decision_type and context_hash=p_context_hash;
  end if;
  return jsonb_build_object(
    'receiptId',v_receipt_id,'sourceIntentId',v_intent.id,'projectId',v_project.id,'decisionType',p_decision_type,
    'memoryProjectId',p_memory_project_id,'memoryProjectKey',p_memory_project_key,'contextStatus',p_context_status,
    'contextHash',p_context_hash,'queryHash',p_query_hash,'retrievalLogId',p_retrieval_log_id,
    'approvedMemoryItemIds',to_jsonb(coalesce(p_approved_memory_item_ids,'{}'::uuid[]))
  );
end;
$$;
revoke all on function public.pandora_record_project_memory_context_v2(uuid,text,uuid,uuid,text,text,text,text,uuid,uuid[])
  from public,anon,authenticated;
grant execute on function public.pandora_record_project_memory_context_v2(uuid,text,uuid,uuid,text,text,text,text,uuid,uuid[])
  to service_role;

-- Retire the customer-authenticated envelope writer installed by v1. Historical
-- function identity is preserved for migration reproducibility, but no caller may use it.
revoke execute on function public.pandora_record_project_memory_context_v1(uuid,text,uuid,text,text,text,uuid,uuid[],jsonb)
  from authenticated,service_role;

commit;
