-- Append-only reconciliation for a provider action that completed outside the
-- durable Operations dispatch boundary. This migration does not execute or
-- retry a provider action. It performs bounded GitHub GET readback, releases a
-- lease already held in reconciliation and advances the task only to
-- independent verification.
--
-- This increment intentionally adds no completion authority. A preserved
-- historical source receipt or handoff remains bound to its old head, so the
-- generic-source release step is not compatible with the reconciled head.
-- Exact-head completion must use the existing service-role verification RPCs
-- through a separately authorized caller; this control action does not expose
-- those RPCs for arbitrary tasks.

create table private.pandora_ops_external_success_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  lease_id uuid not null references private.pandora_ops_leases(id),
  generation bigint not null check (generation > 0),
  task_key text not null,
  reconciler_worker_key text not null,
  reconciler_principal_key text not null,
  provider text not null check (provider = 'github'),
  operation text not null check (operation = 'pull_request_branch_update'),
  provider_operation_id text not null check (
    provider_operation_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,199}$'
  ),
  action_digest text not null check (action_digest ~ '^[a-f0-9]{64}$'),
  provider_receipt_sha256 text not null check (provider_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  repository text not null,
  pull_request integer not null check (pull_request between 1 and 2147483647),
  branch text not null,
  requested_base_sha text not null check (requested_base_sha ~ '^[a-f0-9]{40}$'),
  observed_base_sha text not null check (observed_base_sha ~ '^[a-f0-9]{40}$'),
  prior_task_head_sha text check (prior_task_head_sha is null or prior_task_head_sha ~ '^[a-f0-9]{40}$'),
  observed_head_sha text not null check (observed_head_sha ~ '^[a-f0-9]{40}$'),
  receipt_ref text not null check (length(receipt_ref) between 1 and 1000),
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  provider_readback jsonb not null check (jsonb_typeof(provider_readback) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, lease_id, generation),
  unique (organization_id, project_id, provider, provider_operation_id),
  foreign key (organization_id, project_id, task_key)
    references private.pandora_ops_tasks(organization_id, project_id, task_key),
  foreign key (organization_id, project_id, reconciler_worker_key)
    references private.pandora_ops_workers(organization_id, project_id, worker_key)
);

create index pandora_ops_external_success_task_idx
  on private.pandora_ops_external_success_receipts(
    organization_id, project_id, task_key, generation
  );

alter table private.pandora_ops_external_success_receipts enable row level security;
revoke all on private.pandora_ops_external_success_receipts
  from public, anon, authenticated, service_role;

create function private.pandora_ops_external_success_immutable_v1()
returns trigger
language plpgsql
set search_path=''
as $fn$
begin
  raise exception 'OPS_EXTERNAL_SUCCESS_RECEIPT_IMMUTABLE' using errcode='55000';
end;
$fn$;

create trigger pandora_ops_external_success_immutable
before update or delete on private.pandora_ops_external_success_receipts
for each row execute function private.pandora_ops_external_success_immutable_v1();

