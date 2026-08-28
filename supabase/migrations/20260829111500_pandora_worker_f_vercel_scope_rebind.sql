-- Worker F: forward-only provider scope rebind after canonical Vercel project transfer.
-- The provider credential remains in Supabase Vault secret `vercel`; this migration stores only non-secret account scope metadata.

insert into public.pandora_runtime_provider_configs(provider, config_key, config_value, active)
values ('vercel', 'team_id', 'team_3yw1CN59ce4pj5SwyQGCAqN3', true)
on conflict (provider, config_key) do update
set config_value = excluded.config_value,
    active = excluded.active,
    updated_at = now();
