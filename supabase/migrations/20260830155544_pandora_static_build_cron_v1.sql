-- Keep governed static builds moving even when no customer screen is actively polling.

do $block$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname='pandora-static-build-convergence-v1'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'pandora-static-build-convergence-v1',
    '* * * * *',
    'select private.pandora_converge_static_builds_tick_20260830();'
  );
end
$block$;
