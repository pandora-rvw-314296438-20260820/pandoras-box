-- Generic reconciliation for source work that was completed and merged after
-- a dispatched Operations lease expired. Provider truth remains authoritative;
-- this path never fabricates a merge, check result, or source identity.
begin;

create or replace function public.pandora_ops_reconcile_merged_dispatched_source_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_lease_id uuid,
  p_generation bigint,
  p_reconciler_worker_key text,
  p_reconciler_principal_key text,
  p_repository text,
  p_pull_request integer,
  p_branch text,
  p_expected_head_sha text,
  p_receipt_ref text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_workspace private.pandora_ops_workspaces%rowtype;
  v_lease private.pandora_ops_leases%rowtype;
  v_task private.pandora_ops_tasks%rowtype;
  v_worker private.pandora_ops_workers%rowtype;
  v_pr_response jsonb;
  v_pr jsonb;
  v_checks_response jsonb;
  v_checks jsonb;
  v_main_response jsonb;
  v_main_sha text;
  v_merge_sha text;
  v_main_compare_response jsonb;
  v_main_compare jsonb;
  v_base_compare_response jsonb;
  v_base_compare jsonb;
  v_pending integer;
  v_failed integer;
  v_total integer;
  v_handoff jsonb;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'OPS_MERGED_DISPATCH_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_lease_id is null or p_generation is null or p_generation<1
     or p_pull_request is null or p_pull_request<1
     or not coalesce(p_expected_head_sha~'^[a-f0-9]{40}$',false)
     or not coalesce(length(p_receipt_ref) between 1 and 1000,false)
     or not coalesce(length(p_branch) between 1 and 240,false)
     or p_branch !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,239}$'
     or position('..' in p_branch)>0 or position('//' in p_branch)>0
     or right(p_branch,1)='/' or right(p_branch,5)='.lock'
     or p_repository not in (
       'pandora-rvw-314296438-20260820/pandoras-box',
       'pandora-rvw-314296438-20260820/pandoras-box-memory'
     ) then
    raise exception 'OPS_MERGED_DISPATCH_INPUT_INVALID' using errcode='22023';
  end if;

  perform 1 from private.pandora_ops_project_bindings
   where organization_id=p_organization_id and project_id=p_project_id and state='active';
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  select * into v_workspace from private.pandora_ops_workspaces
   where organization_id=p_organization_id and project_id=p_project_id for update;
  if not found or v_workspace.paused then raise exception 'OPS_WORKSPACE_PAUSED'; end if;

  select * into v_lease from private.pandora_ops_leases
   where id=p_lease_id and organization_id=p_organization_id and project_id=p_project_id
   for update;
  if not found or v_lease.generation is distinct from p_generation
     or v_lease.state not in ('running','reconcile')
     or v_lease.expires_at>clock_timestamp() then
    raise exception 'OPS_MERGED_DISPATCH_LEASE_FENCED';
  end if;

  select * into v_task from private.pandora_ops_tasks
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=v_lease.task_key for update;
  if not found or v_task.generation is distinct from p_generation
     or v_task.cancel_requested
     or v_task.status not in ('claimed','implementing','blocked')
     or v_task.spec->>'risk'<>'source'
     or v_task.spec#>>'{source,repository}' is distinct from p_repository
     or not coalesce(v_task.spec#>>'{source,baseSha}' ~ '^[a-f0-9]{40}$',false)
     or v_task.builder_worker_key is distinct from v_lease.worker_key then
    raise exception 'OPS_MERGED_DISPATCH_TASK_FENCED';
  end if;

  select * into v_worker from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_reconciler_worker_key
     and principal_key=p_reconciler_principal_key;
  if not found or not v_worker.acknowledged or not v_worker.connected
     or v_worker.health<>'ready'
     or v_worker.heartbeat_at is null
     or v_worker.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not ('release'=any(v_worker.lanes))
     or not ('provider.readback'=any(v_worker.capabilities))
     or v_worker.worker_key is not distinct from v_task.builder_worker_key
     or v_worker.principal_key is not distinct from v_task.builder_principal_key then
    raise exception 'OPS_MERGED_DISPATCH_INDEPENDENT_RECONCILER_REQUIRED' using errcode='42501';
  end if;

  v_pr_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/pulls/'||p_pull_request::text,null
  );
  if coalesce((v_pr_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_MERGED_DISPATCH_PR_READBACK_FAILED';
  end if;
  v_pr:=coalesce(v_pr_response->'body','{}'::jsonb);
  v_merge_sha:=v_pr->>'merge_commit_sha';
  if v_pr->>'merged' is distinct from 'true'
     or v_pr#>>'{head,sha}' is distinct from p_expected_head_sha
     or v_pr#>>'{head,ref}' is distinct from p_branch
     or v_pr#>>'{head,repo,full_name}' is distinct from p_repository
     or v_pr#>>'{base,ref}' is distinct from 'main'
     or v_pr#>>'{base,repo,full_name}' is distinct from p_repository
     or not coalesce(v_merge_sha~'^[a-f0-9]{40}$',false) then
    raise exception 'OPS_MERGED_DISPATCH_PR_IDENTITY_MISMATCH';
  end if;

  v_checks_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/commits/'||p_expected_head_sha||'/check-runs?per_page=100',null
  );
  if coalesce((v_checks_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_MERGED_DISPATCH_CHECK_READBACK_FAILED';
  end if;
  v_checks:=coalesce(v_checks_response#>'{body,check_runs}','[]'::jsonb);
  select count(*),
         count(*) filter(where c->>'status'<>'completed'),
         count(*) filter(where c->>'status'='completed'
           and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
    into v_total,v_pending,v_failed
  from jsonb_array_elements(v_checks) c;
  if v_total<1 or v_pending<>0 or v_failed<>0 then
    raise exception 'OPS_MERGED_DISPATCH_CHECKS_NOT_GREEN';
  end if;

  v_main_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/git/ref/heads/main',null
  );
  if coalesce((v_main_response->>'status')::integer,0)<>200
     or not coalesce(v_main_response#>>'{body,object,sha}'~'^[a-f0-9]{40}$',false) then
    raise exception 'OPS_MERGED_DISPATCH_MAIN_READBACK_FAILED';
  end if;
  v_main_sha:=v_main_response#>>'{body,object,sha}';

  v_main_compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/compare/'||v_merge_sha||'%2E%2E%2E'||v_main_sha,null
  );
  if coalesce((v_main_compare_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_MERGED_DISPATCH_MAIN_LINEAGE_READBACK_FAILED';
  end if;
  v_main_compare:=coalesce(v_main_compare_response->'body','{}'::jsonb);
  if not coalesce(v_main_compare->>'status' in ('ahead','identical'),false)
     or coalesce((v_main_compare->>'behind_by')::integer,-1)<>0 then
    raise exception 'OPS_MERGED_DISPATCH_MAIN_LINEAGE_DIVERGED';
  end if;

  v_base_compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/compare/'||
    (v_task.spec#>>'{source,baseSha}')||'%2E%2E%2E'||p_expected_head_sha,null
  );
  if coalesce((v_base_compare_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_MERGED_DISPATCH_BASE_LINEAGE_READBACK_FAILED';
  end if;
  v_base_compare:=coalesce(v_base_compare_response->'body','{}'::jsonb);
  if not coalesce(v_base_compare->>'status' in ('ahead','identical'),false)
     or coalesce((v_base_compare->>'behind_by')::integer,-1)<>0 then
    raise exception 'OPS_MERGED_DISPATCH_BASE_LINEAGE_DIVERGED';
  end if;

  v_handoff:=jsonb_build_object(
    'taskId',v_task.task_key,
    'workerId',v_task.builder_worker_key,
    'generation',p_generation::text,
    'headSha',p_expected_head_sha,
    'pullRequest',p_pull_request,
    'implementationComplete',true,
    'receiptRef',p_receipt_ref,
    'tests',jsonb_build_array(
      'Provider readback confirms the pull request is merged from the expected branch and exact head.',
      'All observed exact-head GitHub check runs are terminal and acceptable.',
      'Merged commit is an ancestor of current main.',
      'Exact head descends from the task source base.'
    ),
    'evidenceRefs',jsonb_build_array(
      'github:pull/'||p_pull_request::text,
      'github:head/'||p_expected_head_sha,
      'github:merge/'||v_merge_sha
    )
  );

  update private.pandora_ops_tasks
     set status='handed_off',
         revision=revision+1,
         head_sha=p_expected_head_sha,
         handoff=v_handoff
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=v_task.task_key;

  perform private.pandora_ops_settle_v1(
    p_organization_id,p_project_id,v_lease.id,p_generation,0,p_receipt_ref
  );
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'merged-dispatch-reconcile:'||v_lease.id::text,
    v_task.task_key,'implementation_handed_off',p_receipt_ref
  );

  return jsonb_build_object(
    'handedOff',true,
    'taskId',v_task.task_key,
    'generation',p_generation,
    'headSha',p_expected_head_sha,
    'pullRequest',p_pull_request,
    'mergeSha',v_merge_sha,
    'currentMainSha',v_main_sha,
    'checksObserved',v_total,
    'releaseVerified',false
  );
end;
$function$;

revoke all on function public.pandora_ops_reconcile_merged_dispatched_source_v1(
  uuid,uuid,uuid,bigint,text,text,text,integer,text,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_ops_reconcile_merged_dispatched_source_v1(
  uuid,uuid,uuid,bigint,text,text,text,integer,text,text,text
) to service_role;

commit;
