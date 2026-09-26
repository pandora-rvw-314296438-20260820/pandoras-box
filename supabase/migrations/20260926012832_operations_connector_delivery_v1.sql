-- Additive source; render through a CLI-generated migration before production deployment.
-- No worker, project, grant, credential, schedule or active workspace is seeded.
create table private.pandora_ops_connector_deliveries (
 dispatch_id uuid primary key references private.pandora_ops_dispatch_outbox(id),
 lease_id uuid not null unique references private.pandora_ops_leases(id),
 organization_id uuid not null,
 project_id uuid not null,
 envelope jsonb not null check(jsonb_typeof(envelope)='object'),
 envelope_digest text not null check(envelope_digest ~ '^[a-f0-9]{64}$'),
 request_digest text not null check(request_digest ~ '^[a-f0-9]{64}$'),
 state text not null default 'sending' check(state in ('sending','delivered','unknown','acknowledged')),
 provider_receipt jsonb,
 authenticated_ack jsonb,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(organization_id,project_id) references private.pandora_ops_workspaces(organization_id,project_id)
);
alter table private.pandora_ops_connector_deliveries enable row level security;
revoke all on private.pandora_ops_connector_deliveries from public,anon,authenticated,service_role;

create function private.pandora_ops_connector_immutable_v1() returns trigger
language plpgsql security definer set search_path='' as $body$
begin
 if tg_op='DELETE' then raise exception 'OPS_CONNECTOR_HISTORY_IMMUTABLE'; end if;
 if row(new.dispatch_id,new.lease_id,new.organization_id,new.project_id,new.envelope,new.envelope_digest,new.request_digest,new.created_at)
  is distinct from row(old.dispatch_id,old.lease_id,old.organization_id,old.project_id,old.envelope,old.envelope_digest,old.request_digest,old.created_at)
  or (old.provider_receipt is not null and new.provider_receipt is distinct from old.provider_receipt)
  or (old.authenticated_ack is not null and new.authenticated_ack is distinct from old.authenticated_ack)
 then raise exception 'OPS_CONNECTOR_HISTORY_IMMUTABLE'; end if;
 return new;
end; $body$;
create trigger pandora_ops_connector_immutable before update or delete on private.pandora_ops_connector_deliveries
 for each row execute function private.pandora_ops_connector_immutable_v1();
revoke all on function private.pandora_ops_connector_immutable_v1() from public,anon,authenticated,service_role;

create function public.pandora_ops_connector_delivery_v1(
 p_operation text,p_organization_id uuid,p_project_id uuid,p_envelope jsonb,p_envelope_digest text,
 p_request_digest text default null,p_receipt jsonb default null
) returns jsonb language plpgsql security definer set search_path='' as $body$
declare
 l private.pandora_ops_leases%rowtype;
 o private.pandora_ops_dispatch_outbox%rowtype;
 w private.pandora_ops_workspaces%rowtype;
 t private.pandora_ops_tasks%rowtype;
 k private.pandora_ops_workers%rowtype;
 d private.pandora_ops_connector_deliveries%rowtype;
 binding_state text;
 can_send boolean:=false;
 core_ack jsonb;
