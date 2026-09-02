-- Pandora paid-source privilege hardening v1.
-- Keep durable-source entitlement administration available to service_role,
-- but remove table-level privilege paths that can bypass the governed RPCs.
-- The access audit is append-only evidence: service_role may read and append,
-- never update, delete, truncate, alter triggers, or use references privileges.

revoke all on table public.pandora_source_entitlements from public, anon, authenticated;
revoke all on table public.pandora_source_access_audit from public, anon, authenticated;

revoke all on table public.pandora_source_entitlements from service_role;
grant select, insert, update, delete
  on table public.pandora_source_entitlements
  to service_role;

revoke all on table public.pandora_source_access_audit from service_role;
grant select, insert
  on table public.pandora_source_access_audit
  to service_role;
