-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- SEMANTIC REDACTION: live HMAC seed omitted; coordinated production rotation required.

begin;

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- Production memory-learning HMAC seed intentionally replaced.
-- Fresh replays receive a database-generated, environment-scoped value.
-- Preserve any pre-existing credential instead of overwriting it.
insert into private.integration_secrets (secret_name, secret_value, created_at, updated_at)
values (
  'projectos_memory_learning_hmac',
  encode(extensions.gen_random_bytes(32), 'hex'),
  now(),
  now()
)
on conflict (secret_name) do nothing;

create table if not exists private.execution_learning_outbox (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null unique references private.execution_plans(id),
  organization_id uuid not null,
  request_id uuid not null,
  intake_id uuid,
  project_id uuid,
  project_key text not null,
  payload jsonb not null,
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending','submitted','delivered','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_request_id bigint,
  last_http_status integer,
  last_response_excerpt text,
  last_error text,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  delivered_at timestamptz,
  check (jsonb_typeof(payload) = 'object')
);

create index if not exists execution_learning_outbox_pending_idx
  on private.execution_learning_outbox (next_attempt_at, created_at)
  where delivery_status in ('pending','submitted');

revoke all on private.execution_learning_outbox from public, anon, authenticated;

create or replace function private.execution_learning_signature_basis(p_payload jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select array_to_string(array[
    'projectos-learning-v1',
    coalesce(p_payload->>'source_event_id', ''),
    coalesce(p_payload->>'source_request_id', ''),
    coalesce(p_payload->>'organization_id', ''),
    coalesce(p_payload->>'intake_id', ''),
    coalesce(p_payload->>'project_id', ''),
    coalesce(p_payload->>'project_key', ''),
    coalesce(p_payload->>'tool', ''),
    coalesce(p_payload->>'risk', ''),
    coalesce(p_payload->>'outcome_status', ''),
    coalesce(p_payload->>'duration_ms', ''),
    coalesce(p_payload->>'completed_at', ''),
    coalesce(p_payload->>'context_status', ''),
    coalesce(p_payload->>'context_hash', ''),
    coalesce(p_payload->>'result_fingerprint', ''),
    coalesce(p_payload->>'error_fingerprint', '')
  ], E'\n')
$$;

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
    raise exception 'projectos_memory_context_missing'
      using errcode = '55000';
  end if;

  if v_context.namespace <> 'real_life'
     or v_context.context_envelope->>'namespace' <> 'real_life'
     or v_context.context_envelope->>'source' <> 'pandora-memory'
     or v_context.context_envelope->>'schemaVersion' <> '1.0.0'
     or v_context.context_envelope->>'status' <> v_context.context_status
     or v_context.context_envelope#>>'{queryBasis,tool}' <> new.tool
     or v_context.context_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'projectos_memory_context_invalid'
      using errcode = '55000';
  end if;

  if new.risk = 'read' then
    if v_context.context_status not in ('available', 'empty') then
      raise exception 'projectos_memory_context_unavailable'
        using errcode = '55000';
    end if;
  elsif v_context.context_status <> 'available' then
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
$$;

drop trigger if exists projectos_require_memory_context_before_execute
  on private.execution_plans;

create trigger projectos_require_memory_context_before_execute
before update of status on private.execution_plans
for each row
when (new.status = 'executing' and old.status is distinct from new.status)
execute function private.enforce_execution_plan_memory_context();

create or replace function private.dispatch_execution_learning(p_outbox_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outbox private.execution_learning_outbox%rowtype;
  v_secret text;
  v_timestamp text;
  v_basis text;
  v_signature text;
  v_request_id bigint;
begin
  select *
  into v_outbox
  from private.execution_learning_outbox
  where id = p_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception 'execution learning outbox item not found'
      using errcode = 'P0002';
  end if;

  if v_outbox.delivery_status = 'delivered' then
    return v_outbox.last_request_id;
  end if;

  if v_outbox.attempt_count >= 5 then
    update private.execution_learning_outbox
    set delivery_status = 'failed',
        last_error = coalesce(last_error, 'maximum delivery attempts reached'),
        updated_at = now()
    where id = v_outbox.id;
    return null;
  end if;

  select secret_value
  into v_secret
  from private.integration_secrets
  where secret_name = 'projectos_memory_learning_hmac';

  if coalesce(v_secret, '') = '' then
    raise exception 'projectos memory learning secret unavailable'
      using errcode = '55000';
  end if;

  v_timestamp := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
  v_basis := private.execution_learning_signature_basis(v_outbox.payload);
  v_signature := encode(
    extensions.hmac(v_timestamp || '.' || v_basis, v_secret, 'sha256'),
    'hex'
  );

  select net.http_post(
    url := 'https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-learning',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-pandora-timestamp', v_timestamp,
      'x-pandora-signature', v_signature
    ),
    body := v_outbox.payload,
    timeout_milliseconds := 10000
  )
  into v_request_id;

  update private.execution_learning_outbox
  set delivery_status = 'submitted',
      attempt_count = attempt_count + 1,
      last_request_id = v_request_id,
      last_http_status = null,
      last_response_excerpt = null,
      last_error = null,
      submitted_at = now(),
      next_attempt_at = now() + interval '2 minutes',
      updated_at = now()
  where id = v_outbox.id;

  return v_request_id;
exception when others then
  update private.execution_learning_outbox
  set delivery_status = case when attempt_count + 1 >= 5 then 'failed' else 'pending' end,
      attempt_count = attempt_count + 1,
      last_error = left(sqlerrm, 1000),
      next_attempt_at = now() + interval '2 minutes',
      updated_at = now()
  where id = p_outbox_id;
  return null;
end;
$$;

create or replace function private.reconcile_execution_learning_responses()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer := 0;
  v_timed_out integer := 0;
begin
  with latest_responses as (
    select
      outbox.id,
      response.status_code,
      response.content,
      response.error_msg,
      response.timed_out
    from private.execution_learning_outbox outbox
    join lateral (
      select status_code, content, error_msg, timed_out
      from net._http_response
      where id = outbox.last_request_id
      order by created desc
      limit 1
    ) response on true
    where outbox.delivery_status = 'submitted'
  )
  update private.execution_learning_outbox outbox
  set delivery_status = case
        when latest.status_code in (200, 202)
          and coalesce(latest.timed_out, false) is false
          and latest.error_msg is null then 'delivered'
        when outbox.attempt_count >= 5 then 'failed'
        else 'pending'
      end,
      last_http_status = latest.status_code,
      last_response_excerpt = left(coalesce(latest.content, ''), 1000),
      last_error = case
        when latest.status_code in (200, 202)
          and coalesce(latest.timed_out, false) is false
          and latest.error_msg is null then null
        else left(coalesce(latest.error_msg, 'HTTP ' || coalesce(latest.status_code::text, 'unknown')), 1000)
      end,
      delivered_at = case
        when latest.status_code in (200, 202)
          and coalesce(latest.timed_out, false) is false
          and latest.error_msg is null then now()
        else outbox.delivered_at
      end,
      next_attempt_at = case
        when latest.status_code in (200, 202)
          and coalesce(latest.timed_out, false) is false
          and latest.error_msg is null then outbox.next_attempt_at
        else now() + interval '2 minutes'
      end,
      updated_at = now()
  from latest_responses latest
  where outbox.id = latest.id;

  get diagnostics v_updated = row_count;

  update private.execution_learning_outbox
  set delivery_status = case when attempt_count >= 5 then 'failed' else 'pending' end,
      last_error = coalesce(last_error, 'delivery response timeout'),
      next_attempt_at = now(),
      updated_at = now()
  where delivery_status = 'submitted'
    and submitted_at < now() - interval '2 minutes'
    and not exists (
      select 1
      from net._http_response response
      where response.id = private.execution_learning_outbox.last_request_id
    );

  get diagnostics v_timed_out = row_count;
  return v_updated + v_timed_out;
end;
$$;

create or replace function private.process_execution_learning_outbox(p_limit integer default 20)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_processed integer := 0;
begin
  perform private.reconcile_execution_learning_responses();

  for v_item in
    select id
    from private.execution_learning_outbox
    where delivery_status = 'pending'
      and attempt_count < 5
      and next_attempt_at <= now()
    order by created_at
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked
  loop
    perform private.dispatch_execution_learning(v_item.id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;

create or replace function private.enqueue_execution_learning()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_context private.execution_plan_contexts%rowtype;
  v_project_id uuid;
  v_project_key text;
  v_completed_at text;
  v_result_fingerprint text;
  v_error_fingerprint text;
  v_payload jsonb;
  v_outbox_id uuid;
begin
  if new.status not in ('completed', 'failed')
     or old.status is not distinct from new.status then
    return new;
  end if;

  select *
  into v_context
  from private.execution_plan_contexts
  where plan_id = new.id
    and organization_id = new.organization_id
    and request_id = new.request_id;

  if v_context.plan_id is null then
    raise exception 'projectos_memory_context_missing_at_completion'
      using errcode = '55000';
  end if;

  select intake.project_id, project.project_key
  into v_project_id, v_project_key
  from public.projectos_intake_requests intake
  join public.projectos_projects project
    on project.id = intake.project_id
   and project.organization_id = intake.organization_id
  where intake.id = new.intake_id
    and intake.organization_id = new.organization_id;

  if v_project_id is null or coalesce(v_project_key, '') = '' then
    raise exception 'projectos_project_context_missing_at_completion'
      using errcode = '55000';
  end if;

  v_completed_at := to_char(
    coalesce(new.completed_at, clock_timestamp()) at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );

  v_result_fingerprint := case
    when new.result_summary is null then null
    else encode(extensions.digest(new.result_summary::text, 'sha256'), 'hex')
  end;

  v_error_fingerprint := case
    when new.error is null then null
    else encode(extensions.digest(new.error, 'sha256'), 'hex')
  end;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'schema_version', 1,
    'product_key', 'projectos',
    'source_event_id', new.id,
    'source_request_id', new.request_id,
    'organization_id', new.organization_id,
    'intake_id', new.intake_id,
    'project_id', v_project_id,
    'project_key', v_project_key,
    'tool', new.tool,
    'risk', new.risk,
    'outcome_status', new.status,
    'duration_ms', greatest(coalesce(new.duration_ms, 0), 0),
    'completed_at', v_completed_at,
    'context_status', v_context.context_status,
    'context_hash', v_context.context_hash,
    'result_fingerprint', v_result_fingerprint,
    'error_fingerprint', v_error_fingerprint,
    'privacy_policy', 'metadata_only_v1'
  ));

  insert into private.execution_learning_outbox (
    plan_id,
    organization_id,
    request_id,
    intake_id,
    project_id,
    project_key,
    payload,
    delivery_status,
    next_attempt_at,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.organization_id,
    new.request_id,
    new.intake_id,
    v_project_id,
    v_project_key,
    v_payload,
    'pending',
    now(),
    now(),
    now()
  )
  on conflict (plan_id) do update
  set payload = excluded.payload,
      project_id = excluded.project_id,
      project_key = excluded.project_key,
      updated_at = now()
  returning id into v_outbox_id;

  begin
    perform private.dispatch_execution_learning(v_outbox_id);
  exception when others then
    update private.execution_learning_outbox
    set delivery_status = 'pending',
        last_error = left(sqlerrm, 1000),
        next_attempt_at = now(),
        updated_at = now()
    where id = v_outbox_id;
  end;

  return new;
end;
$$;

drop trigger if exists projectos_enqueue_memory_learning_after_finish
  on private.execution_plans;

create trigger projectos_enqueue_memory_learning_after_finish
after update of status on private.execution_plans
for each row
when (new.status in ('completed', 'failed') and old.status is distinct from new.status)
execute function private.enqueue_execution_learning();

select cron.schedule(
  'projectos-memory-learning-outbox',
  '* * * * *',
  $job$select private.process_execution_learning_outbox(20);$job$
);

commit;
