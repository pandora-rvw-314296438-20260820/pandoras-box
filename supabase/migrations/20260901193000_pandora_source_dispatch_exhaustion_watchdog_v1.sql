-- Pandora Visible Creation — source-generation dispatch exhaustion watchdog.
-- A lost fifth source-worker request must fail closed instead of leaving durable work dispatching forever.

begin;

create or replace function private.pandora_fail_exhausted_source_dispatches_v1(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_row public.pandora_source_generation_queue%rowtype;
  v_failed integer := 0;
  v_jobs_failed integer := 0;
  v_now timestamptz := clock_timestamp();
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'limit out of range' using errcode = '22023';
  end if;

  for v_row in
    select q.*
    from public.pandora_source_generation_queue q
    where q.status = 'dispatching'
      and q.dispatched_at is not null
      and q.dispatched_at <= v_now - interval '3 minutes'
      and q.dispatch_count >= 5
    order by q.dispatched_at, q.created_at
    limit p_limit
    for update skip locked
  loop
    update public.pandora_source_generation_queue q
       set status = 'failed',
           request_id = null,
           dispatched_at = null,
           last_error_code = 'SOURCE_DISPATCH_RETRY_EXHAUSTED',
           completed_at = coalesce(q.completed_at, v_now),
           updated_at = v_now
     where q.id = v_row.id
       and q.status = 'dispatching'
       and q.dispatch_count >= 5;

    if found then
      v_failed := v_failed + 1;

      -- Modern server-admitted work owns a BuildJob before generation. Fail only
      -- the still-unmaterialized candidate; a verified/current product is untouched.
      if v_row.build_job_id is not null then
        update public.pandora_build_jobs j
           set status = 'failed',
               current_stage = 'failed',
               error_code = 'SOURCE_GENERATION_RETRY_EXHAUSTED',
               public_error_summary = 'Pandora could not finish generating this version. Your current version is unchanged.',
               lease_owner = null,
               lease_token_sha256 = null,
               lease_expires_at = null,
               heartbeat_at = null
         where j.id = v_row.build_job_id
           and j.status = 'queued'
           and j.target_project_version_id is null;

        if found then
          v_jobs_failed := v_jobs_failed + 1;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'sourceDispatchesExhausted', v_failed,
    'admittedJobsFailed', v_jobs_failed,
    'checkedAt', v_now
  );
end;
$fn$;

revoke all on function private.pandora_fail_exhausted_source_dispatches_v1(integer)
  from public, anon, authenticated;
grant execute on function private.pandora_fail_exhausted_source_dispatches_v1(integer)
  to service_role;

create or replace function private.pandora_dispatch_source_generation_tick_20260831()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_row public.pandora_source_generation_queue%rowtype;
  v_key text;
  v_request_id bigint;
  v_dispatched integer := 0;
  v_exhausted jsonb;
  v_refresh jsonb;
begin
  -- Close fifth-attempt dispatches before ordinary retry refresh so no source
  -- request can remain in dispatching forever after its worker disappears.
  v_exhausted := private.pandora_fail_exhausted_source_dispatches_v1(100);
  v_refresh := private.pandora_refresh_source_generation_queue_20260831();

  begin
    select decrypted_secret
      into v_key
    from vault.decrypted_secrets
    where name = 'pandora_source_worker_internal_20260831'
    limit 1;
  exception when others then
    v_key := null;
  end;

  if nullif(v_key, '') is null then
    return v_exhausted || v_refresh || jsonb_build_object(
      'dispatched', 0,
      'workerKeyAvailable', false
    );
  end if;

  for v_row in
    select *
    from public.pandora_source_generation_queue
    where status = 'queued'
      and dispatch_count < 5
    order by created_at
    limit 3
    for update skip locked
  loop
    update public.pandora_source_generation_queue
       set status = 'dispatching',
           dispatch_count = dispatch_count + 1,
           dispatched_at = clock_timestamp(),
           last_error_code = null,
           updated_at = clock_timestamp()
     where id = v_row.id;

    begin
      execute 'select net.http_post($1,$2,$3,$4,$5)'
        into v_request_id
        using
          'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker',
          jsonb_build_object('queueId', v_row.id),
          '{}'::jsonb,
          jsonb_build_object(
            'content-type', 'application/json',
            'x-pandora-internal-key', v_key
          ),
          120000;

      update public.pandora_source_generation_queue
         set request_id = v_request_id,
             updated_at = clock_timestamp()
       where id = v_row.id;
      v_dispatched := v_dispatched + 1;
    exception when others then
      update public.pandora_source_generation_queue
         set status = case when dispatch_count < 5 then 'queued' else 'failed' end,
             last_error_code = 'DISPATCH_FAILED',
             dispatched_at = null,
             updated_at = clock_timestamp(),
             completed_at = case when dispatch_count >= 5 then clock_timestamp() else null end
       where id = v_row.id;
    end;
  end loop;

  v_key := null;
  return v_exhausted || v_refresh || jsonb_build_object(
    'dispatched', v_dispatched,
    'workerKeyAvailable', true
  );
end;
$fn$;

revoke all on function private.pandora_dispatch_source_generation_tick_20260831()
  from public, anon, authenticated;
grant execute on function private.pandora_dispatch_source_generation_tick_20260831()
  to service_role;

commit;
