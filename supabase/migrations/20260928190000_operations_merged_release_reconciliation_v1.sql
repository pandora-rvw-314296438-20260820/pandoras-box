-- Adopt a merged PR's final head for fresh verification; never grants completion.
-- Provider evidence is fetched server-side. Historical handoffs and reviews remain intact.
create table private.pandora_ops_merged_release_receipts (
 id uuid primary key,
 organization_id uuid not null, project_id uuid not null, task_key text not null,
 prior_generation bigint not null, adopted_generation bigint not null,
 prior_revision bigint not null, task_spec_digest text not null,
 prior_head_sha text not null, head_sha text not null, merge_sha text not null,
 canonical_main_sha text not null, repository text not null, pull_request integer not null,
 reconciler_worker_key text not null, reconciler_principal_key text not null,
 prior_task jsonb not null, provider_readback jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,project_id,task_key,prior_generation),
 check(adopted_generation=prior_generation+1),
 check(prior_generation>0 and prior_revision>=0 and pull_request>0),
 check(task_spec_digest ~ '^[a-f0-9]{64}$'),
 check(prior_head_sha ~ '^[a-f0-9]{40}$' and head_sha ~ '^[a-f0-9]{40}$'
       and merge_sha ~ '^[a-f0-9]{40}$' and canonical_main_sha ~ '^[a-f0-9]{40}$'),
 foreign key(organization_id,project_id,task_key)
   references private.pandora_ops_tasks(organization_id,project_id,task_key)
);
alter table private.pandora_ops_merged_release_receipts enable row level security;
revoke all on private.pandora_ops_merged_release_receipts from public,anon,authenticated,service_role;
create function private.pandora_ops_merged_release_immutable_v1()
returns trigger language plpgsql set search_path='' as $fn$
begin raise exception 'OPS_MERGED_RELEASE_RECEIPT_IMMUTABLE' using errcode='55000'; end;
$fn$;
create trigger pandora_ops_merged_release_immutable
before update or delete on private.pandora_ops_merged_release_receipts
for each row execute function private.pandora_ops_merged_release_immutable_v1();

