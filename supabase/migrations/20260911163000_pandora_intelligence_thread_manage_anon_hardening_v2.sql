-- Remove any explicit anonymous execute privilege preserved by CREATE OR REPLACE FUNCTION.
-- Authenticated owner/org guards remain the only client execution path.

revoke all on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) from anon;
revoke all on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) from public;
grant execute on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) to service_role;
