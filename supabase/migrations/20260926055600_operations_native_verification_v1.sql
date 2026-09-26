-- Operations-native verification authority, independent of retired ProjectOS spec/version rows.
create table private.pandora_ops_verification_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  generation bigint not null check(generation>=0),
  head_sha text not null check(head_sha ~ '^[0-9a-f]{40}$'),
  task_spec_digest text not null check(task_spec_digest ~ '^[0-9a-f]{64}$'),
  verification_profile text not null check(length(verification_profile) between 1 and 120),
  builder_worker_key text not null,
  builder_principal_key text not null,
  verifier_worker_key text not null,
  verifier_principal_key text not null,
  status text not null check(status in ('PASS','FAIL','BLOCKED')),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=16384),
  completed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id,project_id)
    references private.pandora_ops_workspaces(organization_id,project_id),
  unique(organization_id,project_id,task_key,generation,verifier_worker_key)
);
alter table private.pandora_ops_verification_receipts enable row level security;
revoke all on private.pandora_ops_verification_receipts from public,anon,authenticated,service_role;

create or replace function public.pandora_ops_record_verification_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_task_key text,
  p_generation bigint,
  p_verifier_key text,
  p_principal_key text,
  p_status text,
  p_evidence jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  t private.pandora_ops_tasks%rowtype;
  worker private.pandora_ops_workers%rowtype;
  existing private.pandora_ops_verification_receipts%rowtype;
  v_id uuid;
begin
  perform 1 from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id
  for update;

  select * into t from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key
  for update;
  if not found or t.generation is distinct from p_generation
     or t.status not in ('handed_off','verifying','complete')
     or t.cancel_requested or t.head_sha is null then
    raise exception 'OPS_VERIFICATION_FENCED';
  end if;

  select * into worker from private.pandora_ops_workers
  where organization_id=p_organization_id and project_id=p_project_id and worker_key=p_verifier_key;
  if not found or not worker.acknowledged or not worker.connected or worker.health<>'ready'
     or worker.heartbeat_at is null or worker.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or worker.principal_key is distinct from p_principal_key
     or worker.principal_key=t.builder_principal_key
     or worker.worker_key=t.builder_worker_key
     or not('release'=any(worker.lanes)) then
    raise exception 'OPS_INDEPENDENT_VERIFIER_REQUIRED' using errcode='42501';
  end if;

  if p_status not in ('PASS','FAIL','BLOCKED')
     or jsonb_typeof(p_evidence) is distinct from 'object'
     or octet_length(p_evidence::text)>16384
     or p_evidence->>'taskId' is distinct from t.task_key
     or p_evidence->>'headSha' is distinct from t.head_sha
     or p_evidence->>'generation' is distinct from p_generation::text
     or p_evidence->>'taskSpecDigest' is distinct from t.spec_digest
     or jsonb_typeof(p_evidence->'criteria') is distinct from 'array'
     or not((p_evidence->'criteria') @> (t.spec->'acceptance'))
     or not coalesce(length(p_evidence->>'ref') between 1 and 1000,false) then
    raise exception 'OPS_VERIFICATION_EVIDENCE_INVALID';
  end if;

  select * into existing from private.pandora_ops_verification_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and task_key=t.task_key and generation=p_generation and verifier_worker_key=p_verifier_key;

  if found then
    if existing.status is distinct from p_status or existing.evidence is distinct from p_evidence
       or existing.verifier_principal_key is distinct from p_principal_key then
      raise exception 'OPS_VERIFICATION_REPLAY_CONFLICT';
    end if;
    return jsonb_build_object('recorded',true,'replayed',true,'verificationRunId',existing.id,'status',existing.status);
  end if;

  insert into private.pandora_ops_verification_receipts(
    organization_id,project_id,task_key,generation,head_sha,task_spec_digest,verification_profile,
    builder_worker_key,builder_principal_key,verifier_worker_key,verifier_principal_key,status,evidence
  ) values (
    p_organization_id,p_project_id,t.task_key,p_generation,t.head_sha,t.spec_digest,t.spec->>'verificationProfile',
    t.builder_worker_key,t.builder_principal_key,p_verifier_key,p_principal_key,p_status,p_evidence
  ) returning id into v_id;

  if t.status='handed_off' then
    update private.pandora_ops_tasks set status='verifying',revision=revision+1
    where organization_id=p_organization_id and project_id=p_project_id and task_key=t.task_key;
  end if;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'verify-record:'||t.task_key||':'||p_generation||':'||p_verifier_key,
    t.task_key,'verification_recorded',v_id::text
  );
  return jsonb_build_object('recorded',true,'verificationRunId',v_id,'status',p_status);
end;
$body$;