create function public.pandora_ops_reconcile_merged_release_v1(
 p_organization_id uuid, p_project_id uuid, p_request_id uuid,
 p_task_key text, p_generation bigint, p_revision bigint,
 p_spec_digest text, p_expected_head_sha text,
 p_reconciler_worker_key text, p_reconciler_principal_key text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 t private.pandora_ops_tasks%rowtype;
 w private.pandora_ops_workers%rowtype;
 receipt private.pandora_ops_merged_release_receipts%rowtype;
 workspace private.pandora_ops_workspaces%rowtype;
 pr jsonb; response jsonb; timeline jsonb; merged_event jsonb;
 merge_commit jsonb; readbacks jsonb := '{}'::jsonb;
 repository text; pr_number integer; final_head text; merge_sha text; main_sha text;
 path text; pair text[]; pairs text[][]; page integer;
begin
 if session_user not in ('postgres','service_role')
    and coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'OPS_MERGED_RELEASE_SERVICE_ROLE_REQUIRED' using errcode='42501';
 end if;
 if p_request_id is null or p_generation is null or p_generation<1
    or p_revision is null or p_revision<0
    or not coalesce(p_task_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$',false)
    or not coalesce(p_spec_digest ~ '^[a-f0-9]{64}$',false)
    or not coalesce(p_expected_head_sha ~ '^[a-f0-9]{40}$',false) then
  raise exception 'OPS_MERGED_RELEASE_INPUT_INVALID' using errcode='22023';
 end if;
 perform 1 from private.pandora_ops_project_bindings
 where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
 if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;
 select * into workspace from private.pandora_ops_workspaces
 where organization_id=p_organization_id and project_id=p_project_id for update;
 if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
 if workspace.paused then raise exception 'OPS_WORKSPACE_PAUSED'; end if;
 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key for update;
 if not found then raise exception 'OPS_MERGED_RELEASE_TASK_FENCED'; end if;
 select * into w from private.pandora_ops_workers
 where organization_id=p_organization_id and project_id=p_project_id
   and worker_key=p_reconciler_worker_key and principal_key=p_reconciler_principal_key;
 if not found or not w.acknowledged or not w.connected or w.health<>'ready'
    or w.heartbeat_at is null or w.heartbeat_at<clock_timestamp()-interval '60 seconds'
    or not ('release'=any(w.lanes)) or not ('provider.readback'=any(w.capabilities))
    or w.worker_key is not distinct from t.builder_worker_key
    or w.principal_key is not distinct from t.builder_principal_key then
  raise exception 'OPS_MERGED_RELEASE_INDEPENDENT_RECONCILER_REQUIRED' using errcode='42501';
 end if;
 select * into receipt from private.pandora_ops_merged_release_receipts where id=p_request_id;
 if found then
  if receipt.organization_id is distinct from p_organization_id
     or receipt.project_id is distinct from p_project_id or receipt.task_key is distinct from p_task_key
     or receipt.prior_generation is distinct from p_generation or receipt.prior_revision is distinct from p_revision
     or receipt.task_spec_digest is distinct from p_spec_digest
     or receipt.prior_head_sha is distinct from p_expected_head_sha
     or receipt.reconciler_worker_key is distinct from p_reconciler_worker_key
     or receipt.reconciler_principal_key is distinct from p_reconciler_principal_key then
   raise exception 'OPS_MERGED_RELEASE_REPLAY_CONFLICT' using errcode='23505';
  end if;
  if t.generation is distinct from receipt.adopted_generation
     or t.head_sha is distinct from receipt.head_sha or t.spec_digest is distinct from receipt.task_spec_digest
     or t.status not in ('verifying','complete') or t.cancel_requested then
   raise exception 'OPS_MERGED_RELEASE_REPLAY_STATE_CONFLICT';
  end if;
  return jsonb_build_object('reconciled',true,'replayed',true,'state',t.status,
    'taskId',t.task_key,'generation',t.generation,'headSha',t.head_sha,
    'receiptId',receipt.id,'completionGranted',false);
 end if;
 if t.generation is distinct from p_generation or t.revision is distinct from p_revision
    or t.spec_digest is distinct from p_spec_digest or t.head_sha is distinct from p_expected_head_sha
    or t.status not in ('handed_off','verifying') or t.cancel_requested
    or t.spec->>'risk' not in ('source','production') then
  raise exception 'OPS_MERGED_RELEASE_TASK_FENCED';
 end if;
 if exists(select 1 from private.pandora_ops_leases
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=p_task_key and state<>'released') then
  raise exception 'OPS_MERGED_RELEASE_ACTIVE_LEASE';
 end if;
 if jsonb_typeof(t.handoff) is distinct from 'object'
    or t.handoff->>'taskId' is distinct from t.task_key
    or t.handoff->>'generation' is distinct from t.generation::text
    or t.handoff->>'headSha' is distinct from t.head_sha
    or t.handoff->>'workerId' is distinct from t.builder_worker_key
    or t.handoff->>'implementationComplete' is distinct from 'true'
    or not coalesce(t.handoff->>'pullRequest' ~ '^[1-9][0-9]{0,8}$',false) then
  raise exception 'OPS_MERGED_RELEASE_HANDOFF_REQUIRED';
 end if;
 repository:=t.spec#>>'{source,repository}';
 if repository is distinct from 'pandora-rvw-314296438-20260820/pandoras-box' then
  raise exception 'OPS_MERGED_RELEASE_REPOSITORY_DENIED';
 end if;
 pr_number:=(t.handoff->>'pullRequest')::integer;
 path:='/repos/'||repository;
 response:=private.pandora_integration_github_api_20260825('GET',path||'/pulls/'||pr_number,null);
 if response->>'status' is distinct from '200' then raise exception 'OPS_MERGED_RELEASE_PR_UNAVAILABLE'; end if;
 pr:=response->'body';
 if pr->>'number' is distinct from pr_number::text or pr->>'state' is distinct from 'closed'
    or pr->'merged' is distinct from 'true'::jsonb or pr->>'merged_at' is null
    or pr#>>'{base,ref}' is distinct from 'main'
    or pr#>>'{base,repo,full_name}' is distinct from repository
    or pr#>>'{head,repo,full_name}' is distinct from repository
    or not coalesce(pr#>>'{head,sha}' ~ '^[a-f0-9]{40}$',false) then
  raise exception 'OPS_MERGED_RELEASE_PR_IDENTITY_MISMATCH';
 end if;
 final_head:=pr#>>'{head,sha}';
 if final_head=t.head_sha then raise exception 'OPS_MERGED_RELEASE_HEAD_ALREADY_CURRENT'; end if;
 -- The broker can omit merge_commit_sha. The PR's merge event supplies independent binding.
 for page in 1..10 loop
  response:=private.pandora_integration_github_api_20260825(
    'GET',path||'/issues/'||pr_number||'/timeline?per_page=100&page='||page,null);
  if response->>'status' is distinct from '200' or jsonb_typeof(response->'body') is distinct from 'array' then
   raise exception 'OPS_MERGED_RELEASE_TIMELINE_UNAVAILABLE';
  end if;
  timeline:=response->'body';
  select e into merged_event from jsonb_array_elements(timeline) e
   where e->>'event'='merged' order by e->>'created_at' desc limit 1;
  exit when merged_event is not null or jsonb_array_length(timeline)<100;
 end loop;
 merge_sha:=merged_event->>'commit_id';
 if not coalesce(merge_sha ~ '^[a-f0-9]{40}$',false)
    or (pr->>'merge_commit_sha' is not null and pr->>'merge_commit_sha'<>merge_sha) then
  raise exception 'OPS_MERGED_RELEASE_MERGE_BINDING_REQUIRED';
 end if;
 response:=private.pandora_integration_github_api_20260825('GET',path||'/commits/'||merge_sha,null);
 merge_commit:=response->'body';
 if response->>'status' is distinct from '200' or merge_commit->>'sha' is distinct from merge_sha
    or jsonb_typeof(merge_commit->'parents') is distinct from 'array'
    or not exists(select 1 from jsonb_array_elements(merge_commit->'parents') p where p->>'sha'=final_head) then
  raise exception 'OPS_MERGED_RELEASE_MERGE_PARENT_MISMATCH';
 end if;
 response:=private.pandora_integration_github_api_20260825('GET',path||'/git/ref/heads/main',null);
 main_sha:=response#>>'{body,object,sha}';
 if response->>'status' is distinct from '200' or not coalesce(main_sha ~ '^[a-f0-9]{40}$',false) then
  raise exception 'OPS_MERGED_RELEASE_MAIN_UNAVAILABLE';
 end if;
 pairs:=array[array[t.head_sha,final_head],array[t.spec#>>'{source,baseSha}',final_head],
   array[merge_sha,main_sha]];
 foreach pair slice 1 in array pairs loop
  if not coalesce(pair[1] ~ '^[a-f0-9]{40}$',false) then raise exception 'OPS_MERGED_RELEASE_LINEAGE_INVALID'; end if;
  response:=private.pandora_integration_github_api_20260825(
    'GET',path||'/compare/'||pair[1]||'%2E%2E%2E'||pair[2],null);
  if response->>'status' is distinct from '200'
     or not coalesce(response#>>'{body,status}' in ('ahead','identical'),false)
     or response#>>'{body,behind_by}' is distinct from '0' then
   raise exception 'OPS_MERGED_RELEASE_LINEAGE_UNCONFIRMED';
  end if;
  readbacks:=readbacks||jsonb_build_object(pair[1]||':'||pair[2],
    jsonb_build_object('status',response#>>'{body,status}','behindBy',0));
 end loop;
 -- A final provider read fences a changed PR response across multi-call readback.
 response:=private.pandora_integration_github_api_20260825('GET',path||'/pulls/'||pr_number,null);
 if response->>'status' is distinct from '200' or response#>>'{body,head,sha}' is distinct from final_head
    or response#>'{body,merged}' is distinct from 'true'::jsonb
    or response#>>'{body,state}' is distinct from 'closed' then
  raise exception 'OPS_MERGED_RELEASE_READBACK_CHANGED';
 end if;
 insert into private.pandora_ops_merged_release_receipts(
   id,organization_id,project_id,task_key,prior_generation,adopted_generation,prior_revision,
   task_spec_digest,prior_head_sha,head_sha,merge_sha,canonical_main_sha,repository,pull_request,
   reconciler_worker_key,reconciler_principal_key,prior_task,provider_readback
 ) values(
   p_request_id,p_organization_id,p_project_id,p_task_key,t.generation,t.generation+1,t.revision,
   t.spec_digest,t.head_sha,final_head,merge_sha,main_sha,repository,pr_number,
   w.worker_key,w.principal_key,to_jsonb(t),
   jsonb_build_object('method','GET','repository',repository,'pullRequest',pr_number,
     'headSha',final_head,'mergeSha',merge_sha,'mainSha',main_sha,'lineage',readbacks)
 ) returning * into receipt;
 -- A new verification generation fences every prior-head PASS. No lease or worker is fabricated.
 update private.pandora_ops_tasks
 set status='verifying',generation=generation+1,revision=revision+1,head_sha=final_head,verification=null
 where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key;
 perform private.pandora_ops_event_v1(p_organization_id,p_project_id,
   'merged-release:'||p_request_id,p_task_key,'merged_release_reconciled',p_request_id::text);
 return jsonb_build_object('reconciled',true,'replayed',false,'state','verifying',
   'taskId',p_task_key,'generation',receipt.adopted_generation,'headSha',final_head,
   'receiptId',receipt.id,'completionGranted',false);
end;
$fn$;
revoke all on function private.pandora_ops_merged_release_immutable_v1()
 from public,anon,authenticated,service_role;
revoke all on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) to service_role;
comment on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) is
 'Authenticated adapter only: GET-only merged-release source adoption. Preserves history and moves to a new verification generation; does not approve, verify, complete, merge or deploy.';
