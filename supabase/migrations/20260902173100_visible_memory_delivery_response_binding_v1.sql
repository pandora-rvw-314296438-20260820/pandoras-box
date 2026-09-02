create or replace function private.try_parse_jsonb(p_value text)
returns jsonb
language plpgsql
immutable
set search_path=''
as $$
begin
  if p_value is null or btrim(p_value) = '' then return null; end if;
  return p_value::jsonb;
exception when others then
  return null;
end;
$$;

create or replace function private.reconcile_execution_learning_responses()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_updated integer := 0;
  v_timed_out integer := 0;
begin
  with latest_responses as (
    select outbox.id,outbox.payload,response.status_code,response.content,response.error_msg,response.timed_out,
           private.try_parse_jsonb(response.content) as response_json
    from private.execution_learning_outbox outbox
    join lateral (
      select status_code,content,error_msg,timed_out from net._http_response
      where id=outbox.last_request_id order by created desc limit 1
    ) response on true
    where outbox.delivery_status='submitted'
  ), adjudicated as (
    select *,case
      when status_code not in (200,202) or coalesce(timed_out,false) or error_msg is not null then false
      when payload->>'learning_kind'='visible_creation_evidence_v1' then
        response_json is not null
        and response_json->>'ok'='true'
        and response_json->>'review_required'='true'
        and response_json->>'canonical_memory_written'='false'
        and coalesce(response_json->>'candidate_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        and coalesce(response_json->>'review_item_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        and response_json->>'source_event_id'=payload->>'source_event_id'
        and response_json->>'evidence_kind'=payload->>'evidence_kind'
        and response_json->>'proof_stage'=payload->>'proof_stage'
        and response_json->>'visible_project_id'=payload->>'visible_project_id'
      else true end as response_valid
    from latest_responses
  )
  update private.execution_learning_outbox outbox
  set delivery_status=case when latest.response_valid then 'delivered' when outbox.attempt_count>=5 then 'failed' else 'pending' end,
      last_http_status=latest.status_code,
      last_response_excerpt=left(coalesce(latest.content,''),1000),
      last_error=case when latest.response_valid then null
        when latest.status_code in (200,202) and coalesce(latest.timed_out,false)=false and latest.error_msg is null
          and latest.payload->>'learning_kind'='visible_creation_evidence_v1' then 'VISIBLE_MEMORY_RESPONSE_CONTRACT_INVALID'
        else left(coalesce(latest.error_msg,'HTTP '||coalesce(latest.status_code::text,'unknown')),1000) end,
      delivered_at=case when latest.response_valid then now() else outbox.delivered_at end,
      next_attempt_at=case when latest.response_valid then outbox.next_attempt_at else now()+interval '2 minutes' end,
      updated_at=now()
  from adjudicated latest where outbox.id=latest.id;
  get diagnostics v_updated=row_count;

  update private.execution_learning_outbox
  set delivery_status=case when attempt_count>=5 then 'failed' else 'pending' end,
      last_error=coalesce(last_error,'delivery response timeout'),next_attempt_at=now(),updated_at=now()
  where delivery_status='submitted' and submitted_at<now()-interval '2 minutes'
    and not exists(select 1 from net._http_response response where response.id=private.execution_learning_outbox.last_request_id);
  get diagnostics v_timed_out=row_count;
  return v_updated+v_timed_out;
end;
$$;

revoke all on function private.try_parse_jsonb(text) from public,anon,authenticated;
revoke all on function private.reconcile_execution_learning_responses() from public,anon,authenticated;
