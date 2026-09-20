-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_begin_reconciliation(
  p_organization_id uuid,
  p_project_key text,
  p_provider text,
  p_cursor_before jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_run public.projectos_reconciliation_runs%rowtype;
begin
  perform private.assert_control_service_role();
  select id into strict v_project_id from public.projectos_projects
    where organization_id=p_organization_id and project_key=p_project_key;
  insert into public.projectos_reconciliation_runs(
    organization_id,project_id,provider,status,cursor_before
  ) values (
    p_organization_id,v_project_id,p_provider,'running',coalesce(p_cursor_before,'{}'::jsonb)
  ) returning * into v_run;
  return to_jsonb(v_run);
end;
$$;

create or replace function public.projectos_finish_reconciliation(
  p_organization_id uuid,
  p_run_id uuid,
  p_status text,
  p_cursor_after jsonb default '{}'::jsonb,
  p_stats jsonb default '{}'::jsonb,
  p_error_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_run public.projectos_reconciliation_runs%rowtype;
begin
  perform private.assert_control_service_role();
  if p_status not in ('succeeded','partial','failed') then
    raise exception 'invalid_reconciliation_status';
  end if;
  update public.projectos_reconciliation_runs set
    status=p_status,
    cursor_after=coalesce(p_cursor_after,'{}'::jsonb),
    stats=coalesce(p_stats,'{}'::jsonb),
    error_code=p_error_code,
    completed_at=now()
  where organization_id=p_organization_id and id=p_run_id
  returning * into strict v_run;
  return to_jsonb(v_run);
end;
$$;

grant execute on function public.projectos_begin_reconciliation(uuid,text,text,jsonb) to service_role;
grant execute on function public.projectos_finish_reconciliation(uuid,uuid,text,jsonb,jsonb,text) to service_role;
