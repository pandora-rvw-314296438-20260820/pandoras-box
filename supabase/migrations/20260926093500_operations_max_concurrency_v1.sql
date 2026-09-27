-- Owner/admin revision-fenced Operations concurrency control.
-- Adds no worker capacity and never bypasses lane/capability/resource/dependency fences.

create or replace function public.pandora_ops_set_max_concurrency_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_actor_id uuid,
  p_expected_revision bigint,
  p_max_concurrency integer
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  w private.pandora_ops_workspaces%rowtype;
  v_active integer;
begin
  if p_max_concurrency is null or p_max_concurrency not between 1 and 16 then
    raise exception 'OPS_MAX_CONCURRENCY_INVALID';
  end if;

  perform 1
  from public.memberships
  where organization_id=p_organization_id
    and user_id=p_actor_id
    and status='active'
    and role in ('owner','admin')
  for share;
  if not found then
    raise exception 'OPS_OWNER_SCOPE_DENIED' using errcode='42501';
  end if;

  perform 1
  from private.pandora_ops_project_bindings
  where organization_id=p_organization_id
    and project_id=p_project_id
    and state='active'
  for share;
  if not found then
    raise exception 'OPS_OWNER_PROJECT_DENIED' using errcode='42501';
  end if;

  select * into w
  from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id
  for update;
  if not found or w.revision is distinct from p_expected_revision then
    raise exception 'OPS_CONTROL_REVISION_CONFLICT';
  end if;

  select count(*) into v_active
  from private.pandora_ops_leases
  where organization_id=p_organization_id
    and project_id=p_project_id
    and state<>'released';

  if p_max_concurrency < v_active then
    raise exception 'OPS_MAX_CONCURRENCY_BELOW_ACTIVE_LEASES';
  end if;

  update private.pandora_ops_workspaces
  set max_concurrency=p_max_concurrency,
      revision=revision+1,
      updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
  returning * into w;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'control:'||w.revision::text,null,'owner_set_max_concurrency'
  );

  return jsonb_build_object(
    'revision',w.revision,
    'paused',w.paused,
    'noProduction',w.no_production,
    'maxConcurrency',w.max_concurrency
  );
end;
$body$;

create or replace function public.pandora_ops_owner_request_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_actor_id uuid,
  p_operation text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
begin
 perform 1 from public.memberships
 where organization_id=p_organization_id
   and user_id=p_actor_id
   and status='active'
   and role in ('owner','admin')
 for share;
 if not found then raise exception 'OPS_OWNER_SCOPE_DENIED' using errcode='42501'; end if;

 perform 1 from private.pandora_ops_project_bindings
 where project_id=p_project_id
   and organization_id=p_organization_id
   and state='active'
 for share;
 if not found then raise exception 'OPS_OWNER_PROJECT_DENIED' using errcode='42501'; end if;

 if p_operation='overview' then
  return public.pandora_ops_snapshot_v1(p_organization_id,p_project_id);
 elsif p_operation='ingest' then
  return public.pandora_ops_ingest_v1(p_organization_id,p_project_id,p_payload->'tasks');
 elsif p_operation='set_max_concurrency' then
  return public.pandora_ops_set_max_concurrency_v1(
    p_organization_id,p_project_id,p_actor_id,
    (p_payload->>'expectedRevision')::bigint,
    (p_payload->>'maxConcurrency')::integer
  );
 elsif p_operation in ('pause','resume','no_production','allow_production','cancel_task') then
  return public.pandora_ops_control_v1(
    p_organization_id,p_project_id,
    (p_payload->>'expectedRevision')::bigint,
    p_operation,
    case when p_operation='cancel_task' then p_payload->>'taskId' else null end
  );
 end if;
 raise exception 'OPS_OWNER_OPERATION_NOT_EXPOSED' using errcode='42501';
end;
$body$;

revoke all on function public.pandora_ops_set_max_concurrency_v1(uuid,uuid,uuid,bigint,integer)
from public,anon,authenticated;
grant execute on function public.pandora_ops_set_max_concurrency_v1(uuid,uuid,uuid,bigint,integer)
to service_role;

revoke all on function public.pandora_ops_owner_request_v1(uuid,uuid,uuid,text,jsonb)
from public,anon,authenticated;
grant execute on function public.pandora_ops_owner_request_v1(uuid,uuid,uuid,text,jsonb)
to service_role;