create function public.pandora_ops_reconcile_external_success_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_lease_id uuid,
  p_generation bigint,
  p_reconciler_worker_key text,
  p_reconciler_principal_key text,
  p_receipt jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  workspace private.pandora_ops_workspaces%rowtype;
  lease private.pandora_ops_leases%rowtype;
  task private.pandora_ops_tasks%rowtype;
  reconciler private.pandora_ops_workers%rowtype;
  source_receipt private.pandora_ops_source_execution_receipts%rowtype;
  existing private.pandora_ops_external_success_receipts%rowtype;
  provider_replay private.pandora_ops_external_success_receipts%rowtype;
  pr_response jsonb;
  pr_body jsonb;
  compare_response jsonb;
  compare_body jsonb;
  base_compare_response jsonb;
  base_compare_body jsonb;
  prior_compare_response jsonb;
  prior_compare_body jsonb := '{}'::jsonb;
  main_response jsonb;
  v_repository text;
  v_pull_request integer;
  v_branch text;
  v_requested_base_sha text;
  v_observed_base_sha text;
  v_observed_head_sha text;
  v_provider_operation_id text;
  v_action_digest text;
  v_provider_receipt_sha256 text;
  v_readback jsonb;
  expected_fields constant text[] := array[
    'taskId','taskSpecDigest','repository','pullRequest','branch',
    'observedHeadSha','ref'
  ];
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_EXTERNAL_SUCCESS_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  perform 1 from private.pandora_ops_project_bindings
   where organization_id=p_organization_id and project_id=p_project_id and state='active'
   for share;
  if not found then
    raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501';
  end if;

  select * into workspace from private.pandora_ops_workspaces
   where organization_id=p_organization_id and project_id=p_project_id for update;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;

  if jsonb_typeof(p_receipt) is distinct from 'object'
     or not (p_receipt ?& expected_fields)
     or (select count(*) from jsonb_object_keys(p_receipt)) <> cardinality(expected_fields)
     or not coalesce(p_receipt->>'taskId' ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$',false)
     or not coalesce(p_receipt->>'taskSpecDigest' ~ '^[a-f0-9]{64}$',false)
     or not coalesce(p_receipt->>'observedHeadSha' ~ '^[a-f0-9]{40}$',false)
     or not coalesce((p_receipt->>'pullRequest') ~ '^[1-9][0-9]{0,9}$',false)
     or not coalesce(length(p_receipt->>'ref') between 1 and 1000,false)
     or octet_length(p_receipt::text) > 8192 then
    raise exception 'OPS_EXTERNAL_SUCCESS_RECEIPT_INVALID' using errcode='22023';
  end if;

  v_repository:=p_receipt->>'repository';
  v_pull_request:=(p_receipt->>'pullRequest')::integer;
  v_branch:=p_receipt->>'branch';
  v_observed_head_sha:=p_receipt->>'observedHeadSha';

  if not coalesce(v_repository=any(array[
       'pandora-rvw-314296438-20260820/pandoras-box',
       'pandora-rvw-314296438-20260820/pandoras-box-memory'
     ]),false)
     or not coalesce(
       length(v_branch) between 1 and 240
       and v_branch ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,239}$'
       and position('..' in v_branch)=0
       and position('//' in v_branch)=0
       and right(v_branch,1)<>'/'
       and right(v_branch,5)<>'.lock',
       false
     ) then
    raise exception 'OPS_EXTERNAL_SUCCESS_SOURCE_INVALID' using errcode='22023';
  end if;

  select * into existing from private.pandora_ops_external_success_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and lease_id=p_lease_id and generation=p_generation;
  if found then
    if existing.receipt is distinct from p_receipt
       or existing.reconciler_worker_key is distinct from p_reconciler_worker_key
       or existing.reconciler_principal_key is distinct from p_reconciler_principal_key then
      raise exception 'OPS_EXTERNAL_SUCCESS_REPLAY_CONFLICT' using errcode='23505';
    end if;
    select * into task from private.pandora_ops_tasks
     where organization_id=p_organization_id and project_id=p_project_id
       and task_key=existing.task_key;
    if not found or task.generation is distinct from existing.generation
       or task.head_sha is distinct from existing.observed_head_sha
       or task.status not in ('verifying','complete') then
      raise exception 'OPS_EXTERNAL_SUCCESS_REPLAY_STATE_CONFLICT';
    end if;
    return jsonb_build_object(
      'state',task.status,'taskId',existing.task_key,'generation',existing.generation,
      'headSha',existing.observed_head_sha,'leaseReleased',true,'complete',task.status='complete',
      'replayed',true,'receiptId',existing.id
    );
  end if;

  select receipt.* into provider_replay from private.pandora_ops_external_success_receipts receipt
   where receipt.organization_id=p_organization_id and receipt.project_id=p_project_id
     and receipt.provider='github'
     and receipt.provider_operation_id='github:pull_request_branch_update:'||v_pull_request::text||':'||v_observed_head_sha;
  if found then raise exception 'OPS_EXTERNAL_SUCCESS_PROVIDER_REPLAY' using errcode='23505'; end if;

  select * into lease from private.pandora_ops_leases
   where id=p_lease_id and organization_id=p_organization_id and project_id=p_project_id
   for update;
  if not found or lease.generation is distinct from p_generation or lease.state<>'reconcile'
     or lease.expires_at>clock_timestamp() then
    raise exception 'OPS_EXTERNAL_SUCCESS_LEASE_FENCED';
  end if;
  if exists(select 1 from private.pandora_ops_dispatch_outbox where lease_id=p_lease_id) then
    raise exception 'OPS_EXTERNAL_SUCCESS_DISPATCH_PRESENT';
  end if;

  select * into task from private.pandora_ops_tasks
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=lease.task_key for update;
  if not found or task.generation is distinct from p_generation
     or task.status<>'blocked' or task.cancel_requested then
    raise exception 'OPS_EXTERNAL_SUCCESS_TASK_FENCED';
  end if;
  if p_receipt->>'taskId' is distinct from task.task_key
     or p_receipt->>'taskSpecDigest' is distinct from task.spec_digest
     or v_repository is distinct from task.spec#>>'{source,repository}'
     or task.spec->>'risk' is distinct from 'source' then
    raise exception 'OPS_EXTERNAL_SUCCESS_TASK_BINDING_MISMATCH';
  end if;
  if not exists(
       select 1 from jsonb_array_elements(task.spec->'resources') resource
       where resource->>'key'='git/branch/'||v_branch and resource->>'mode'='write'
     )
     or not exists(
       select 1 from jsonb_array_elements(task.spec->'resources') resource
       where resource->>'key'='release/pr/'||v_pull_request::text and resource->>'mode'='write'
     ) then
    raise exception 'OPS_EXTERNAL_SUCCESS_RESOURCE_BINDING_MISMATCH';
  end if;
  if task.handoff is not null and (
       task.handoff->>'pullRequest' is distinct from v_pull_request::text
       or task.handoff->>'headSha' is distinct from task.head_sha
     ) then
    raise exception 'OPS_EXTERNAL_SUCCESS_PRIOR_HANDOFF_MISMATCH';
  end if;
  select * into source_receipt from private.pandora_ops_source_execution_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=task.task_key and generation=p_generation;
  if found and (
       source_receipt.pull_request is distinct from v_pull_request
       or source_receipt.branch_name is distinct from v_branch
       or source_receipt.head_sha is distinct from task.head_sha
     ) then
    raise exception 'OPS_EXTERNAL_SUCCESS_PRIOR_SOURCE_RECEIPT_MISMATCH';
  end if;
  v_requested_base_sha:=task.spec#>>'{source,baseSha}';

  select * into reconciler from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_reconciler_worker_key
     and principal_key=p_reconciler_principal_key;
  if not found or not reconciler.acknowledged or not reconciler.connected
     or reconciler.health<>'ready'
     or reconciler.heartbeat_at is null
     or reconciler.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not ('release'=any(reconciler.lanes))
     or not ('provider.readback'=any(reconciler.capabilities))
     or reconciler.worker_key=task.builder_worker_key
     or reconciler.principal_key=task.builder_principal_key then
    raise exception 'OPS_EXTERNAL_SUCCESS_INDEPENDENT_RECONCILER_REQUIRED' using errcode='42501';
  end if;

  pr_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repository||'/pulls/'||v_pull_request::text,null
  );
  if coalesce((pr_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_EXTERNAL_SUCCESS_PR_READBACK_FAILED';
  end if;
  pr_body:=coalesce(pr_response->'body','{}'::jsonb);
  if pr_body#>>'{head,sha}' is distinct from v_observed_head_sha
     or pr_body#>>'{head,ref}' is distinct from v_branch
     or pr_body#>>'{head,repo,full_name}' is distinct from v_repository
     or pr_body#>>'{base,ref}' is distinct from 'main'
     or pr_body#>>'{base,repo,full_name}' is distinct from v_repository
     or not coalesce(pr_body#>>'{base,sha}' ~ '^[a-f0-9]{40}$',false)
     or pr_body->>'state' is distinct from 'open' then
    raise exception 'OPS_EXTERNAL_SUCCESS_PR_IDENTITY_MISMATCH';
  end if;
  v_observed_base_sha:=pr_body#>>'{base,sha}';

  main_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repository||'/git/ref/heads/main',null
  );
  if coalesce((main_response->>'status')::integer,0)<>200
     or main_response#>>'{body,object,sha}' is distinct from v_observed_base_sha then
    raise exception 'OPS_EXTERNAL_SUCCESS_CANONICAL_BASE_MISMATCH';
  end if;

  compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repository||'/compare/'||v_observed_base_sha||'%2E%2E%2E'||v_observed_head_sha,null
  );
  if coalesce((compare_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_EXTERNAL_SUCCESS_COMPARE_READBACK_FAILED';
  end if;
  compare_body:=coalesce(compare_response->'body','{}'::jsonb);
  if not coalesce(compare_body->>'status' in ('ahead','identical'),false)
     or coalesce((compare_body->>'behind_by')::integer,-1)<>0 then
    raise exception 'OPS_EXTERNAL_SUCCESS_SOURCE_DIVERGED';
  end if;

  base_compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repository||'/compare/'||v_requested_base_sha||'%2E%2E%2E'||v_observed_base_sha,null
  );
  if coalesce((base_compare_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_EXTERNAL_SUCCESS_BASE_READBACK_FAILED';
  end if;
  base_compare_body:=coalesce(base_compare_response->'body','{}'::jsonb);
  if not coalesce(base_compare_body->>'status' in ('ahead','identical'),false)
     or coalesce((base_compare_body->>'behind_by')::integer,-1)<>0 then
    raise exception 'OPS_EXTERNAL_SUCCESS_BASE_DIVERGED';
  end if;

  if task.head_sha is not null then
    prior_compare_response:=private.pandora_integration_github_api_20260825(
      'GET','/repos/'||v_repository||'/compare/'||task.head_sha||'%2E%2E%2E'||v_observed_head_sha,null
    );
    if coalesce((prior_compare_response->>'status')::integer,0)<>200 then
      raise exception 'OPS_EXTERNAL_SUCCESS_PRIOR_HEAD_READBACK_FAILED';
    end if;
    prior_compare_body:=coalesce(prior_compare_response->'body','{}'::jsonb);
    if not coalesce(prior_compare_body->>'status' in ('ahead','identical'),false)
       or coalesce((prior_compare_body->>'behind_by')::integer,-1)<>0 then
      raise exception 'OPS_EXTERNAL_SUCCESS_PRIOR_HEAD_DIVERGED';
    end if;
  end if;

  v_provider_operation_id:='github:pull_request_branch_update:'||v_pull_request::text||':'||v_observed_head_sha;
  v_action_digest:=encode(extensions.digest(convert_to(jsonb_build_object(
    'provider','github','operation','pull_request_branch_update',
    'providerOperationId',v_provider_operation_id,
    'repository',v_repository,'pullRequest',v_pull_request,'branch',v_branch,
    'requestedBaseSha',v_requested_base_sha,'observedBaseSha',v_observed_base_sha,
    'observedHeadSha',v_observed_head_sha
  )::text,'UTF8'),'sha256'),'hex');
  v_readback:=jsonb_build_object(
    'provider','github','method','GET','pullRequest',v_pull_request,
    'repository',v_repository,'branch',v_branch,'headSha',v_observed_head_sha,
    'baseBranch','main','baseSha',v_observed_base_sha,'pullRequestState',pr_body->>'state',
    'lineageStatus',compare_body->>'status','behindBy',(compare_body->>'behind_by')::integer,
    'requestedBaseLineageStatus',base_compare_body->>'status',
    'requestedBaseBehindBy',(base_compare_body->>'behind_by')::integer,
    'priorHeadSha',task.head_sha,
    'priorHeadLineageStatus',prior_compare_body->>'status',
    'priorHeadBehindBy',case when prior_compare_body ? 'behind_by'
      then (prior_compare_body->>'behind_by')::integer else null end
  );
  v_provider_receipt_sha256:=encode(
    extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'
  );

  insert into private.pandora_ops_external_success_receipts(
    organization_id,project_id,lease_id,generation,task_key,
    reconciler_worker_key,reconciler_principal_key,provider,operation,
    provider_operation_id,action_digest,provider_receipt_sha256,repository,
    pull_request,branch,requested_base_sha,observed_base_sha,prior_task_head_sha,observed_head_sha,
    receipt_ref,receipt,provider_readback
  ) values (
    p_organization_id,p_project_id,p_lease_id,p_generation,task.task_key,
    p_reconciler_worker_key,p_reconciler_principal_key,'github','pull_request_branch_update',
    v_provider_operation_id,v_action_digest,v_provider_receipt_sha256,v_repository,
    v_pull_request,v_branch,v_requested_base_sha,v_observed_base_sha,task.head_sha,v_observed_head_sha,
    p_receipt->>'ref',p_receipt,v_readback
  ) returning * into existing;

  -- This changes the task's current source projection but preserves the original
  -- handoff and every historical event. The immutable receipt is the authority
  -- for why verification now targets the externally observed head.
  update private.pandora_ops_tasks
     set status='verifying',revision=revision+1,head_sha=v_observed_head_sha
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=task.task_key;
  perform private.pandora_ops_settle_v1(
    p_organization_id,p_project_id,p_lease_id,p_generation,0,p_receipt->>'ref'
  );
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'external-success:'||p_lease_id::text,
    task.task_key,'external_success_reconciled',p_receipt->>'ref'
  );

  return jsonb_build_object(
    'state','verifying','taskId',task.task_key,'generation',p_generation,
    'headSha',v_observed_head_sha,'leaseReleased',true,'complete',false,
    'replayed',false,'receiptId',existing.id
  );
end;
$fn$;

revoke all on function private.pandora_ops_external_success_immutable_v1()
  from public,anon,authenticated,service_role;
revoke all on function public.pandora_ops_reconcile_external_success_v1(
  uuid,uuid,uuid,bigint,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_ops_reconcile_external_success_v1(
  uuid,uuid,uuid,bigint,text,text,jsonb
) to service_role;

comment on table private.pandora_ops_external_success_receipts is
  'Append-only evidence for externally completed GitHub branch updates. Receipt acceptance does not complete an Operations task; independent exact-head verification remains required.';
comment on function public.pandora_ops_reconcile_external_success_v1(
  uuid,uuid,uuid,bigint,text,text,jsonb
) is
  'Service-only, GET-readback reconciliation of one known successful GitHub branch update. Never executes or retries provider mutation, advances only to verifying, and grants no verification or completion authority.';
