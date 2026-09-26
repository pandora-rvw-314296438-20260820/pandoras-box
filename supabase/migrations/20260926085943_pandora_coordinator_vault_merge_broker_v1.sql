-- Permanent Vault-backed GitHub merge broker for canonical Pandora.
-- Executes only a live coordinator PASS + exact merge claim; PAT remains inside Supabase Vault.


create table if not exists private.pandora_coordinator_vault_merge_receipts (
  id uuid primary key default gen_random_uuid(),
  repository text not null,
  pull_request_number integer not null check (pull_request_number > 0),
  decision_generation bigint not null check (decision_generation > 0),
  claim_id uuid not null,
  coordinator_check_run_id bigint not null check (coordinator_check_run_id > 0),
  head_sha text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  base_sha text not null check (base_sha ~ '^[0-9a-f]{40}$'),
  merge_sha text not null check (merge_sha ~ '^[0-9a-f]{40}$'),
  mode text not null check (mode in ('merged','recovered')),
  provider_readback jsonb not null,
  completed_at timestamptz not null default clock_timestamp(),
  unique (repository, pull_request_number, claim_id)
);
alter table private.pandora_coordinator_vault_merge_receipts enable row level security;
revoke all on private.pandora_coordinator_vault_merge_receipts from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.pandora_reject_coordinator_vault_merge_receipt_mutation_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_RECEIPT_IMMUTABLE'
    using errcode='55000';
end;
$function$



