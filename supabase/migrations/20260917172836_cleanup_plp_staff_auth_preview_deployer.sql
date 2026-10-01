drop function if exists private.invoke_plp_staff_auth_preview_20260918();
delete from vault.secrets where name='plp_staff_auth_preview_run_20260918';
