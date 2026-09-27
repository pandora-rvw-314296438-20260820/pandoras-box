-- Operations model -> RDP bridge v1.
-- Read-risk automation only. The reasoning model may select a bounded execution profile;
-- it never supplies shell, paths, credentials, source mutations, deployment actions, or commands.

create table if not exists private.pandora_ops_reasoning_rdp_links (
  organization_id uuid not null,
  project_id uuid not null,
  parent_task_key text not null,
  parent_generation bigint not null check(parent_generation>0),
  parent_lease_id uuid not null,
  inference_request_id uuid not null unique,
  source_sha text not null check(source_sha ~ '^[a-f0-9]{40}$'),
  allowed_profiles jsonb not null check(jsonb_typeof(allowed_profiles)='array' and jsonb_array_length(allowed_profiles)>0),
  state text not null check(state in (
    'reasoning','child_queued','child_handed_off','child_complete',
    'parent_handed_off','complete','reconciliation_required'
  )),
  plan jsonb,
  output_digest text check(output_digest is null or output_digest ~ '^[a-f0-9]{64}$'),
  provider_receipt text,
  child_task_key text,
  profile text check(profile is null or profile in (
    'toolchain_verify','github_runner_verify','android_verify','flutter_verify','repo_test','repo_build'
  )),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,project_id,parent_task_key,parent_generation),
  foreign key(organization_id,project_id,parent_task_key)
    references private.pandora_ops_tasks(organization_id,project_id,task_key),
  foreign key(parent_lease_id) references private.pandora_ops_leases(id)
);
alter table private.pandora_ops_reasoning_rdp_links enable row level security;
revoke all on private.pandora_ops_reasoning_rdp_links from public,anon,authenticated,service_role;

