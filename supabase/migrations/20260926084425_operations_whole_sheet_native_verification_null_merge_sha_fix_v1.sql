-- Source-sync of live migration 20260926084425.
-- Independent whole-sheet verification tolerates GitHub PR merge_commit_sha=null only when exact signed commit-parent proof succeeds.

CREATE OR REPLACE FUNCTION private.pandora_ops_verify_whole_sheet_acceptance_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_org constant uuid := '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;
  v_project constant uuid := 'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid;
  v_task constant text := 'OPS-WHOLE-SHEET-ACCEPTANCE-V3';
  v_release constant text := 'pandora-supabase-cron-release-v1';
  v_release_principal constant text := 'supabase:pg-cron:operations-release-v1';
  t private.pandora_ops_tasks%rowtype;
  rb jsonb;
  pr jsonb;
  commit_readback jsonb;
  checks jsonb;
  vercel jsonb;
  v_pr integer;
  v_pr_head text;
  v_deployment_id text;
  v_parent_matches integer;
  v_pending integer;
  v_failed integer;
  v_event_count integer;
  v_record jsonb;
  v_verification_id uuid;
  v_evidence jsonb;
  v_receipt jsonb;
  v_result jsonb;
begin
  select * into t
  from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=v_task
  for update;

  if not found then raise exception 'OPS_WHOLE_SHEET_TASK_MISSING'; end if;
  if t.status='complete' then
    return jsonb_build_object('complete',true,'replayed',true,'verification',t.verification);
  end if;
  if t.status not in ('handed_off','verifying') or t.head_sha is null then
    raise exception 'OPS_WHOLE_SHEET_TASK_NOT_READY';
  end if;

  rb := public.pandora_ops_final_acceptance_readback_v1(v_org,v_project);

  if coalesce(rb#>>'{tasks,OPS-SESSION-SHEETS-BRIDGE-V2,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-WAKE-RECOVERY-V3,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-INTELLIGENCE-ROUTER-SERVICE-V1,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-THEATRE-LIVE-EVENTS-V1,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-SERIALIZATION-CANARY-A-V1,status}','')<>'complete'
     or coalesce(rb#>>'{tasks,OPS-SERIALIZATION-CANARY-B-V1,status}','')<>'complete' then
    raise exception 'OPS_WHOLE_SHEET_DEPENDENCY_READBACK_FAILED';
  end if;

  if rb#>>'{tasks,OPS-SESSION-SHEETS-BRIDGE-V2,verification,providerReadback,validationPreserved}' <> 'true'
     or rb#>>'{tasks,OPS-SESSION-SHEETS-BRIDGE-V2,verification,providerReadback,ownerColumnsPreserved}' <> 'A:N'
     or rb#>>'{tasks,OPS-SESSION-SHEETS-BRIDGE-V2,verification,providerReadback,machineColumnsChanged}' <> 'O:U'
     or rb#>>'{tasks,OPS-WAKE-RECOVERY-V3,verification,providerReadback,recoveredProviderReadbackVerified}' <> 'true'
     or rb#>>'{tasks,OPS-INTELLIGENCE-ROUTER-SERVICE-V1,verification,providerReadback,routerEdgeFunction}' <> 'ACTIVE:v1'
     or rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,deliveryVerified}' <> 'true'
     or rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,canonicalMemoryWritten}' <> 'false'
     or rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,reviewStatus}' <> 'pending_review'
     or rb#>>'{tasks,OPS-THEATRE-LIVE-EVENTS-V1,verification,providerReadback,syntheticProgress}' <> 'false'
     or rb#>>'{tasks,OPS-THEATRE-LIVE-EVENTS-V1,verification,providerReadback,eventAuthority}' <> 'immutable_operations_events'
     or rb#>>'{tasks,OPS-SERIALIZATION-CANARY-B-V1,verification,providerReadback,initialClaim}' <> 'resource_conflict' then
    raise exception 'OPS_WHOLE_SHEET_PROVIDER_READBACK_FAILED';
  end if;

  if coalesce(t.builder_worker_key,'') !~ '^chatgpt-pro-session'
     or coalesce(t.builder_principal_key,'') !~ '^chatgpt:interactive:'
     or t.builder_worker_key=v_release then
    raise exception 'OPS_WHOLE_SHEET_BUILDER_IDENTITY_INVALID';
  end if;

  v_pr := nullif(t.handoff->>'pullRequest','')::integer;
  if v_pr is null or v_pr < 1 then raise exception 'OPS_WHOLE_SHEET_PR_REQUIRED'; end if;

  pr := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/'||v_pr::text,
    null
  );
  if (pr->>'status')::integer<>200
     or pr#>>'{body,merged_at}' is null
     or pr#>>'{body,number}' is distinct from v_pr::text then
    raise exception 'OPS_WHOLE_SHEET_MERGE_READBACK_FAILED';
  end if;
  v_pr_head := pr#>>'{body,head,sha}';
  if coalesce(v_pr_head,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'OPS_WHOLE_SHEET_PR_HEAD_INVALID';
  end if;

  commit_readback := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||t.head_sha,
    null
  );
  if (commit_readback->>'status')::integer<>200
     or commit_readback#>>'{body,sha}' is distinct from t.head_sha
     or commit_readback#>>'{body,commit,verification,verified}' <> 'true' then
    raise exception 'OPS_WHOLE_SHEET_MERGE_COMMIT_READBACK_FAILED';
  end if;
  select count(*) into v_parent_matches
  from jsonb_array_elements(coalesce(commit_readback#>'{body,parents}','[]'::jsonb)) p
  where p->>'sha'=v_pr_head;
  if v_parent_matches<>1 then
    raise exception 'OPS_WHOLE_SHEET_MERGE_PARENT_MISMATCH';
  end if;

  checks := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||v_pr_head||'/check-runs?per_page=100',
    null
  );
  if (checks->>'status')::integer<>200 then raise exception 'OPS_WHOLE_SHEET_CHECK_READBACK_FAILED'; end if;
  select
    count(*) filter(where c->>'status'<>'completed'),
    count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
  into v_pending,v_failed
  from jsonb_array_elements(coalesce(checks#>'{body,check_runs}','[]'::jsonb)) c;
  if v_pending<>0 or v_failed<>0
     or not exists(
       select 1
       from jsonb_array_elements(coalesce(checks#>'{body,check_runs}','[]'::jsonb)) c
       where c->>'name'='Pandora coordinator / integration' and c->>'conclusion'='success'
     ) then
    raise exception 'OPS_WHOLE_SHEET_CHECK_READBACK_FAILED';
  end if;

  select (regexp_match(x, '^vercel:deployment:(dpl_[A-Za-z0-9]+):source:[0-9a-f]{40}$'))[1]
  into v_deployment_id
  from jsonb_array_elements_text(coalesce(t.handoff->'evidenceRefs','[]'::jsonb)) x
  where x ~ '^vercel:deployment:dpl_[A-Za-z0-9]+:source:[0-9a-f]{40}$'
  limit 1;
  if v_deployment_id is null then raise exception 'OPS_WHOLE_SHEET_VERCEL_RECEIPT_REQUIRED'; end if;

  vercel := private.pandora_exact_vercel_api_20260825(
    'GET','/v13/deployments/'||v_deployment_id,null
  );
  if (vercel->>'status')::integer<>200
     or vercel#>>'{body,readyState}'<>'READY'
     or coalesce(vercel#>>'{body,meta,githubCommitSha}',vercel#>>'{body,gitSource,sha}','') is distinct from t.head_sha then
    raise exception 'OPS_WHOLE_SHEET_VERCEL_SOURCE_MISMATCH';
  end if;

  select count(*) into v_event_count
  from private.pandora_ops_events e
  where e.organization_id=v_org and e.project_id=v_project and e.task_key=v_task
    and e.event_type in ('task_claimed','worker_started','implementation_handed_off');
  if v_event_count<3
     or not exists(select 1 from private.pandora_ops_events where organization_id=v_org and project_id=v_project and task_key=v_task and event_type='task_claimed')
     or not exists(select 1 from private.pandora_ops_events where organization_id=v_org and project_id=v_project and task_key=v_task and event_type='worker_started')
     or not exists(select 1 from private.pandora_ops_events where organization_id=v_org and project_id=v_project and task_key=v_task and event_type='implementation_handed_off') then
    raise exception 'OPS_WHOLE_SHEET_EVENT_READBACK_FAILED';
  end if;

  perform public.pandora_ops_heartbeat_v1(
    v_org,v_project,v_release,v_release_principal,true,'ready'
  );

  v_evidence := jsonb_build_object(
    'taskId',t.task_key,
    'generation',t.generation::text,
    'headSha',t.head_sha,
    'taskSpecDigest',t.spec_digest,
    'criteria',t.spec->'acceptance',
    'ref','ops-native-release:whole-sheet:'||t.head_sha,
    'providerReadback',jsonb_build_object(
      'pullRequest',v_pr,
      'pullRequestHead',v_pr_head,
      'mergeCommit',t.head_sha,
      'mergeCommitContainsPullRequestHead',true,
      'coordinator','success',
      'vercelDeploymentId',v_deployment_id,
      'vercelReadyState',vercel#>>'{body,readyState}',
      'vercelSourceCommit',coalesce(vercel#>>'{body,meta,githubCommitSha}',vercel#>>'{body,gitSource,sha}'),
      'sessionWorker',t.builder_worker_key,
      'sessionPrincipal',t.builder_principal_key,
      'sheets',jsonb_build_object(
        'spreadsheetId',rb#>>'{tasks,OPS-SESSION-SHEETS-BRIDGE-V2,verification,providerReadback,spreadsheetId}',
        'validationPreserved',true,
        'ownerColumnsPreserved','A:N',
        'machineColumnsChanged','O:U'
      ),
      'memory',jsonb_build_object(
        'state',rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,outcomeState}',
        'reviewStatus',rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,reviewStatus}',
        'deliveryVerified',true,
        'canonicalMemoryWritten',false,
        'receiptRef',rb#>>'{tasks,OPS-MEMORY-CALLER-ADOPTION-V1,verification,providerReadback,receiptRef}'
      ),
      'serialization',jsonb_build_object(
        'initialClaim',rb#>>'{tasks,OPS-SERIALIZATION-CANARY-B-V1,verification,providerReadback,initialClaim}',
        'resource',rb#>>'{tasks,OPS-SERIALIZATION-CANARY-B-V1,verification,providerReadback,resource}'
      ),
      'theatre',jsonb_build_object(
        'eventAuthority',rb#>>'{tasks,OPS-THEATRE-LIVE-EVENTS-V1,verification,providerReadback,eventAuthority}',
        'syntheticProgress',false
      ),
      'router',jsonb_build_object(
        'edgeFunction',rb#>>'{tasks,OPS-INTELLIGENCE-ROUTER-SERVICE-V1,verification,providerReadback,routerEdgeFunction}',
        'providerProbe',rb#>>'{tasks,OPS-INTELLIGENCE-ROUTER-SERVICE-V1,verification,providerReadback,providerProbe}'
      ),
      'wake',jsonb_build_object('recoveredProviderReadbackVerified',true),
      'immutableTaskEventCount',v_event_count
    )
  );

  v_record := public.pandora_ops_record_verification_v1(
    v_org,v_project,t.task_key,t.generation,v_release,v_release_principal,'PASS',v_evidence
  );
  v_verification_id := (v_record->>'verificationRunId')::uuid;
  v_receipt := v_evidence || jsonb_build_object('verificationRunId',v_verification_id::text);
  v_result := public.pandora_ops_verify_v1(
    v_org,v_project,t.task_key,t.generation,v_release,v_release_principal,v_verification_id,v_receipt
  );

  return v_result || jsonb_build_object(
    'providerReadbackVerified',true,
    'mergeCommitShaNullHandledBySignedCommitParentProof',true,
    'verifierWorker',v_release
  );
end;
$function$
;

revoke all on function private.pandora_ops_verify_whole_sheet_acceptance_v1() from public, anon, authenticated, service_role;
