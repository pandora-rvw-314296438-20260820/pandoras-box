-- Pandora Project Experience Projection privilege hardening v2
-- Keep authenticated clients strictly read-only. TRUNCATE is not protected by RLS.

revoke all on table public.pandora_project_experience_projection from authenticated;
grant select on table public.pandora_project_experience_projection to authenticated;
revoke all on table public.pandora_project_experience_projection from anon;
