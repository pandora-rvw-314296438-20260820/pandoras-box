-- Rollback for 20261010091000_plp_paypal_webhook_ingest_v1.sql
-- Unschedules pg_cron job 'pandora-plp-billing-reconcile-v1' if present,
-- then drops the 3 webhook / background reconcile functions with exact signatures.

do $unschedule$
declare
  v_job record;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and to_regnamespace('cron') is not null then
    for v_job in execute
      'select jobid from cron.job where jobname = $1'
      using 'pandora-plp-billing-reconcile-v1'
    loop
      execute 'select cron.unschedule($1)' using v_job.jobid;
    end loop;
  end if;
end;
$unschedule$;

drop function if exists public.pandora_plp_paypal_webhook_ingest_v1(jsonb, text);
drop function if exists private.pandora_paypal_verify_webhook_v1(jsonb, text);
drop function if exists private.pandora_plp_billing_reconcile_open_v1(int);
