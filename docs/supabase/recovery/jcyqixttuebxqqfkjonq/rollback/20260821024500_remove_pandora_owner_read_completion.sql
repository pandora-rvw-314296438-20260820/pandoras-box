-- Roll back the Phase 0 owner-read completion RPC only.
-- Historical intake/audit evidence is intentionally retained as immutable truth.
revoke all on function public.pandora_complete_owner_read_intake(uuid, uuid, text, jsonb) from public, anon, authenticated, service_role;
drop function if exists public.pandora_complete_owner_read_intake(uuid, uuid, text, jsonb);
