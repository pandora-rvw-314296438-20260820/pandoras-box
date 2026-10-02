revoke all on function public.pandora_connection_verify_vault_no_spend_v1(uuid,text,uuid) from public, anon, authenticated;

grant execute on function public.pandora_connection_verify_vault_no_spend_v1(uuid,text,uuid) to service_role;