create or replace function public.pandora_ops_register_reasoning_rdp_bridge_v1(
  p_organization_id uuid,p_project_id uuid,p_worker_key text,p_principal_key text,
  p_lanes text[],p_capabilities text[],p_capacity integer,p_receipt_ref text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
begin
  perform 1 from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active'
  for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
     or p_lanes<>array['backend','reliability','web','mobile']::text[]
     or p_capabilities<>array[
       'inference.route','rdp.execute','rdp.delegate',
       'rdp.toolchain.verify','rdp.github_runner.verify','rdp.android.verify',
       'rdp.flutter.verify','rdp.repo.test','rdp.repo.build','worker.reconcile'
     ]::text[]
     or p_capacity<>1
     or p_receipt_ref<>'vercel-oidc:mcpmaster:production:pandora-reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_INVALID' using errcode='22023'; end if;

  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  ) values(
    p_organization_id,p_project_id,p_worker_key,p_principal_key,'pandora_native',
    p_lanes,p_capabilities,1,true,true,'ready',clock_timestamp(),p_receipt_ref
  )
  on conflict(organization_id,project_id,worker_key) do update
  set lanes=excluded.lanes,capabilities=excluded.capabilities,capacity=1,
      acknowledged=true,connected=true,health='ready',heartbeat_at=clock_timestamp(),
      registration_receipt=excluded.registration_receipt
  where private.pandora_ops_workers.principal_key=excluded.principal_key
    and private.pandora_ops_workers.engine='pandora_native';

  if not found then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_CONFLICT' using errcode='42501'; end if;
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'worker:'||p_worker_key,null,'worker_acknowledged',p_receipt_ref
  );
  return jsonb_build_object('registered',true,'workerId',p_worker_key);
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_candidate_v1(
  p_organization_id uuid,p_project_id uuid,p_worker_key text,p_principal_key text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare
  w private.pandora_ops_workspaces%rowtype;
  worker private.pandora_ops_workers%rowtype;
  t private.pandora_ops_tasks%rowtype;
  required_caps text[];
  available_budget bigint;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;

  select * into w from private.pandora_ops_workspaces
  where organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
  if w.paused then return jsonb_build_object('state','paused','controlRevision',w.revision); end if;

  select * into worker from private.pandora_ops_workers
  where organization_id=p_organization_id and project_id=p_project_id and worker_key=p_worker_key;
  if not found or worker.principal_key<>p_principal_key or not worker.acknowledged
     or not worker.connected or worker.health<>'ready'
     or worker.heartbeat_at<clock_timestamp()-interval '60 seconds'
  then return jsonb_build_object('state','worker_unavailable'); end if;

  select q.* into t
  from private.pandora_ops_tasks q
  where q.organization_id=p_organization_id and q.project_id=p_project_id
    and q.status='queued' and not q.cancel_requested
    and q.task_key !~ '^OPS-RDP-'
    and q.spec->>'risk'='read'
    and q.spec->>'verificationProfile'='automation'
    and q.spec->'source'<>'null'::jsonb
    and q.spec#>>'{source,baseSha}' ~ '^[a-f0-9]{40}$'
    and (q.spec->'requiredCapabilities') ? 'rdp.execute'
    and not exists(
      select 1 from private.pandora_ops_dependencies d
      join private.pandora_ops_tasks dep
        on dep.organization_id=d.organization_id and dep.project_id=d.project_id
       and dep.task_key=d.dependency_key
      where d.organization_id=q.organization_id and d.project_id=q.project_id
        and d.task_key=q.task_key and dep.status<>'complete'
    )
    and not exists(
      select 1 from private.pandora_ops_human_gates g
      where g.organization_id=q.organization_id and g.project_id=q.project_id
        and g.task_key=q.task_key and g.state<>'approved'
    )
    and not exists(
      select 1 from private.pandora_ops_reasoning_rdp_links l
      where l.organization_id=q.organization_id and l.project_id=q.project_id
        and l.parent_task_key=q.task_key and l.parent_generation=q.generation+1
    )
  order by (q.spec->>'priority')::integer asc,q.queued_at asc,q.task_key asc
  limit 1;

  if not found then return jsonb_build_object('state','idle','reason','no_dependency_ready_rdp_automation_task'); end if;

  select array_agg(value) into required_caps
  from jsonb_array_elements_text(t.spec->'requiredCapabilities');
  if not coalesce(required_caps <@ worker.capabilities,false) then
    return jsonb_build_object('state','ineligible','taskId',t.task_key,'reason','bridge_capability_mismatch');
  end if;

  available_budget:=w.total_budget_micros-w.reserved_micros-w.spent_micros;
  if (t.spec->>'maxCostMicros')::bigint<1000000 or available_budget<(t.spec->>'maxCostMicros')::bigint then
    return jsonb_build_object(
      'state','budget_required','taskId',t.task_key,'taskRevision',t.revision,
      'controlRevision',w.revision,'requiredTaskBudgetMicros',greatest(1000000,(t.spec->>'maxCostMicros')::bigint),
      'workspaceAvailableMicros',available_budget
    );
  end if;

  return jsonb_build_object(
    'state','ready','taskId',t.task_key,'taskRevision',t.revision,
    'controlRevision',w.revision,'sourceSha',t.spec#>>'{source,baseSha}',
    'maxCostMicros',(t.spec->>'maxCostMicros')::bigint
  );
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_begin_v1(
  p_organization_id uuid,p_project_id uuid,p_task_key text,p_lease_id uuid,p_generation bigint,
  p_worker_key text,p_principal_key text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare
  l private.pandora_ops_leases%rowtype;
  t private.pandora_ops_tasks%rowtype;
  existing private.pandora_ops_reasoning_rdp_links%rowtype;
  request_id uuid:=gen_random_uuid();
  profiles text[]:=array[]::text[];
  caps jsonb;
  prompt text;
  inference_budget bigint;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;

  select * into l from private.pandora_ops_leases
  where id=p_lease_id and organization_id=p_organization_id and project_id=p_project_id
  for update;
  if not found or l.task_key<>p_task_key or l.worker_key<>p_worker_key
     or l.generation<>p_generation or l.state<>'running' or l.expires_at<=clock_timestamp()
  then raise exception 'OPS_REASONING_RDP_LEASE_FENCED'; end if;

  select * into t from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key
  for update;
  if not found or t.status<>'implementing' or t.generation<>p_generation
     or t.builder_worker_key<>p_worker_key or t.builder_principal_key<>p_principal_key
     or t.spec->>'risk'<>'read' or t.spec->>'verificationProfile'<>'automation'
     or not((t.spec->'requiredCapabilities') ? 'rdp.execute')
     or t.spec->'source'='null'::jsonb
  then raise exception 'OPS_REASONING_RDP_PARENT_INVALID'; end if;

  select * into existing from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_task_key and parent_generation=p_generation;
  if found then
    return jsonb_build_object(
      'state',existing.state,'requestId',existing.inference_request_id,
      'sourceSha',existing.source_sha,'allowedProfiles',existing.allowed_profiles,
      'childTaskId',existing.child_task_key,'profile',existing.profile
    );
  end if;

  caps:=t.spec->'requiredCapabilities';
  if t.spec->>'lane'='reliability' then profiles:=profiles||array['toolchain_verify','github_runner_verify','repo_test']; end if;
  if t.spec->>'lane' in ('backend','web') then profiles:=profiles||array['repo_test','repo_build']; end if;
  if t.spec->>'lane'='mobile' then profiles:=profiles||array['flutter_verify','android_verify','repo_test','repo_build']; end if;
  if caps ? 'rdp.toolchain.verify' then profiles:=profiles||array['toolchain_verify']; end if;
  if caps ? 'rdp.github_runner.verify' then profiles:=profiles||array['github_runner_verify']; end if;
  if caps ? 'rdp.android.verify' then profiles:=profiles||array['android_verify']; end if;
  if caps ? 'rdp.flutter.verify' then profiles:=profiles||array['flutter_verify']; end if;
  if caps ? 'rdp.repo.test' then profiles:=profiles||array['repo_test']; end if;
  if caps ? 'rdp.repo.build' then profiles:=profiles||array['repo_build']; end if;
  select array_agg(distinct x order by x) into profiles from unnest(profiles) x;
  if profiles is null or cardinality(profiles)=0 then raise exception 'OPS_REASONING_RDP_PROFILE_UNAVAILABLE'; end if;

  inference_budget:=least(l.reserved_micros,1000000);
  if inference_budget<1000000 then raise exception 'OPS_REASONING_RDP_INFERENCE_BUDGET_REQUIRED'; end if;

  prompt:='Return one JSON object only. You are choosing a bounded Windows execution profile, not writing commands. '
    ||'Allowed profile values: '||to_json(profiles)::text||'. '
    ||'Schema exactly: {"profile":"<allowed value>","reason":"<one concise sentence>"}. '
    ||'Never output shell, code, paths, URLs, credentials, arguments, or extra keys. '
    ||'Task title: '||to_json(t.spec->>'title')::text||'. '
    ||'Acceptance criteria: '||(t.spec->'acceptance')::text||'.';

  insert into private.pandora_ops_reasoning_rdp_links(
    organization_id,project_id,parent_task_key,parent_generation,parent_lease_id,
    inference_request_id,source_sha,allowed_profiles,state
  ) values(
    p_organization_id,p_project_id,p_task_key,p_generation,p_lease_id,
    request_id,t.spec#>>'{source,baseSha}',to_jsonb(profiles),'reasoning'
  );

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'reasoning-rdp:begin:'||request_id,p_task_key,
    'reasoning_rdp_started','inference-request:'||request_id
  );

  return jsonb_build_object(
    'state','reasoning','requestId',request_id,'sourceSha',t.spec#>>'{source,baseSha}',
    'prompt',prompt,'taskClass','structured_extraction','maxOutputTokens',128,
    'maxCostMicros',inference_budget,'deadlineMs',45000,'allowedProfiles',to_jsonb(profiles)
  );
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_materialize_v1(
  p_organization_id uuid,p_project_id uuid,p_task_key text,p_generation bigint,
  p_worker_key text,p_principal_key text,p_output text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare
  link private.pandora_ops_reasoning_rdp_links%rowtype;
  parent private.pandora_ops_tasks%rowtype;
  req private.pandora_ops_inference_requests%rowtype;
  attempt private.pandora_ops_inference_attempts%rowtype;
  plan jsonb;
  profile text;
  reason text;
  output_digest text;
  child_id text;
  child_lane text;
  cap text;
  acceptance jsonb;
  child_spec jsonb;
  child private.pandora_ops_tasks%rowtype;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;
  if p_output is null or octet_length(p_output)>4096 then raise exception 'OPS_REASONING_RDP_PLAN_INVALID'; end if;

  select * into link from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_task_key and parent_generation=p_generation
  for update;
  if not found then raise exception 'OPS_REASONING_RDP_LINK_MISSING'; end if;
  if link.state in ('child_queued','child_handed_off','child_complete','parent_handed_off','complete') then
    return jsonb_build_object('state',link.state,'childTaskId',link.child_task_key,'profile',link.profile,'replayed',true);
  end if;
  if link.state<>'reasoning' then raise exception 'OPS_REASONING_RDP_LINK_FENCED'; end if;

  select * into parent from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key
  for update;
  if not found or parent.status<>'implementing' or parent.generation<>p_generation
     or parent.builder_worker_key<>p_worker_key or parent.builder_principal_key<>p_principal_key
  then raise exception 'OPS_REASONING_RDP_PARENT_FENCED'; end if;

  select * into req from private.pandora_ops_inference_requests
  where id=link.inference_request_id and organization_id=p_organization_id and project_id=p_project_id
  for share;
  if not found or req.task_key<>p_task_key or req.generation<>p_generation
     or req.lease_id<>link.parent_lease_id or req.source_sha<>link.source_sha
     or req.worker_key<>p_worker_key or req.principal_key<>p_principal_key
     or req.state not in ('verification_pending','verified') or req.selected_attempt is null
  then raise exception 'OPS_REASONING_RDP_INFERENCE_UNVERIFIED'; end if;

  select * into attempt from private.pandora_ops_inference_attempts
  where id=req.selected_attempt and request_id=req.id for share;
  output_digest:=encode(extensions.digest(convert_to(p_output,'UTF8'),'sha256'),'hex');
  if not found or attempt.state<>'received' or attempt.receipt->>'outputDigest'<>output_digest
     or nullif(attempt.receipt->>'providerReceipt','') is null
  then raise exception 'OPS_REASONING_RDP_OUTPUT_DIGEST_MISMATCH'; end if;

  begin plan:=p_output::jsonb; exception when others then raise exception 'OPS_REASONING_RDP_PLAN_INVALID'; end;
  if jsonb_typeof(plan)<>'object' or (select count(*) from jsonb_object_keys(plan))<>2
     or not(plan ?& array['profile','reason'])
  then raise exception 'OPS_REASONING_RDP_PLAN_INVALID'; end if;
  profile:=plan->>'profile'; reason:=plan->>'reason';
  if not coalesce((link.allowed_profiles ? profile),false)
     or reason is null or length(reason) not between 1 and 500
     or reason<>btrim(reason) or reason ~ '[\x01-\x1f]'
     or reason ~* '(powershell|cmd\.exe|bash|curl|wget|https?://|[A-Za-z]:\\|/bin/|secret|token|password|credential)'
  then raise exception 'OPS_REASONING_RDP_PLAN_INVALID'; end if;

  child_id:='OPS-RDP-AUTO-'||upper(left(encode(extensions.digest(
    convert_to(p_task_key||':'||p_generation::text||':'||output_digest,'UTF8'),'sha256'
  ),'hex'),32));

  if profile='toolchain_verify' then child_lane:='reliability'; cap:='rdp.toolchain.verify';
    acceptance:='["Windows toolchain executes successfully from the governed RDP worker.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  elsif profile='github_runner_verify' then child_lane:='reliability'; cap:='rdp.github_runner.verify';
    acceptance:='["The canonical GitHub runner binding is verified on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  elsif profile='android_verify' then child_lane:='mobile'; cap:='rdp.android.verify';
    acceptance:='["Android platform tools execute successfully on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  elsif profile='flutter_verify' then child_lane:='mobile'; cap:='rdp.flutter.verify';
    acceptance:='["Flutter tooling executes successfully on the Windows RDP.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  elsif profile='repo_test' then child_lane:='backend'; cap:='rdp.repo.test';
    acceptance:='["The exact source SHA is verified as an ancestor of canonical main before execution.","Dependencies install without source mutation and the repository test suite exits successfully.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  elsif profile='repo_build' then child_lane:='backend'; cap:='rdp.repo.build';
    acceptance:='["The exact source SHA is verified as an ancestor of canonical main before execution.","Dependencies install without source mutation and the canonical build exits successfully.","Hashed machine proof is returned through the Operations handoff."]'::jsonb;
  else raise exception 'OPS_REASONING_RDP_PROFILE_INVALID'; end if;

  child_spec:=jsonb_build_object(
    'id',child_id,
    'title','Automatic Windows execution for '||left(parent.spec->>'title',200),
    'lane',child_lane,
    'priority',(parent.spec->>'priority')::integer,
    'dependsOn','[]'::jsonb,
    'resources',jsonb_build_array(jsonb_build_object(
      'key','runtime/operations/rdp-windows-01/jobs/'||lower(right(child_id,32)),'mode','read'
    )),
    'requiredCapabilities',jsonb_build_array('rdp.execute',cap),
    'maxCostMicros',0,
    'maxDurationSeconds',least(3600,greatest(300,(parent.spec->>'maxDurationSeconds')::integer)),
    'maxAttempts',2,
    'risk','read',
    'acceptance',acceptance,
    'source',parent.spec->'source',
    'verificationProfile','automation'
  );

  perform public.pandora_ops_ingest_v1(p_organization_id,p_project_id,jsonb_build_array(child_spec));
  select * into child from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=child_id;

  update private.pandora_ops_reasoning_rdp_links
  set state='child_queued',plan=plan,output_digest=output_digest,
      provider_receipt=attempt.receipt->>'providerReceipt',child_task_key=child_id,
      profile=profile,updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_task_key and parent_generation=p_generation;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'reasoning-rdp:materialize:'||link.inference_request_id,
    p_task_key,'reasoning_rdp_child_queued','child-task:'||child_id
  );
  return jsonb_build_object(
    'state','child_queued','childTaskId',child_id,'profile',profile,
    'outputDigest',output_digest,'providerReceipt',attempt.receipt->>'providerReceipt'
  );
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_status_v1(
  p_organization_id uuid,p_project_id uuid,p_worker_key text,p_principal_key text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare link private.pandora_ops_reasoning_rdp_links%rowtype;
declare child private.pandora_ops_tasks%rowtype;
declare parent private.pandora_ops_tasks%rowtype;
declare req private.pandora_ops_inference_requests%rowtype;
declare attempt private.pandora_ops_inference_attempts%rowtype;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;

  select * into link from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id and state<>'complete'
  order by created_at asc limit 1 for update skip locked;
  if not found then return jsonb_build_object('state','idle'); end if;

  select * into parent from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=link.parent_task_key;
  if link.child_task_key is not null then
    select * into child from private.pandora_ops_tasks
    where organization_id=p_organization_id and project_id=p_project_id and task_key=link.child_task_key;
    if child.status='complete' and link.state in ('child_queued','child_handed_off') then
      update private.pandora_ops_reasoning_rdp_links set state='child_complete',updated_at=clock_timestamp()
      where organization_id=p_organization_id and project_id=p_project_id
        and parent_task_key=link.parent_task_key and parent_generation=link.parent_generation
      returning * into link;
    elsif child.status in ('handed_off','verifying') and link.state='child_queued' then
      update private.pandora_ops_reasoning_rdp_links set state='child_handed_off',updated_at=clock_timestamp()
      where organization_id=p_organization_id and project_id=p_project_id
        and parent_task_key=link.parent_task_key and parent_generation=link.parent_generation
      returning * into link;
    elsif child.status in ('failed','cancelled','blocked') and link.state not in ('reconciliation_required','complete') then
      update private.pandora_ops_reasoning_rdp_links set state='reconciliation_required',updated_at=clock_timestamp()
      where organization_id=p_organization_id and project_id=p_project_id
        and parent_task_key=link.parent_task_key and parent_generation=link.parent_generation
      returning * into link;
    end if;
  end if;
  if parent.status='complete' then
    update private.pandora_ops_reasoning_rdp_links set state='complete',updated_at=clock_timestamp()
    where organization_id=p_organization_id and project_id=p_project_id
      and parent_task_key=link.parent_task_key and parent_generation=link.parent_generation
    returning * into link;
  end if;

  select * into req from private.pandora_ops_inference_requests where id=link.inference_request_id;
  if req.selected_attempt is not null then
    select * into attempt from private.pandora_ops_inference_attempts where id=req.selected_attempt;
  end if;

  return jsonb_build_object(
    'state',link.state,'parentTaskId',link.parent_task_key,'parentGeneration',link.parent_generation,
    'parentLeaseId',link.parent_lease_id,'parentStatus',parent.status,
    'inferenceRequestId',link.inference_request_id,'inferenceState',req.state,
    'inferenceBilledMicros',attempt.billed_micros,
    'childTaskId',link.child_task_key,'childStatus',child.status,
    'profile',link.profile,'sourceSha',link.source_sha,'outputDigest',link.output_digest
  );
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_verify_child_v1(
  p_organization_id uuid,p_project_id uuid,p_parent_task_key text,p_parent_generation bigint,
  p_verifier_key text,p_verifier_principal text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare link private.pandora_ops_reasoning_rdp_links%rowtype;
declare child private.pandora_ops_tasks%rowtype;
declare proof jsonb;
declare dispatch_id text;
declare expected text;
declare evidence jsonb;
declare recorded jsonb;
declare accepted jsonb;
begin
  select * into link from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation
  for update;
  if not found or link.state not in ('child_handed_off','child_complete') or link.child_task_key is null
  then raise exception 'OPS_REASONING_RDP_CHILD_NOT_READY'; end if;

  select * into child from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=link.child_task_key
  for update;
  if child.status='complete' then
    update private.pandora_ops_reasoning_rdp_links set state='child_complete',updated_at=clock_timestamp()
    where organization_id=p_organization_id and project_id=p_project_id
      and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
    return jsonb_build_object('complete',true,'replayed',true,'childTaskId',child.task_key);
  end if;
  if child.status not in ('handed_off','verifying')
     or child.builder_worker_key<>'pandora-rdp-windows-01'
     or child.head_sha<>link.source_sha
     or child.handoff->>'workerId'<>'pandora-rdp-windows-01'
     or child.handoff->>'headSha'<>link.source_sha
     or child.handoff->>'implementationComplete'<>'true'
  then raise exception 'OPS_REASONING_RDP_CHILD_EVIDENCE_INVALID'; end if;

  proof:=child.handoff->'machineProof';
  dispatch_id:=child.handoff->>'dispatchId';
  if jsonb_typeof(proof)<>'object' or dispatch_id !~ '^[0-9a-f-]{36}$'
     or proof->>'profile'<>link.profile or proof->>'exitCode'<>'0'
     or proof->>'stdoutSha256' !~ '^[a-f0-9]{64}$'
     or proof->>'proofSha256' !~ '^[a-f0-9]{64}$'
  then raise exception 'OPS_REASONING_RDP_CHILD_PROOF_INVALID'; end if;
  expected:=encode(extensions.digest(convert_to(
    dispatch_id||':'||child.task_key||':'||child.generation::text||':'||
    (proof->>'profile')||':0:'||(proof->>'stdoutSha256'),'UTF8'
  ),'sha256'),'hex');
  if expected<>proof->>'proofSha256' then raise exception 'OPS_REASONING_RDP_CHILD_PROOF_INVALID'; end if;

  evidence:=jsonb_build_object(
    'taskId',child.task_key,'generation',child.generation::text,'headSha',child.head_sha,
    'taskSpecDigest',child.spec_digest,'criteria',child.spec->'acceptance',
    'ref','reasoning-rdp-child:'||(proof->>'proofSha256'),
    'providerReadback',jsonb_build_object(
      'parentTaskId',p_parent_task_key,'profile',link.profile,'dispatchId',dispatch_id,
      'stdoutSha256',proof->>'stdoutSha256','proofSha256',proof->>'proofSha256',
      'reasoningOutputDigest',link.output_digest
    )
  );
  recorded:=public.pandora_ops_record_verification_v1(
    p_organization_id,p_project_id,child.task_key,child.generation,
    p_verifier_key,p_verifier_principal,'PASS',evidence
  );
  accepted:=public.pandora_ops_verify_v1(
    p_organization_id,p_project_id,child.task_key,child.generation,
    p_verifier_key,p_verifier_principal,(recorded->>'verificationRunId')::uuid,
    evidence||jsonb_build_object('verificationRunId',recorded->>'verificationRunId')
  );
  update private.pandora_ops_reasoning_rdp_links set state='child_complete',updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
  return jsonb_build_object('complete',true,'childTaskId',child.task_key,'verification',accepted);
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_parent_handoff_v1(
  p_organization_id uuid,p_project_id uuid,p_parent_task_key text,p_parent_generation bigint,
  p_worker_key text,p_principal_key text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare link private.pandora_ops_reasoning_rdp_links%rowtype;
declare parent private.pandora_ops_tasks%rowtype;
declare child private.pandora_ops_tasks%rowtype;
declare req private.pandora_ops_inference_requests%rowtype;
declare attempt private.pandora_ops_inference_attempts%rowtype;
declare unknown_billing integer;
declare actual_cost bigint;
declare handoff jsonb;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;

  select * into link from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation
  for update;
  if not found or link.state not in ('child_complete','parent_handed_off') then
    raise exception 'OPS_REASONING_RDP_PARENT_NOT_READY'; end if;

  select * into parent from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_parent_task_key
  for update;
  if parent.status in ('handed_off','verifying','complete') then
    update private.pandora_ops_reasoning_rdp_links set state=case when parent.status='complete' then 'complete' else 'parent_handed_off' end,
      updated_at=clock_timestamp()
    where organization_id=p_organization_id and project_id=p_project_id
      and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
    return jsonb_build_object('state',parent.status,'replayed',true);
  end if;
  if parent.status<>'implementing' or parent.generation<>p_parent_generation then
    raise exception 'OPS_REASONING_RDP_PARENT_FENCED'; end if;

  select * into child from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=link.child_task_key;
  if not found or child.status<>'complete' or child.head_sha<>link.source_sha then
    raise exception 'OPS_REASONING_RDP_CHILD_NOT_VERIFIED'; end if;

  select * into req from private.pandora_ops_inference_requests where id=link.inference_request_id;
  if not found or req.selected_attempt is null or req.state not in ('verification_pending','verified') then
    raise exception 'OPS_REASONING_RDP_INFERENCE_UNVERIFIED'; end if;
  select * into attempt from private.pandora_ops_inference_attempts where id=req.selected_attempt;
  if not found or attempt.state<>'received' or attempt.receipt->>'outputDigest'<>link.output_digest then
    raise exception 'OPS_REASONING_RDP_INFERENCE_UNVERIFIED'; end if;

  select count(*) filter(where billed_micros is null),coalesce(sum(billed_micros),0)
  into unknown_billing,actual_cost
  from private.pandora_ops_inference_attempts where request_id=req.id;
  if unknown_billing<>0 then
    return jsonb_build_object(
      'state','billing_pending','taskId',parent.task_key,'inferenceRequestId',req.id,
      'reason','provider_billing_evidence_required'
    );
  end if;

  handoff:=jsonb_build_object(
    'taskId',parent.task_key,'workerId',p_worker_key,'generation',parent.generation,
    'headSha',link.source_sha,
    'tests',jsonb_build_array(
      'Governed reasoning route returned a schema-valid bounded RDP profile PASS',
      'Automatic RDP child completed with independent release verification PASS',
      'Exact source SHA remained unchanged across reasoning, execution, and verification PASS'
    ),
    'evidenceRefs',jsonb_build_array(
      'inference-request:'||req.id::text,
      'inference-output-sha256:'||link.output_digest,
      'rdp-child:'||child.task_key,
      'child-verification:'||coalesce(child.verification->>'verificationRunId','unknown')
    ),
    'receiptRef','reasoning-rdp-parent:'||encode(extensions.digest(convert_to(
      parent.task_key||':'||parent.generation::text||':'||link.output_digest||':'||child.task_key,'UTF8'
    ),'sha256'),'hex'),
    'implementationComplete',true,
    'reasoningPlan',link.plan,
    'childTaskId',child.task_key
  );

  perform public.pandora_ops_handoff_v1(
    p_organization_id,p_project_id,link.parent_lease_id,parent.generation,
    p_principal_key,handoff,actual_cost
  );
  update private.pandora_ops_reasoning_rdp_links set state='parent_handed_off',updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
  return jsonb_build_object('state','parent_handed_off','taskId',parent.task_key,'actualCostMicros',actual_cost);
end;
$body$;

create or replace function public.pandora_ops_reasoning_rdp_verify_parent_v1(
  p_organization_id uuid,p_project_id uuid,p_parent_task_key text,p_parent_generation bigint,
  p_verifier_key text,p_verifier_principal text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
declare link private.pandora_ops_reasoning_rdp_links%rowtype;
declare parent private.pandora_ops_tasks%rowtype;
declare child private.pandora_ops_tasks%rowtype;
declare evidence jsonb;
declare recorded jsonb;
declare accepted jsonb;
begin
  select * into link from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation
  for update;
  if not found or link.state not in ('parent_handed_off','complete') then
    raise exception 'OPS_REASONING_RDP_PARENT_NOT_HANDED_OFF'; end if;
  select * into parent from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=p_parent_task_key
  for update;
  if parent.status='complete' then
    update private.pandora_ops_reasoning_rdp_links set state='complete',updated_at=clock_timestamp()
    where organization_id=p_organization_id and project_id=p_project_id
      and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
    return jsonb_build_object('complete',true,'replayed',true);
  end if;
  if parent.status not in ('handed_off','verifying') or parent.spec->>'verificationProfile'<>'automation' then
    raise exception 'OPS_REASONING_RDP_PARENT_VERIFICATION_FENCED'; end if;
  select * into child from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id and task_key=link.child_task_key;
  if not found or child.status<>'complete' then raise exception 'OPS_REASONING_RDP_CHILD_NOT_VERIFIED'; end if;

  evidence:=jsonb_build_object(
    'taskId',parent.task_key,'generation',parent.generation::text,'headSha',parent.head_sha,
    'taskSpecDigest',parent.spec_digest,'criteria',parent.spec->'acceptance',
    'ref','reasoning-rdp-parent:'||link.output_digest,
    'providerReadback',jsonb_build_object(
      'inferenceRequestId',link.inference_request_id,'reasoningOutputDigest',link.output_digest,
      'profile',link.profile,'childTaskId',link.child_task_key,
      'childVerificationRunId',child.verification->>'verificationRunId',
      'boundedPlanOnly',true,'arbitraryCommandAuthority',false
    )
  );
  recorded:=public.pandora_ops_record_verification_v1(
    p_organization_id,p_project_id,parent.task_key,parent.generation,
    p_verifier_key,p_verifier_principal,'PASS',evidence
  );
  accepted:=public.pandora_ops_verify_v1(
    p_organization_id,p_project_id,parent.task_key,parent.generation,
    p_verifier_key,p_verifier_principal,(recorded->>'verificationRunId')::uuid,
    evidence||jsonb_build_object('verificationRunId',recorded->>'verificationRunId')
  );
  update private.pandora_ops_reasoning_rdp_links set state='complete',updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;
  return accepted;
end;
$body$;

-- Expand the RDP registration contract for exact-source repo test/build profiles.
create or replace function public.pandora_ops_register_rdp_worker_v1(
  p_organization_id uuid,p_project_id uuid,p_worker_key text,p_principal_key text,
  p_lanes text[],p_capabilities text[],p_capacity integer,p_receipt_ref text
) returns jsonb
language plpgsql security definer set search_path=''
as $body$
begin
  perform 1 from private.pandora_ops_project_bindings
  where organization_id=p_organization_id and project_id=p_project_id and state='active'
  for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  if p_worker_key<>'pandora-rdp-windows-01'
     or p_principal_key<>'rdp:EC2AMAZ-SPAE2VG:operations-worker-v1'
     or p_capacity<>1
     or p_lanes<>array['reliability','mobile','backend','web']::text[]
     or p_capabilities<>array[
       'rdp.execute','rdp.toolchain.verify','rdp.github_runner.verify',
       'rdp.android.verify','rdp.flutter.verify','rdp.repo.test','rdp.repo.build','worker.reconcile'
     ]::text[]
     or p_receipt_ref<>'rdp:EC2AMAZ-SPAE2VG:scheduled-worker-v1'
  then raise exception 'OPS_RDP_WORKER_REGISTRATION_INVALID' using errcode='22023'; end if;

  insert into private.pandora_ops_workers(
    organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
    capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
  ) values(
    p_organization_id,p_project_id,p_worker_key,p_principal_key,'rdp',p_lanes,p_capabilities,
    1,true,true,'ready',clock_timestamp(),p_receipt_ref
  )
  on conflict(organization_id,project_id,worker_key) do update
  set engine='rdp',lanes=excluded.lanes,capabilities=excluded.capabilities,capacity=1,
      acknowledged=true,connected=true,health='ready',heartbeat_at=clock_timestamp(),
      registration_receipt=excluded.registration_receipt
  where private.pandora_ops_workers.principal_key=excluded.principal_key
    and private.pandora_ops_workers.engine='rdp';
  if not found then raise exception 'OPS_RDP_WORKER_IDENTITY_CONFLICT' using errcode='42501'; end if;
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'rdp-worker:'||p_worker_key,null,'worker_acknowledged',p_receipt_ref
  );
  return jsonb_build_object('registered',true,'engine','rdp','workerId',p_worker_key);
end;
$body$;

-- Restore a usable governed Gemini route while preserving the Bedrock catalog in provider hold.
do $policy$
declare current_policy jsonb;
declare bedrock_models jsonb;
declare gemini_models jsonb;
declare observed text:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
declare expires text:=to_char((clock_timestamp()+interval '30 days') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if exists(
    select 1 from private.pandora_ops_workspaces
    where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  ) then
    select policy into current_policy from private.pandora_ops_inference_policies
    where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid and active
    for update;
    if current_policy is not null then
      select coalesce(jsonb_agg(m order by m->>'model'),'[]'::jsonb) into bedrock_models
      from jsonb_array_elements(current_policy->'models') m where m->>'provider'<>'gemini';

      gemini_models:=jsonb_build_array(
        jsonb_build_object(
          'provider','gemini','model','gemini-3.5-flash-lite','modelRevision',null,
          'configurationDigest',encode(extensions.digest(convert_to('gemini-rpc|gemini-3.5-flash-lite|bridge-v1','UTF8'),'sha256'),'hex'),
          'classes',jsonb_build_array('structured_extraction','cheap_bulk','fast_coding','research'),
          'modalities',jsonb_build_array('text','image'),'executionBoundary','cloud','riskTier',2,
          'contextTokens',1000000,'maxInputBytes',1048576,'maxOutputTokens',8192,'imageTokenUpperBound',32768,
          'transport','gemini_rpc','approved',true,'approvalRef','owner:chat:2026-09-27:model-rdp-bridge',
          'approvalExpiresAt',expires,'available',true,'healthObservedAt',observed,
          'estimatedLatencyMs',null,'maxCostMicros',1000000,'maxConcurrency',2
        ),
        jsonb_build_object(
          'provider','gemini','model','gemini-3.7-flash','modelRevision',null,
          'configurationDigest',encode(extensions.digest(convert_to('gemini-rpc|gemini-3.7-flash|bridge-v1','UTF8'),'sha256'),'hex'),
          'classes',jsonb_build_array('structured_extraction','cheap_bulk','fast_coding','complex_coding','research','long_context','vision'),
          'modalities',jsonb_build_array('text','image'),'executionBoundary','cloud','riskTier',2,
          'contextTokens',1000000,'maxInputBytes',1048576,'maxOutputTokens',8192,'imageTokenUpperBound',32768,
          'transport','gemini_rpc','approved',true,'approvalRef','owner:chat:2026-09-27:model-rdp-bridge',
          'approvalExpiresAt',expires,'available',true,'healthObservedAt',observed,
          'estimatedLatencyMs',null,'maxCostMicros',1000000,'maxConcurrency',2
        ),
        jsonb_build_object(
          'provider','gemini','model','gemini-3.1-pro-preview','modelRevision',null,
          'configurationDigest',encode(extensions.digest(convert_to('gemini-rpc|gemini-3.1-pro-preview|bridge-v1','UTF8'),'sha256'),'hex'),
          'classes',jsonb_build_array('structured_extraction','complex_coding','deep_reasoning','research','long_context','vision','independent_verification'),
          'modalities',jsonb_build_array('text','image'),'executionBoundary','cloud','riskTier',3,
          'contextTokens',1000000,'maxInputBytes',1048576,'maxOutputTokens',8192,'imageTokenUpperBound',32768,
          'transport','gemini_rpc','approved',true,'approvalRef','owner:chat:2026-09-27:model-rdp-bridge',
          'approvalExpiresAt',expires,'available',true,'healthObservedAt',observed,
          'estimatedLatencyMs',null,'maxCostMicros',1000000,'maxConcurrency',1
        )
      );

      update private.pandora_ops_inference_policies
      set revision=revision+1,
          policy=jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(current_policy,'{version}',to_jsonb('operations-model-rdp-bridge-v1'::text),false),
                '{models}',bedrock_models||gemini_models,false
              ),
              '{allowedProviders}','["bedrock","gemini"]'::jsonb,false
            ),
            '{maxHealthAgeMs}','2592000000'::jsonb,false
          ),
          approval_ref='owner:chat:2026-09-27:model-rdp-bridge'
      where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
        and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid and active;
    end if;
  end if;
end;
$policy$;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
 ('operations_model_rdp_bridge','enabled','true',true,clock_timestamp()),
 ('operations_model_rdp_bridge','routing_mode','reason_then_bounded_rdp_child',true,clock_timestamp()),
 ('operations_model_rdp_bridge','risk_scope','read',true,clock_timestamp()),
 ('operations_model_rdp_bridge','verification_profile','automation',true,clock_timestamp()),
 ('operations_model_rdp_bridge','inference_budget_floor_micros','1000000',true,clock_timestamp()),
 ('operations_model_rdp_bridge','arbitrary_shell_allowed','false',true,clock_timestamp()),
 ('operations_model_rdp_bridge','source_mutation_allowed','false',true,clock_timestamp())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=true,updated_at=clock_timestamp();

-- Minute wake reuses the already-provisioned Operations HMAC secret.
create or replace function private.pandora_ops_emit_reasoning_rdp_bridge_wake_v1()
returns bigint
language plpgsql security definer
set search_path='pg_catalog','private','vault','extensions','net'
as $body$
declare
  v_secret text;
  v_timestamp text;
  v_nonce uuid:=gen_random_uuid();
  v_message text;
  v_signature text;
  v_request_id bigint;
begin
  select decrypted_secret into strict v_secret
  from vault.decrypted_secrets where name='pandora_ops_vercel_wake_hmac_v1' limit 1;
  if nullif(trim(v_secret),'') is null then raise exception 'OPS_WAKE_HMAC_SECRET_UNAVAILABLE' using errcode='55000'; end if;
  v_timestamp:=floor(extract(epoch from clock_timestamp()))::bigint::text;
  v_message:=v_timestamp||E'\n'||v_nonce::text||E'\nPOST\n/api/operations-reasoning-rdp-bridge\n{}';
  v_signature:=encode(extensions.hmac(convert_to(v_message,'UTF8'),convert_to(v_secret,'UTF8'),'sha256'),'hex');
  v_request_id:=net.http_post(
    url:='https://mcpmaster.vercel.app/api/operations-reasoning-rdp-bridge',
    body:='{}'::jsonb,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-pandora-wake-timestamp',v_timestamp,
      'x-pandora-wake-nonce',v_nonce::text,
      'x-pandora-wake-signature',v_signature
    ),
    timeout_milliseconds:=55000
  );
  v_secret:=null;v_message:=null;v_signature:=null;
  return v_request_id;
end;
$body$;

create or replace function private.pandora_ops_enable_reasoning_rdp_bridge_schedule_v1()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','private','vault','cron'
as $body$
declare v_job bigint;
begin
  if not exists(
    select 1 from vault.decrypted_secrets
    where name='pandora_ops_vercel_wake_hmac_v1' and nullif(trim(decrypted_secret),'') is not null
  ) then raise exception 'OPS_WAKE_HMAC_SECRET_UNAVAILABLE' using errcode='55000'; end if;
  if exists(select 1 from cron.job where jobname='pandora-operations-reasoning-rdp-bridge-v1') then
    perform cron.unschedule('pandora-operations-reasoning-rdp-bridge-v1');
  end if;
  v_job:=cron.schedule(
    'pandora-operations-reasoning-rdp-bridge-v1','* * * * *',
    'select private.pandora_ops_emit_reasoning_rdp_bridge_wake_v1();'
  );
  return jsonb_build_object('scheduled',true,'jobId',v_job,'schedule','* * * * *');
end;
$body$;

revoke all on function public.pandora_ops_register_reasoning_rdp_bridge_v1(uuid,uuid,text,text,text[],text[],integer,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_register_reasoning_rdp_bridge_v1(uuid,uuid,text,text,text[],text[],integer,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_candidate_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_candidate_v1(uuid,uuid,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_begin_v1(uuid,uuid,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_begin_v1(uuid,uuid,text,uuid,bigint,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_materialize_v1(uuid,uuid,text,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_materialize_v1(uuid,uuid,text,bigint,text,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_status_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_status_v1(uuid,uuid,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_verify_child_v1(uuid,uuid,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_verify_child_v1(uuid,uuid,text,bigint,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_parent_handoff_v1(uuid,uuid,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_parent_handoff_v1(uuid,uuid,text,bigint,text,text) to service_role;
revoke all on function public.pandora_ops_reasoning_rdp_verify_parent_v1(uuid,uuid,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_verify_parent_v1(uuid,uuid,text,bigint,text,text) to service_role;
revoke all on function private.pandora_ops_emit_reasoning_rdp_bridge_wake_v1() from public,anon,authenticated,service_role;
revoke all on function private.pandora_ops_enable_reasoning_rdp_bridge_schedule_v1() from public,anon,authenticated,service_role;
