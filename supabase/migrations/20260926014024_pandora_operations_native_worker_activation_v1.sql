alter table private.pandora_ops_workers
  drop constraint pandora_ops_workers_engine_check;
alter table private.pandora_ops_workers
  add constraint pandora_ops_workers_engine_check
  check (engine in ('chatgpt','pandora_native'));

create or replace function public.pandora_ops_register_native_worker_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_lanes text[],
  p_capabilities text[],
  p_capacity integer,
  p_receipt_ref text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
begin
  perform 1
  from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active'
  for share;
  if not found then
    raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501';
  end if;

  if p_worker_key is null or p_worker_key !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$'
     or p_principal_key is null or length(p_principal_key) not between 1 and 200
     or p_receipt_ref is null or length(p_receipt_ref) not between 1 and 1000
     or p_capacity < 1 or p_capacity > 32
     or cardinality(p_lanes) < 1
     or not (p_lanes <@ array['web','backend','mobile','growth','reliability','release','ares']::text[])
     or cardinality(p_capabilities) < 1
     or exists(select 1 from unnest(p_capabilities) c where c !~ '^[a-z0-9][a-z0-9_.:-]{0,119}$')
  then
    raise exception 'OPS_NATIVE_WORKER_REGISTRATION_INVALID' using errcode='22023';
  end if;

  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  )
  values(
    p_organization_id,p_project_id,p_worker_key,p_principal_key,'pandora_native',
    p_lanes,p_capabilities,p_capacity,true,true,'ready',clock_timestamp(),p_receipt_ref
  )
  on conflict (organization_id,project_id,worker_key) do update
    set principal_key=excluded.principal_key,
        engine='pandora_native',
        lanes=excluded.lanes,
        capabilities=excluded.capabilities,
        capacity=excluded.capacity,
        acknowledged=true,
        connected=true,
        health='ready',
        heartbeat_at=clock_timestamp(),
        registration_receipt=excluded.registration_receipt
    where private.pandora_ops_workers.engine='pandora_native'
      and private.pandora_ops_workers.principal_key=excluded.principal_key;

  if not found then
    raise exception 'OPS_NATIVE_WORKER_IDENTITY_CONFLICT' using errcode='42501';
  end if;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'native-worker:'||p_worker_key,null,
    'worker_acknowledged',p_receipt_ref
  );
  return jsonb_build_object('registered',true,'engine','pandora_native','workerId',p_worker_key);
end;
$body$;

revoke all on function public.pandora_ops_register_native_worker_v1(uuid,uuid,text,text,text[],text[],integer,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_register_native_worker_v1(uuid,uuid,text,text,text[],text[],integer,text)
  to service_role;

do $body$
declare v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='pandora_ops_wake_token_v1'
  limit 1;
  if nullif(v_secret,'') is null then
    perform vault.create_secret(
      rtrim(translate(encode(extensions.gen_random_bytes(48),'base64'),'+/','-_'),'='),
      'pandora_ops_wake_token_v1',
      'Operations Room Vercel scheduler wake bearer token v1'
    );
  end if;
end;
$body$;

create or replace function public.pandora_ops_wake_authorize_v1(p_token_sha256 text)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $body$
declare v_secret text; v_expected text;
begin
  if p_token_sha256 is null or p_token_sha256 !~ '^[a-f0-9]{64}$' then
    return false;
  end if;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='pandora_ops_wake_token_v1'
  limit 1;
  if nullif(v_secret,'') is null then return false; end if;
  v_expected:=encode(extensions.digest(convert_to(v_secret,'UTF8'),'sha256'),'hex');
  return v_expected=p_token_sha256;
end;
$body$;

revoke all on function public.pandora_ops_wake_authorize_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_ops_wake_authorize_v1(text) to service_role;

create or replace function public.pandora_ops_activation_readback_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare v_workspace private.pandora_ops_workspaces%rowtype;
begin
  perform 1 from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active';
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  select * into v_workspace
  from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;

  return jsonb_build_object(
    'paused',v_workspace.paused,
    'noProduction',v_workspace.no_production,
    'revision',v_workspace.revision,
    'maxConcurrency',v_workspace.max_concurrency,
    'connectorDeliveryTable',to_regclass('private.pandora_ops_connector_deliveries') is not null,
    'connectorDeliveryRpc',to_regprocedure('public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb)') is not null,
    'connectorReconcileRpc',to_regprocedure('public.pandora_ops_connector_reconcile_v1(uuid,uuid,uuid,bigint,text)') is not null,
    'nativeWorkerRpc',to_regprocedure('public.pandora_ops_register_native_worker_v1(uuid,uuid,text,text,text[],text[],integer,text)') is not null,
    'workers',(select count(*) from private.pandora_ops_workers where organization_id=p_organization_id and project_id=p_project_id),
    'freshWorkers',(select count(*) from private.pandora_ops_workers where organization_id=p_organization_id and project_id=p_project_id and acknowledged and connected and health='ready' and heartbeat_at>clock_timestamp()-interval '60 seconds'),
    'queuedTasks',(select count(*) from private.pandora_ops_tasks where organization_id=p_organization_id and project_id=p_project_id and status='queued')
  );
end;
$body$;

revoke all on function public.pandora_ops_activation_readback_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.pandora_ops_activation_readback_v1(uuid,uuid) to service_role;