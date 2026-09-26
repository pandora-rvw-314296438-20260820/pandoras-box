-- Operations Room generic source worker v1.
-- Provider credentials remain inside existing Supabase Vault transports.

create table if not exists private.pandora_ops_source_execution_receipts (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  generation bigint not null check (generation > 0),
  builder_worker_key text not null,
  builder_principal_key text not null,
  requested_base_sha text not null check (requested_base_sha ~ '^[0-9a-f]{40}$'),
  effective_base_sha text not null check (effective_base_sha ~ '^[0-9a-f]{40}$'),
  branch_name text not null,
  head_sha text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  pull_request integer not null check (pull_request > 0),
  pull_request_url text not null,
  provider_readback jsonb not null check (jsonb_typeof(provider_readback)='object'),
  authority_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,task_key,generation)
);
alter table private.pandora_ops_source_execution_receipts enable row level security;
revoke all on table private.pandora_ops_source_execution_receipts from public,anon,authenticated;

create table if not exists private.pandora_ops_source_release_state (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  generation bigint not null check (generation > 0),
  publish_request_id bigint,
  claim_request_id bigint,
  merge_sha text check (merge_sha is null or merge_sha ~ '^[0-9a-f]{40}$'),
  last_error text,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,task_key,generation)
);
alter table private.pandora_ops_source_release_state enable row level security;
revoke all on table private.pandora_ops_source_release_state from public,anon,authenticated;

create table if not exists private.pandora_ops_human_gates (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  gate_kind text not null check (gate_kind in ('owner_decision','privacy_approval','interactive_oauth','spend_authorization','client_authorization')),
  state text not null default 'blocked' check (state in ('blocked','approved','rejected')),
  evidence_ref text not null,
  decided_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,task_key)
);
alter table private.pandora_ops_human_gates enable row level security;
revoke all on table private.pandora_ops_human_gates from public,anon,authenticated;

insert into private.pandora_ops_human_gates(
  organization_id,project_id,task_key,gate_kind,state,evidence_ref
) values
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-003','owner_decision','blocked','facebook-tracker:FB-003:owner-ratification-required'),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-005','owner_decision','blocked','facebook-tracker:FB-005:scope-policy-required'),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-007','privacy_approval','blocked','facebook-tracker:FB-007:privacy-ratification-required'),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-011','interactive_oauth','blocked','facebook-tracker:FB-011:owner-oauth-required'),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-046','spend_authorization','blocked','facebook-tracker:FB-046:pilot-spend-authorization-required'),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','FB-059','client_authorization','blocked','facebook-tracker:FB-059:client-authorization-required')
on conflict (organization_id,project_id,task_key) do nothing;

create or replace function public.pandora_ops_generic_source_candidate_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  w private.pandora_ops_workspaces%rowtype;
  k private.pandora_ops_workers%rowtype;
  t private.pandora_ops_tasks%rowtype;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_GENERIC_SOURCE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  perform 1 from private.pandora_ops_project_bindings
    where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  select * into w from private.pandora_ops_workspaces
    where organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
  if w.paused then return jsonb_build_object('state','paused'); end if;

  select * into k from private.pandora_ops_workers
    where organization_id=p_organization_id and project_id=p_project_id
      and worker_key=p_worker_key and principal_key=p_principal_key;
  if not found or not k.acknowledged or not k.connected or k.health<>'ready'
     or k.heartbeat_at is null or k.heartbeat_at<clock_timestamp()-interval '60 seconds' then
    raise exception 'OPS_GENERIC_SOURCE_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select q.* into t
  from private.pandora_ops_tasks q
  where q.organization_id=p_organization_id and q.project_id=p_project_id
    and q.status='queued' and not q.cancel_requested
    and q.spec->>'risk'='source'
    and q.spec#>>'{source,repository}'='pandora-rvw-314296438-20260820/pandoras-box'
    and q.spec->>'lane'=any(k.lanes)
    and array(select jsonb_array_elements_text(q.spec->'requiredCapabilities')) <@ k.capabilities
    and q.attempts < (q.spec->>'maxAttempts')::integer
    and not exists (
      select 1 from private.pandora_ops_dependencies d
      join private.pandora_ops_tasks dep
        on dep.organization_id=d.organization_id and dep.project_id=d.project_id and dep.task_key=d.dependency_key
      where d.organization_id=q.organization_id and d.project_id=q.project_id
        and d.task_key=q.task_key and dep.status<>'complete'
    )
    and not exists (
      select 1 from private.pandora_ops_human_gates g
      where g.organization_id=q.organization_id and g.project_id=q.project_id
        and g.task_key=q.task_key and g.state<>'approved'
    )
  order by (q.spec->>'priority')::integer, q.queued_at, q.task_key
  limit 1;

  if not found then
    return jsonb_build_object(
      'state','idle',
      'reason','no_dependency_ready_authorized_source_task',
      'humanBlocked',(
        select count(*) from private.pandora_ops_tasks q
        join private.pandora_ops_human_gates g
          on g.organization_id=q.organization_id and g.project_id=q.project_id and g.task_key=q.task_key
        where q.organization_id=p_organization_id and q.project_id=p_project_id
          and q.status='queued' and g.state<>'approved'
      )
    );
  end if;

  return jsonb_build_object(
    'state','ready',
    'taskId',t.task_key,
    'taskRevision',t.revision,
    'controlRevision',w.revision,
    'spec',t.spec
  );
