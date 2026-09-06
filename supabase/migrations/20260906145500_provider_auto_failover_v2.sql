-- Explicit owner-directed provider failover convergence.
-- No secrets are stored here. Provider credentials remain behind their existing Vault/RPC boundaries.
insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('kimi','enabled','true',true,now()),
  ('kimi','routing_eligible','true',true,now()),
  ('kimi','fallback_enabled','true',true,now()),
  ('kimi','policy_version','provider-auto-failover-v2',true,now())
on conflict (provider,config_key) do update
set config_value=excluded.config_value, active=excluded.active, updated_at=excluded.updated_at;

revoke insert, update, delete on public.pandora_runtime_provider_configs from anon, authenticated;
