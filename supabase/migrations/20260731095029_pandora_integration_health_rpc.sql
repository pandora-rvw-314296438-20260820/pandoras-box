-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_set_integration_health(
  p_organization_id uuid,
  p_project_key text,
  p_provider text,
  p_status text,
  p_details jsonb default '{}'::jsonb,
  p_last_event_at timestamptz default null,
  p_last_success_at timestamptz default null,
  p_stale_after timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_row public.projectos_integration_health%rowtype;
begin
  perform private.assert_control_service_role();
  if p_status not in ('healthy','degraded','down','unknown','not_configured') then
    raise exception 'invalid_integration_status';
  end if;
  select id into strict v_project_id from public.projectos_projects
    where organization_id=p_organization_id and project_key=p_project_key;
  insert into public.projectos_integration_health(
    organization_id,project_id,provider,status,last_event_at,last_success_at,stale_after,details
  ) values (
    p_organization_id,v_project_id,p_provider,p_status,p_last_event_at,p_last_success_at,p_stale_after,coalesce(p_details,'{}'::jsonb)
  ) on conflict (project_id,provider) do update set
    status=excluded.status,
    last_event_at=coalesce(excluded.last_event_at,projectos_integration_health.last_event_at),
    last_success_at=coalesce(excluded.last_success_at,projectos_integration_health.last_success_at),
    stale_after=excluded.stale_after,
    details=excluded.details,
    updated_at=now()
  returning * into v_row;
  perform public.projectos_recompute_project(p_organization_id,p_project_key);
  return to_jsonb(v_row);
end;
$$;
grant execute on function public.projectos_set_integration_health(uuid,text,text,text,jsonb,timestamptz,timestamptz,timestamptz) to service_role;
