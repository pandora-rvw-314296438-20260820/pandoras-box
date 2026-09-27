-- Durable ARTEMIS verifier identity for the authorized Windows RDP.
-- The execution worker remains separate; this verifier has no source-write, deploy, merge, spend, OAuth or Memory authority.

create or replace function public.pandora_ops_register_rdp_artemis_verifier_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_receipt_ref text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_RDP_ARTEMIS_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  perform 1
  from private.pandora_ops_project_bindings
  where organization_id=p_organization_id
    and project_id=p_project_id
    and state='active'
  for share;
  if not found then
    raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501';
  end if;

  if p_worker_key <> 'pandora-rdp-artemis-01'
     or p_principal_key <> 'rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1'
     or p_receipt_ref <> 'rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1' then
    raise exception 'OPS_RDP_ARTEMIS_IDENTITY_INVALID' using errcode='22023';
  end if;

  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  ) values(
    p_organization_id,p_project_id,p_worker_key,p_principal_key,'rdp',
    array['release']::text[],
    array['release.verify','provider.readback','rdp.release.verify']::text[],
    1,true,true,'ready',clock_timestamp(),p_receipt_ref
  )
  on conflict (organization_id,project_id,worker_key) do update
    set engine='rdp',
        lanes=excluded.lanes,
        capabilities=excluded.capabilities,
        capacity=1,
        acknowledged=true,
        connected=true,
        health='ready',
        heartbeat_at=clock_timestamp(),
        registration_receipt=excluded.registration_receipt
    where private.pandora_ops_workers.principal_key=excluded.principal_key
      and private.pandora_ops_workers.engine='rdp';

  if not found then
    raise exception 'OPS_RDP_ARTEMIS_IDENTITY_CONFLICT' using errcode='42501';
  end if;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'rdp-artemis-worker:'||p_worker_key,
    null,'worker_acknowledged',p_receipt_ref
  );

  return jsonb_build_object(
    'registered',true,
    'workerId',p_worker_key,
    'principalKey',p_principal_key,
    'engine','rdp',
    'role','independent_release_verifier'
  );
end;
$fn$;

revoke all on function public.pandora_ops_register_rdp_artemis_verifier_v1(uuid,uuid,text,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_ops_register_rdp_artemis_verifier_v1(uuid,uuid,text,text,text)
to service_role;