begin
 if p_operation is null or p_operation not in ('prepare','admit','delivered','unknown','read','acknowledge')
  or jsonb_typeof(p_envelope) is distinct from 'object'
  or octet_length(p_envelope::text)>4096
  or p_envelope - array['organizationId','projectId','workerId','principalKey','taskId','dispatchId','leaseId','generation','channelId'] <> '{}'::jsonb
  or not(p_envelope ?& array['organizationId','projectId','workerId','principalKey','taskId','dispatchId','leaseId','generation','channelId'])
  or p_envelope->>'organizationId' is distinct from p_organization_id::text
  or p_envelope->>'projectId' is distinct from p_project_id::text
  or not coalesce(p_envelope->>'dispatchId' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',false)
  or not coalesce(p_envelope->>'leaseId' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',false)
  or not coalesce(p_envelope->>'channelId' ~ '^agtch_[A-Za-z0-9_-]{1,160}$',false)
  or jsonb_typeof(p_envelope->'generation') is distinct from 'number'
  or not coalesce(p_envelope_digest ~ '^[a-f0-9]{64}$',false)
 then raise exception 'OPS_CONNECTOR_ENVELOPE_INVALID' using errcode='22023'; end if;
 select state into binding_state from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id for share;
 select * into w from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id for update;
 if not found then raise exception 'OPS_CONNECTOR_SCOPE_DENIED' using errcode='42501'; end if;
 select * into l from private.pandora_ops_leases where id=(p_envelope->>'leaseId')::uuid
  and organization_id=p_organization_id and project_id=p_project_id for update;
 if not found or l.task_key is distinct from p_envelope->>'taskId'
  or l.worker_key is distinct from p_envelope->>'workerId'
  or l.generation::text is distinct from p_envelope->>'generation'
 then raise exception 'OPS_CONNECTOR_LEASE_MISMATCH' using errcode='42501'; end if;
 select * into o from private.pandora_ops_dispatch_outbox
  where id=(p_envelope->>'dispatchId')::uuid and lease_id=l.id for update;
 if not found then raise exception 'OPS_CONNECTOR_DISPATCH_MISMATCH' using errcode='42501'; end if;
 select * into k from private.pandora_ops_workers where organization_id=p_organization_id
  and project_id=p_project_id and worker_key=l.worker_key for share;
 if not found or k.principal_key is distinct from p_envelope->>'principalKey' or not k.acknowledged
 then raise exception 'OPS_CONNECTOR_PRINCIPAL_MISMATCH' using errcode='42501'; end if;
 select * into t from private.pandora_ops_tasks where organization_id=p_organization_id
  and project_id=p_project_id and task_key=l.task_key for update;
 select * into d from private.pandora_ops_connector_deliveries where dispatch_id=o.id for update;
 if found and (d.envelope<>p_envelope or d.envelope_digest<>p_envelope_digest)
 then raise exception 'OPS_CONNECTOR_ENVELOPE_CONFLICT'; end if;
 if p_operation in ('prepare','admit','acknowledge') then
  if binding_state is distinct from 'active' or w.paused or t.cancel_requested
   or (w.no_production and t.spec->>'risk' in ('production','destructive'))
   or l.state='released' or l.expires_at<=clock_timestamp()
   or t.generation<>l.generation or t.builder_principal_key<>k.principal_key
  then raise exception 'OPS_CONNECTOR_EXECUTION_FENCED' using errcode='42501'; end if;
 end if;
 if p_operation='prepare' then
  if not coalesce(p_request_digest ~ '^[a-f0-9]{64}$',false) then raise exception 'OPS_CONNECTOR_REQUEST_INVALID'; end if;
  if d.dispatch_id is not null then
   if d.request_digest<>p_request_digest then raise exception 'OPS_CONNECTOR_REQUEST_CONFLICT'; end if;
  else
   if o.state<>'sending' or l.state<>'dispatching' then raise exception 'OPS_CONNECTOR_SEND_INTENT_REQUIRED'; end if;
   insert into private.pandora_ops_connector_deliveries(dispatch_id,lease_id,organization_id,project_id,envelope,envelope_digest,request_digest)
    values(o.id,l.id,p_organization_id,p_project_id,p_envelope,p_envelope_digest,p_request_digest) returning * into d;
   can_send:=true;
  end if;
 elsif d.dispatch_id is null then
  raise exception 'OPS_CONNECTOR_DELIVERY_MISSING';
 elsif p_operation='admit' then
  if d.state<>'sending' or o.state<>'sending' or l.state<>'dispatching' or d.provider_receipt is not null
   or not k.connected or k.health<>'ready' or k.heartbeat_at<clock_timestamp()-interval '60 seconds'
  then raise exception 'OPS_CONNECTOR_SEND_FENCED' using errcode='42501'; end if;
  return jsonb_build_object('allowed',true,'envelopeDigest',d.envelope_digest);
 elsif p_operation='delivered' then
  if jsonb_typeof(p_receipt) is distinct from 'object' or octet_length(p_receipt::text)>8192
   or p_receipt - array['envelope','requestDigest','runId','conversationUrl','state','workerAcknowledged','taskComplete'] <> '{}'::jsonb
   or p_receipt->'envelope' is distinct from d.envelope
   or p_receipt->>'requestDigest' is distinct from d.request_digest
   or not coalesce(p_receipt->>'runId' ~ '^apirun_[A-Za-z0-9_-]{1,160}$',false)
   or not coalesce(p_receipt->>'conversationUrl' ~ '^https://chatgpt[.]com/c/[A-Za-z0-9-]{1,160}$',false)
   or p_receipt->>'state' is distinct from 'provider_queued'
   or p_receipt->'workerAcknowledged' is distinct from 'false'::jsonb
   or p_receipt->'taskComplete' is distinct from 'false'::jsonb
  then raise exception 'OPS_CONNECTOR_PROVIDER_RECEIPT_INVALID'; end if;
  if d.provider_receipt is not null and d.provider_receipt<>p_receipt then raise exception 'OPS_CONNECTOR_PROVIDER_RECEIPT_CONFLICT'; end if;
  update private.pandora_ops_connector_deliveries set provider_receipt=p_receipt,
   state=case when authenticated_ack is not null then 'acknowledged' else 'delivered' end,updated_at=clock_timestamp()
   where dispatch_id=o.id returning * into d;
  perform private.pandora_ops_event_v1(p_organization_id,p_project_id,'provider-queued:'||o.id,l.task_key,'worker_trigger_queued',p_receipt->>'runId');
 elsif p_operation='unknown' then
  update private.pandora_ops_connector_deliveries set state=case when provider_receipt is null then 'unknown' else state end,
   updated_at=clock_timestamp() where dispatch_id=o.id returning * into d;
 elsif p_operation='acknowledge' then
  if d.provider_receipt is null or jsonb_typeof(p_receipt) is distinct from 'object'
   or p_receipt - array['authenticated','principalKey','runId','envelopeDigest','accepted','receiptRef'] <> '{}'::jsonb
   or p_receipt->'authenticated' is distinct from 'true'::jsonb
   or p_receipt->'accepted' is distinct from 'true'::jsonb
   or p_receipt->>'principalKey' is distinct from k.principal_key
   or p_receipt->>'runId' is distinct from d.provider_receipt->>'runId'
   or p_receipt->>'envelopeDigest' is distinct from d.envelope_digest
   or not coalesce(p_receipt->>'receiptRef' ~ '^ops-worker-ack:[a-f0-9]{64}$',false)
  then raise exception 'OPS_CONNECTOR_AUTHENTICATED_ACK_REQUIRED' using errcode='42501'; end if;
  if d.authenticated_ack is not null and d.authenticated_ack<>p_receipt then raise exception 'OPS_CONNECTOR_ACK_CONFLICT'; end if;
  if l.state not in ('dispatching','reconcile','running') or o.state not in ('sending','reconcile','acknowledged')
  then raise exception 'OPS_CONNECTOR_ACK_FENCED'; end if;
  core_ack:=jsonb_build_object('accepted',true,'dispatchId',o.id,'workerId',l.worker_key,
   'taskId',l.task_key,'generation',l.generation,'receiptRef',p_receipt->>'receiptRef');
  if l.state='reconcile' then update private.pandora_ops_leases set state='dispatching' where id=l.id; end if;
  if o.state='reconcile' then update private.pandora_ops_dispatch_outbox set state='sending' where id=o.id; end if;
  perform public.pandora_ops_dispatch_v1(p_organization_id,p_project_id,l.id,l.generation,core_ack);
  update private.pandora_ops_connector_deliveries set authenticated_ack=p_receipt,state='acknowledged',updated_at=clock_timestamp()
   where dispatch_id=o.id returning * into d;
 end if;
 return jsonb_build_object('canSend',can_send,'requestDigest',d.request_digest,'state',d.state,
  'receipt',d.provider_receipt,'acknowledgement',d.authenticated_ack,'envelopeDigest',d.envelope_digest);
end; $body$;
revoke all on function public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb) to service_role;

create function public.pandora_ops_connector_reconcile_v1(
 p_organization_id uuid,p_project_id uuid,p_lease_id uuid,p_generation bigint,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $body$
declare l private.pandora_ops_leases%rowtype; a jsonb; o private.pandora_ops_dispatch_outbox%rowtype;
begin
 perform 1 from private.pandora_ops_workspaces where organization_id=p_organization_id and project_id=p_project_id for update;
 select * into l from private.pandora_ops_leases where id=p_lease_id and organization_id=p_organization_id and project_id=p_project_id for update;
 if not found or l.generation<>p_generation or l.state='released' then raise exception 'OPS_LEASE_FENCED'; end if;
 select * into o from private.pandora_ops_dispatch_outbox where lease_id=l.id for update;
 select authenticated_ack into a from private.pandora_ops_connector_deliveries where dispatch_id=o.id for update;
 if a is not null and l.state='running' and o.state='acknowledged'
  and o.acknowledgement->>'receiptRef'=a->>'receiptRef'
 then return jsonb_build_object('reconciliationRequired',false,'leaseRetained',true,'workerAcknowledged',true); end if;
 return public.pandora_ops_reconcile_required_v1(p_organization_id,p_project_id,p_lease_id,p_generation,p_reason);
end; $body$;
revoke all on function public.pandora_ops_connector_reconcile_v1(uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_connector_reconcile_v1(uuid,uuid,uuid,bigint,text) to service_role;