-- Harden the recent-chat timestamp trigger function.
--
-- This SECURITY DEFINER function is trigger-only. It is not an RPC surface,
-- so client roles must not have direct EXECUTE privileges.

revoke execute on function public.pandora_intelligence_touch_thread_v1()
from public, anon, authenticated, service_role;
