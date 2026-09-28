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
 if t.task_key='FB-012' or t.spec->>'risk'='production'
    or t.spec->>'verificationProfile'='production_release' then
  raise exception 'OPS_MERGED_RELEASE_PRODUCTION_TASK_UNSUPPORTED' using errcode='22023';
 end if;
 if t.task_key<>'FB-025'
    or p_spec_digest is distinct from 'a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc'
    or t.spec_digest is distinct from 'a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc'
    or t.spec->>'risk' is distinct from 'source'
    or t.spec->>'verificationProfile' is distinct from 'backend_service'
    or t.spec#>>'{source,repository}' is distinct from 'pandora-rvw-314296438-20260820/pandoras-box'
    or t.spec#>>'{source,baseSha}' is distinct from 'f4675344f99a3d2cc23a9c360c9512826e921c5c'
    or t.spec->'acceptance' is distinct from
       '["Schema distinguishes verified fact, user decision, provider evidence, inference, assumption, and superseded information."]'::jsonb then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_SPEC_UNSUPPORTED' using errcode='22023';
 end if;
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
-- Complete only FB-025 source verification from provider-owned, exact-head evidence.
create function public.pandora_ops_verify_merged_release_source_v1(
 p_organization_id uuid, p_project_id uuid, p_task_key text, p_generation bigint,
 p_spec_digest text, p_expected_head_sha text, p_reconciliation_receipt_id uuid,
 p_verifier_worker_key text, p_verifier_principal_key text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 t private.pandora_ops_tasks%rowtype;
 receipt private.pandora_ops_merged_release_receipts%rowtype;
 response jsonb; pr jsonb; checks jsonb; comment_full jsonb; comment_carry jsonb;
 timeline jsonb; merged_event jsonb; merge_commit jsonb;
 check_rows jsonb; provider_readback jsonb; evidence jsonb; recorded jsonb; verification_id uuid;
 item jsonb; item_path text; item_sha text;
 total_count integer; run_count integer; required_count integer; page integer;
begin
 if session_user not in ('postgres','service_role')
    and coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'OPS_MERGED_RELEASE_SERVICE_ROLE_REQUIRED' using errcode='42501';
 end if;
 if p_task_key<>'FB-025' then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_TASK_UNSUPPORTED' using errcode='22023';
 end if;
 if p_generation is null or p_generation<1
    or not coalesce(p_spec_digest ~ '^[a-f0-9]{64}$',false)
    or not coalesce(p_expected_head_sha ~ '^[a-f0-9]{40}$',false)
    or p_reconciliation_receipt_id is null then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_INPUT_INVALID' using errcode='22023';
 end if;
 if p_verifier_worker_key is distinct from 'pandora-native-release-v1'
    or p_verifier_principal_key is distinct from 'vercel:mcpmaster:operations-native-release-v1' then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_VERIFIER_DENIED' using errcode='42501';
 end if;
 perform 1 from private.pandora_ops_project_bindings
 where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
 if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_workspaces
 where organization_id=p_organization_id and project_id=p_project_id and not paused for update;
 if not found then raise exception 'OPS_WORKSPACE_PAUSED'; end if;
 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key for update;
 if not found or t.generation is distinct from p_generation
    or p_spec_digest is distinct from 'a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc'
    or t.spec_digest is distinct from p_spec_digest or t.head_sha is distinct from p_expected_head_sha
    or t.head_sha is distinct from '3e38b571ae963cc663e622fc1a75d5578b6fb7a2'
    or t.status not in ('verifying','complete') or t.cancel_requested
    or t.spec->>'risk' is distinct from 'source'
    or t.spec->>'verificationProfile' is distinct from 'backend_service'
    or t.spec#>>'{source,repository}' is distinct from 'pandora-rvw-314296438-20260820/pandoras-box'
    or t.spec#>>'{source,baseSha}' is distinct from 'f4675344f99a3d2cc23a9c360c9512826e921c5c'
    or t.spec->'acceptance' is distinct from
       '["Schema distinguishes verified fact, user decision, provider evidence, inference, assumption, and superseded information."]'::jsonb then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_TASK_FENCED';
 end if;
 select * into receipt from private.pandora_ops_merged_release_receipts
 where id=p_reconciliation_receipt_id for share;
 if not found
    or receipt.organization_id is distinct from p_organization_id
    or receipt.project_id is distinct from p_project_id
    or receipt.task_key is distinct from t.task_key
    or receipt.adopted_generation is distinct from t.generation
    or receipt.task_spec_digest is distinct from t.spec_digest
    or receipt.prior_head_sha is distinct from '5448f61715b139dff7bbedf9d3056ca80cadb585'
    or receipt.head_sha is distinct from t.head_sha
    or receipt.repository is distinct from 'pandora-rvw-314296438-20260820/pandoras-box'
    or receipt.pull_request is distinct from 786
    or receipt.reconciler_worker_key is distinct from p_verifier_worker_key
    or receipt.reconciler_principal_key is distinct from p_verifier_principal_key then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_RECEIPT_MISMATCH';
 end if;

 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/786',null);
 pr:=response->'body';
 if response->>'status' is distinct from '200'
    or pr->>'number' is distinct from '786' or pr->>'state' is distinct from 'closed'
    or pr->'merged' is distinct from 'true'::jsonb or pr->>'merged_at' is null
    or pr#>>'{base,ref}' is distinct from 'main'
    or pr#>>'{base,repo,full_name}' is distinct from receipt.repository
    or pr#>>'{head,repo,full_name}' is distinct from receipt.repository
    or pr#>>'{head,sha}' is distinct from t.head_sha then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_PR_MISMATCH';
 end if;
 for page in 1..10 loop
  response:=private.pandora_integration_github_api_20260825(
   'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/issues/786/timeline?per_page=100&page='||page,null);
  if response->>'status' is distinct from '200'
     or jsonb_typeof(response->'body') is distinct from 'array' then
   raise exception 'OPS_MERGED_RELEASE_SOURCE_TIMELINE_UNAVAILABLE';
  end if;
  timeline:=response->'body';
  select e into merged_event from jsonb_array_elements(timeline) e
   where e->>'event'='merged' order by e->>'created_at' desc limit 1;
  exit when merged_event is not null or jsonb_array_length(timeline)<100;
 end loop;
 if merged_event->>'commit_id' is distinct from receipt.merge_sha then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_MERGE_BINDING_MISMATCH';
 end if;
 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||receipt.merge_sha,null);
 merge_commit:=response->'body';
 if response->>'status' is distinct from '200'
    or merge_commit->>'sha' is distinct from receipt.merge_sha
    or jsonb_typeof(merge_commit->'parents') is distinct from 'array'
    or not exists(select 1 from jsonb_array_elements(merge_commit->'parents') p where p->>'sha'=t.head_sha) then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_MERGE_PARENT_MISMATCH';
 end if;

 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||t.head_sha||'/check-runs?per_page=100',null);
 checks:=response->'body';
 if response->>'status' is distinct from '200'
    or jsonb_typeof(checks->'check_runs') is distinct from 'array'
    or not coalesce(checks->>'total_count' ~ '^[0-9]+$',false) then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_CHECK_READBACK_FAILED';
 end if;
 total_count:=(checks->>'total_count')::integer;
 run_count:=jsonb_array_length(checks->'check_runs');
 if total_count<1 or total_count>100 or total_count<>run_count then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_CHECK_SET_INCOMPLETE';
 end if;
 if exists(select 1 from jsonb_array_elements(checks->'check_runs') c
   where not coalesce(c->>'id' ~ '^[1-9][0-9]*$',false)
      or not coalesce(length(c->>'name') between 1 and 200,false)
      or c->>'head_sha' is distinct from t.head_sha
      or not coalesce(c#>>'{app,id}' ~ '^[1-9][0-9]*$',false)
      or not coalesce(length(c#>>'{app,slug}') between 1 and 120,false)
      or c->>'status' is distinct from 'completed'
      or coalesce(c->>'conclusion','') not in ('success','neutral','skipped')) then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_CHECKS_NOT_GREEN';
 end if;
 if (select count(*) from jsonb_array_elements(checks->'check_runs')) <>
    (select count(distinct c->>'name') from jsonb_array_elements(checks->'check_runs') c) then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_CHECK_DUPLICATE';
 end if;
 select count(*) into required_count from jsonb_array_elements(checks->'check_runs') c
 where (c->>'id',c->>'name',c#>>'{app,id}',c->>'conclusion') in (
  ('108608310169','Pandora coordinator / integration','4785021','success'),
  ('108607598769','node24','15368','success'),
  ('108607620011','Windows worker contract','15368','success'),
  ('108607598884','canonical-release-source-contract','15368','success'),
  ('108607599143','Dependency review','15368','success'),
  ('108607661171','CodeQL','57789','success')
 ) and (c->>'id'<>'108607661171' or c#>>'{app,slug}'='github-advanced-security');
 if required_count<>6 then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_REQUIRED_CHECK_MISSING';
 end if;
 select jsonb_agg(jsonb_build_object('id',(c->>'id')::bigint,'name',c->>'name',
          'headSha',c->>'head_sha','appId',(c#>>'{app,id}')::bigint,'appSlug',c#>>'{app,slug}',
          'conclusion',c->>'conclusion') order by c->>'name',(c->>'id')::bigint)
 into check_rows from jsonb_array_elements(checks->'check_runs') c;

 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/issues/comments/5854323698',null);
 comment_full:=response->'body';
 if response->>'status' is distinct from '200' or comment_full->>'id' is distinct from '5854323698'
    or comment_full#>>'{user,login}' is distinct from 'coderabbitai[bot]'
    or comment_full#>>'{user,id}' is distinct from '136622811'
    or comment_full#>>'{user,type}' is distinct from 'Bot'
    or comment_full#>>'{performed_via_github_app,id}' is distinct from '347564'
    or comment_full#>>'{performed_via_github_app,slug}' is distinct from 'coderabbitai'
    or comment_full->>'created_at' is distinct from '2026-09-27T08:46:48Z'
    or comment_full->>'updated_at' is distinct from '2026-09-27T11:10:38Z'
    or octet_length(comment_full->>'body')<>10461
    or pg_catalog.encode(extensions.digest(pg_catalog.convert_to(comment_full->>'body','UTF8'),'sha256'),'hex')
       is distinct from 'defa2c5cfceab021d282fa1cd3904de894bf0c2abf1c3223d55a9d5612feda08'
    or position('57ff9a46-47b0-4ba2-bad8-cb80de09efd0' in comment_full->>'body')=0
    or position('5448f61715b139dff7bbedf9d3056ca80cadb585' in comment_full->>'body')=0 then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_FULL_REVIEW_MISMATCH';
 end if;

 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/issues/comments/5855325039',null);
 comment_carry:=response->'body';
 if response->>'status' is distinct from '200' or comment_carry->>'id' is distinct from '5855325039'
    or comment_carry#>>'{user,login}' is distinct from 'coderabbitai[bot]'
    or comment_carry#>>'{user,id}' is distinct from '136622811'
    or comment_carry#>>'{user,type}' is distinct from 'Bot'
    or comment_carry#>>'{performed_via_github_app,id}' is distinct from '347564'
    or comment_carry#>>'{performed_via_github_app,slug}' is distinct from 'coderabbitai'
    or comment_carry->>'created_at' is distinct from '2026-09-27T11:12:57Z'
    or comment_carry->>'updated_at' is distinct from '2026-09-27T11:12:57Z'
    or octet_length(comment_carry->>'body')<>5465
    or pg_catalog.encode(extensions.digest(pg_catalog.convert_to(comment_carry->>'body','UTF8'),'sha256'),'hex')
       is distinct from '4f5b0f33bfce1bdffafce66db3bf3af62c89ea9a2310f727cf87ad6f4e6061de'
    or position('5448f61715b139dff7bbedf9d3056ca80cadb585' in comment_carry->>'body')=0
    or position('3e38b571ae963cc663e622fc1a75d5578b6fb7a2' in comment_carry->>'body')=0
    or position('a4bad29c027b4d78d821f94eb1aeddbbc5d46991' in comment_carry->>'body')=0
    or position('13ea5c37f04d7c07fdf6439a0e1bbd97d27b6f36' in comment_carry->>'body')=0
    or position('0f2f9eab39fab6a89f48ab52bb1f1d4e1726a04d' in comment_carry->>'body')=0 then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_CARRIED_REVIEW_MISMATCH';
 end if;

 foreach item in array array[
  jsonb_build_object('path','docs/growth/FB025_GROWTH_LEARNING_SCHEMA.md','sha','a4bad29c027b4d78d821f94eb1aeddbbc5d46991'),
  jsonb_build_object('path','src/pandora-growth-learning-schema.js','sha','13ea5c37f04d7c07fdf6439a0e1bbd97d27b6f36'),
  jsonb_build_object('path','test/pandora-growth-learning-schema.test.js','sha','0f2f9eab39fab6a89f48ab52bb1f1d4e1726a04d')
 ] loop
  item_path:=item->>'path'; item_sha:=item->>'sha';
  response:=private.pandora_integration_github_api_20260825(
   'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/'||item_path||'?ref='||t.head_sha,null);
  if response->>'status' is distinct from '200'
     or response#>>'{body,path}' is distinct from item_path
     or response#>>'{body,type}' is distinct from 'file'
     or response#>>'{body,sha}' is distinct from item_sha then
   raise exception 'OPS_MERGED_RELEASE_SOURCE_BLOB_MISMATCH';
  end if;
 end loop;

 response:=private.pandora_integration_github_api_20260825(
  'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/786',null);
 if response->>'status' is distinct from '200'
    or response#>>'{body,head,sha}' is distinct from t.head_sha
    or response#>'{body,merged}' is distinct from 'true'::jsonb
    or response#>>'{body,state}' is distinct from 'closed' then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_READBACK_CHANGED';
 end if;

 provider_readback:=jsonb_build_object(
  'repository',receipt.repository,'pullRequest',786,'headSha',t.head_sha,'mergeSha',receipt.merge_sha,
  'checks',check_rows,
  'fullReview',jsonb_build_object('commentId',5854323698,'bodySha256','defa2c5cfceab021d282fa1cd3904de894bf0c2abf1c3223d55a9d5612feda08','updatedAt','2026-09-27T11:10:38Z'),
  'carriedReview',jsonb_build_object('commentId',5855325039,'bodySha256','4f5b0f33bfce1bdffafce66db3bf3af62c89ea9a2310f727cf87ad6f4e6061de','updatedAt','2026-09-27T11:12:57Z'),
  'blobs',jsonb_build_object(
   'docs/growth/FB025_GROWTH_LEARNING_SCHEMA.md','a4bad29c027b4d78d821f94eb1aeddbbc5d46991',
   'src/pandora-growth-learning-schema.js','13ea5c37f04d7c07fdf6439a0e1bbd97d27b6f36',
   'test/pandora-growth-learning-schema.test.js','0f2f9eab39fab6a89f48ab52bb1f1d4e1726a04d'
  )
 );
 evidence:=jsonb_build_object(
  'taskId',t.task_key,'generation',t.generation::text,'headSha',t.head_sha,
  'taskSpecDigest',t.spec_digest,'criteria',t.spec->'acceptance',
  'ref','ops-merged-release:'||receipt.id||':'||t.head_sha,
  'providerReadback',provider_readback
 );
 recorded:=public.pandora_ops_record_verification_v1(
  p_organization_id,p_project_id,t.task_key,t.generation,
  p_verifier_worker_key,p_verifier_principal_key,'PASS',evidence);
 verification_id:=(recorded->>'verificationRunId')::uuid;
 return public.pandora_ops_verify_v1(
   p_organization_id,p_project_id,t.task_key,t.generation,
   p_verifier_worker_key,p_verifier_principal_key,verification_id,
   evidence||jsonb_build_object('verificationRunId',verification_id::text)
  )||jsonb_build_object('providerReadbackVerified',true,'reconciliationReceiptId',receipt.id);
end;
$fn$;

-- One fixed native-release step makes the historical FB-025 repair retryable without caller evidence.
create function public.pandora_ops_merged_release_source_step_v1(
 p_organization_id uuid, p_project_id uuid, p_worker_key text, p_principal_key text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 t private.pandora_ops_tasks%rowtype;
 reconciled jsonb; verified jsonb;
 receipt_id uuid; receipt_count bigint; did_reconcile boolean:=false;
 failure_message text;
begin
 if session_user not in ('postgres','service_role')
    and coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'OPS_MERGED_RELEASE_SERVICE_ROLE_REQUIRED' using errcode='42501';
 end if;
 if p_worker_key is distinct from 'pandora-native-release-v1'
    or p_principal_key is distinct from 'vercel:mcpmaster:operations-native-release-v1' then
  raise exception 'OPS_MERGED_RELEASE_SOURCE_VERIFIER_DENIED' using errcode='42501';
 end if;
 perform 1 from private.pandora_ops_project_bindings
 where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
 if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;
 perform 1 from private.pandora_ops_workspaces
 where organization_id=p_organization_id and project_id=p_project_id and not paused for update;
 if not found then raise exception 'OPS_WORKSPACE_PAUSED'; end if;
 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key='FB-025' for update;
 if not found then
  return jsonb_build_object('state','idle','taskId','FB-025','reason','task_missing');
 end if;
 if t.cancel_requested
    or t.spec_digest is distinct from 'a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc'
    or t.spec->>'risk' is distinct from 'source'
    or t.spec->>'verificationProfile' is distinct from 'backend_service'
    or t.spec#>>'{source,repository}' is distinct from 'pandora-rvw-314296438-20260820/pandoras-box'
    or t.spec#>>'{source,baseSha}' is distinct from 'f4675344f99a3d2cc23a9c360c9512826e921c5c'
    or t.spec->'acceptance' is distinct from
       '["Schema distinguishes verified fact, user decision, provider evidence, inference, assumption, and superseded information."]'::jsonb then
  return jsonb_build_object('state','held','taskId','FB-025','reason','source_spec_drift',
    'status',t.status,'generation',t.generation,'headSha',t.head_sha);
 end if;

 begin
  if t.head_sha='5448f61715b139dff7bbedf9d3056ca80cadb585'
     and t.generation=4 and t.revision=12 and t.status in ('handed_off','verifying') then
  reconciled:=public.pandora_ops_reconcile_merged_release_v1(
   p_organization_id,p_project_id,gen_random_uuid(),t.task_key,t.generation,t.revision,
   t.spec_digest,t.head_sha,p_worker_key,p_principal_key);
  receipt_id:=(reconciled->>'receiptId')::uuid;
  did_reconcile:=true;
  select * into t from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key='FB-025' for update;
 elsif t.head_sha='3e38b571ae963cc663e622fc1a75d5578b6fb7a2'
    and t.generation=5 and t.status in ('verifying','complete') then
  select count(*),min(id::text)::uuid into receipt_count,receipt_id
  from private.pandora_ops_merged_release_receipts
  where organization_id=p_organization_id and project_id=p_project_id and task_key='FB-025'
    and adopted_generation=t.generation and task_spec_digest=t.spec_digest and head_sha=t.head_sha;
  if receipt_count<>1 then
   return jsonb_build_object('state','held','taskId','FB-025','reason','reconciliation_receipt_missing_or_ambiguous',
     'status',t.status,'generation',t.generation,'headSha',t.head_sha);
  end if;
 else
  return jsonb_build_object('state','held','taskId','FB-025','reason','source_state_not_eligible',
    'status',t.status,'generation',t.generation,'headSha',t.head_sha);
 end if;

  verified:=public.pandora_ops_verify_merged_release_source_v1(
   p_organization_id,p_project_id,t.task_key,t.generation,t.spec_digest,t.head_sha,
   receipt_id,p_worker_key,p_principal_key);
 exception when others then
  get stacked diagnostics failure_message=message_text;
  if failure_message=any(array[
   'OPS_MERGED_RELEASE_TASK_FENCED','OPS_MERGED_RELEASE_ACTIVE_LEASE',
   'OPS_MERGED_RELEASE_HANDOFF_REQUIRED','OPS_MERGED_RELEASE_PR_IDENTITY_MISMATCH',
   'OPS_MERGED_RELEASE_HEAD_ALREADY_CURRENT','OPS_MERGED_RELEASE_MERGE_BINDING_REQUIRED',
   'OPS_MERGED_RELEASE_MERGE_PARENT_MISMATCH','OPS_MERGED_RELEASE_LINEAGE_UNCONFIRMED',
   'OPS_MERGED_RELEASE_READBACK_CHANGED','OPS_MERGED_RELEASE_SOURCE_TASK_FENCED',
   'OPS_MERGED_RELEASE_SOURCE_RECEIPT_MISMATCH','OPS_MERGED_RELEASE_SOURCE_PR_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_MERGE_BINDING_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_MERGE_PARENT_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_CHECK_SET_INCOMPLETE',
   'OPS_MERGED_RELEASE_SOURCE_CHECKS_NOT_GREEN',
   'OPS_MERGED_RELEASE_SOURCE_CHECK_DUPLICATE',
   'OPS_MERGED_RELEASE_SOURCE_REQUIRED_CHECK_MISSING',
   'OPS_MERGED_RELEASE_SOURCE_FULL_REVIEW_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_CARRIED_REVIEW_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_BLOB_MISMATCH',
   'OPS_MERGED_RELEASE_SOURCE_READBACK_CHANGED',
   'OPS_VERIFICATION_REPLAY_CONFLICT'
  ]) then
   select * into t from private.pandora_ops_tasks
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key='FB-025';
   return jsonb_build_object(
    'state','held','taskId','FB-025','reason','provider_proof_unconfirmed',
    'status',t.status,'generation',t.generation,'headSha',t.head_sha);
  end if;
  raise;
 end;
 select * into t from private.pandora_ops_tasks
 where organization_id=p_organization_id and project_id=p_project_id and task_key='FB-025';
 return jsonb_build_object(
  'state','complete','taskId',t.task_key,'generation',t.generation,'headSha',t.head_sha,
  'reconciliationReceiptId',receipt_id,'reconciled',did_reconcile,'verification',verified);
end;
$fn$;

revoke all on function public.pandora_ops_merged_release_source_step_v1(uuid,uuid,text,text)
 from public,anon,authenticated;
grant execute on function public.pandora_ops_merged_release_source_step_v1(uuid,uuid,text,text)
 to service_role;
comment on function public.pandora_ops_merged_release_source_step_v1(uuid,uuid,text,text) is
 'Fixed native-release retry step for the pinned historical FB-025 source repair. It reconciles and verifies atomically or returns an explicit idle/held state without caller-selected task, receipt, verdict or evidence.';

revoke all on function public.pandora_ops_verify_merged_release_source_v1(
 uuid,uuid,text,bigint,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_verify_merged_release_source_v1(
 uuid,uuid,text,bigint,text,text,uuid,text,text) to service_role;
comment on function public.pandora_ops_verify_merged_release_source_v1(
 uuid,uuid,text,bigint,text,text,uuid,text,text) is
 'Task-specific FB-025 source acceptance from fixed GitHub PR, exact-head checks, immutable CodeRabbit review digests and reviewed blob identities. FB-012 production release remains unsupported.';

revoke all on function private.pandora_ops_merged_release_immutable_v1()
 from public,anon,authenticated,service_role;
revoke all on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) to service_role;
comment on function public.pandora_ops_reconcile_merged_release_v1(
 uuid,uuid,uuid,text,bigint,bigint,text,text,text,text) is
 'Authenticated adapter only: GET-only merged-release source adoption. Preserves history and moves to a new verification generation; does not approve, verify, complete, merge or deploy.';
