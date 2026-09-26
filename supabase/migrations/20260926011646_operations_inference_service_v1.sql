-- Additive inference lifecycle. No policies, callers, credentials, workers or jobs are seeded.
-- Parent Operations leases retain global scheduling and financial authority.
create table private.pandora_ops_inference_policies (
 organization_id uuid not null, project_id uuid not null, revision bigint not null check(revision>0),
 policy jsonb not null check(jsonb_typeof(policy)='object' and octet_length(policy::text)<=131072),
 active boolean not null default false, approval_ref text not null check(length(approval_ref) between 8 and 500),
 primary key(organization_id,project_id),
 foreign key(organization_id,project_id) references private.pandora_ops_workspaces(organization_id,project_id)
);
create table private.pandora_ops_inference_callers (
 token_digest text primary key check(token_digest ~ '^[a-f0-9]{64}$'),
 organization_id uuid not null, project_id uuid not null, worker_key text not null, principal_key text not null,
 enabled boolean not null default false, expires_at timestamptz not null,
 classes text[] not null check(cardinality(classes)>0 and classes <@ array['deep_reasoning','complex_coding','fast_coding','vision','long_context','research','structured_extraction','local_private','cheap_bulk','independent_verification']),
 enrollment_receipt text not null check(length(enrollment_receipt) between 8 and 500),
 foreign key(organization_id,project_id,worker_key) references private.pandora_ops_workers(organization_id,project_id,worker_key)
);
create table private.pandora_ops_inference_requests (
 id uuid primary key, organization_id uuid not null, project_id uuid not null,
 task_key text not null, worker_key text not null, principal_key text not null, caller_digest text not null,
 lease_id uuid not null references private.pandora_ops_leases(id), generation bigint not null check(generation>0),
 source_sha text not null check(source_sha ~ '^[a-f0-9]{40}$'), task_class text not null,
 request_digest text not null check(request_digest ~ '^[a-f0-9]{64}$'), metadata jsonb not null,
 max_cost_micros bigint not null check(max_cost_micros between 0 and 1000000000000),
 state text not null default 'admitted' check(state in ('admitted','executing','verification_pending','verified','failed','reconciliation_required','cancel_requested','cancelled')),
 cancel_requested boolean not null default false, selected_attempt uuid, verification_run_id uuid references public.pandora_verification_runs(id),
 created_at timestamptz not null default clock_timestamp(), completed_at timestamptz,
 foreign key(organization_id,project_id,task_key) references private.pandora_ops_tasks(organization_id,project_id,task_key),
 foreign key(organization_id,project_id,worker_key) references private.pandora_ops_workers(organization_id,project_id,worker_key)
);
create index pandora_ops_inference_requests_lease on private.pandora_ops_inference_requests(lease_id,generation);
create table private.pandora_ops_inference_attempts (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references private.pandora_ops_inference_requests(id),
 organization_id uuid not null, project_id uuid not null, ordinal integer not null check(ordinal between 1 and 3),
 model_key text not null, model_snapshot jsonb not null, policy_digest text not null check(policy_digest ~ '^[a-f0-9]{64}$'),
 circuit_generation bigint not null default 0, state text not null default 'prepared' check(state in ('prepared','sent','received','failed','not_sent','reconciliation_required')),
 reserved_micros bigint not null check(reserved_micros between 0 and 1000000000000), billed_micros bigint,
 receipt jsonb, billing_receipt text, created_at timestamptz not null default clock_timestamp(), completed_at timestamptz,
 unique(request_id,ordinal), unique(request_id,model_key),
 check(billed_micros is null or billed_micros between 0 and reserved_micros)
);
create index pandora_ops_inference_attempts_capacity on private.pandora_ops_inference_attempts(organization_id,model_key,state);
create table private.pandora_ops_inference_circuits (
 organization_id uuid not null, model_key text not null, failures integer not null default 0 check(failures>=0),
 state text not null default 'closed' check(state in ('closed','open','half_open')),
 generation bigint not null default 0, retry_after timestamptz, probe_attempt uuid references private.pandora_ops_inference_attempts(id),
 primary key(organization_id,model_key)
);
alter table private.pandora_ops_inference_policies enable row level security;
alter table private.pandora_ops_inference_callers enable row level security;
alter table private.pandora_ops_inference_requests enable row level security;
alter table private.pandora_ops_inference_attempts enable row level security;
alter table private.pandora_ops_inference_circuits enable row level security;
revoke all on private.pandora_ops_inference_policies,private.pandora_ops_inference_callers,private.pandora_ops_inference_requests,private.pandora_ops_inference_attempts,private.pandora_ops_inference_circuits from public,anon,authenticated,service_role;

