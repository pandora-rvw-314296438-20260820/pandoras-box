-- ChatGPT connected-session direct Operations ingress v1.
-- This is a management-plane-only adapter for work already reasoned in ChatGPT.
-- It skips a second model call and never asserts a ChatGPT model identity.
-- Execution remains bounded to read-risk RDP profiles, exact canonical main,
-- Operations leases, independent verification and review-gated Memory learning.

create table if not exists private.pandora_ops_chatgpt_direct_links (
  organization_id uuid not null,
  project_id uuid not null,
  ingress_id uuid not null,
  parent_task_key text not null,
  parent_generation bigint not null check(parent_generation>0),
  parent_lease_id uuid not null,
  child_task_key text not null,
  source_sha text not null check(source_sha ~ '^[a-f0-9]{40}$'),
  profile text not null check(profile in (
    'toolchain_verify','github_runner_verify','android_verify',
    'flutter_verify','repo_test','repo_build'
  )),
  reason text not null check(length(reason) between 1 and 500),
  state text not null check(state in (
    'child_queued','child_handed_off','child_complete',
    'parent_handed_off','complete','reconciliation_required'
  )),
  learning_outbox_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,project_id,ingress_id),
  unique(organization_id,project_id,parent_task_key,parent_generation),
  unique(organization_id,project_id,child_task_key),
  foreign key(organization_id,project_id,parent_task_key)
    references private.pandora_ops_tasks(organization_id,project_id,task_key),
  foreign key(organization_id,project_id,child_task_key)
    references private.pandora_ops_tasks(organization_id,project_id,task_key),
  foreign key(parent_lease_id) references private.pandora_ops_leases(id)
);
alter table private.pandora_ops_chatgpt_direct_links enable row level security;
revoke all on private.pandora_ops_chatgpt_direct_links from public,anon,authenticated,service_role;

