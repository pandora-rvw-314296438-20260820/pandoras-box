drop function if exists private.publish_plp_oidc_runtime_fix_20260917();
drop function if exists private.gate_plp_pr7_20260917(boolean);
drop function if exists private.invoke_plp_final_deployer_20260917();
delete from vault.secrets where name='plp_final_deploy_run_secret_20260917';
