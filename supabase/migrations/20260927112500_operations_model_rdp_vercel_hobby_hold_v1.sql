-- Hold the model-first Vercel wake on Hobby function-count limits.
-- The DB/control contracts remain installed, but no standalone API function is
-- deployed while the project is capped at 12 Serverless Functions.
-- ChatGPT-direct execution is unaffected because its ingress/tick are private DB contracts.

do $body$
declare v_job bigint;
begin
  select jobid into v_job
  from cron.job
  where jobname='pandora-operations-reasoning-rdp-bridge-v1'
  limit 1;
  if v_job is not null then
    perform cron.unschedule(v_job);
  end if;
end;
$body$;

insert into public.pandora_runtime_provider_configs(
  provider,config_key,config_value,active,updated_at
) values
  ('operations_model_rdp_bridge','enabled','false',true,clock_timestamp()),
  ('operations_model_rdp_bridge','runtime_state','held',true,clock_timestamp()),
  ('operations_model_rdp_bridge','runtime_hold_reason','vercel_hobby_function_limit_and_zero_workspace_budget',true,clock_timestamp())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,
    active=true,
    updated_at=clock_timestamp();

comment on function private.pandora_ops_enable_reasoning_rdp_bridge_schedule_v1() is
  'Model-first wake remains disabled while mcpmaster is capped at 12 Vercel Serverless Functions and Operations inference budget is zero. Do not enable until the handler is consolidated into an existing function or the deployment limit changes.';
