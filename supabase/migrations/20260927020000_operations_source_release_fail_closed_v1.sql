-- Fail closed on generic Operations source releases until an exact-head
-- substantive independent review and explicit owner release authorization
-- are durably verified for the same PR. This replaces only the release RPC;
-- source candidate/claim/execute/handoff remain available.
create or replace function public.pandora_ops_generic_source_release_step_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_verifier_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box';
  t private.pandora_ops_tasks%rowtype;
  verifier private.pandora_ops_workers%rowtype;
  src private.pandora_ops_source_execution_receipts%rowtype;
  v_pr jsonb;
  v_pr_body jsonb;
  v_checks jsonb;
  v_pr_no integer;
  v_pending integer;
  v_failed integer;
  v_success integer;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_GENERIC_SOURCE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  select * into verifier from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_verifier_key and principal_key=p_principal_key;
  if not found or not verifier.acknowledged or not verifier.connected
     or verifier.health<>'ready'
     or verifier.heartbeat_at is null
     or verifier.heartbeat_at<clock_timestamp()-interval '60 seconds'
     or not('release'=any(verifier.lanes)) then
    raise exception 'OPS_GENERIC_SOURCE_RELEASE_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select q.* into t from private.pandora_ops_tasks q
   where q.organization_id=p_organization_id and q.project_id=p_project_id
     and q.status in ('handed_off','verifying')
     and q.spec->>'risk'='source'
     and q.spec#>>'{source,repository}'=v_repo
   order by q.queued_at,q.task_key limit 1;
  if not found then return jsonb_build_object('state','idle'); end if;

  select * into src from private.pandora_ops_source_execution_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=t.task_key and generation=t.generation;
  if not found or src.head_sha is distinct from t.head_sha
     or src.pull_request is distinct from nullif(t.handoff->>'pullRequest','')::integer then
    raise exception 'OPS_GENERIC_SOURCE_EXECUTION_RECEIPT_MISSING';
  end if;
  v_pr_no:=src.pull_request;

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

  if v_pr_body->>'state'<>'open' then
    return jsonb_build_object(
      'state','manual_reconciliation_required',
      'taskId',t.task_key,'generation',t.generation,
      'pullRequest',v_pr_no,'headSha',t.head_sha
    );
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
      and c->>'status'='completed'
      and coalesce(c->>'conclusion','') not in ('success','neutral','skipped')),
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

  -- The legacy path published coordinator PASS with a placeholder review and
  -- merged on CI alone. No review or owner release receipt can currently
  -- establish both required proofs for this generic task. Keep the PR open.
  return jsonb_build_object(
    'state','release_authorization_required',
    'taskId',t.task_key,'generation',t.generation,
    'pullRequest',v_pr_no,'headSha',t.head_sha,
    'reviewStatus','unverified',
    'ownerReleaseAuthorization','unverified',
    'required',jsonb_build_array(
      'substantive different-vendor review for this exact PR and head SHA',
      'explicit owner release authorization for this exact PR and head SHA'
    )
  );
end;
$fn$;

revoke all on function public.pandora_ops_generic_source_release_step_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_generic_source_release_step_v1(uuid,uuid,text,text)
  to service_role;
