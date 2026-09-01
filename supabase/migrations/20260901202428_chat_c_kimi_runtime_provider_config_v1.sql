-- Chat C runtime provider configuration bootstrap.
-- Non-secret, server-authoritative controls only. Kimi remains disabled for customer routing.
insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('kimi','enabled','false',true,now()),
  ('kimi','default_model','kimi-k3',true,now()),
  ('kimi','allowed_models','["kimi-k3"]',true,now()),
  ('kimi','routing_eligible','true',true,now()),
  ('kimi','task_eligibility','["chat","clarify","create_project","change_project","inspect_project","build","preview","publish","domain","other"]',true,now()),
  ('kimi','policy_version','chat-c-v1',true,now())
on conflict (provider,config_key) do update
set config_value=excluded.config_value, active=excluded.active, updated_at=excluded.updated_at;

revoke insert, update, delete on public.pandora_runtime_provider_configs from anon, authenticated;
