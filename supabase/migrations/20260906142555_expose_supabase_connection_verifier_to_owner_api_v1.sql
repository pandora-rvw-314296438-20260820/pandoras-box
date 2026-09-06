create or replace function public.pandora_verify_supabase_project_connection_20260906(
  p_organization_id uuid,
  p_installation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_user not in ('postgres','service_role')
     and coalesce(auth.jwt() ->> 'role','') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from public.connector_installations c
    where c.id = p_installation_id
      and c.organization_id = p_organization_id
      and c.provider = 'supabase'
      and c.status = 'active'::public.connector_status
  ) then
    raise exception 'Supabase connector not found' using errcode='P0002';
  end if;

  return private.pandora_verify_supabase_project_connection_20260906(
    p_installation_id
  );
end;
$$;

revoke all on function public.pandora_verify_supabase_project_connection_20260906(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pandora_verify_supabase_project_connection_20260906(uuid, uuid)
  to service_role;
