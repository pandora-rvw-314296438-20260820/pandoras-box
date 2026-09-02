-- Canonical Vercel project identity + Supabase MCP Connect registration.
-- Non-secret provider metadata is durable here; OAuth client secrets remain provider-managed.

insert into public.pandora_runtime_provider_configs(provider, config_key, config_value, active)
values
  ('vercel', 'mcpmaster_project_id', 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk', true),
  ('vercel', 'memory_project_id', 'prj_brg3BJDcHfSftHH84NhnFtDJAnDO', true),
  ('supabase_connect', 'service_id', 'scl_cViLYUHbII9VXkBUY7ikA', true),
  ('supabase_connect', 'client_name', 'pandoras-box', true),
  ('supabase_connect', 'client_id', '3f8cd9ca-54c4-4563-a16b-0deb01208233', true),
  ('supabase_connect', 'mcp_slug', 'mcp.supabase.com/pandoras-box', true),
  ('supabase_connect', 'server_url', 'https://mcp.supabase.com/mcp', true),
  ('supabase_connect', 'discovery_url', 'https://api.supabase.com', true),
  ('supabase_connect', 'authorization_endpoint', 'https://api.supabase.com/v1/oauth/authorize', true),
  ('supabase_connect', 'token_endpoint', 'https://api.supabase.com/v1/oauth/token', true),
  ('supabase_connect', 'subject_type', 'user', true),
  ('supabase_connect', 'registration_method', 'dcr', true),
  ('supabase_connect', 'token_auth_method', 'client_secret_basic', true),
  ('supabase_connect', 'pkce_required', 'false', true),
  ('supabase_connect', 'client_secret_storage', 'vercel_connect_managed', true),
  ('supabase_connect', 'user_authorization_scopes', 'organizations:read,projects:read,projects:write,database:write,database:read,analytics:read,edge_functions:read,edge_functions:write,environment:read,environment:write,storage:read,storage:write', true),
  ('supabase_connect', 'secrets_read_requested', 'false', true)
on conflict (provider, config_key) do update
set config_value = excluded.config_value,
    active = excluded.active,
    updated_at = now();

update public.connector_installations
set configuration = jsonb_set(
      jsonb_set(
        configuration,
        '{project_repo_allowlist,prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk}',
        to_jsonb('pandora-rvw-314296438-20260820/pandoras-box'::text),
        true
      ),
      '{project_repo_allowlist,prj_brg3BJDcHfSftHH84NhnFtDJAnDO}',
      to_jsonb('pandora-rvw-314296438-20260820/pandoras-box-memory'::text),
      true
    ),
    updated_at = now()
where provider = 'vercel'
  and status in ('pending','active');

-- Fail closed if the canonical Vercel project map did not persist exactly.
do $$
begin
  if not exists (
    select 1
    from public.connector_installations
    where provider = 'vercel'
      and status in ('pending','active')
      and configuration #>> '{project_repo_allowlist,prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk}' = 'pandora-rvw-314296438-20260820/pandoras-box'
      and configuration #>> '{project_repo_allowlist,prj_brg3BJDcHfSftHH84NhnFtDJAnDO}' = 'pandora-rvw-314296438-20260820/pandoras-box-memory'
  ) then
    raise exception 'canonical Vercel project mapping is not installed';
  end if;

  if exists (
    select 1
    from public.pandora_runtime_provider_configs
    where provider = 'supabase_connect'
      and config_key = 'secrets_read_requested'
      and config_value <> 'false'
      and active = true
  ) then
    raise exception 'Supabase Connect secrets:read must remain disabled';
  end if;
end
$$;