end;
$fn$;

revoke all on function public.pandora_ops_generic_source_candidate_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_generic_source_candidate_v1(uuid,uuid,text,text)
  to service_role;

create or replace function public.pandora_ops_generic_source_execute_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_task_key text,
  p_generation bigint,
  p_worker_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','auth','extensions','vault','pg_temp'
as $fn$
declare
  t private.pandora_ops_tasks%rowtype;
  l private.pandora_ops_leases%rowtype;
  k private.pandora_ops_workers%rowtype;
  existing private.pandora_ops_source_execution_receipts%rowtype;
  v_owner uuid;
  v_requested_base text;
  v_main text;
  v_effective_base text;
  v_compare jsonb;
  v_env jsonb;
  v_result jsonb;
  v_readback jsonb;
  v_message text;
  v_pr integer;
  v_branch text;
  v_head text;
  v_url text;
  v_files jsonb;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_GENERIC_SOURCE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  select * into existing from private.pandora_ops_source_execution_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=p_task_key and generation=p_generation;
  if found then
    return jsonb_build_object(
      'state','completed','replayed',true,'taskId',existing.task_key,
      'headSha',existing.head_sha,'pullRequest',existing.pull_request,
      'pullRequestUrl',existing.pull_request_url,'branch',existing.branch_name,
      'requestedBaseSha',existing.requested_base_sha,'effectiveBaseSha',existing.effective_base_sha,
      'providerReadback',existing.provider_readback,
      'receiptRef','ops-source:'||existing.task_key||':'||existing.generation::text||':'||existing.head_sha
    );
  end if;

  select * into t from private.pandora_ops_tasks
    where organization_id=p_organization_id and project_id=p_project_id and task_key=p_task_key for update;
  if not found or t.generation is distinct from p_generation or t.status<>'implementing'
     or t.cancel_requested or t.builder_worker_key is distinct from p_worker_key
     or t.builder_principal_key is distinct from p_principal_key then
    raise exception 'OPS_GENERIC_SOURCE_TASK_FENCED';
  end if;

  select * into k from private.pandora_ops_workers
    where organization_id=p_organization_id and project_id=p_project_id
      and worker_key=p_worker_key and principal_key=p_principal_key;
  if not found or not k.acknowledged or not k.connected or k.health<>'ready'
     or k.heartbeat_at is null or k.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not('source.write'=any(k.capabilities)) then
    raise exception 'OPS_GENERIC_SOURCE_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select * into l from private.pandora_ops_leases
    where organization_id=p_organization_id and project_id=p_project_id
      and task_key=p_task_key and generation=p_generation and worker_key=p_worker_key
      and state='running' and expires_at>clock_timestamp() for update;
  if not found then raise exception 'OPS_GENERIC_SOURCE_LEASE_REQUIRED'; end if;

  if t.spec->>'risk'<>'source'
     or t.spec#>>'{source,repository}'<>'pandora-rvw-314296438-20260820/pandoras-box'
     or exists (
       select 1 from private.pandora_ops_human_gates g
       where g.organization_id=p_organization_id and g.project_id=p_project_id
         and g.task_key=p_task_key and g.state<>'approved'
     ) then
    raise exception 'OPS_GENERIC_SOURCE_AUTHORITY_DENIED' using errcode='42501';
  end if;

  v_requested_base:=t.spec#>>'{source,baseSha}';
  if coalesce(v_requested_base,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'OPS_GENERIC_SOURCE_BASE_INVALID';
  end if;

  v_env:=private.pandora_integration_github_api_20260825(
    'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/git/ref/heads/main',null
  );
  if coalesce((v_env->>'status')::integer,0)<>200 then
    raise exception 'OPS_GENERIC_SOURCE_MAIN_READ_FAILED';
  end if;
  v_main:=v_env#>>'{body,object,sha}';
  if coalesce(v_main,'') !~ '^[0-9a-f]{40}$' then raise exception 'OPS_GENERIC_SOURCE_MAIN_INVALID'; end if;

  if v_main<>v_requested_base then
    v_compare:=private.pandora_integration_github_api_20260825(
      'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/compare/'||
        v_requested_base||'%2E%2E%2E'||v_main,null
    );
    if coalesce((v_compare->>'status')::integer,0)<>200
       or v_compare#>>'{body,status}' not in ('ahead','identical')
       or coalesce((v_compare#>>'{body,behind_by}')::integer,0)<>0 then
      raise exception 'OPS_GENERIC_SOURCE_BASE_DIVERGED';
    end if;
  end if;

  select m.user_id into v_owner
  from public.memberships m
  where m.organization_id=p_organization_id and m.status='active' and m.role in ('owner','admin')
  order by case when m.role='owner' then 0 else 1 end, m.user_id
  limit 1;
  if v_owner is null then raise exception 'OPS_GENERIC_SOURCE_OWNER_AUTHORITY_MISSING' using errcode='42501'; end if;
  perform set_config('request.jwt.claim.sub',v_owner::text,true);

  v_message:=left(
    'Operations Room task '||t.task_key||' generation '||t.generation::text||'. '||
    'Implement only this canonical pandoras-box source task. Title: '||(t.spec->>'title')||'. '||
    'Acceptance: '||coalesce((select string_agg(value,'; ') from jsonb_array_elements_text(t.spec->'acceptance')),'')||'. '||
    'Use the smallest safe exact-source change. Preserve authorization, tenant isolation, audit, verification, Vault boundaries and existing behavior. '||
    'Create a branch and pull request only. Do not merge, deploy, authorize spend, satisfy a human approval, or claim final verification.',
    7800
  );

  v_result:=private.pandora_direct_box_code_edit_v1(p_organization_id,v_message,null,null);
  v_readback:=v_result->'providerReadback';
  if v_result->'handled' is distinct from 'true'::jsonb
     or v_readback->'verified' is distinct from 'true'::jsonb
     or v_readback->>'repository'<>'pandora-rvw-314296438-20260820/pandoras-box'
     or v_readback->>'baseBranch'<>'main'
     or coalesce(v_readback->>'baseSha','') !~ '^[0-9a-f]{40}$'
     or coalesce(v_readback->>'commitSha','') !~ '^[0-9a-f]{40}$'
     or coalesce(v_readback->>'pullRequest','') !~ '^[1-9][0-9]{0,9}$'
     or v_readback->>'pullRequestState'<>'open' then
    raise exception 'OPS_GENERIC_SOURCE_PROVIDER_READBACK_INVALID';
  end if;

  v_effective_base:=v_readback->>'baseSha';
  v_head:=v_readback->>'commitSha';
  v_pr:=(v_readback->>'pullRequest')::integer;
  v_branch:=v_readback->>'branch';
  v_url:=v_readback->>'pullRequestUrl';
  v_files:=coalesce(v_readback->'files','[]'::jsonb);

  if v_effective_base<>v_requested_base then
    v_compare:=private.pandora_integration_github_api_20260825(
      'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/compare/'||
        v_requested_base||'%2E%2E%2E'||v_effective_base,null
    );
    if coalesce((v_compare->>'status')::integer,0)<>200
       or v_compare#>>'{body,status}' not in ('ahead','identical')
       or coalesce((v_compare#>>'{body,behind_by}')::integer,0)<>0 then
      raise exception 'OPS_GENERIC_SOURCE_EFFECTIVE_BASE_DIVERGED';
    end if;
  end if;

  insert into private.pandora_ops_source_execution_receipts(
    organization_id,project_id,task_key,generation,builder_worker_key,builder_principal_key,
    requested_base_sha,effective_base_sha,branch_name,head_sha,pull_request,pull_request_url,
    provider_readback,authority_ref
  ) values (
    p_organization_id,p_project_id,t.task_key,t.generation,p_worker_key,p_principal_key,
    v_requested_base,v_effective_base,v_branch,v_head,v_pr,v_url,v_readback,
    'operations-workspace:owner-authorized-source'
  );

  return jsonb_build_object(
    'state','completed','replayed',false,'taskId',t.task_key,'headSha',v_head,
    'pullRequest',v_pr,'pullRequestUrl',v_url,'branch',v_branch,'files',v_files,
    'requestedBaseSha',v_requested_base,'effectiveBaseSha',v_effective_base,
    'providerReadback',v_readback,
    'receiptRef','ops-source:'||t.task_key||':'||t.generation::text||':'||v_head
  );
end;
$fn$;

revoke all on function public.pandora_ops_generic_source_execute_v1(uuid,uuid,text,bigint,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_generic_source_execute_v1(uuid,uuid,text,bigint,text,text)
  to service_role;

create or replace function public.pandora_ops_generic_source_release_step_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_verifier_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','vault','extensions','net','pg_temp'
as $fn$
declare
  v_repo constant text:='pandora-rvw-314296438-20260820/pandoras-box';
  t private.pandora_ops_tasks%rowtype;
  verifier private.pandora_ops_workers%rowtype;
  src private.pandora_ops_source_execution_receipts%rowtype;
  rel private.pandora_ops_source_release_state%rowtype;
  v_pr_no integer;
  v_pr jsonb;
  v_pr_body jsonb;
  v_checks jsonb;
  v_pending integer;
  v_failed integer;
  v_success integer;
  v_coord jsonb;
  v_coord_row jsonb;
  v_coord_receipt jsonb;
  v_snapshot jsonb;
  v_internal_key text;
  v_envelope jsonb;
  v_request bigint;
  v_http_status integer;
  v_http_content text;
  v_merge jsonb;
  v_merge_sha text;
  v_main jsonb;
  v_main_sha text;
  v_compare jsonb;
  v_evidence jsonb;
  v_record jsonb;
  v_verification_id uuid;
  v_receipt jsonb;
  v_result jsonb;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_GENERIC_SOURCE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  select * into verifier from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_verifier_key and principal_key=p_principal_key;
  if not found or not verifier.acknowledged or not verifier.connected or verifier.health<>'ready'
     or verifier.heartbeat_at is null or verifier.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not('release'=any(verifier.lanes)) then
    raise exception 'OPS_GENERIC_SOURCE_RELEASE_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select q.* into t
  from private.pandora_ops_tasks q
  where q.organization_id=p_organization_id and q.project_id=p_project_id
    and q.status in ('handed_off','verifying')
    and q.spec->>'risk'='source'
    and q.spec#>>'{source,repository}'=v_repo
  order by q.queued_at,q.task_key
  limit 1;
  if not found then return jsonb_build_object('state','idle'); end if;

  select * into src from private.pandora_ops_source_execution_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=t.task_key and generation=t.generation;
  if not found or src.head_sha is distinct from t.head_sha
     or src.pull_request is distinct from nullif(t.handoff->>'pullRequest','')::integer then
    raise exception 'OPS_GENERIC_SOURCE_EXECUTION_RECEIPT_MISSING';
  end if;
  v_pr_no:=src.pull_request;

  insert into private.pandora_ops_source_release_state(
    organization_id,project_id,task_key,generation
  ) values (p_organization_id,p_project_id,t.task_key,t.generation)
  on conflict do nothing;
  select * into rel from private.pandora_ops_source_release_state
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=t.task_key and generation=t.generation for update;

  v_pr:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/pulls/'||v_pr_no::text,null
  );
  if coalesce((v_pr->>'status')::integer,0)<>200 then
    raise exception 'OPS_GENERIC_SOURCE_PR_READBACK_FAILED';
  end if;
  v_pr_body:=coalesce(v_pr->'body','{}'::jsonb);
  if v_pr_body#>>'{head,sha}' is distinct from t.head_sha
     or v_pr_body#>>'{base,ref}' is distinct from 'main'
     or v_pr_body#>>'{base,sha}' is distinct from src.effective_base_sha then
    raise exception 'OPS_GENERIC_SOURCE_PR_IDENTITY_MISMATCH';
  end if;

  v_checks:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/commits/'||t.head_sha||'/check-runs?per_page=100',null
  );
  if coalesce((v_checks->>'status')::integer,0)<>200 then
    raise exception 'OPS_GENERIC_SOURCE_CHECK_READBACK_FAILED';
  end if;
  select
    count(*) filter(where c->>'name'<>'Pandora coordinator / integration' and c->>'status'<>'completed'),
    count(*) filter(where c->>'name'<>'Pandora coordinator / integration'
      and c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped')),
    count(*) filter(where c->>'name'<>'Pandora coordinator / integration'
      and c->>'status'='completed' and c->>'conclusion'='success')
  into v_pending,v_failed,v_success
  from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;

  if v_failed<>0 then
    return jsonb_build_object('state','checks_failed','taskId',t.task_key,'pullRequest',v_pr_no);
  end if;
  if v_pending<>0 or v_success=0 then
    return jsonb_build_object('state','checks_pending','taskId',t.task_key,'pullRequest',v_pr_no);
  end if;

  v_coord:=public.pandora_coordinator_vault_merge_status_v1(v_pr_no);
  v_coord_row:=v_coord->'coordinator';
  v_coord_receipt:=v_coord->'receipt';

  if v_coord_row is null or v_coord_row='null'::jsonb then
    if rel.publish_request_id is null then
      select decrypted_secret into strict v_internal_key
      from vault.decrypted_secrets where name=('pandora_coordinator_gate_'||'internal_v1') limit 1;
      v_snapshot:=public.pandora_coordinator_snapshot_read_effective_v1(v_internal_key,v_repo);
      if v_snapshot is null or v_snapshot->>'fenceState'<>'idle' then
        return jsonb_build_object('state','coordinator_busy','taskId',t.task_key);
      end if;
      v_envelope:=jsonb_build_object(
        'schemaVersion',1,
        'repositoryId',1345495177,
        'repository',v_repo,
        'pullRequestNumber',v_pr_no,
        'headSha',t.head_sha,
        'baseRef','main',
        'baseSha',src.effective_base_sha,
        'rulesetId',21532267,
        'ruleContext','Pandora coordinator / integration',
        'integrationAppId',4785021,
        'spreadsheetId',v_snapshot->>'spreadsheetId',
        'authoritativeSnapshotGeneration',(v_snapshot->>'snapshotGeneration')::bigint,
        'authoritativeSnapshotRevision',v_snapshot->>'snapshotRevision',
        'authoritativeSnapshotSha256',v_snapshot->>'snapshotSha256',
        'criticalHighHoldDispositions','[]'::jsonb,
        'policyVersion','ops-generic-source-v1',
        'decisionGeneration',1,
        'priorGeneration',null,
        'priorCheckRunId',null,
        'decision','PASS',
        'reasons',jsonb_build_array(
          'Operations source task has a durable lease-bound provider execution receipt.',
          'All observed non-coordinator exact-head check runs are terminal and acceptable.',
          'Human, privacy, OAuth and spend gates are excluded from generic source execution.'
        ),
        'reviewId','not-required-by-ruleset',
        'reviewerVendor','github',
        'reviewCandidateSha',t.head_sha,
        'decisionNonce','ops-source-'||t.task_key||'-'||t.generation::text||'-'||gen_random_uuid()::text,
        'evaluatedAt',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'expiresAt',to_char((clock_timestamp()+interval '10 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      );
      v_request:=private.pandora_coordinator_gate_invoke_v1(
        jsonb_build_object('action','publish','envelope',v_envelope)
      );
      update private.pandora_ops_source_release_state
       set publish_request_id=v_request,updated_at=clock_timestamp()
       where organization_id=p_organization_id and project_id=p_project_id
         and task_key=t.task_key and generation=t.generation;
      return jsonb_build_object('state','coordinator_publishing','taskId',t.task_key,'requestId',v_request);
    end if;

    select status_code,content into v_http_status,v_http_content
    from net._http_response where id=rel.publish_request_id;
    if not found then
      return jsonb_build_object('state','coordinator_publishing','taskId',t.task_key,'requestId',rel.publish_request_id);
    end if;
    if v_http_status<>200 then
      update private.pandora_ops_source_release_state
       set last_error='coordinator_publish_http_'||v_http_status::text,updated_at=clock_timestamp()
       where organization_id=p_organization_id and project_id=p_project_id
         and task_key=t.task_key and generation=t.generation;
      return jsonb_build_object('state','coordinator_blocked','taskId',t.task_key,'httpStatus',v_http_status);
    end if;
    update private.pandora_ops_source_release_state
     set publish_request_id=null,last_error=null,updated_at=clock_timestamp()
     where organization_id=p_organization_id and project_id=p_project_id
       and task_key=t.task_key and generation=t.generation;
    v_coord:=public.pandora_coordinator_vault_merge_status_v1(v_pr_no);
    v_coord_row:=v_coord->'coordinator';
    if v_coord_row is null or v_coord_row='null'::jsonb then
      return jsonb_build_object('state','coordinator_publishing','taskId',t.task_key);
    end if;
  end if;

  if v_coord_row->>'decision'<>'PASS'
     or v_coord_row->>'providerStatus'<>'completed'
     or v_coord_row->>'providerConclusion'<>'success'
     or v_coord_row->>'headSha' is distinct from t.head_sha then
    return jsonb_build_object('state','coordinator_blocked','taskId',t.task_key,'decision',v_coord_row->>'decision');
  end if;

  if v_coord_row->>'claimId' is null then
    select * into rel from private.pandora_ops_source_release_state
     where organization_id=p_organization_id and project_id=p_project_id
       and task_key=t.task_key and generation=t.generation for update;
    if rel.claim_request_id is null then
      v_request:=private.pandora_coordinator_gate_invoke_v1(
        jsonb_build_object('action','claimMerge','pullRequestNumber',v_pr_no)
      );
      update private.pandora_ops_source_release_state
       set claim_request_id=v_request,updated_at=clock_timestamp()
       where organization_id=p_organization_id and project_id=p_project_id
         and task_key=t.task_key and generation=t.generation;
      return jsonb_build_object('state','coordinator_claiming','taskId',t.task_key,'requestId',v_request);
    end if;
    select status_code,content into v_http_status,v_http_content
    from net._http_response where id=rel.claim_request_id;
    if not found then
      return jsonb_build_object('state','coordinator_claiming','taskId',t.task_key,'requestId',rel.claim_request_id);
    end if;
    if v_http_status<>200 then
      update private.pandora_ops_source_release_state
       set last_error='coordinator_claim_http_'||v_http_status::text,updated_at=clock_timestamp()
       where organization_id=p_organization_id and project_id=p_project_id
         and task_key=t.task_key and generation=t.generation;
      return jsonb_build_object('state','coordinator_blocked','taskId',t.task_key,'httpStatus',v_http_status);
    end if;
    update private.pandora_ops_source_release_state
     set claim_request_id=null,last_error=null,updated_at=clock_timestamp()
     where organization_id=p_organization_id and project_id=p_project_id
       and task_key=t.task_key and generation=t.generation;
    v_coord:=public.pandora_coordinator_vault_merge_status_v1(v_pr_no);
    v_coord_row:=v_coord->'coordinator';
    if v_coord_row->>'claimId' is null then
      return jsonb_build_object('state','coordinator_claiming','taskId',t.task_key);
    end if;
  end if;

  v_coord_receipt:=v_coord->'receipt';
  if v_coord_receipt is null or v_coord_receipt='null'::jsonb then
    v_merge:=public.pandora_coordinator_vault_merge_v1(v_pr_no,t.head_sha);
    v_merge_sha:=v_merge->>'mergeSha';
    if coalesce(v_merge_sha,'') !~ '^[0-9a-f]{40}$'
       or v_merge->'providerReadbackVerified' is distinct from 'true'::jsonb then
      raise exception 'OPS_GENERIC_SOURCE_MERGE_READBACK_FAILED';
    end if;
    update private.pandora_ops_source_release_state
     set merge_sha=v_merge_sha,last_error=null,updated_at=clock_timestamp()
     where organization_id=p_organization_id and project_id=p_project_id
       and task_key=t.task_key and generation=t.generation;
    v_coord:=public.pandora_coordinator_vault_merge_status_v1(v_pr_no);
    v_coord_receipt:=v_coord->'receipt';
  end if;

  v_merge_sha:=coalesce(v_coord_receipt->>'mergeSha',
    (select merge_sha from private.pandora_ops_source_release_state
      where organization_id=p_organization_id and project_id=p_project_id
        and task_key=t.task_key and generation=t.generation));
  if coalesce(v_merge_sha,'') !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object('state','merge_readback_pending','taskId',t.task_key);
  end if;

  v_pr:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/pulls/'||v_pr_no::text,null
  );
  if coalesce((v_pr->>'status')::integer,0)<>200
     or v_pr#>>'{body,merged}'<>'true'
     or v_pr#>>'{body,head,sha}' is distinct from t.head_sha then
    raise exception 'OPS_GENERIC_SOURCE_POST_MERGE_PR_MISMATCH';
  end if;

  v_checks:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/commits/'||t.head_sha||'/check-runs?per_page=100',null
  );
  select
    count(*) filter(where c->>'status'<>'completed'),
    count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
  into v_pending,v_failed
  from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;
  if v_pending<>0 or v_failed<>0
     or not exists(
       select 1 from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c
       where c->>'name'='Pandora coordinator / integration' and c->>'conclusion'='success'
     ) then
    return jsonb_build_object('state','post_merge_checks_pending','taskId',t.task_key);
  end if;

  v_main:=private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/branches/main',null
  );
  if coalesce((v_main->>'status')::integer,0)<>200 then raise exception 'OPS_GENERIC_SOURCE_MAIN_READBACK_FAILED'; end if;
  v_main_sha:=v_main#>>'{body,commit,sha}';
  if v_main_sha<>v_merge_sha then
    v_compare:=private.pandora_integration_github_api_20260825(
      'GET','/repos/'||v_repo||'/compare/'||v_merge_sha||'%2E%2E%2E'||v_main_sha,null
    );
    if coalesce((v_compare->>'status')::integer,0)<>200
       or v_compare#>>'{body,status}' not in ('ahead','identical')
       or coalesce((v_compare#>>'{body,behind_by}')::integer,0)<>0 then
      raise exception 'OPS_GENERIC_SOURCE_MAIN_READBACK_MISMATCH';
    end if;
  end if;

  v_evidence:=jsonb_build_object(
    'taskId',t.task_key,
    'generation',t.generation::text,
    'headSha',t.head_sha,
    'taskSpecDigest',t.spec_digest,
    'criteria',t.spec->'acceptance',
    'ref','ops-generic-source-release:'||t.task_key||':'||t.generation::text||':'||t.head_sha,
    'providerReadback',jsonb_build_object(
      'pullRequest',v_pr_no,
      'pullRequestHead',t.head_sha,
      'mergeSha',v_merge_sha,
      'mainShaAtReadback',v_main_sha,
      'coordinator','success',
      'credentialSource','supabase-vault',
      'requestedBaseSha',src.requested_base_sha,
      'effectiveBaseSha',src.effective_base_sha,
      'branch',src.branch_name,
      'files',src.provider_readback->'files'
    )
  );
  v_record:=public.pandora_ops_record_verification_v1(
    p_organization_id,p_project_id,t.task_key,t.generation,p_verifier_key,p_principal_key,'PASS',v_evidence
  );
  v_verification_id:=(v_record->>'verificationRunId')::uuid;
  v_receipt:=v_evidence||jsonb_build_object('verificationRunId',v_verification_id::text);
  v_result:=public.pandora_ops_verify_v1(
    p_organization_id,p_project_id,t.task_key,t.generation,p_verifier_key,p_principal_key,v_verification_id,v_receipt
  );
  return v_result||jsonb_build_object(
    'state','complete','taskId',t.task_key,'pullRequest',v_pr_no,'mergeSha',v_merge_sha,
    'providerReadbackVerified',true
  );
end;
$fn$;

revoke all on function public.pandora_ops_generic_source_release_step_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_generic_source_release_step_v1(uuid,uuid,text,text)
  to service_role;
