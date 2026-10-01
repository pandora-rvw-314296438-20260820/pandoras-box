drop function if exists private.publish_plp_oidc_client_20260917();
drop function if exists private.gate_plp_pr6_20260917(boolean);
drop function if exists private.invoke_plp_oidc_deployer_20260917();
drop function if exists private.test_plp_oidc_gateway_20260917();
delete from vault.secrets where name in ('plp_oidc_deploy_run_secret_20260917','plp_temp_staff_code_20260917');
