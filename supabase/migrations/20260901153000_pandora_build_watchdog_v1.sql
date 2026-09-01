-- Pandora Visible Creation — Phase 3 stalled-job watchdog and bounded recovery.
-- Reuses the existing BuildJob lease/attempt authority; does not create a competing queue.

begin;

create index if not exists pandora_build_jobs_deadline_idx
  on public.pandora_build_jobs(deadline_at, status)
  where deadline_at is not null
    and status in ('queued','claimed','running','waiting_approval','waiting_verification');

create or replace function private.pandora_build_watchdog_tick_v1(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_job public.pandora_build_jobs%rowtype;
  v_requeued integer := 0;
  v_exhausted integer := 0;
  v_deadline_failed integer := 0;
  v_now timestamptz := clock_timestamp();
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'limit out of range' using errcode = '22023';
  end if;

  -- deadline_at is the server-owned hard stop for admitted work, including queued/unclaimed work.
  for v_job in
    select j.*
    from public.pandora_build_jobs j
    where j.status in ('queued','claimed','running','waiting_approval','waiting_verification')
      and j.deadline_at is not null
      and j.deadline_at <= v_now
    order by j.deadline_at, j.created_at
    limit p_limit
    for update skip locked
  loop
    update public.pandora_build_job_attempts a
       set status = case when a.status = 'running' then 'failed' else a.status end,
           failure_class = coalesce(a.failure_class, 'deadline_exceeded'),
           finished_at = coalesce(a.finished_at, v_now)
     where a.build_job_id = v_job.id
       and a.status = 'running';

    update public.pandora_build_jobs j
       set status = 'failed',
           current_stage = 'failed',
           error_code = 'BUILD_DEADLINE_EXCEEDED',
           public_error_summary = 'Build stopped because its execution deadline was reached.',
           lease_owner = null,
           lease_token_sha256 = null,
           lease_expires_at = null,
           heartbeat_at = null
     where j.id = v_job.id
       and j.status in ('queued','claimed','running','waiting_approval','waiting_verification')
       and j.deadline_at is not null
       and j.deadline_at <= v_now;

    if found then
      update public.pandora_source_generation_queue q
         set status = 'failed',
             last_error_code = 'BUILD_DEADLINE_EXCEEDED',
             dispatched_at = null,
             completed_at = coalesce(q.completed_at, v_now),
             updated_at = v_now
       where q.build_job_id = v_job.id
         and q.status in ('queued','dispatching');
      v_deadline_failed := v_deadline_failed + 1;
    end if;
  end loop;

  -- Existing lease authority remains canonical for retryable expirations.
  v_requeued := private.pandora_requeue_expired_build_jobs(p_limit);

  -- The legacy reclaimer intentionally skips attempt_count=max_attempts.
  -- Close those exhausted leases instead of allowing a claimed/running job to strand forever.
  for v_job in
    select j.*
    from public.pandora_build_jobs j
    where j.status in ('claimed','running')
      and j.lease_expires_at is not null
      and j.lease_expires_at <= v_now
      and j.attempt_count >= j.max_attempts
    order by j.lease_expires_at, j.created_at
    limit p_limit
    for update skip locked
  loop
    update public.pandora_build_job_attempts a
       set status = case when a.status = 'running' then 'expired' else a.status end,
           failure_class = coalesce(a.failure_class, 'lease_retry_exhausted'),
           finished_at = coalesce(a.finished_at, v_now)
     where a.build_job_id = v_job.id
       and a.attempt_no = v_job.attempt_count
       and a.status = 'running';

    update public.pandora_build_jobs j
       set status = 'failed',
           current_stage = 'failed',
           error_code = 'BUILD_LEASE_RETRY_EXHAUSTED',
           public_error_summary = 'Build stopped after the retry limit was reached.',
           lease_owner = null,
           lease_token_sha256 = null,
           lease_expires_at = null,
           heartbeat_at = null
     where j.id = v_job.id
       and j.status in ('claimed','running')
       and j.attempt_count >= j.max_attempts;

    if found then
      update public.pandora_source_generation_queue q
         set status = 'failed',
             last_error_code = 'BUILD_LEASE_RETRY_EXHAUSTED',
             dispatched_at = null,
             completed_at = coalesce(q.completed_at, v_now),
             updated_at = v_now
       where q.build_job_id = v_job.id
         and q.status in ('queued','dispatching');
      v_exhausted := v_exhausted + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'retryableLeasesRequeued', v_requeued,
    'exhaustedLeasesFailed', v_exhausted,
    'deadlineJobsFailed', v_deadline_failed,
    'checkedAt', v_now
  );
end;
$fn$;

revoke all on function private.pandora_build_watchdog_tick_v1(integer)
  from public, anon, authenticated;
grant execute on function private.pandora_build_watchdog_tick_v1(integer)
  to service_role;

do $cron$
declare
  v_job_id bigint;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    for v_job_id in
      select jobid from cron.job where jobname = 'pandora-build-watchdog-v1'
    loop
      perform cron.unschedule(v_job_id);
    end loop;
    perform cron.schedule(
      'pandora-build-watchdog-v1',
      '* * * * *',
      'select private.pandora_build_watchdog_tick_v1(100);'
    );
  end if;
exception when others then
  -- Replay/test databases may intentionally omit pg_cron.
  null;
end
$cron$;

commit;
