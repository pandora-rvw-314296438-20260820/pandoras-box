-- Generic provider-verified source adoption for expired/stranded source tasks.
-- This does not grant production/spend authority and cannot complete a task by itself.
begin;

create table if not exists private.pandora_ops_provider_source_adoptions(
  id uuid primary key,
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  prior_generation bigint not null,
  adopted_generation bigint not null,
  prior_revision bigint not null,
  task_spec_digest text not null,
  repository text not null,
  pull_request integer not null,
  head_sha text not null,
  merge_sha text not null,
  canonical_main_sha text not null,
  reconciler_worker_key text not null,
  reconciler_principal_key text not null,
  provider_readback jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,task_key,adopted_generation)
);

create or replace function private.pandora_ops_provider_source_adoption_immutable_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_IMMUTABLE' using errcode='55000';
end;
$function$;

drop trigger if exists pandora_ops_provider_source_adoption_immutable_v1
on private.pandora_ops_provider_source_adoptions;
create trigger pandora_ops_provider_source_adoption_immutable_v1
before update or delete on private.pandora_ops_provider_source_adoptions
for each row execute function private.pandora_ops_provider_source_adoption_immutable_v1();

create or replace function public.pandora_ops_adopt_provider_verified_source_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_adoption_id uuid,
  p_task_key text,
  p_expected_revision bigint,
  p_expected_generation bigint,
  p_repository text,
  p_pull_request integer,
  p_head_sha text,
  p_merge_sha text,
  p_reconciler_worker_key text,
  p_reconciler_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  t private.pandora_ops_tasks%rowtype;
  w private.pandora_ops_workers%rowtype;
  existing private.pandora_ops_provider_source_adoptions%rowtype;
  l private.pandora_ops_leases%rowtype;
  pr_response jsonb;
  pr jsonb;
  checks_response jsonb;
  checks jsonb;
  merge_response jsonb;
  merge_commit jsonb;
  main_response jsonb;
  main_sha text;
  compare_response jsonb;
  base_compare_response jsonb;
  pending_count integer;
  failed_count integer;
  adopted_generation bigint;
  readback jsonb;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_adoption_id is null
     or p_expected_revision is null or p_expected_revision<0
     or p_expected_generation is null or p_expected_generation<0
     or p_pull_request is null or p_pull_request<1
     or not coalesce(p_task_key~'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$',false)
     or p_repository not in (
       'pandora-rvw-314296438-20260820/pandoras-box',
       'pandora-rvw-314296438-20260820/pandoras-box-memory'
     )
     or not coalesce(p_head_sha~'^[a-f0-9]{40}$',false)
     or not coalesce(p_merge_sha~'^[a-f0-9]{40}$',false) then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_INPUT_INVALID' using errcode='22023';
  end if;

  perform 1 from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active';
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  perform 1 from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id and not paused;
  if not found then raise exception 'OPS_WORKSPACE_PAUSED'; end if;

  select * into t from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key
  for update;
  if not found
     or t.revision is distinct from p_expected_revision
     or t.generation is distinct from p_expected_generation
     or t.cancel_requested
     or t.spec->>'risk' is distinct from 'source'
     or t.spec#>>'{source,repository}' is distinct from p_repository
     or t.status in ('complete','cancelled') then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_TASK_FENCED';
  end if;

  select * into existing from private.pandora_ops_provider_source_adoptions
  where id=p_adoption_id;
  if found then
    if existing.organization_id is distinct from p_organization_id
       or existing.project_id is distinct from p_project_id
       or existing.task_key is distinct from p_task_key
       or existing.head_sha is distinct from p_head_sha
       or existing.merge_sha is distinct from p_merge_sha then
      raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_REPLAY_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object(
      'adopted',true,'replayed',true,'taskId',existing.task_key,
      'generation',existing.adopted_generation,'headSha',existing.head_sha,
      'receiptId',existing.id
    );
  end if;

  if exists(
    select 1 from private.pandora_ops_leases
    where organization_id=p_organization_id and project_id=p_project_id
      and task_key=p_task_key and state<>'released' and expires_at>clock_timestamp()
  ) then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_ACTIVE_LEASE';
  end if;

  for l in
    select * from private.pandora_ops_leases
    where organization_id=p_organization_id and project_id=p_project_id
      and task_key=p_task_key and state<>'released' and expires_at<=clock_timestamp()
    for update
  loop
    perform private.pandora_ops_settle_v1(
      p_organization_id,p_project_id,l.id,l.generation,0,
      'provider-source-adoption:'||p_adoption_id::text
    );
  end loop;

  select * into w from private.pandora_ops_workers
  where organization_id=p_organization_id and project_id=p_project_id
    and worker_key=p_reconciler_worker_key and principal_key=p_reconciler_principal_key;
  if not found or not w.acknowledged or not w.connected or w.health<>'ready'
     or w.heartbeat_at is null or w.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not ('release'=any(w.lanes))
     or not ('provider.readback'=any(w.capabilities))
     or w.worker_key is not distinct from t.builder_worker_key
     or w.principal_key is not distinct from t.builder_principal_key then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_INDEPENDENT_RECONCILER_REQUIRED' using errcode='42501';
  end if;

  pr_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/pulls/'||p_pull_request::text,null
  );
  if coalesce((pr_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_PR_READBACK_FAILED';
  end if;
  pr:=coalesce(pr_response->'body','{}'::jsonb);
  if pr->'merged' is distinct from 'true'::jsonb
     or pr->>'state' is distinct from 'closed'
     or pr#>>'{head,sha}' is distinct from p_head_sha
     or pr#>>'{head,repo,full_name}' is distinct from p_repository
     or pr#>>'{base,ref}' is distinct from 'main'
     or pr#>>'{base,repo,full_name}' is distinct from p_repository
     or pr->>'merge_commit_sha' is distinct from p_merge_sha then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_PR_IDENTITY_MISMATCH';
  end if;

  merge_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/commits/'||p_merge_sha,null
  );
  merge_commit:=coalesce(merge_response->'body','{}'::jsonb);
  if coalesce((merge_response->>'status')::integer,0)<>200
     or merge_commit->>'sha' is distinct from p_merge_sha
     or not exists(
       select 1 from jsonb_array_elements(coalesce(merge_commit->'parents','[]'::jsonb)) p
       where p->>'sha'=p_head_sha
     ) then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_MERGE_PARENT_MISMATCH';
  end if;

  checks_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/commits/'||p_head_sha||'/check-runs?per_page=100',null
  );
  if coalesce((checks_response->>'status')::integer,0)<>200 then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_CHECK_READBACK_FAILED';
  end if;
  checks:=coalesce(checks_response#>'{body,check_runs}','[]'::jsonb);
  if jsonb_typeof(checks) is distinct from 'array' or jsonb_array_length(checks)=0 then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_CHECKS_REQUIRED';
  end if;
  select
    count(*) filter(where c->>'status'<>'completed'),
    count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
  into pending_count,failed_count
  from jsonb_array_elements(checks) c;
  if pending_count<>0 or failed_count<>0
     or not exists(
       select 1 from jsonb_array_elements(checks) c
       where c->>'name'='Pandora coordinator / integration' and c->>'conclusion'='success'
     ) then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_CHECKS_NOT_ACCEPTABLE';
  end if;

  main_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/git/ref/heads/main',null
  );
  main_sha:=main_response#>>'{body,object,sha}';
  if coalesce((main_response->>'status')::integer,0)<>200
     or not coalesce(main_sha~'^[a-f0-9]{40}$',false) then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_MAIN_READBACK_FAILED';
  end if;

  compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/compare/'||p_merge_sha||'%2E%2E%2E'||main_sha,null
  );
  if coalesce((compare_response->>'status')::integer,0)<>200
     or coalesce(compare_response#>>'{body,status}','') not in ('ahead','identical')
     or coalesce((compare_response#>>'{body,behind_by}')::integer,-1)<>0 then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_MAIN_LINEAGE_UNCONFIRMED';
  end if;

  base_compare_response:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||p_repository||'/compare/'||
    (t.spec#>>'{source,baseSha}')||'%2E%2E%2E'||p_head_sha,null
  );
  if coalesce((base_compare_response->>'status')::integer,0)<>200
     or coalesce(base_compare_response#>>'{body,status}','') not in ('ahead','identical')
     or coalesce((base_compare_response#>>'{body,behind_by}')::integer,-1)<>0 then
    raise exception 'OPS_PROVIDER_SOURCE_ADOPTION_BASE_LINEAGE_UNCONFIRMED';
  end if;

  adopted_generation:=t.generation+1;
  readback:=jsonb_build_object(
    'provider','github','pullRequest',p_pull_request,'headSha',p_head_sha,
    'mergeSha',p_merge_sha,'mainSha',main_sha,
    'checkCount',jsonb_array_length(checks),'allChecksTerminalAcceptable',true,
    'coordinator','success','baseSha',t.spec#>>'{source,baseSha}'
  );

  insert into private.pandora_ops_provider_source_adoptions(
    id,organization_id,project_id,task_key,prior_generation,adopted_generation,
    prior_revision,task_spec_digest,repository,pull_request,head_sha,merge_sha,
    canonical_main_sha,reconciler_worker_key,reconciler_principal_key,provider_readback
  ) values(
    p_adoption_id,p_organization_id,p_project_id,t.task_key,t.generation,adopted_generation,
    t.revision,t.spec_digest,p_repository,p_pull_request,p_head_sha,p_merge_sha,
    main_sha,w.worker_key,w.principal_key,readback
  );

  update private.pandora_ops_tasks
  set status='verifying',
      generation=adopted_generation,
      revision=revision+1,
      head_sha=p_head_sha,
      verification=null,
      handoff=coalesce(handoff,jsonb_build_object(
        'taskId',task_key,'generation',adopted_generation::text,
        'headSha',p_head_sha,'pullRequest',p_pull_request,
        'workerId',coalesce(builder_worker_key,'provider-source-adoption'),
        'implementationComplete',true,
        'providerSourceAdoption',true,'adoptionId',p_adoption_id::text
      ))
  where organization_id=p_organization_id and project_id=p_project_id and task_key=t.task_key;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'provider-source-adoption:'||p_adoption_id::text,
    t.task_key,'provider_source_adopted',p_adoption_id::text
  );

  return jsonb_build_object(
    'adopted',true,'replayed',false,'state','verifying','taskId',t.task_key,
    'generation',adopted_generation,'headSha',p_head_sha,'receiptId',p_adoption_id,
    'providerReadback',readback
  );
end;
$function$;

revoke all on private.pandora_ops_provider_source_adoptions from public,anon,authenticated;
revoke all on function public.pandora_ops_adopt_provider_verified_source_v1(
  uuid,uuid,uuid,text,bigint,bigint,text,integer,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_ops_adopt_provider_verified_source_v1(
  uuid,uuid,uuid,text,bigint,bigint,text,integer,text,text,text,text
) to service_role;

commit;