revoke all on function public.pandora_ops_record_verification_v1(uuid,uuid,text,bigint,text,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_record_verification_v1(uuid,uuid,text,bigint,text,text,text,jsonb)
  to service_role;

create or replace function public.pandora_ops_verify_v1(
 p_organization_id uuid,p_project_id uuid,p_task_key text,p_generation bigint,
 p_verifier_key text,p_principal_key text,p_verification_run_id uuid,p_receipt jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
 t private.pandora_ops_tasks%rowtype;
 worker private.pandora_ops_workers%rowtype;
 ov private.pandora_ops_verification_receipts%rowtype;
 legacy public.pandora_verification_runs%rowtype;
 v_source_commit text;
 v_profile text;
 v_completed_at timestamptz;
 v_status text;
begin
 perform 1 from private.pandora_ops_workspaces
 where organization_id=p_organization_id and project_id=p_project_id for update;

 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key
 for update;
 if not found or t.generation is distinct from p_generation
    or t.status not in ('handed_off','verifying','complete') or t.cancel_requested then
  raise exception 'OPS_VERIFICATION_FENCED';
 end if;

 select * into worker from private.pandora_ops_workers
 where organization_id=p_organization_id and project_id=p_project_id and worker_key=p_verifier_key;
 if not found or not worker.acknowledged or not worker.connected or worker.health<>'ready'
    or worker.heartbeat_at is null or worker.heartbeat_at<clock_timestamp()-interval '60 seconds'
    or worker.principal_key is distinct from p_principal_key
    or worker.principal_key=t.builder_principal_key or worker.worker_key=t.builder_worker_key
    or not('release'=any(worker.lanes)) then
  raise exception 'OPS_INDEPENDENT_VERIFIER_REQUIRED' using errcode='42501';
 end if;

 select * into ov from private.pandora_ops_verification_receipts
 where id=p_verification_run_id and organization_id=p_organization_id and project_id=p_project_id;
 if found then
  if ov.task_key is distinct from t.task_key or ov.generation is distinct from t.generation
     or ov.verifier_worker_key is distinct from p_verifier_key
     or ov.verifier_principal_key is distinct from p_principal_key then
    raise exception 'OPS_CANONICAL_VERIFICATION_REQUIRED';
  end if;
  v_source_commit:=ov.head_sha; v_profile:=ov.verification_profile;
  v_completed_at:=ov.completed_at; v_status:=ov.status;
 else
  select * into legacy from public.pandora_verification_runs
  where id=p_verification_run_id and organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_CANONICAL_VERIFICATION_REQUIRED'; end if;
  v_source_commit:=legacy.source_commit; v_profile:=legacy.required_check_profile;
  v_completed_at:=legacy.completed_at; v_status:=legacy.status;
 end if;

 if v_status is distinct from 'PASS' or v_completed_at is null
    or v_source_commit is distinct from t.head_sha
    or v_profile is distinct from t.spec->>'verificationProfile' then
  raise exception 'OPS_CANONICAL_VERIFICATION_REQUIRED';
 end if;

 if jsonb_typeof(p_receipt) is distinct from 'object'
    or p_receipt->>'taskId' is distinct from t.task_key
    or p_receipt->>'headSha' is distinct from t.head_sha
    or p_receipt->>'generation' is distinct from p_generation::text
    or p_receipt->>'taskSpecDigest' is distinct from t.spec_digest
    or p_receipt->>'verificationRunId' is distinct from p_verification_run_id::text
    or not coalesce(length(p_receipt->>'ref') between 1 and 1000,false)
    or jsonb_typeof(p_receipt->'criteria') is distinct from 'array'
    or not((p_receipt->'criteria') @> (t.spec->'acceptance'))
    or octet_length(p_receipt::text)>16384 then
  raise exception 'OPS_VERIFICATION_RECEIPT_MISMATCH';
 end if;

 if t.spec->>'risk' in ('production','destructive')
    and (not coalesce(length(p_receipt->>'approvalRef')>0,false)
      or not coalesce(length(p_receipt->>'rollbackRef')>0,false)) then
  raise exception 'OPS_PRODUCTION_PROOF_REQUIRED';
 end if;

 if t.status='complete' then
  if t.verification is distinct from p_receipt then raise exception 'OPS_VERIFICATION_REPLAY_CONFLICT'; end if;
  return jsonb_build_object('complete',true,'replayed',true);
 end if;

 update private.pandora_ops_tasks
 set status='complete',revision=revision+1,verification=p_receipt
 where organization_id=p_organization_id and project_id=p_project_id and task_key=t.task_key;

 perform private.pandora_ops_event_v1(
  p_organization_id,p_project_id,'verify:'||t.task_key||':'||p_generation,
  t.task_key,'verification_accepted',p_verification_run_id::text
 );
 return jsonb_build_object('complete',true,'verificationRunId',p_verification_run_id,'physicalDeviceVerified',false);
end;
$body$;

revoke all on function public.pandora_ops_verify_v1(uuid,uuid,text,bigint,text,text,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_verify_v1(uuid,uuid,text,bigint,text,text,uuid,jsonb)
  to service_role;

create or replace function public.pandora_ops_native_release_verify_v1(
 p_organization_id uuid,p_project_id uuid,p_task_key text,p_verifier_key text,p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
 t private.pandora_ops_tasks%rowtype;
 v_pr jsonb; v_checks jsonb; v_head text; v_merge text;
 v_failed integer; v_pending integer;
 v_evidence jsonb; v_record jsonb; v_id uuid; v_receipt jsonb; v_result jsonb;
begin
 if p_task_key<>'OPS-CLOUD-CONNECTORS-RELEASE-V1' then
  raise exception 'OPS_NATIVE_RELEASE_TASK_UNSUPPORTED' using errcode='22023';
 end if;

 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key;
 if not found or t.status not in ('handed_off','verifying','complete') or t.head_sha is null then
  raise exception 'OPS_NATIVE_RELEASE_TASK_NOT_READY';
 end if;

 v_pr:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/741',null
 );
 if (v_pr->>'status')::integer<>200 or v_pr#>>'{body,merged}'<>'true' then
  raise exception 'OPS_NATIVE_RELEASE_PR_READBACK_FAILED';
 end if;
 v_head:=v_pr#>>'{body,head,sha}'; v_merge:=v_pr#>>'{body,merge_commit_sha}';
 if v_head!~'^[0-9a-f]{40}$' or v_merge is distinct from t.head_sha then
  raise exception 'OPS_NATIVE_RELEASE_SOURCE_MISMATCH';
 end if;

 v_checks:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||v_head||'/check-runs?per_page=100',null
 );
 if (v_checks->>'status')::integer<>200 then raise exception 'OPS_NATIVE_RELEASE_CHECK_READBACK_FAILED'; end if;
 select
  count(*) filter(where c->>'status'<>'completed'),
  count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
 into v_pending,v_failed
 from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;
 if v_pending<>0 or v_failed<>0 then raise exception 'OPS_NATIVE_RELEASE_CHECKS_NOT_GREEN'; end if;

 if not exists(select 1 from jsonb_array_elements(v_checks#>'{body,check_runs}') c where c->>'name'='Pandora coordinator / integration' and c->>'conclusion'='success')
    or not exists(select 1 from jsonb_array_elements(v_checks#>'{body,check_runs}') c where c->>'name'='connector-contract' and c->>'conclusion'='success')
    or not exists(select 1 from jsonb_array_elements(v_checks#>'{body,check_runs}') c where c->>'name'='node24' and c->>'conclusion'='success')
    or not exists(select 1 from jsonb_array_elements(v_checks#>'{body,check_runs}') c where c->>'name'='Dependency review' and c->>'conclusion'='success')
    or not exists(select 1 from jsonb_array_elements(v_checks#>'{body,check_runs}') c where c->>'name'='canonical-release-source-contract' and c->>'conclusion'='success') then
  raise exception 'OPS_NATIVE_RELEASE_REQUIRED_CHECK_MISSING';
 end if;

 if not exists(select 1 from supabase_migrations.schema_migrations where version='20260926012832' and name='operations_connector_delivery_v1')
    or to_regclass('private.pandora_ops_connector_deliveries') is null
    or to_regprocedure('public.pandora_ops_connector_delivery_v1(text,uuid,uuid,jsonb,text,text,jsonb)') is null
    or to_regprocedure('public.pandora_ops_connector_reconcile_v1(uuid,uuid,uuid,bigint,text)') is null then
  raise exception 'OPS_NATIVE_RELEASE_RUNTIME_READBACK_FAILED';
 end if;

 v_evidence:=jsonb_build_object(
  'taskId',t.task_key,'generation',t.generation::text,'headSha',t.head_sha,'taskSpecDigest',t.spec_digest,
  'criteria',t.spec->'acceptance',
  'ref','ops-native-release:pr741:'||t.head_sha,
  'providerReadback',jsonb_build_object(
    'pullRequest',741,'headSha',v_head,'mergeSha',v_merge,
    'coordinator','success','connectorContract','success','node24','success','dependencyReview','success',
    'migration','20260926012832','connectorDeliveryTable',true,'connectorDeliveryRpc',true,'connectorReconcileRpc',true
  )
 );

 v_record:=public.pandora_ops_record_verification_v1(
  p_organization_id,p_project_id,t.task_key,t.generation,p_verifier_key,p_principal_key,'PASS',v_evidence
 );
 v_id:=(v_record->>'verificationRunId')::uuid;
 v_receipt:=v_evidence||jsonb_build_object('verificationRunId',v_id::text);

 v_result:=public.pandora_ops_verify_v1(
  p_organization_id,p_project_id,t.task_key,t.generation,p_verifier_key,p_principal_key,v_id,v_receipt
 );
 return v_result||jsonb_build_object('providerReadbackVerified',true,'legacyProjectOSDependency',false);
end;
$body$;

revoke all on function public.pandora_ops_native_release_verify_v1(uuid,uuid,text,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_native_release_verify_v1(uuid,uuid,text,text,text)
  to service_role;
