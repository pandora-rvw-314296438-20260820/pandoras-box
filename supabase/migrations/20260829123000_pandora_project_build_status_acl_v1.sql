-- Fail closed: owner-safe build status is authenticated-only.
-- PostgreSQL grants EXECUTE to PUBLIC on newly created functions unless explicitly revoked.

revoke all on function public.pandora_project_build_status_20260829(uuid) from public;
revoke all on function public.pandora_project_build_status_20260829(uuid) from anon;
grant execute on function public.pandora_project_build_status_20260829(uuid) to authenticated;
grant execute on function public.pandora_project_build_status_20260829(uuid) to service_role;