drop trigger if exists pandora_coordinator_vault_merge_receipt_immutable_v1
on private.pandora_coordinator_vault_merge_receipts;
create trigger pandora_coordinator_vault_merge_receipt_immutable_v1
before update or delete on private.pandora_coordinator_vault_merge_receipts
for each row execute function private.pandora_reject_coordinator_vault_merge_receipt_mutation_v1();
revoke all on function private.pandora_reject_coordinator_vault_merge_receipt_mutation_v1()
from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.pandora_coordinator_vault_merge_execute_v1(p_pull_request_number integer, p_expected_head_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'vault', 'extensions'
AS $function$
declare
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box';
  v_app_id constant bigint := 4785021;
  v_rule_context constant text := 'Pandora coordinator / integration';
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_fence private.pandora_coordinator_repository_fence%rowtype;
  v_existing private.pandora_coordinator_vault_merge_receipts%rowtype;
  v_internal_key text;
  v_pr jsonb;
  v_check jsonb;
  v_checks jsonb;
  v_merge jsonb;
  v_commit jsonb;
  v_main jsonb;
  v_compare jsonb;
  v_commits jsonb;
  v_merge_sha text;
  v_main_sha text;
  v_mode text := 'merged';
  v_pending integer := 0;
  v_failed integer := 0;
  v_parent_head integer := 0;
  v_parent_base integer := 0;
  v_total_checks integer := 0;
  v_pr_merged boolean := false;
  v_merged_at timestamptz;
  v_complete jsonb;
  v_readback jsonb;
begin
  if p_pull_request_number is null or p_pull_request_number < 1
     or p_expected_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_INPUT_INVALID'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('pandora-coordinator-vault-merge:'||v_repo,0)
  );

  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=v_repo and pull_request_number=p_pull_request_number
  for update;
  if not found then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_STATE_MISSING';
  end if;

  select * into v_fence
  from private.pandora_coordinator_repository_fence
  where repository=v_repo
  for update;
  if not found then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_FENCE_MISSING';
  end if;

  if v_state.head_sha is distinct from p_expected_head_sha
     or v_state.decision<>'PASS'
     or v_state.provider_status<>'completed'
     or v_state.provider_conclusion<>'success'
     or v_state.current_check_run_id is null
     or v_state.merge_claim_id is null then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_NOT_AUTHORIZED'
      using errcode='42501';
  end if;

  if v_fence.fence_state<>'merging'
     or v_fence.active_merge_claim_id is distinct from v_state.merge_claim_id
     or v_fence.active_merge_pull_request_number is distinct from p_pull_request_number
     or v_fence.effective_snapshot_generation is distinct from v_state.authoritative_snapshot_generation
     or v_fence.effective_snapshot_revision is distinct from v_state.authoritative_snapshot_revision
     or v_fence.effective_snapshot_sha256 is distinct from v_state.authoritative_snapshot_sha256 then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_FENCE_MISMATCH'
      using errcode='23505';
  end if;

  select * into v_existing
  from private.pandora_coordinator_vault_merge_receipts
  where repository=v_repo
    and pull_request_number=p_pull_request_number
    and claim_id=v_state.merge_claim_id;
  if found then
    if v_existing.head_sha is distinct from p_expected_head_sha then
      raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_REPLAY_CONFLICT'
        using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'mode','replay','pullRequestNumber',p_pull_request_number,
      'headSha',v_existing.head_sha,'mergeSha',v_existing.merge_sha,
      'claimId',v_existing.claim_id,'receiptId',v_existing.id
    );
  end if;

  if v_state.consumed_at is not null then
    if v_state.merged_sha !~ '^[0-9a-f]{40}$' then
      raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_CONSUMED_WITHOUT_SHA';
    end if;
    return jsonb_build_object(
      'ok',true,'mode','coordinator_replay','pullRequestNumber',p_pull_request_number,
      'headSha',v_state.head_sha,'mergeSha',v_state.merged_sha,
      'claimId',v_state.merge_claim_id
    );
  end if;

  perform 1
  from vault.decrypted_secrets
  where name='Github_supabase'
    and nullif(btrim(decrypted_secret),'') is not null;
  if not found then
    raise exception 'PANDORA_COORDINATOR_VAULT_GITHUB_CREDENTIAL_UNAVAILABLE'
      using errcode='55000';
  end if;

  select decrypted_secret into strict v_internal_key
  from vault.decrypted_secrets
  where name='pandora_coordinator_gate_internal_v1'
  limit 1;
  if nullif(btrim(v_internal_key),'') is null
     or not public.pandora_validate_coordinator_gate_key_v1(v_internal_key) then
    raise exception 'PANDORA_COORDINATOR_INTERNAL_KEY_UNAVAILABLE'
      using errcode='55000';
  end if;

  v_pr := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/pulls/'||p_pull_request_number::text,null
  );
  if (v_pr->>'status')::integer<>200
     or v_pr#>>'{body,number}' is distinct from p_pull_request_number::text
     or v_pr#>>'{body,head,sha}' is distinct from p_expected_head_sha
     or v_pr#>>'{body,base,ref}' is distinct from 'main'
     or v_pr#>>'{body,base,sha}' is distinct from v_state.base_sha
     or coalesce((v_pr#>>'{body,draft}')::boolean,false) then
    raise exception 'PANDORA_COORDINATOR_VAULT_PR_IDENTITY_MISMATCH';
  end if;

  v_pr_merged := coalesce((v_pr#>>'{body,merged}')::boolean,false);
  if v_pr#>>'{body,merged_at}' is not null then
    v_merged_at := (v_pr#>>'{body,merged_at}')::timestamptz;
  end if;

  if not v_pr_merged then
    if v_state.expires_at<=clock_timestamp() then
      raise exception 'PANDORA_COORDINATOR_VAULT_CLAIM_EXPIRED'
        using errcode='55000';
    end if;
    if v_pr#>>'{body,state}' is distinct from 'open'
       or coalesce((v_pr#>>'{body,mergeable}')::boolean,false) is not true
       or v_pr#>>'{body,mergeable_state}' is distinct from 'clean' then
      raise exception 'PANDORA_COORDINATOR_VAULT_PR_NOT_CLEAN'
        using errcode='55000';
    end if;
  elsif v_state.expires_at<=clock_timestamp()
        and (v_merged_at is null or v_merged_at>v_state.expires_at) then
    raise exception 'PANDORA_COORDINATOR_VAULT_EXPIRED_AMBIGUOUS_MERGE'
      using errcode='55000';
  end if;

  v_check := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/check-runs/'||v_state.current_check_run_id::text,null
  );
  if (v_check->>'status')::integer<>200
     or v_check#>>'{body,id}' is distinct from v_state.current_check_run_id::text
     or v_check#>>'{body,name}' is distinct from v_rule_context
     or v_check#>>'{body,head_sha}' is distinct from p_expected_head_sha
     or v_check#>>'{body,status}' is distinct from 'completed'
     or v_check#>>'{body,conclusion}' is distinct from 'success'
     or coalesce((v_check#>>'{body,app,id}')::bigint,0)<>v_app_id then
    raise exception 'PANDORA_COORDINATOR_VAULT_CHECK_IDENTITY_MISMATCH';
  end if;

  v_checks := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/commits/'||p_expected_head_sha||'/check-runs?per_page=100',null
  );
  if (v_checks->>'status')::integer<>200 then
    raise exception 'PANDORA_COORDINATOR_VAULT_CHECK_READBACK_FAILED';
  end if;
  v_total_checks := coalesce((v_checks#>>'{body,total_count}')::integer,0);
  if v_total_checks>100 then
    raise exception 'PANDORA_COORDINATOR_VAULT_CHECK_SET_UNBOUNDED';
  end if;
  select
    count(*) filter(
      where c->>'status'<>'completed'
        and not (
          c->>'name'=v_rule_context
          and coalesce((c->>'id')::bigint,0)<>v_state.current_check_run_id
        )
    ),
    count(*) filter(
      where c->>'status'='completed'
        and coalesce(c->>'conclusion','') not in ('success','neutral','skipped')
        and not (
          c->>'name'=v_rule_context
          and coalesce((c->>'id')::bigint,0)<>v_state.current_check_run_id
        )
    )
  into v_pending,v_failed
  from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;
  if v_pending<>0 or v_failed<>0 then
    raise exception 'PANDORA_COORDINATOR_VAULT_CHECKS_NOT_GREEN';
  end if;

  v_main := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/branches/main',null
  );
  if (v_main->>'status')::integer<>200 then
    raise exception 'PANDORA_COORDINATOR_VAULT_MAIN_READBACK_FAILED';
  end if;
  v_main_sha := v_main#>>'{body,commit,sha}';

  if not v_pr_merged then
    if v_main_sha is distinct from v_state.base_sha then
      raise exception 'PANDORA_COORDINATOR_VAULT_MAIN_MOVED'
        using errcode='40001';
    end if;

    v_merge := private.pandora_integration_github_api_20260825(
      'PUT',
      '/repos/'||v_repo||'/pulls/'||p_pull_request_number::text||'/merge',
      jsonb_build_object(
        'sha',p_expected_head_sha,
        'merge_method','merge',
        'commit_title','Pandora governed merge PR #'||p_pull_request_number::text,
        'commit_message','Coordinator PASS '||v_state.current_check_run_id::text||
          '; claim '||v_state.merge_claim_id::text||'; exact head '||p_expected_head_sha||'.'
      )
    );

    if (v_merge->>'status')::integer<>200
       or coalesce((v_merge#>>'{body,merged}')::boolean,false) is not true
       or coalesce(v_merge#>>'{body,sha}','') !~ '^[0-9a-f]{40}$' then
      v_pr := private.pandora_integration_github_api_20260825(
        'GET','/repos/'||v_repo||'/pulls/'||p_pull_request_number::text,null
      );
      if (v_pr->>'status')::integer<>200
         or coalesce((v_pr#>>'{body,merged}')::boolean,false) is not true then
        raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_REJECTED';
      end if;
      v_mode := 'recovered';
    else
      v_merge_sha := v_merge#>>'{body,sha}';
    end if;
  else
    v_mode := 'recovered';
  end if;

  if v_merge_sha is null then
    if coalesce(v_pr#>>'{body,merge_commit_sha}','') ~ '^[0-9a-f]{40}$' then
      v_merge_sha := v_pr#>>'{body,merge_commit_sha}';
    else
      v_commits := private.pandora_integration_github_api_20260825(
        'GET','/repos/'||v_repo||'/commits?sha=main&per_page=100',null
      );
      if (v_commits->>'status')::integer<>200
         or jsonb_typeof(v_commits->'body') is distinct from 'array' then
        raise exception 'PANDORA_COORDINATOR_VAULT_RECOVERY_HISTORY_UNAVAILABLE';
      end if;
      select c->>'sha' into v_merge_sha
      from jsonb_array_elements(v_commits->'body') c
      where coalesce(c->>'sha','') ~ '^[0-9a-f]{40}$'
        and exists(
          select 1 from jsonb_array_elements(coalesce(c->'parents','[]'::jsonb)) p
          where p->>'sha'=p_expected_head_sha
        )
        and exists(
          select 1 from jsonb_array_elements(coalesce(c->'parents','[]'::jsonb)) p
          where p->>'sha'=v_state.base_sha
        )
      limit 1;
    end if;
  end if;

  if coalesce(v_merge_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_SHA_UNRESOLVED';
  end if;

  v_commit := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/commits/'||v_merge_sha,null
  );
  if (v_commit->>'status')::integer<>200
     or v_commit#>>'{body,sha}' is distinct from v_merge_sha
     or v_commit#>>'{body,commit,verification,verified}' <> 'true' then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_COMMIT_INVALID';
  end if;
  select count(*) into v_parent_head
  from jsonb_array_elements(coalesce(v_commit#>'{body,parents}','[]'::jsonb)) p
  where p->>'sha'=p_expected_head_sha;
  select count(*) into v_parent_base
  from jsonb_array_elements(coalesce(v_commit#>'{body,parents}','[]'::jsonb)) p
  where p->>'sha'=v_state.base_sha;
  if v_parent_head<>1 or v_parent_base<>1 then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_PARENT_MISMATCH';
  end if;

  v_pr := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/pulls/'||p_pull_request_number::text,null
  );
  if (v_pr->>'status')::integer<>200
     or coalesce((v_pr#>>'{body,merged}')::boolean,false) is not true
     or v_pr#>>'{body,head,sha}' is distinct from p_expected_head_sha then
    raise exception 'PANDORA_COORDINATOR_VAULT_POST_MERGE_PR_MISMATCH';
  end if;

  v_main := private.pandora_integration_github_api_20260825(
    'GET','/repos/'||v_repo||'/branches/main',null
  );
  if (v_main->>'status')::integer<>200 then
    raise exception 'PANDORA_COORDINATOR_VAULT_POST_MERGE_MAIN_UNAVAILABLE';
  end if;
  v_main_sha := v_main#>>'{body,commit,sha}';
  if v_main_sha is distinct from v_merge_sha then
    v_compare := private.pandora_integration_github_api_20260825(
      'GET','/repos/'||v_repo||'/compare/'||v_merge_sha||'%2E%2E%2E'||v_main_sha,null
    );
    if (v_compare->>'status')::integer<>200
       or v_compare#>>'{body,status}' not in ('ahead','identical')
       or coalesce((v_compare#>>'{body,behind_by}')::integer,0)<>0 then
      raise exception 'PANDORA_COORDINATOR_VAULT_POST_MERGE_MAIN_MISMATCH';
    end if;
  end if;

  v_complete := public.pandora_coordinator_gate_complete_merge_v2(
    v_internal_key,
    v_repo,
    p_pull_request_number,
    v_state.current_generation,
    v_state.merge_claim_id,
    v_merge_sha
  );

  v_readback := jsonb_build_object(
    'coordinatorDecision','PASS',
    'coordinatorCheckRunId',v_state.current_check_run_id,
    'coordinatorCheckAppId',v_app_id,
    'headSha',p_expected_head_sha,
    'baseSha',v_state.base_sha,
    'mergeSha',v_merge_sha,
    'mainShaAtReadback',v_main_sha,
    'mergeCommitVerified',true,
    'mergeParentsVerified',true,
    'pullRequestMerged',true,
    'allObservedChecksTerminal',v_pending=0,
    'allObservedChecksAcceptable',v_failed=0,
    'observedCheckCount',v_total_checks,
    'coordinatorCompletion',v_complete
  );

  insert into private.pandora_coordinator_vault_merge_receipts(
    repository,pull_request_number,decision_generation,claim_id,
    coordinator_check_run_id,head_sha,base_sha,merge_sha,mode,provider_readback
  ) values (
    v_repo,p_pull_request_number,v_state.current_generation,v_state.merge_claim_id,
    v_state.current_check_run_id,p_expected_head_sha,v_state.base_sha,v_merge_sha,v_mode,v_readback
  )
  returning id into v_existing.id;

  return jsonb_build_object(
    'ok',true,
    'mode',v_mode,
    'pullRequestNumber',p_pull_request_number,
    'headSha',p_expected_head_sha,
    'mergeSha',v_merge_sha,
    'claimId',v_state.merge_claim_id,
    'coordinatorCheckRunId',v_state.current_check_run_id,
    'receiptId',v_existing.id,
    'credentialSource','supabase-vault',
    'providerReadbackVerified',true
  );
end;
$function$


revoke all on function private.pandora_coordinator_vault_merge_execute_v1(integer,text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.pandora_coordinator_vault_merge_v1(p_pull_request_number integer, p_expected_head_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'PANDORA_COORDINATOR_VAULT_MERGE_SERVICE_ROLE_REQUIRED'
      using errcode='42501';
  end if;
  return private.pandora_coordinator_vault_merge_execute_v1(
    p_pull_request_number,p_expected_head_sha
  );
end;
$function$


revoke all on function public.pandora_coordinator_vault_merge_v1(integer,text) from public, anon, authenticated;
grant execute on function public.pandora_coordinator_vault_merge_v1(integer,text) to service_role;

CREATE OR REPLACE FUNCTION public.pandora_coordinator_vault_merge_status_v1(p_pull_request_number integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'coordinator',(
      select jsonb_build_object(
        'decision',s.decision,
        'generation',s.current_generation,
        'headSha',s.head_sha,
        'baseSha',s.base_sha,
        'checkRunId',s.current_check_run_id,
        'providerStatus',s.provider_status,
        'providerConclusion',s.provider_conclusion,
        'claimId',s.merge_claim_id,
        'claimExpiresAt',s.expires_at,
        'consumedAt',s.consumed_at,
        'mergedSha',s.merged_sha
      )
      from private.pandora_coordinator_gate_state s
      where s.repository='pandora-rvw-314296438-20260820/pandoras-box'
        and s.pull_request_number=p_pull_request_number
    ),
    'receipt',(
      select jsonb_build_object(
        'receiptId',r.id,
        'headSha',r.head_sha,
        'baseSha',r.base_sha,
        'mergeSha',r.merge_sha,
        'mode',r.mode,
        'providerReadback',r.provider_readback,
        'completedAt',r.completed_at
      )
      from private.pandora_coordinator_vault_merge_receipts r
      where r.repository='pandora-rvw-314296438-20260820/pandoras-box'
        and r.pull_request_number=p_pull_request_number
      order by r.completed_at desc
      limit 1
    )
  );
$function$


revoke all on function public.pandora_coordinator_vault_merge_status_v1(integer) from public, anon, authenticated;
grant execute on function public.pandora_coordinator_vault_merge_status_v1(integer) to service_role;

CREATE OR REPLACE FUNCTION private.pandora_coordinator_vault_merge_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_target private.pandora_coordinator_gate_state%rowtype;
begin
  if not pg_try_advisory_xact_lock(
    hashtextextended('pandora-coordinator-vault-merge-tick-v1',0)
  ) then
    return jsonb_build_object('ok',true,'state','busy');
  end if;

  select s.* into v_target
  from private.pandora_coordinator_gate_state s
  join private.pandora_coordinator_repository_fence f
    on f.repository=s.repository
  where s.repository='pandora-rvw-314296438-20260820/pandoras-box'
    and s.decision='PASS'
    and s.provider_status='completed'
    and s.provider_conclusion='success'
    and s.consumed_at is null
    and s.merge_claim_id is not null
    and f.fence_state='merging'
    and f.active_merge_claim_id=s.merge_claim_id
    and f.active_merge_pull_request_number=s.pull_request_number
    and (
      s.expires_at>clock_timestamp()
      or exists(
        select 1
        from private.pandora_coordinator_vault_merge_receipts r
        where r.repository=s.repository
          and r.pull_request_number=s.pull_request_number
          and r.claim_id=s.merge_claim_id
      )
    )
  order by s.merge_claimed_at
  limit 1;

  if not found then
    return jsonb_build_object('ok',true,'state','idle');
  end if;

  return private.pandora_coordinator_vault_merge_execute_v1(
    v_target.pull_request_number,
    v_target.head_sha
  ) || jsonb_build_object('state','processed');
end;
$function$


revoke all on function private.pandora_coordinator_vault_merge_tick_v1() from public, anon, authenticated, service_role;


do $schedule$
begin
  if exists(select 1 from cron.job where jobname='pandora-coordinator-vault-merge-v1') then
    perform cron.unschedule('pandora-coordinator-vault-merge-v1');
  end if;
  perform cron.schedule(
    'pandora-coordinator-vault-merge-v1',
    '* * * * *',
    'select private.pandora_coordinator_vault_merge_tick_v1();'
  );
end;
$schedule$;

