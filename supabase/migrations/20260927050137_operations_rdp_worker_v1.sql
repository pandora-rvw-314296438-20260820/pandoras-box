-- Governed Windows RDP worker identity for Pandora Operations Room.
-- The raw worker token remains only on the authorized RDP. Supabase Vault stores only its SHA-256 verifier.

alter table private.pandora_ops_workers
  drop constraint if exists pandora_ops_workers_engine_check;

alter table private.pandora_ops_workers
  add constraint pandora_ops_workers_engine_check
  check (engine = any (array['chatgpt'::text,'pandora_native'::text,'rdp'::text]));

create or replace function public.pandora_ops_register_rdp_worker_v1(
  p_organization_id uuid, p_project_id uuid, p_worker_key text, p_principal_key text,
  p_lanes text[], p_capabilities text[], p_capacity integer, p_receipt_ref text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
begin
  perform 1 from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;
  if p_worker_key <> 'pandora-rdp-windows-01'
     or p_principal_key <> 'rdp:EC2AMAZ-SPAE2VG:operations-worker-v1'
     or p_capacity <> 1
     or p_lanes <> array['reliability','mobile']::text[]
     or p_capabilities <> array['rdp.execute','rdp.toolchain.verify','rdp.github_runner.verify','rdp.android.verify','rdp.flutter.verify','worker.reconcile']::text[]
     or p_receipt_ref <> 'rdp:EC2AMAZ-SPAE2VG:scheduled-worker-v1'
  then raise exception 'OPS_RDP_WORKER_REGISTRATION_INVALID' using errcode='22023'; end if;
  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  ) values(
    p_organization_id,p_project_id,p_worker_key,p_principal_key,'rdp',
    p_lanes,p_capabilities,p_capacity,true,true,'ready',clock_timestamp(),p_receipt_ref
  )
  on conflict (organization_id,project_id,worker_key) do update
    set engine='rdp',lanes=excluded.lanes,capabilities=excluded.capabilities,capacity=1,
        acknowledged=true,connected=true,health='ready',heartbeat_at=clock_timestamp(),
        registration_receipt=excluded.registration_receipt
    where private.pandora_ops_workers.principal_key=excluded.principal_key
      and private.pandora_ops_workers.engine='rdp';
  if not found then raise exception 'OPS_RDP_WORKER_IDENTITY_CONFLICT' using errcode='42501'; end if;
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'rdp-worker:'||p_worker_key,null,
    'worker_acknowledged',p_receipt_ref
  );
  return jsonb_build_object('registered',true,'engine','rdp','workerId',p_worker_key);
end;
$body$;

create or replace function public.pandora_ops_rdp_authorize_v1(
  p_organization_id uuid, p_worker_key text, p_token_sha256 text
) returns boolean
language plpgsql security definer set search_path=''
as $body$
declare expected_hash text;
begin
  if p_organization_id <> '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
     or p_worker_key <> 'pandora-rdp-windows-01'
     or p_token_sha256 !~ '^[0-9a-f]{64}$'
  then return false; end if;
  select trim(decrypted_secret) into expected_hash
  from vault.decrypted_secrets
  where name='pandora_operations_rdp_worker_token_sha256'
  limit 1;
  return expected_hash is not null
    and expected_hash ~ '^[0-9a-f]{64}$'
    and expected_hash=p_token_sha256;
end;
$body$;

revoke all on function public.pandora_ops_register_rdp_worker_v1(uuid,uuid,text,text,text[],text[],integer,text)
from public,anon,authenticated;
grant execute on function public.pandora_ops_register_rdp_worker_v1(uuid,uuid,text,text,text[],text[],integer,text)
to service_role;
revoke all on function public.pandora_ops_rdp_authorize_v1(uuid,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_ops_rdp_authorize_v1(uuid,text,text)
to service_role;
