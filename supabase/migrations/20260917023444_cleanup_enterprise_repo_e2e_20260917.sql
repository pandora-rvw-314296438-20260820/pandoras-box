delete from public.pandora_runtime_provider_configs
where provider='enterprise_e2e' and config_key='one_time_key';

drop function if exists private.pandora_enterprise_e2e_invoke_20260917();
drop table if exists private.enterprise_repo_upload_staging_20260917;
