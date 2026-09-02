begin;

-- Route Task95 decision influence/outcome metadata to the dedicated Memory
-- decision-lineage boundary. The existing outbox and HMAC trust root remain the
-- only transport authority; no parallel queue or credential surface is added.
create or replace function private.dispatch_execution_learning(p_outbox_id uuid)
returns bigint
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_outbox private.execution_learning_outbox%rowtype;
  v_secret text;
  v_timestamp text;
  v_basis text;
  v_signature text;
  v_request_id bigint;
  v_kind text;
  v_target_url text;
begin
  select * into v_outbox
  from private.execution_learning_outbox
  where id=p_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception 'execution learning outbox item not found' using errcode='P0002';
  end if;
  if v_outbox.delivery_status='delivered' then return v_outbox.last_request_id; end if;
  if v_outbox.attempt_count>=5 then
    update private.execution_learning_outbox
    set delivery_status='failed',
        last_error=coalesce(last_error,'maximum delivery attempts reached'),
        updated_at=now()
    where id=v_outbox.id;
    return null;
  end if;

  v_kind:=coalesce(v_outbox.payload->>'learning_kind','');
  v_target_url:=case
    when v_kind in ('visible_creation_decision_influence_v1','visible_creation_decision_outcome_v1')
      then 'https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-decision-lineage'
    else 'https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-learning'
  end;

  select secret_value into v_secret
  from private.integration_secrets
  where secret_name='projectos_memory_learning_hmac';
  if coalesce(v_secret,'')='' then
    raise exception 'projectos memory learning secret unavailable' using errcode='55000';
  end if;

  v_timestamp:=floor(extract(epoch from clock_timestamp())*1000)::bigint::text;
  v_basis:=private.execution_learning_signature_basis(v_outbox.payload);
  v_signature:=encode(extensions.hmac(v_timestamp||'.'||v_basis,v_secret,'sha256'),'hex');

  select net.http_post(
    url:=v_target_url,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-pandora-timestamp',v_timestamp,
      'x-pandora-signature',v_signature
    ),
    body:=v_outbox.payload,
    timeout_milliseconds:=10000
  ) into v_request_id;

  update private.execution_learning_outbox
  set delivery_status='submitted',
      attempt_count=attempt_count+1,
      last_request_id=v_request_id,
      last_http_status=null,
      last_response_excerpt=null,
      last_error=null,
      submitted_at=now(),
      next_attempt_at=now()+interval '2 minutes',
      updated_at=now()
  where id=v_outbox.id;
  return v_request_id;
exception when others then
  update private.execution_learning_outbox
  set delivery_status=case when attempt_count+1>=5 then 'failed' else 'pending' end,
      attempt_count=attempt_count+1,
      last_error=left(sqlerrm,1000),
      next_attempt_at=now()+interval '2 minutes',
      updated_at=now()
  where id=p_outbox_id;
  return null;
end;
$fn$;

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
as $fn$
declare
  v_body jsonb;
  v_kind text:=coalesce(p_payload->>'learning_kind','');
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
begin
  if p_status not in (200,202) or coalesce(p_timed_out,false) or p_error is not null then
    return false;
  end if;
  if v_kind='' then return true; end if;
  if v_kind not in (
    'visible_creation_evidence_v1',
    'visible_creation_decision_influence_v1',
    'visible_creation_decision_outcome_v1'
  ) then
    return true;
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
$fn$;

revoke all on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  from public,anon,authenticated;
grant execute on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  to service_role;

commit;