create function private.pandora_ops_inference_scope_v1(a jsonb,p_lease uuid,p_generation bigint)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare c private.pandora_ops_inference_callers%rowtype; w private.pandora_ops_workspaces%rowtype;
 l private.pandora_ops_leases%rowtype; t private.pandora_ops_tasks%rowtype; worker private.pandora_ops_workers%rowtype;
begin
 select * into c from private.pandora_ops_inference_callers where token_digest=a->>'callerDigest' and enabled and expires_at>clock_timestamp() for share;
 if not found or c.organization_id::text is distinct from a->>'organizationId' or c.project_id::text is distinct from a->>'projectId'
  or c.worker_key is distinct from a->>'workerId' or c.principal_key is distinct from a->>'principalKey' then raise exception 'INFERENCE_CALLER_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_project_bindings where organization_id=c.organization_id and project_id=c.project_id and state='active' for share;
 if not found then raise exception 'INFERENCE_PROJECT_DENIED' using errcode='42501'; end if;
 select * into w from private.pandora_ops_workspaces where organization_id=c.organization_id and project_id=c.project_id for update;
 if not found or w.paused then raise exception 'INFERENCE_WORKSPACE_PAUSED'; end if;
 select * into l from private.pandora_ops_leases where id=p_lease and organization_id=c.organization_id and project_id=c.project_id for update;
 if not found or l.generation is distinct from p_generation or l.worker_key is distinct from c.worker_key or l.state<>'running' or l.expires_at<=clock_timestamp() then raise exception 'INFERENCE_LEASE_FENCED'; end if;
 select * into t from private.pandora_ops_tasks where organization_id=c.organization_id and project_id=c.project_id and task_key=l.task_key for update;
 if not found or t.generation is distinct from l.generation or t.cancel_requested or t.status<>'implementing' then raise exception 'INFERENCE_TASK_FENCED'; end if;
 if w.no_production and t.spec->>'risk' in ('production','destructive') then raise exception 'INFERENCE_PRODUCTION_DISABLED'; end if;
 select * into worker from private.pandora_ops_workers where organization_id=c.organization_id and project_id=c.project_id and worker_key=c.worker_key for share;
 if not found or worker.principal_key is distinct from c.principal_key or not worker.acknowledged or not worker.connected or worker.health<>'ready'
  or worker.heartbeat_at is null or worker.heartbeat_at<clock_timestamp()-interval '60 seconds' or worker.heartbeat_at>clock_timestamp()+interval '5 seconds' then raise exception 'INFERENCE_WORKER_UNAVAILABLE'; end if;
 return jsonb_build_object('organizationId',c.organization_id,'projectId',c.project_id,'taskId',t.task_key,'workerId',c.worker_key,
  'principalKey',c.principal_key,'risk',t.spec->>'risk','sourceSha',coalesce(t.head_sha,t.spec#>>'{source,baseSha}'),'classes',c.classes,'leaseBudgetMicros',l.reserved_micros);
end; $body$;
revoke all on function private.pandora_ops_inference_scope_v1(jsonb,uuid,bigint) from public,anon,authenticated,service_role;

create function public.pandora_ops_inference_authenticate_v1(p_digest text)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare c private.pandora_ops_inference_callers%rowtype;
begin
 if p_digest is null or p_digest !~ '^[a-f0-9]{64}$' then raise exception 'INFERENCE_CALLER_DENIED' using errcode='42501'; end if;
 select * into c from private.pandora_ops_inference_callers where token_digest=p_digest and enabled and expires_at>clock_timestamp();
 if not found then raise exception 'INFERENCE_CALLER_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_project_bindings b join private.pandora_ops_workers w on w.organization_id=b.organization_id and w.project_id=b.project_id
 where b.organization_id=c.organization_id and b.project_id=c.project_id and b.state='active'
 and w.worker_key=c.worker_key and w.principal_key=c.principal_key and w.acknowledged;
 if not found then raise exception 'INFERENCE_CALLER_DENIED' using errcode='42501'; end if;
 return jsonb_build_object('organizationId',c.organization_id,'projectId',c.project_id,'workerId',c.worker_key,'principalKey',c.principal_key,'callerDigest',c.token_digest);
end; $body$;
revoke all on function public.pandora_ops_inference_authenticate_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_ops_inference_authenticate_v1(text) to service_role;

create function public.pandora_ops_inference_transition_v1(p_operation text,p_actor jsonb,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare org uuid; project uuid; scope jsonb; r private.pandora_ops_inference_requests%rowtype;
 a private.pandora_ops_inference_attempts%rowtype; c private.pandora_ops_inference_circuits%rowtype;
 policy private.pandora_ops_inference_policies%rowtype; model jsonb; pd text; n integer; total numeric; v_receipt jsonb;
 v public.pandora_verification_runs%rowtype; verifier private.pandora_ops_workers%rowtype; now_at timestamptz:=clock_timestamp(); k text;
begin
 if jsonb_typeof(p_actor) is distinct from 'object' or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>32768 then raise exception 'INFERENCE_INPUT_INVALID'; end if;
 org:=(p_actor->>'organizationId')::uuid; project:=(p_actor->>'projectId')::uuid;
 if org is null or project is null or nullif(p_actor->>'callerDigest','') is null then raise exception 'INFERENCE_CALLER_DENIED' using errcode='42501'; end if;
 if p_operation in ('context','admit') then
  scope:=private.pandora_ops_inference_scope_v1(p_actor,(p_payload->>'leaseId')::uuid,(p_payload->>'generation')::bigint);
  if scope->>'taskId' is distinct from p_payload->>'taskId' or scope->>'sourceSha' is distinct from p_payload->>'sourceSha'
   or not coalesce((scope->'classes') ? (p_payload->>'taskClass'),false) then raise exception 'INFERENCE_REQUEST_SCOPE_DENIED' using errcode='42501'; end if;
  -- This cloud service never admits a phone-private payload for remote inference.
  if p_payload->>'taskClass'='local_private' then raise exception 'INFERENCE_PHONE_LOCAL_REQUIRED'; end if;
  select * into policy from private.pandora_ops_inference_policies where organization_id=org and project_id=project and active for share;
  if not found then raise exception 'INFERENCE_POLICY_NOT_CONFIGURED'; end if;
  pd:=encode(extensions.digest(convert_to(policy.policy::text,'UTF8'),'sha256'),'hex');
  if p_operation='context' then return jsonb_build_object('scope',scope,'policy',policy.policy,'policyDigest',pd,'policyRevision',policy.revision); end if;
  if not coalesce(p_payload->>'requestDigest' ~ '^[a-f0-9]{64}$',false) or not coalesce(p_payload->>'maxCostMicros' ~ '^[0-9]{1,13}$',false)
   or not coalesce(p_payload->>'sourceSha' ~ '^[a-f0-9]{40}$',false) then raise exception 'INFERENCE_REQUEST_INVALID'; end if;
  for k in select jsonb_object_keys(p_payload) loop
   if k<>all(array['requestId','taskId','leaseId','generation','sourceSha','taskClass','requestDigest','maxCostMicros','maxOutputTokens','deadlineMs','textBytes','inputBytes','imageCount','modalities','inputDigest']) then raise exception 'INFERENCE_METADATA_ONLY'; end if;
  end loop;
  if not coalesce(p_payload->>'inputDigest' ~ '^[a-f0-9]{64}$',false) then raise exception 'INFERENCE_REQUEST_INVALID'; end if;
  for k in select unnest(array['maxOutputTokens','deadlineMs','textBytes','inputBytes','imageCount']) loop
   if not coalesce(jsonb_typeof(p_payload->k)='number' and p_payload->>k ~ '^[0-9]{1,9}$',false) then raise exception 'INFERENCE_REQUEST_INVALID'; end if;
  end loop;
  if (p_payload->>'maxOutputTokens')::int not between 1 and 65536 or (p_payload->>'deadlineMs')::int not between 100 and 60000
   or (p_payload->>'textBytes')::int>1100000 or (p_payload->>'inputBytes')::int>1100000 or (p_payload->>'inputBytes')::int<(p_payload->>'textBytes')::int
   or (p_payload->>'imageCount')::int>16 or jsonb_typeof(p_payload->'modalities') is distinct from 'array'
   or not coalesce((p_payload->'modalities') <@ '["text","image"]'::jsonb,false) then raise exception 'INFERENCE_REQUEST_INVALID'; end if;
  select * into r from private.pandora_ops_inference_requests where id=(p_payload->>'requestId')::uuid for update;
  if found then
   if r.organization_id is distinct from org or r.project_id is distinct from project or r.caller_digest is distinct from p_actor->>'callerDigest'
    or r.metadata is distinct from p_payload then raise exception 'INFERENCE_REQUEST_REPLAY_CONFLICT'; end if;
   return jsonb_build_object('created',false,'requestId',r.id,'state',r.state,'canSend',false);
  end if;
  select coalesce(sum(max_cost_micros),0) into total from private.pandora_ops_inference_requests where lease_id=(p_payload->>'leaseId')::uuid;
  if (p_payload->>'maxCostMicros')::numeric+total>(scope->>'leaseBudgetMicros')::numeric then raise exception 'INFERENCE_PARENT_BUDGET_EXHAUSTED'; end if;
  insert into private.pandora_ops_inference_requests(id,organization_id,project_id,task_key,worker_key,principal_key,caller_digest,lease_id,generation,source_sha,task_class,request_digest,metadata,max_cost_micros)
  values((p_payload->>'requestId')::uuid,org,project,scope->>'taskId',scope->>'workerId',scope->>'principalKey',p_actor->>'callerDigest',(p_payload->>'leaseId')::uuid,(p_payload->>'generation')::bigint,
   p_payload->>'sourceSha',p_payload->>'taskClass',p_payload->>'requestDigest',p_payload,(p_payload->>'maxCostMicros')::bigint) returning * into r;
  perform private.pandora_ops_event_v1(org,project,'infer:admit:'||r.id,r.task_key,'inference_admitted','inference-request:'||r.id);
  return jsonb_build_object('created',true,'requestId',r.id,'state',r.state,'canSend',false);
 end if;
 -- Lock the parent workspace first, consistently with existing Operations settlement/handoff.
 perform 1 from private.pandora_ops_workspaces where organization_id=org and project_id=project for update;
 select * into r from private.pandora_ops_inference_requests where id=(p_payload->>'requestId')::uuid and organization_id=org and project_id=project for update;
 if not found or r.worker_key is distinct from p_actor->>'workerId' or r.principal_key is distinct from p_actor->>'principalKey'
  or r.caller_digest is distinct from p_actor->>'callerDigest' then raise exception 'INFERENCE_REQUEST_DENIED' using errcode='42501'; end if;
 if p_operation='status' then
  return jsonb_build_object('request',to_jsonb(r)-'caller_digest','attempts',coalesce((select jsonb_agg(to_jsonb(x) order by x.ordinal) from private.pandora_ops_inference_attempts x where x.request_id=r.id),'[]'::jsonb),'scope','inference_only','taskComplete',false);
 end if;
 if p_operation='cancel' then
  if r.state='verified' then return jsonb_build_object('requestId',r.id,'state',r.state,'cancelled',false); end if;
  update private.pandora_ops_inference_requests set cancel_requested=true,state=case when exists(select 1 from private.pandora_ops_inference_attempts where request_id=r.id and state in ('prepared','sent','reconciliation_required')) then 'cancel_requested' else 'cancelled' end where id=r.id returning * into r;
  perform private.pandora_ops_event_v1(org,project,'infer:cancel:'||r.id,r.task_key,'inference_cancel_requested','inference-request:'||r.id);
  return jsonb_build_object('requestId',r.id,'state',r.state,'cancelled',r.state='cancelled','providerStopped',false);
 end if;
 if p_operation in ('prepare','send') then
  scope:=private.pandora_ops_inference_scope_v1(p_actor,r.lease_id,r.generation);
  if r.cancel_requested or r.state in ('verified','verification_pending','reconciliation_required','cancel_requested','cancelled') then raise exception 'INFERENCE_REQUEST_FENCED'; end if;
  select * into policy from private.pandora_ops_inference_policies where organization_id=org and project_id=project and active for share;
  if not found then raise exception 'INFERENCE_POLICY_NOT_CONFIGURED'; end if;
  pd:=encode(extensions.digest(convert_to(policy.policy::text,'UTF8'),'sha256'),'hex');
  if pd is distinct from p_payload->>'policyDigest' then raise exception 'INFERENCE_POLICY_CHANGED'; end if;
  if p_operation='send' then
   select * into a from private.pandora_ops_inference_attempts where id=(p_payload->>'attemptId')::uuid and request_id=r.id for update;
   if not found or a.policy_digest is distinct from pd then raise exception 'INFERENCE_ATTEMPT_FENCED'; end if;
   if a.state<>'prepared' then return jsonb_build_object('canSend',false,'attemptId',a.id,'state',a.state); end if;
   update private.pandora_ops_inference_attempts set state='sent' where id=a.id;
   update private.pandora_ops_inference_requests set state='executing' where id=r.id;
   perform private.pandora_ops_event_v1(org,project,'infer:send:'||a.id,r.task_key,'inference_send_started','inference-attempt:'||a.id);
   return jsonb_build_object('canSend',true,'attemptId',a.id,'state','sent');
  end if;
  select value into model from jsonb_array_elements(policy.policy->'models') where (value->>'provider')||':'||(value->>'model')=p_payload->>'modelKey';
  if model is null or not(model ?& array['provider','model','classes','approved','available','approvalExpiresAt','healthObservedAt','executionBoundary','riskTier','modalities','maxInputBytes','maxOutputTokens','contextTokens','imageTokenUpperBound','maxConcurrency','maxCostMicros']) or model->>'approved' is distinct from 'true' or model->>'available' is distinct from 'true'
   or (model->>'approvalExpiresAt')::timestamptz<=now_at or (model->>'healthObservedAt')::timestamptz>now_at+interval '5 seconds'
   or (model->>'healthObservedAt')::timestamptz<now_at-((policy.policy->>'maxHealthAgeMs')::bigint*interval '1 millisecond')
   or not coalesce((model->'classes') ? r.task_class,false) or model->>'executionBoundary'<>'cloud'
   or not coalesce((policy.policy->'allowedProviders') ? (model->>'provider'),false)
   or not coalesce((policy.policy->'allowedBoundaries') ? (model->>'executionBoundary'),false)
   or (model->>'riskTier')::int<(policy.policy#>>array['minimumRiskTier',scope->>'risk'])::int
   or not coalesce((model->'modalities') @> (r.metadata->'modalities'),false)
   or (r.metadata->>'inputBytes')::bigint>(model->>'maxInputBytes')::bigint
   or (r.metadata->>'maxOutputTokens')::bigint>(model->>'maxOutputTokens')::bigint
   or (r.metadata->>'textBytes')::bigint+(r.metadata->>'imageCount')::bigint*(model->>'imageTokenUpperBound')::bigint+(r.metadata->>'maxOutputTokens')::bigint>(model->>'contextTokens')::bigint
   then raise exception 'INFERENCE_MODEL_INELIGIBLE'; end if;
  select * into a from private.pandora_ops_inference_attempts where request_id=r.id and model_key=p_payload->>'modelKey';
  if found then return jsonb_build_object('created',false,'attemptId',a.id,'state',a.state,'canSend',false); end if;
  if exists(select 1 from private.pandora_ops_inference_attempts where request_id=r.id and state in ('prepared','sent','reconciliation_required')) then raise exception 'INFERENCE_UNKNOWN_OUTCOME_HELD'; end if;
  select count(*),coalesce(sum(coalesce(billed_micros,reserved_micros)),0) into n,total from private.pandora_ops_inference_attempts where request_id=r.id;
  if n>=(policy.policy->>'maxAttempts')::int or n>=3 then raise exception 'INFERENCE_ATTEMPTS_EXHAUSTED'; end if;
  if model->>'maxCostMicros' is null or (model->>'maxCostMicros')::numeric<0 or total+(model->>'maxCostMicros')::numeric>r.max_cost_micros then raise exception 'INFERENCE_BUDGET_EXHAUSTED'; end if;
  insert into private.pandora_ops_inference_circuits(organization_id,model_key) values(org,p_payload->>'modelKey') on conflict do nothing;
  select * into c from private.pandora_ops_inference_circuits where organization_id=org and model_key=p_payload->>'modelKey' for update;
  if c.state='half_open' or c.probe_attempt is not null or (c.state='open' and (c.retry_after is null or c.retry_after>now_at)) then raise exception 'INFERENCE_CIRCUIT_HELD'; end if;
  if (select count(*) from private.pandora_ops_inference_attempts where organization_id=org and model_key=p_payload->>'modelKey' and state in ('prepared','sent','reconciliation_required')) >= (model->>'maxConcurrency')::int then raise exception 'INFERENCE_CAPACITY_HELD'; end if;
  insert into private.pandora_ops_inference_attempts(request_id,organization_id,project_id,ordinal,model_key,model_snapshot,policy_digest,reserved_micros,circuit_generation)
  values(r.id,org,project,n+1,p_payload->>'modelKey',model,pd,(model->>'maxCostMicros')::bigint,c.generation) returning * into a;
  if c.state='open' then update private.pandora_ops_inference_circuits set state='half_open',probe_attempt=a.id where organization_id=org and model_key=a.model_key; end if;
  perform private.pandora_ops_event_v1(org,project,'infer:route:'||a.id,r.task_key,'inference_routed','inference-attempt:'||a.id);
  return jsonb_build_object('created',true,'attemptId',a.id,'ordinal',a.ordinal,'reservedMicros',a.reserved_micros,'canSend',false);
 end if;
 if p_operation in ('record','billing') then
  select * into a from private.pandora_ops_inference_attempts where id=(p_payload->>'attemptId')::uuid and request_id=r.id for update;
  if not found then raise exception 'INFERENCE_ATTEMPT_FENCED'; end if;
  if p_operation='billing' then
   if a.state in ('prepared','sent','reconciliation_required') or nullif(p_payload->>'receiptRef','') is null or length(p_payload->>'receiptRef')>500
    or not coalesce(p_payload->>'billedCostMicros' ~ '^[0-9]{1,13}$',false) or (p_payload->>'billedCostMicros')::bigint>a.reserved_micros then raise exception 'INFERENCE_BILLING_EVIDENCE_REQUIRED'; end if;
   if a.billed_micros is not null and (a.billed_micros is distinct from (p_payload->>'billedCostMicros')::bigint or a.billing_receipt is distinct from p_payload->>'receiptRef') then raise exception 'INFERENCE_BILLING_CONFLICT'; end if;
   update private.pandora_ops_inference_attempts set billed_micros=(p_payload->>'billedCostMicros')::bigint,billing_receipt=p_payload->>'receiptRef' where id=a.id;
   perform private.pandora_ops_event_v1(org,project,'infer:billing:'||a.id,r.task_key,'inference_billing_reconciled',p_payload->>'receiptRef');
   return jsonb_build_object('recorded',true,'attemptId',a.id);
  end if;
  v_receipt:=p_payload->'receipt';
  if jsonb_typeof(v_receipt) is distinct from 'object' or octet_length(v_receipt::text)>8192 then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  if not(v_receipt ?& array['state','outputDigest','providerReceipt','billedCostMicros','usage','code','latencyMs','modelRevision'])
   or jsonb_typeof(v_receipt->'usage') is distinct from 'object' or (v_receipt->'usage')-array['inputTokens','outputTokens','totalTokens'] <> '{}'::jsonb
   or not((v_receipt->'usage') ?& array['inputTokens','outputTokens','totalTokens']) then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  for k in select unnest(array['inputTokens','outputTokens','totalTokens']) loop
   if (v_receipt#>array['usage',k])<>'null'::jsonb and not coalesce(v_receipt#>>array['usage',k] ~ '^[0-9]{1,15}$',false) then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  end loop;
  if v_receipt->>'state'='received' and v_receipt->'code'<>'null'::jsonb then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  if v_receipt->>'state'='failed' and not coalesce(v_receipt->>'code' in ('rate_limit','unavailable','invalid_output','verification_failed','permission_denied','safety_refusal','model_revision_mismatch'),false) then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  if v_receipt->>'modelRevision' is not null and (length(v_receipt->>'modelRevision')>180 or v_receipt->>'modelRevision' !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]*$') then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  if v_receipt->>'latencyMs' is not null and not coalesce(v_receipt->>'latencyMs' ~ '^[0-9]{1,8}$',false) then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  for k in select jsonb_object_keys(v_receipt) loop
   if k<>all(array['state','outputDigest','providerReceipt','billedCostMicros','usage','code','latencyMs','modelRevision']) then raise exception 'INFERENCE_RECEIPT_METADATA_ONLY'; end if;
  end loop;
  if not coalesce(v_receipt->>'state' in ('received','failed','not_sent','reconciliation_required'),false)
   or nullif(v_receipt->>'providerReceipt','') is null or length(v_receipt->>'providerReceipt')>500
   or (v_receipt->>'billedCostMicros' is not null and not coalesce(v_receipt->>'billedCostMicros' ~ '^[0-9]{1,13}$' and (v_receipt->>'billedCostMicros')::bigint<=a.reserved_micros,false))
   or (v_receipt->>'state'='received' and not coalesce(v_receipt->>'outputDigest' ~ '^[a-f0-9]{64}$',false)) then raise exception 'INFERENCE_RECEIPT_INVALID'; end if;
  if a.receipt=v_receipt then return jsonb_build_object('recorded',true,'replayed',true,'attemptId',a.id,'state',a.state); end if;
  if a.state not in ('prepared','sent','reconciliation_required') or (a.state='prepared' and v_receipt->>'state' not in ('not_sent','reconciliation_required'))
   or (v_receipt->>'state'='not_sent' and (a.state<>'prepared' or v_receipt->>'billedCostMicros' is distinct from '0')) then raise exception 'INFERENCE_RECEIPT_CONFLICT'; end if;
  update private.pandora_ops_inference_attempts set state=v_receipt->>'state',receipt=v_receipt,billed_micros=(v_receipt->>'billedCostMicros')::bigint,
   completed_at=case when v_receipt->>'state'='reconciliation_required' then null else now_at end where id=a.id;
  if v_receipt->>'state'='reconciliation_required' then
   update private.pandora_ops_inference_requests set state='reconciliation_required' where id=r.id;
   perform public.pandora_ops_reconcile_required_v1(org,project,r.lease_id,r.generation,'INFERENCE_OUTCOME_UNKNOWN');
  else
   select * into c from private.pandora_ops_inference_circuits where organization_id=org and model_key=a.model_key for update;
   if v_receipt->>'state'='received' then
    update private.pandora_ops_inference_circuits set state='closed',failures=0,retry_after=null,probe_attempt=null,generation=generation+1 where organization_id=org and model_key=a.model_key and generation=a.circuit_generation and (probe_attempt is null or probe_attempt=a.id);
    update private.pandora_ops_inference_requests set state=case when cancel_requested then 'cancel_requested' else 'verification_pending' end,selected_attempt=a.id where id=r.id;
   elsif v_receipt->>'state'='failed' then
    update private.pandora_ops_inference_circuits set failures=failures+1,generation=case when failures+1>=3 or probe_attempt=a.id then generation+1 else generation end,state=case when failures+1>=3 or probe_attempt=a.id then 'open' else state end,
     retry_after=case when failures+1>=3 or probe_attempt=a.id then now_at+interval '30 seconds' else retry_after end,probe_attempt=case when probe_attempt=a.id then null else probe_attempt end where organization_id=org and model_key=a.model_key and generation=a.circuit_generation and (probe_attempt is null or probe_attempt=a.id);
    update private.pandora_ops_inference_requests set state='failed' where id=r.id;
   else
    update private.pandora_ops_inference_circuits set state=case when probe_attempt=a.id then 'open' else state end,probe_attempt=case when probe_attempt=a.id then null else probe_attempt end where organization_id=org and model_key=a.model_key and generation=a.circuit_generation and (probe_attempt is null or probe_attempt=a.id);
    update private.pandora_ops_inference_requests set state=case when cancel_requested then 'cancelled' else 'admitted' end where id=r.id;
   end if;
  end if;
  perform private.pandora_ops_event_v1(org,project,'infer:receipt:'||a.id||':'||(v_receipt->>'state'),r.task_key,'inference_'||(v_receipt->>'state'),v_receipt->>'providerReceipt');
  return jsonb_build_object('recorded',true,'attemptId',a.id,'state',v_receipt->>'state','taskComplete',false);
 end if;
 if p_operation='verify' then
  perform 1 from private.pandora_ops_project_bindings where organization_id=org and project_id=project and state='active' for share;
  if not found then raise exception 'INFERENCE_VERIFICATION_FENCED'; end if;
  perform 1 from private.pandora_ops_tasks where organization_id=org and project_id=project and task_key=r.task_key and generation=r.generation and not cancel_requested and status='implementing' for share;
  if not found then raise exception 'INFERENCE_VERIFICATION_FENCED'; end if;
  if r.cancel_requested or r.state not in ('verification_pending','verified') then raise exception 'INFERENCE_VERIFICATION_FENCED'; end if;
  select * into a from private.pandora_ops_inference_attempts where id=r.selected_attempt;
  select * into v from public.pandora_verification_runs where id=(p_payload->>'verificationRunId')::uuid and organization_id=org and project_id=project for share;
  if not found or v.status is distinct from 'PASS' or v.completed_at is null or v.source_commit is distinct from r.source_sha
   or v.artifact_digest is distinct from a.receipt->>'outputDigest' or v.runtime_target_digest is distinct from r.request_digest or v.builder_identity is distinct from r.principal_key
   or nullif(v.verifier_identity,'') is null or v.verifier_identity=r.principal_key or v.required_check_profile is distinct from 'backend_service' then raise exception 'INFERENCE_CANONICAL_VERIFICATION_REQUIRED'; end if;
  select * into verifier from private.pandora_ops_workers where organization_id=org and project_id=project and principal_key=v.verifier_identity
   and worker_key<>r.worker_key and acknowledged and connected and health='ready' and heartbeat_at between now_at-interval '60 seconds' and now_at+interval '5 seconds' and 'release'=any(lanes);
  if not found then raise exception 'INFERENCE_INDEPENDENT_VERIFIER_REQUIRED' using errcode='42501'; end if;
  if r.state='verified' and r.verification_run_id is distinct from v.id then raise exception 'INFERENCE_VERIFICATION_REPLAY_CONFLICT'; end if;
  update private.pandora_ops_inference_requests set state='verified',verification_run_id=v.id,completed_at=coalesce(completed_at,now_at) where id=r.id;
  perform private.pandora_ops_event_v1(org,project,'infer:verify:'||r.id,r.task_key,'inference_verified','verification-run:'||v.id);
  return jsonb_build_object('requestId',r.id,'state','verified','verificationRunId',v.id,'scope','inference_only','taskComplete',false);
 end if;
 raise exception 'INFERENCE_OPERATION_DENIED' using errcode='42501';
end; $body$;
revoke all on function public.pandora_ops_inference_transition_v1(text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_ops_inference_transition_v1(text,jsonb,jsonb) to service_role;

create function private.pandora_ops_inference_settlement_guard_v1()
returns trigger language plpgsql security definer set search_path='' as $body$
declare cost numeric;
begin
 if new.state='released' and old.state<>'released' then
  if exists(select 1 from private.pandora_ops_inference_requests r join private.pandora_ops_inference_attempts a on a.request_id=r.id where r.lease_id=new.id and (a.state in ('prepared','sent','reconciliation_required') or a.billed_micros is null)) then raise exception 'INFERENCE_OUTCOME_OR_BILLING_UNRESOLVED'; end if;
  select coalesce(sum(a.billed_micros),0) into cost from private.pandora_ops_inference_requests r join private.pandora_ops_inference_attempts a on a.request_id=r.id where r.lease_id=new.id;
  if new.charged_micros is null or new.charged_micros<cost then raise exception 'INFERENCE_SETTLEMENT_UNDERREPORTED'; end if;
 end if;
 return new;
end; $body$;
revoke all on function private.pandora_ops_inference_settlement_guard_v1() from public,anon,authenticated,service_role;
create trigger pandora_ops_inference_settlement_guard before update of state on private.pandora_ops_leases for each row execute function private.pandora_ops_inference_settlement_guard_v1();

create function public.pandora_ops_event_feed_v1(p_organization_id uuid,p_project_id uuid,p_actor_id uuid,p_after bigint default 0,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare high bigint; result jsonb; next_id bigint; more boolean;
begin
 if p_after is null or p_after<0 or p_limit is null or p_limit not between 1 and 200 then raise exception 'OPS_EVENT_CURSOR_INVALID'; end if;
 perform 1 from public.memberships where organization_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin') for share;
 if not found then raise exception 'OPS_EVENT_OWNER_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_project_bindings where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
 if not found then raise exception 'OPS_EVENT_PROJECT_DENIED' using errcode='42501'; end if;
 select coalesce(max(id),0) into high from private.pandora_ops_events where organization_id=p_organization_id and project_id=p_project_id;
 if p_after>high then raise exception 'OPS_EVENT_CURSOR_AHEAD'; end if;
 with bounded as (select id,event_key,task_key,event_type,receipt_ref,occurred_at from private.pandora_ops_events where organization_id=p_organization_id and project_id=p_project_id and id>p_after and id<=high order by id limit p_limit),
 encoded as (select id,jsonb_build_object('id',id::text,'key',event_key,'taskId',task_key,'type',event_type,'receiptRef',receipt_ref,'occurredAt',occurred_at) value from bounded)
 select coalesce(jsonb_agg(value order by id),'[]'::jsonb),coalesce(max(id),p_after) into result,next_id from encoded;
 select exists(select 1 from private.pandora_ops_events where organization_id=p_organization_id and project_id=p_project_id and id>next_id and id<=high) into more;
 return jsonb_build_object('schemaVersion','pandora-operations-events-v1','organizationId',p_organization_id,'projectId',p_project_id,'observedAt',clock_timestamp(),
  'events',result,'nextCursor',next_id::text,'highWatermark',high::text,'hasMore',more,'authority','immutable_operations_events','syntheticProgress',false);
end; $body$;
revoke all on function public.pandora_ops_event_feed_v1(uuid,uuid,uuid,bigint,integer) from public,anon,authenticated;
grant execute on function public.pandora_ops_event_feed_v1(uuid,uuid,uuid,bigint,integer) to service_role;
