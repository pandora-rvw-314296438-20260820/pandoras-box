do $do$
begin
  if not exists (select 1 from vault.secrets where name='plp_oidc_deploy_run_secret_20260917') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),
      'plp_oidc_deploy_run_secret_20260917',
      'One-time authorization for exact-source PLP OIDC preview deployment'
    );
  end if;
end
$do$;
