
revoke execute on function public.pandora_ci_rescue_claim_v1(integer) from public, anon, authenticated;
revoke execute on function public.pandora_ci_rescue_internal_auth_v1(text) from public, anon, authenticated;
revoke execute on function public.pandora_ci_rescue_update_v1(uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.pandora_ci_rescue_claim_v1(integer) to service_role;
grant execute on function public.pandora_ci_rescue_internal_auth_v1(text) to service_role;
grant execute on function public.pandora_ci_rescue_update_v1(uuid,uuid,text,jsonb) to service_role;
