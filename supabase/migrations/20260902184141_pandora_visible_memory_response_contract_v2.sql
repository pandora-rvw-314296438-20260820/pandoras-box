begin;

-- Visible Creation Memory response contract v2.
-- Preserve legacy learning delivery semantics, but fail closed for typed
-- visible-creation evidence unless Memory proves review-gated non-canonical
-- intake for the exact outbox event and visible project identity.
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
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
begin
  if p_status not in (200,202) or coalesce(p_timed_out,false) or p_error is not null then
    return false;
  end if;
  if coalesce(p_payload->>'learning_kind','') <> 'visible_creation_evidence_v1' then
    return true;
  end if;
  begin
    v_body := p_content::jsonb;
  exception when others then
    return false;
  end;
  return coalesce(v_body->>'ok','')='true'
    and coalesce(v_body->>'review_required','')='true'
    and coalesce(v_body->>'canonical_memory_written','')='false'
    and lower(coalesce(v_body->>'source_event_id',''))=lower(coalesce(p_payload->>'source_event_id',''))
    and lower(coalesce(v_body->>'visible_project_id',''))=lower(coalesce(p_payload->>'visible_project_id',''))
    and coalesce(v_body->>'evidence_kind','')=coalesce(p_payload->>'evidence_kind','')
    and coalesce(v_body->>'proof_stage','')=coalesce(p_payload->>'proof_stage','')
    and lower(coalesce(v_body->>'candidate_id','')) ~ v_uuid_pattern
    and lower(coalesce(v_body->>'review_item_id','')) ~ v_uuid_pattern;
end;
$fn$;

create or replace function private.reconcile_execution_learning_responses()
returns integer
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_updated integer := 0;
  v_timed_out integer := 0;
begin
  with latest_responses as (
    select
      outbox.id,
      outbox.payload,
      response.status_code,
      response.content,
      response.error_msg,
      response.timed_out,
      private.execution_learning_response_is_valid(
        outbox.payload,response.status_code,response.content,response.error_msg,response.timed_out
      ) as response_valid
    from private.execution_learning_outbox outbox
    join lateral (
      select status_code,content,error_msg,timed_out
      from net._http_response
      where id=outbox.last_request_id
      order by created desc
      limit 1
    ) response on true
    where outbox.delivery_status='submitted'
  )
  update private.execution_learning_outbox outbox
  set delivery_status=case
        when latest.response_valid then 'delivered'
        when outbox.attempt_count >= 5 then 'failed'
        else 'pending'
      end,
      last_http_status=latest.status_code,
      last_response_excerpt=left(coalesce(latest.content,''),1000),
      last_error=case
        when latest.response_valid then null
        when latest.status_code in (200,202) and coalesce(latest.timed_out,false) is false and latest.error_msg is null
          then 'invalid learning response contract'
        else left(coalesce(latest.error_msg,'HTTP '||coalesce(latest.status_code::text,'unknown')),1000)
      end,
      delivered_at=case when latest.response_valid then now() else outbox.delivered_at end,
      next_attempt_at=case when latest.response_valid then outbox.next_attempt_at else now()+interval '2 minutes' end,
      updated_at=now()
  from latest_responses latest
  where outbox.id=latest.id;

  get diagnostics v_updated=row_count;

  update private.execution_learning_outbox
  set delivery_status=case when attempt_count >= 5 then 'failed' else 'pending' end,
      last_error=coalesce(last_error,'delivery response timeout'),
      next_attempt_at=now(),
      updated_at=now()
  where delivery_status='submitted'
    and submitted_at < now()-interval '2 minutes'
    and not exists (
      select 1 from net._http_response response
      where response.id=private.execution_learning_outbox.last_request_id
    );

  get diagnostics v_timed_out=row_count;
  return v_updated+v_timed_out;
end;
$fn$;

revoke all on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  from public,anon,authenticated;
grant execute on function private.execution_learning_response_is_valid(jsonb,integer,text,text,boolean)
  to service_role;
revoke all on function private.reconcile_execution_learning_responses()
  from public,anon,authenticated;
grant execute on function private.reconcile_execution_learning_responses()
  to service_role;

commit;