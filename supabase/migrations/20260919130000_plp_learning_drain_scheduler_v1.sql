-- Schedule the PLP verified-learning drain from Supabase rather than Vercel Cron.
-- This avoids Vercel Hobby cron-frequency limits while preserving the existing
-- CRON_SECRET + VERCEL_OIDC_TOKEN security boundary inside the Vercel handler.

do $$
declare
  v_job record;
begin
  for v_job in
    select jobid from cron.job where jobname = 'plp-learning-drain'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
end;
$$;

select cron.schedule(
  'plp-learning-drain',
  '* * * * *',
  $cron$
    select net.http_get(
      url := 'https://enterprise-omega-five.vercel.app/api/plp-learning-drain',
      params := '{}'::jsonb,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'plp_enterprise_cron_secret'
          limit 1
        ),
        'Accept', 'application/json',
        'User-Agent', 'Pandora-PLP-Learning-Cron/1.0'
      ),
      timeout_milliseconds := 20000
    );
  $cron$
);