create or replace function private.pandora_ops_chatgpt_direct_profile_v1(p_profile text)
returns jsonb
language plpgsql immutable
set search_path=''
as $body$
begin
  if p_profile='toolchain_verify' then
    return jsonb_build_object(
      'lane','reliability','capability','rdp.toolchain.verify',
      'acceptance','["Windows toolchain executes successfully from the governed RDP worker.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  elsif p_profile='github_runner_verify' then
    return jsonb_build_object(
      'lane','reliability','capability','rdp.github_runner.verify',
      'acceptance','["The canonical GitHub runner binding is verified on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  elsif p_profile='android_verify' then
    return jsonb_build_object(
      'lane','mobile','capability','rdp.android.verify',
      'acceptance','["Android platform tools execute successfully on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  elsif p_profile='flutter_verify' then
    return jsonb_build_object(
      'lane','mobile','capability','rdp.flutter.verify',
      'acceptance','["Flutter tooling executes successfully on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  elsif p_profile='repo_test' then
    return jsonb_build_object(
      'lane','backend','capability','rdp.repo.test',
      'acceptance','["The exact source SHA is canonical main before execution.","Dependencies install without source mutation and the repository test suite exits successfully.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  elsif p_profile='repo_build' then
    return jsonb_build_object(
      'lane','backend','capability','rdp.repo.build',
      'acceptance','["The exact source SHA is canonical main before execution.","Dependencies install without source mutation and the canonical build exits successfully.","Hashed machine proof is returned through the Operations handoff."]'::jsonb
    );
  end if;
  raise exception 'OPS_CHATGPT_DIRECT_PROFILE_INVALID' using errcode='22023';
end;
$body$;

create or replace function private.pandora_ops_chatgpt_direct_submit_v1(
  p_ingress_id uuid,
  p_title text,
  p_profile text,
  p_reason text,
  p_acceptance jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $body$
declare
  v_org constant uuid:='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;
  v_project constant uuid:='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid;
  v_worker constant text:='chatgpt-direct-ingress-v1';
  v_principal constant text:='chatgpt:connected-session:operations-ingress-v1';
  v_release jsonb;
  v_main jsonb;
  v_source_sha text;
  v_profile jsonb;
  v_parent_id text;
  v_child_id text;
  v_parent_spec jsonb;
  v_child_spec jsonb;
  v_workspace private.pandora_ops_workspaces%rowtype;
  v_parent private.pandora_ops_tasks%rowtype;
  v_claim jsonb;
  v_dispatch jsonb;
  v_dispatch_id uuid;
  v_generation bigint;
  v_lease_id uuid;
  v_existing private.pandora_ops_chatgpt_direct_links%rowtype;
  v_item jsonb;
begin
  if p_ingress_id is null then raise exception 'OPS_CHATGPT_DIRECT_INGRESS_ID_REQUIRED' using errcode='22023'; end if;
  if p_title is null or length(p_title) not between 1 and 200 or p_title<>btrim(p_title)
     or p_title ~ '[\x01-\x1f]' then raise exception 'OPS_CHATGPT_DIRECT_TITLE_INVALID' using errcode='22023'; end if;
  if p_reason is null or length(p_reason) not between 1 and 500 or p_reason<>btrim(p_reason)
     or p_reason ~ '[\x01-\x1f]'
     or p_reason ~* '(powershell|cmd\.exe|bash|curl|wget|https?://|[A-Za-z]:\\|/bin/|secret|token|password|credential)'
  then raise exception 'OPS_CHATGPT_DIRECT_REASON_INVALID' using errcode='22023'; end if;
  if jsonb_typeof(p_acceptance)<>'array' or jsonb_array_length(p_acceptance) not between 1 and 16
     or exists(
       select 1 from jsonb_array_elements(p_acceptance) e
       where jsonb_typeof(e)<>'string'
         or length(e#>>'{}') not between 1 and 500
         or (e#>>'{}')<>btrim(e#>>'{}')
         or (e#>>'{}') ~ '[\x01-\x1f]'
     )
  then raise exception 'OPS_CHATGPT_DIRECT_ACCEPTANCE_INVALID' using errcode='22023'; end if;

  select * into v_existing
  from private.pandora_ops_chatgpt_direct_links
  where organization_id=v_org and project_id=v_project and ingress_id=p_ingress_id;
  if found then
    return jsonb_build_object(
      'accepted',true,'replayed',true,'ingressId',p_ingress_id,
      'parentTaskId',v_existing.parent_task_key,'childTaskId',v_existing.child_task_key,
      'profile',v_existing.profile,'state',v_existing.state,'sourceSha',v_existing.source_sha,
      'specialistReasoningInvoked',false
    );
  end if;

  select * into v_workspace from private.pandora_ops_workspaces
  where organization_id=v_org and project_id=v_project for update;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
  if v_workspace.paused then raise exception 'OPS_WORKSPACE_PAUSED'; end if;

  v_profile:=private.pandora_ops_chatgpt_direct_profile_v1(p_profile);

  -- Source authority is server-read canonical main, never caller-supplied.
  v_main:=private.pandora_integration_github_api_20260825(
    'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/git/ref/heads/main',null
  );
  if (v_main->>'status')::integer<>200 then raise exception 'OPS_CHATGPT_DIRECT_MAIN_READBACK_FAILED'; end if;
  v_source_sha:=v_main#>>'{body,object,sha}';
  if v_source_sha !~ '^[a-f0-9]{40}$' then raise exception 'OPS_CHATGPT_DIRECT_MAIN_READBACK_FAILED'; end if;

  -- A connected management session may submit already-completed reasoning.
  -- The database records origin but never pretends to know the ChatGPT model.
  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  ) values(
    v_org,v_project,v_worker,v_principal,'chatgpt',
    array['backend','reliability','web','mobile']::text[],
    array['chatgpt.reasoned','rdp.delegate']::text[],
    1,true,true,'ready',clock_timestamp(),
    'supabase-management:chatgpt-connected-session:operations-ingress-v1'
  )
  on conflict(organization_id,project_id,worker_key) do update
  set lanes=excluded.lanes,capabilities=excluded.capabilities,capacity=1,
      acknowledged=true,connected=true,health='ready',heartbeat_at=clock_timestamp(),
      registration_receipt=excluded.registration_receipt
  where private.pandora_ops_workers.engine='chatgpt'
    and private.pandora_ops_workers.principal_key=v_principal;
  if not found then raise exception 'OPS_CHATGPT_DIRECT_WORKER_IDENTITY_CONFLICT' using errcode='42501'; end if;

  v_parent_id:='OPS-CHATGPT-DIRECT-'||upper(left(encode(extensions.digest(
    convert_to(p_ingress_id::text,'UTF8'),'sha256'
  ),'hex'),24));
  v_child_id:='OPS-RDP-DIRECT-'||upper(left(encode(extensions.digest(
    convert_to(p_ingress_id::text||':'||p_profile,'UTF8'),'sha256'
  ),'hex'),24));

  v_parent_spec:=jsonb_build_object(
    'id',v_parent_id,
    'title',p_title,
    'lane',v_profile->>'lane',
    'priority',1,
    'dependsOn','[]'::jsonb,
    'resources',jsonb_build_array(jsonb_build_object(
      'key','runtime/operations/chatgpt-direct/'||lower(replace(p_ingress_id::text,'-','')),'mode','read'
    )),
    'requiredCapabilities',jsonb_build_array('chatgpt.reasoned','rdp.delegate'),
    'maxCostMicros',0,
    'maxDurationSeconds',3600,
    'maxAttempts',2,
    'risk','read',
    'acceptance',p_acceptance,
    'source',jsonb_build_object(
      'repository','pandora-rvw-314296438-20260820/pandoras-box',
      'baseSha',v_source_sha
    ),
    'verificationProfile','automation'
  );
  perform public.pandora_ops_ingest_v1(v_org,v_project,jsonb_build_array(v_parent_spec));
  select * into v_parent from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=v_parent_id;

  v_claim:=public.pandora_ops_claim_v1(
    v_org,v_project,v_parent_id,v_worker,v_parent.revision,v_workspace.revision
  );
  if coalesce((v_claim->>'claimed')::boolean,false) is not true then
    raise exception 'OPS_CHATGPT_DIRECT_PARENT_CLAIM_FAILED:%',coalesce(v_claim->>'reason','unknown');
  end if;
  v_lease_id:=(v_claim->>'leaseId')::uuid;
  v_generation:=(v_claim->>'generation')::bigint;

  v_dispatch:=public.pandora_ops_dispatch_v1(v_org,v_project,v_lease_id,v_generation,null);
  v_dispatch_id:=(v_dispatch->>'dispatchId')::uuid;
  if coalesce((v_dispatch->>'acknowledged')::boolean,false) is not true then
    perform public.pandora_ops_dispatch_v1(
      v_org,v_project,v_lease_id,v_generation,
      jsonb_build_object(
        'accepted',true,'dispatchId',v_dispatch_id::text,'workerId',v_worker,
        'taskId',v_parent_id,'generation',v_generation,
        'receiptRef','chatgpt-direct:dispatch:'||v_dispatch_id::text
      )
    );
  end if;

  v_child_spec:=jsonb_build_object(
    'id',v_child_id,
    'title','Windows execution for '||left(p_title,210),
    'lane',v_profile->>'lane',
    'priority',1,
    'dependsOn','[]'::jsonb,
    'resources',jsonb_build_array(jsonb_build_object(
      'key','runtime/operations/rdp-windows-01/jobs/'||lower(replace(p_ingress_id::text,'-','')),'mode','read'
    )),
    'requiredCapabilities',jsonb_build_array('rdp.execute',v_profile->>'capability'),
    'maxCostMicros',0,
    'maxDurationSeconds',3600,
    'maxAttempts',2,
    'risk','read',
    'acceptance',v_profile->'acceptance',
    'source',jsonb_build_object(
      'repository','pandora-rvw-314296438-20260820/pandoras-box',
      'baseSha',v_source_sha
    ),
    'verificationProfile','automation'
  );
  perform public.pandora_ops_ingest_v1(v_org,v_project,jsonb_build_array(v_child_spec));

  insert into private.pandora_ops_chatgpt_direct_links(
    organization_id,project_id,ingress_id,parent_task_key,parent_generation,parent_lease_id,
    child_task_key,source_sha,profile,reason,state
  ) values(
    v_org,v_project,p_ingress_id,v_parent_id,v_generation,v_lease_id,
    v_child_id,v_source_sha,p_profile,p_reason,'child_queued'
  );

  perform private.pandora_ops_event_v1(
    v_org,v_project,'chatgpt-direct:ingress:'||p_ingress_id,v_parent_id,
    'chatgpt_direct_ingress_accepted','chatgpt-connected-session:'||p_ingress_id
  );
  perform private.pandora_ops_event_v1(
    v_org,v_project,'chatgpt-direct:child:'||p_ingress_id,v_parent_id,
    'chatgpt_direct_rdp_child_queued','child-task:'||v_child_id
  );

  return jsonb_build_object(
    'accepted',true,'replayed',false,'ingressId',p_ingress_id,
    'parentTaskId',v_parent_id,'parentGeneration',v_generation,'parentLeaseId',v_lease_id,
    'childTaskId',v_child_id,'profile',p_profile,'sourceSha',v_source_sha,
    'reasoningOrigin','chatgpt_connected_session','modelIdentityAsserted',false,
    'specialistReasoningInvoked',false,'reservedInferenceMicros',0
  );
end;
$body$;

create or replace function private.pandora_ops_chatgpt_direct_tick_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $body$
declare
  v_org constant uuid:='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;
  v_project constant uuid:='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid;
  v_release constant text:='pandora-native-release-v1';
  v_release_principal constant text:='vercel:mcpmaster:operations-native-release-v1';
  l private.pandora_ops_chatgpt_direct_links%rowtype;
  parent private.pandora_ops_tasks%rowtype;
  child private.pandora_ops_tasks%rowtype;
  proof jsonb;
  dispatch_id text;
  expected text;
  evidence jsonb;
  recorded jsonb;
  verified jsonb;
  handoff jsonb;
  outbox_id uuid;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('pandora-ops-chatgpt-direct-tick-v1',0)) then
    return jsonb_build_object('ok',true,'state','busy');
  end if;

  if not exists(
    select 1 from private.pandora_ops_workers
    where organization_id=v_org and project_id=v_project
      and worker_key=v_release and principal_key=v_release_principal and engine='pandora_native'
  ) then
    perform public.pandora_ops_register_native_worker_v1(
      v_org,v_project,v_release,v_release_principal,
      array['release']::text[],
      array['release.verify','provider.readback','canary.execute']::text[],
      1,'vercel-oidc:mcpmaster:production:pandora-native-release-v1'
    );
  else
    perform public.pandora_ops_heartbeat_v1(
      v_org,v_project,v_release,v_release_principal,true,'ready'
    );
  end if;

  select * into l
  from private.pandora_ops_chatgpt_direct_links
  where organization_id=v_org and project_id=v_project and state<>'complete'
  order by created_at asc
  limit 1
  for update skip locked;
  if not found then return jsonb_build_object('ok',true,'state','idle'); end if;

  select * into parent from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=l.parent_task_key for update;
  select * into child from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=l.child_task_key for update;

  if parent.status='complete' then
    update private.pandora_ops_chatgpt_direct_links set state='complete',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
  end if;

  if child.status in ('blocked','failed','cancelled') and l.state<>'reconciliation_required' then
    update private.pandora_ops_chatgpt_direct_links set state='reconciliation_required',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
    perform private.pandora_ops_event_v1(
      v_org,v_project,'chatgpt-direct:reconcile:'||l.ingress_id,l.parent_task_key,
      'reconciliation_required','child-state:'||child.status
    );
    return jsonb_build_object('ok',false,'state','reconciliation_required','parentTaskId',l.parent_task_key,'childTaskId',l.child_task_key);
  end if;

  if child.status in ('handed_off','verifying') and l.state in ('child_queued','child_handed_off') then
    proof:=child.handoff->'machineProof';
    dispatch_id:=child.handoff->>'dispatchId';
    if child.builder_worker_key<>'pandora-rdp-windows-01'
       or child.head_sha<>l.source_sha
       or child.handoff->>'workerId'<>'pandora-rdp-windows-01'
       or child.handoff->>'headSha'<>l.source_sha
       or child.handoff->>'implementationComplete'<>'true'
       or jsonb_typeof(proof)<>'object'
       or dispatch_id !~ '^[0-9a-f-]{36}$'
       or proof->>'profile'<>l.profile
       or proof->>'exitCode'<>'0'
       or proof->>'stdoutSha256' !~ '^[a-f0-9]{64}$'
       or proof->>'proofSha256' !~ '^[a-f0-9]{64}$'
    then raise exception 'OPS_CHATGPT_DIRECT_CHILD_PROOF_INVALID'; end if;

    expected:=encode(extensions.digest(convert_to(
      dispatch_id||':'||child.task_key||':'||child.generation::text||':'||
      (proof->>'profile')||':0:'||(proof->>'stdoutSha256'),'UTF8'
    ),'sha256'),'hex');
    if expected<>proof->>'proofSha256' then raise exception 'OPS_CHATGPT_DIRECT_CHILD_PROOF_INVALID'; end if;

    evidence:=jsonb_build_object(
      'taskId',child.task_key,'generation',child.generation::text,'headSha',child.head_sha,
      'taskSpecDigest',child.spec_digest,'criteria',child.spec->'acceptance',
      'ref','chatgpt-direct-child:'||(proof->>'proofSha256'),
      'providerReadback',jsonb_build_object(
        'ingressId',l.ingress_id,'parentTaskId',l.parent_task_key,'profile',l.profile,
        'dispatchId',dispatch_id,'stdoutSha256',proof->>'stdoutSha256',
        'proofSha256',proof->>'proofSha256','reasoningOrigin','chatgpt_connected_session',
        'modelIdentityAsserted',false
      )
    );
    recorded:=public.pandora_ops_record_verification_v1(
      v_org,v_project,child.task_key,child.generation,
      v_release,v_release_principal,'PASS',evidence
    );
    verified:=public.pandora_ops_verify_v1(
      v_org,v_project,child.task_key,child.generation,
      v_release,v_release_principal,(recorded->>'verificationRunId')::uuid,
      evidence||jsonb_build_object('verificationRunId',recorded->>'verificationRunId')
    );
    update private.pandora_ops_chatgpt_direct_links set state='child_complete',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
    select * into child from private.pandora_ops_tasks
    where organization_id=v_org and project_id=v_project and task_key=l.child_task_key;
  elsif child.status='complete' and l.state in ('child_queued','child_handed_off') then
    update private.pandora_ops_chatgpt_direct_links set state='child_complete',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
  end if;

  if l.state='child_complete' and parent.status='implementing' then
    handoff:=jsonb_build_object(
      'taskId',parent.task_key,'workerId','chatgpt-direct-ingress-v1',
      'generation',parent.generation,'headSha',l.source_sha,
      'tests',jsonb_build_array(
        'ChatGPT connected-session intent passed bounded Operations validation PASS',
        'Automatic Windows RDP child completed with independent verification PASS',
        'Exact canonical main SHA remained unchanged across ingress, execution and verification PASS'
      ),
      'evidenceRefs',jsonb_build_array(
        'chatgpt-connected-session:'||l.ingress_id::text,
        'rdp-child:'||l.child_task_key,
        'child-verification:'||coalesce(child.verification->>'verificationRunId','unknown')
      ),
      'receiptRef','chatgpt-direct-parent:'||encode(extensions.digest(convert_to(
        parent.task_key||':'||parent.generation::text||':'||l.child_task_key||':'||l.source_sha,'UTF8'
      ),'sha256'),'hex'),
      'implementationComplete',true,
      'profile',l.profile,
      'reasoningOrigin','chatgpt_connected_session',
      'modelIdentityAsserted',false,
      'specialistReasoningInvoked',false
    );
    perform public.pandora_ops_handoff_v1(
      v_org,v_project,l.parent_lease_id,parent.generation,
      'chatgpt:connected-session:operations-ingress-v1',handoff,0
    );
    update private.pandora_ops_chatgpt_direct_links set state='parent_handed_off',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
    select * into parent from private.pandora_ops_tasks
    where organization_id=v_org and project_id=v_project and task_key=l.parent_task_key;
  end if;

  if parent.status in ('handed_off','verifying') and l.state='parent_handed_off' then
    evidence:=jsonb_build_object(
      'taskId',parent.task_key,'generation',parent.generation::text,'headSha',parent.head_sha,
      'taskSpecDigest',parent.spec_digest,'criteria',parent.spec->'acceptance',
      'ref','chatgpt-direct-parent:'||l.ingress_id::text,
      'providerReadback',jsonb_build_object(
        'ingressId',l.ingress_id,'profile',l.profile,'childTaskId',l.child_task_key,
        'childVerificationRunId',child.verification->>'verificationRunId',
        'reasoningOrigin','chatgpt_connected_session','modelIdentityAsserted',false,
        'specialistReasoningInvoked',false,'arbitraryCommandAuthority',false
      )
    );
    recorded:=public.pandora_ops_record_verification_v1(
      v_org,v_project,parent.task_key,parent.generation,
      v_release,v_release_principal,'PASS',evidence
    );
    verified:=public.pandora_ops_verify_v1(
      v_org,v_project,parent.task_key,parent.generation,
      v_release,v_release_principal,(recorded->>'verificationRunId')::uuid,
      evidence||jsonb_build_object('verificationRunId',recorded->>'verificationRunId')
    );
    update private.pandora_ops_chatgpt_direct_links set state='complete',updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id
    returning * into l;
    select * into parent from private.pandora_ops_tasks
    where organization_id=v_org and project_id=v_project and task_key=l.parent_task_key;
  end if;

  if l.state='complete' and l.learning_outbox_id is null then
    insert into public.pandora_verified_learning_outbox(
      organization_id,activity_job_id,thread_id,idempotency_key,memory_project_id,namespace,
      learning_kind,learning_summary,promotion_basis,confidence,execution,
      incident_verification_ref,additional_evidence_refs,state,attempt_count,created_at,updated_at
    ) values(
      v_org,l.ingress_id,null,
      'operations-chatgpt-direct:'||l.ingress_id::text,
      '7c686cbd-d968-49d5-86cc-918f5e777bd2'::uuid,'real_life',
      'outcome',
      'A ChatGPT-connected Operations intent used profile '||l.profile||
        ' on the governed Windows RDP and passed independent verification.',
      'Operations parent and RDP child both reached canonical PASS verification on exact source '||l.source_sha||
        '; this is a review-gated learning candidate and not self-promoted Memory.',
      1.0,
      jsonb_build_object(
        'schemaVersion','operations-chatgpt-direct-v1',
        'ingressId',l.ingress_id,'parentTaskId',l.parent_task_key,
        'parentGeneration',l.parent_generation,'childTaskId',l.child_task_key,
        'profile',l.profile,'sourceSha',l.source_sha,
        'reasoningOrigin','chatgpt_connected_session','modelIdentityAsserted',false,
        'specialistReasoningInvoked',false,'arbitraryCommandAuthority',false,
        'parentVerificationRunId',parent.verification->>'verificationRunId',
        'childVerificationRunId',child.verification->>'verificationRunId'
      ),
      null,
      array[
        'ops-task:'||l.parent_task_key,
        'rdp-task:'||l.child_task_key,
        'source-sha:'||l.source_sha
      ]::text[],
      'pending',0,now(),now()
    )
    on conflict(idempotency_key) do update set updated_at=excluded.updated_at
    returning id into outbox_id;

    update private.pandora_ops_chatgpt_direct_links
    set learning_outbox_id=outbox_id,updated_at=clock_timestamp()
    where organization_id=v_org and project_id=v_project and ingress_id=l.ingress_id;

    perform private.pandora_ops_event_v1(
      v_org,v_project,'chatgpt-direct:memory:'||l.ingress_id,l.parent_task_key,
      'verified_learning_queued','verified-learning-outbox:'||outbox_id::text
    );
  end if;

  return jsonb_build_object(
    'ok',true,'state',l.state,'ingressId',l.ingress_id,
    'parentTaskId',l.parent_task_key,'parentStatus',parent.status,
    'childTaskId',l.child_task_key,'childStatus',child.status,
    'profile',l.profile,'learningOutboxId',coalesce(l.learning_outbox_id,outbox_id),
    'specialistReasoningInvoked',false
  );
end;
$body$;

-- Poll direct ChatGPT/RDP completion using the existing database scheduler.
do $cron$
begin
  if exists(select 1 from cron.job where jobname='pandora-operations-chatgpt-direct-v1') then
    perform cron.unschedule('pandora-operations-chatgpt-direct-v1');
  end if;
  perform cron.schedule(
    'pandora-operations-chatgpt-direct-v1',
    '* * * * *',
    'select private.pandora_ops_chatgpt_direct_tick_v1();'
  );
end;
$cron$;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('operations_chatgpt_direct','enabled','true',true,clock_timestamp()),
  ('operations_chatgpt_direct','ingress','supabase_management_private_rpc',true,clock_timestamp()),
  ('operations_chatgpt_direct','reasoning_origin','chatgpt_connected_session',true,clock_timestamp()),
  ('operations_chatgpt_direct','model_identity_asserted','false',true,clock_timestamp()),
  ('operations_chatgpt_direct','specialist_reasoning_default','false',true,clock_timestamp()),
  ('operations_chatgpt_direct','risk_scope','read',true,clock_timestamp()),
  ('operations_chatgpt_direct','source_scope','canonical_main_only',true,clock_timestamp()),
  ('operations_chatgpt_direct','inference_cost_micros','0',true,clock_timestamp()),
  ('operations_chatgpt_direct','arbitrary_shell_allowed','false',true,clock_timestamp()),
  ('operations_chatgpt_direct','memory_mode','verified_review_gated_outbox',true,clock_timestamp())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=true,updated_at=clock_timestamp();

-- Deliberately management-plane only. It is not callable by browser, app runtime,
-- service-role REST clients, workers, or models.
revoke all on function private.pandora_ops_chatgpt_direct_submit_v1(uuid,text,text,text,jsonb)
from public,anon,authenticated,service_role;
revoke all on function private.pandora_ops_chatgpt_direct_tick_v1()
from public,anon,authenticated,service_role;
revoke all on function private.pandora_ops_chatgpt_direct_profile_v1(text)
from public,anon,authenticated,service_role;

