begin;

revoke all on table public.pandora_project_versions from anon;
revoke all on table public.pandora_project_deployments from anon;
revoke all on table public.pandora_project_domains from anon;

revoke insert, update, delete, truncate, references, trigger
  on table public.pandora_project_versions from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.pandora_project_deployments from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.pandora_project_domains from authenticated;

grant select on table public.pandora_project_versions to authenticated;
grant select on table public.pandora_project_deployments to authenticated;
grant select on table public.pandora_project_domains to authenticated;

commit;
