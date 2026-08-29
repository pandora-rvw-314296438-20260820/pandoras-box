-- Forward-only ACL repair for owner-safe generated build status.
-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default, so revoking
-- only anon is insufficient because anon inherits the PUBLIC grant.

revoke all on function public.pandora_project_build_status_20260829(uuid) from public;
revoke all on function public.pandora_project_build_status_20260829(uuid) from anon;
grant execute on function public.pandora_project_build_status_20260829(uuid) to authenticated;
grant execute on function public.pandora_project_build_status_20260829(uuid) to service_role;
