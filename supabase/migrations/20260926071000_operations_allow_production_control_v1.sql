-- Governed owner/admin transition for re-enabling production-risk task claims.
-- no_production remains fail-closed by default and can only be cleared through
-- revision-fenced owner_request admission.
create or replace function public.pandora_ops_control_v1(
 p_organization_id uuid,p_project_id uuid,p_expected_revision bigint,
 p_action text,p_task_key text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w private.pandora_ops_workspaces%rowtype;
begin
 select * into w from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id for update;
 if not found or w.revision is distinct from p_expected_revision then
  raise exception 'OPS_CONTROL_REVISION_CONFLICT';
 end if;
 if p_action='pause' then w.paused:=true;
 elsif p_action='resume' then w.paused:=false;
 elsif p_action='no_production' then w.no_production:=true;
 elsif p_action='allow_production' then w.no_production:=false;
 elsif p_action='cancel_task' then
  update private.pandora_ops_tasks
   set cancel_requested=true,
       status=case when status in ('queued','handed_off','verifying') then 'cancelled' else status end,
       revision=revision+1
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=p_task_key and status not in ('complete','cancelled','failed');
  if not found then raise exception 'OPS_TASK_NOT_CANCELLABLE'; end if;
 else raise exception 'OPS_CONTROL_NOT_REGISTERED'; end if;
 update private.pandora_ops_workspaces
  set paused=w.paused,no_production=w.no_production,revision=revision+1,updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
  returning * into w;
 perform private.pandora_ops_event_v1(
  p_organization_id,p_project_id,'control:'||w.revision::text,p_task_key,'owner_'||p_action
 );
 return jsonb_build_object('revision',w.revision,'paused',w.paused,'noProduction',w.no_production);
end; $$;

create or replace function public.pandora_ops_owner_request_v1(
 p_organization_id uuid,p_project_id uuid,p_actor_id uuid,
 p_operation text,p_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.memberships
  where organization_id=p_organization_id and user_id=p_actor_id
    and status='active' and role in ('owner','admin') for share;
 if not found then raise exception 'OPS_OWNER_SCOPE_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_project_bindings
  where project_id=p_project_id and organization_id=p_organization_id and state='active' for share;
 if not found then raise exception 'OPS_OWNER_PROJECT_DENIED' using errcode='42501'; end if;
 if p_operation='overview' then
  return public.pandora_ops_snapshot_v1(p_organization_id,p_project_id);
 elsif p_operation='ingest' then
  return public.pandora_ops_ingest_v1(p_organization_id,p_project_id,p_payload->'tasks');
 elsif p_operation in ('pause','resume','no_production','allow_production','cancel_task') then
  return public.pandora_ops_control_v1(
   p_organization_id,p_project_id,(p_payload->>'expectedRevision')::bigint,p_operation,
   case when p_operation='cancel_task' then p_payload->>'taskId' else null end
  );
 end if;
 raise exception 'OPS_OWNER_OPERATION_NOT_EXPOSED' using errcode='42501';
end; $$;

revoke all on function public.pandora_ops_control_v1(uuid,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_control_v1(uuid,uuid,bigint,text,text) to service_role;
revoke all on function public.pandora_ops_owner_request_v1(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_ops_owner_request_v1(uuid,uuid,uuid,text,jsonb) to service_role;
