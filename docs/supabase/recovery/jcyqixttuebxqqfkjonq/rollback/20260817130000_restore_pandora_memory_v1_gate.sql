-- TESTED DATABASE ROLLBACK FOR 20260817130000.
-- Restores the immediately preceding Pandora Memory v1 execution gate without altering migration history.
-- Apply only as a separately authorized incident rollback; this file is not an active migration.

create or replace function private.enforce_execution_plan_memory_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_context private.execution_plan_contexts%rowtype;
  v_retrieved_at timestamptz;
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
    raise exception 'pandora_memory_context_missing'
      using errcode = '55000';
  end if;

  if v_context.namespace <> 'real_life'
     or v_context.context_envelope->>'namespace' <> 'real_life'
     or v_context.context_envelope->>'source' <> 'pandora-memory'
     or v_context.context_envelope->>'schemaVersion' <> '1.0.0'
     or v_context.context_envelope->>'status' <> v_context.context_status
     or v_context.context_envelope#>>'{queryBasis,tool}' <> new.tool
     or v_context.context_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'pandora_memory_context_invalid'
      using errcode = '55000';
  end if;

  if new.risk = 'read' then
    if v_context.context_status not in ('available', 'empty') then
      raise exception 'pandora_memory_context_unavailable'
        using errcode = '55000';
    end if;
  elsif v_context.context_status <> 'available' then
    raise exception 'pandora_memory_context_unavailable_for_stateful_action'
      using errcode = '55000';
  end if;

  begin
    v_retrieved_at := nullif(v_context.context_envelope->>'retrievedAt', '')::timestamptz;
  exception when others then
    raise exception 'pandora_memory_context_timestamp_invalid'
      using errcode = '55000';
  end;

  if v_retrieved_at is null
     or v_retrieved_at < new.created_at - interval '10 minutes'
     or v_retrieved_at > clock_timestamp() + interval '1 minute'
     or v_context.recorded_at < new.created_at - interval '2 seconds'
     or v_context.recorded_at > clock_timestamp() + interval '1 minute' then
    raise exception 'pandora_memory_context_stale'
      using errcode = '55000';
  end if;

  return new;
end;
$$;
