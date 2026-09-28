-- Operations Room completion: reconcile verified external GitHub success and harden private server tables.
-- Partial provider success is preserved as partial success: the task is requeued, never marked complete.

create table if not exists private.pandora_ops_external_success_receipts (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  generation bigint not null check (generation > 0),
  provider text not null check (provider in ('github')),
  operation text not null check (operation in ('pull_request_branch_update')),
  provider_ref text not null check (length(provider_ref) between 1 and 1000),
  provider_readback jsonb not null check (jsonb_typeof(provider_readback)='object'),
  reconciled_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,task_key,generation)
);
alter table private.pandora_ops_external_success_receipts enable row level security;
revoke all on table private.pandora_ops_external_success_receipts from public,anon,authenticated;

create or replace function public.pandora_ops_reconcile_external_success_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_lease_id uuid,
  p_generation bigint,
  p_provider text,
  p_receipt jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  l private.pandora_ops_leases%rowtype;
  t private.pandora_ops_tasks%rowtype;
  prior private.pandora_ops_external_success_receipts%rowtype;
  v_pr integer;
  v_branch text;
  v_head text;
  v_base text;
  v_ref text;
  v_api jsonb;
  v_body jsonb;
  v_compare jsonb;
  v_readback jsonb;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_EXTERNAL_RECONCILE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  perform 1 from private.pandora_ops_project_bindings
   where organization_id=p_organization_id and project_id=p_project_id and state='active'
   for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  perform 1 from private.pandora_ops_workspaces
   where organization_id=p_organization_id and project_id=p_project_id for update;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;

  select * into l from private.pandora_ops_leases
   where id=p_lease_id and organization_id=p_organization_id and project_id=p_project_id
   for update;
  if not found or l.generation is distinct from p_generation or l.state<>'reconcile' then
    raise exception 'OPS_EXTERNAL_RECONCILE_FENCED';
  end if;

  select * into t from private.pandora_ops_tasks
   where organization_id=p_organization_id and project_id=p_project_id and task_key=l.task_key
   for update;
  if not found or t.generation is distinct from p_generation or t.status<>'blocked'
     or t.cancel_requested or t.spec->>'risk'<>'source'
     or t.spec#>>'{source,repository}'<>'pandora-rvw-314296438-20260820/pandoras-box' then
    raise exception 'OPS_EXTERNAL_RECONCILE_TASK_MISMATCH';
  end if;

  if exists (select 1 from private.pandora_ops_dispatch_outbox where lease_id=l.id) then
    raise exception 'OPS_EXTERNAL_RECONCILE_DISPATCH_EXISTS';
  end if;

  if p_provider is distinct from 'github'
     or jsonb_typeof(p_receipt) is distinct from 'object'
     or p_receipt->>'taskId' is distinct from t.task_key
     or p_receipt->>'generation' is distinct from p_generation::text
     or p_receipt->>'provider' is distinct from 'github'
     or p_receipt->>'operation' is distinct from 'pull_request_branch_update'
     or p_receipt->>'repository' is distinct from 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_receipt->'providerOutcomeKnown' is distinct from 'true'::jsonb
     or p_receipt->'externalActorFenced' is distinct from 'true'::jsonb
     or coalesce(p_receipt->>'pullRequest','') !~ '^[1-9][0-9]{0,9}$'
     or coalesce(p_receipt->>'branch','') !~ '^[A-Za-z0-9._/-]{1,200}$'
     or coalesce(p_receipt->>'headSha','') !~ '^[0-9a-f]{40}$'
     or coalesce(p_receipt->>'baseSha','') !~ '^[0-9a-f]{40}$'
     or not coalesce(length(p_receipt->>'ref') between 1 and 1000,false)
     or octet_length(p_receipt::text)>16384 then
    raise exception 'OPS_EXTERNAL_RECONCILE_RECEIPT_INVALID';
  end if;

  v_pr:=(p_receipt->>'pullRequest')::integer;
  v_branch:=p_receipt->>'branch';
  v_head:=p_receipt->>'headSha';
  v_base:=p_receipt->>'baseSha';
  v_ref:=p_receipt->>'ref';

  if v_base is distinct from t.spec#>>'{source,baseSha}'
     or not exists (
       select 1 from jsonb_array_elements(coalesce(t.spec->'resources','[]'::jsonb)) r
       where r->>'key'='release/pr/'||v_pr::text and r->>'mode'='write'
     )
     or not exists (
       select 1 from jsonb_array_elements(coalesce(t.spec->'resources','[]'::jsonb)) r
       where r->>'key'='git/branch/'||v_branch and r->>'mode'='write'
     ) then
    raise exception 'OPS_EXTERNAL_RECONCILE_AUTHORITY_MISMATCH' using errcode='42501';
  end if;

  select * into prior from private.pandora_ops_external_success_receipts
   where organization_id=p_organization_id and project_id=p_project_id
     and task_key=t.task_key and generation=p_generation;
  if found then
    if prior.provider is distinct from p_provider
       or prior.operation is distinct from p_receipt->>'operation'
       or prior.provider_ref is distinct from v_ref
       or prior.provider_readback->>'headSha' is distinct from v_head
       or prior.provider_readback->>'pullRequest' is distinct from v_pr::text then
      raise exception 'OPS_EXTERNAL_RECONCILE_REPLAY_CONFLICT';
    end if;
    return jsonb_build_object(
      'state',t.status,'replayed',true,'leaseReleased',l.state='released',
      'taskId',t.task_key,'headSha',v_head,'pullRequest',v_pr
    );
  end if;

  v_api:=private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/'||v_pr::text,
    null
  );
  if coalesce((v_api->>'status')::integer,0)<>200 then
    raise exception 'OPS_EXTERNAL_RECONCILE_PROVIDER_READ_FAILED';
  end if;
  v_body:=coalesce(v_api->'body','{}'::jsonb);
  if v_body#>>'{head,ref}' is distinct from v_branch
     or v_body#>>'{head,sha}' is distinct from v_head
     or v_body#>>'{base,ref}' is distinct from 'main'
     or v_body#>>'{base,sha}' is distinct from v_base then
    raise exception 'OPS_EXTERNAL_RECONCILE_PROVIDER_MISMATCH';
  end if;

  v_compare:=private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/compare/'||
      v_base||'%2E%2E%2E'||v_head,
    null
  );
  if coalesce((v_compare->>'status')::integer,0)<>200
     or v_compare#>>'{body,status}' not in ('ahead','identical')
     or coalesce((v_compare#>>'{body,behind_by}')::integer,0)<>0 then
    raise exception 'OPS_EXTERNAL_RECONCILE_ANCESTRY_MISMATCH';
  end if;

  v_readback:=jsonb_build_object(
    'repository','pandora-rvw-314296438-20260820/pandoras-box',
    'pullRequest',v_pr::text,'branch',v_branch,'headSha',v_head,'baseSha',v_base,
    'pullRequestState',v_body->>'state','mergeable',v_body->'mergeable',
    'ancestryStatus',v_compare#>>'{body,status}',
    'behindBy',coalesce((v_compare#>>'{body,behind_by}')::integer,0)
  );

  insert into private.pandora_ops_external_success_receipts(
    organization_id,project_id,task_key,generation,provider,operation,
    provider_ref,provider_readback
  ) values(
    p_organization_id,p_project_id,t.task_key,p_generation,p_provider,
    p_receipt->>'operation',v_ref,v_readback
  );

  perform private.pandora_ops_settle_v1(
    p_organization_id,p_project_id,l.id,p_generation,0,v_ref
  );

  update private.pandora_ops_tasks
   set status='queued',revision=revision+1,queued_at=clock_timestamp()
   where organization_id=p_organization_id and project_id=p_project_id and task_key=t.task_key;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,'external-success:'||l.id,
    t.task_key,'external_provider_success_reconciled',v_ref
  );

  return jsonb_build_object(
    'state','queued','replayed',false,'leaseReleased',true,
    'taskId',t.task_key,'headSha',v_head,'pullRequest',v_pr,'providerReadback',v_readback
  );
end;
$fn$;

revoke all on function public.pandora_ops_reconcile_external_success_v1(uuid,uuid,uuid,bigint,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.pandora_ops_reconcile_external_success_v1(uuid,uuid,uuid,bigint,text,jsonb)
  to service_role;

revoke all on schema private from public,anon,authenticated;

alter table if exists private.pandora_project_memory_context_receipts enable row level security;
alter table if exists private.pandora_edge_function_retirement_receipts enable row level security;
alter table if exists private.pandora_base44_identity_links enable row level security;
alter table if exists private.pandora_google_workspace_oauth_states enable row level security;
alter table if exists private.pandora_google_workspace_connections enable row level security;
alter table if exists private.pandora_external_worker_dispatches enable row level security;
alter table if exists private.pandora_coordinator_gate_decisions enable row level security;
alter table if exists private.pandora_coordinator_gate_state enable row level security;
alter table if exists private.pandora_coordinator_repository_fence enable row level security;
alter table if exists private.pandora_coordinator_snapshot_promotions enable row level security;
alter table if exists private.pandora_coordinator_snapshot_revocations enable row level security;
alter table if exists private.pandora_ci_rescue_jobs enable row level security;
alter table if exists private.phone_local_ai_acceptance_challenges enable row level security;
alter table if exists private.phone_local_ai_acceptance_receipts enable row level security;
alter table if exists private.plp_staff_task_action_receipts enable row level security;
alter table if exists private.pandora_meta_oauth_states enable row level security;
alter table if exists private.pandora_meta_connections enable row level security;
alter table if exists private.pandora_meta_page_tokens enable row level security;

revoke all on table
  private.pandora_project_memory_context_receipts,
  private.pandora_edge_function_retirement_receipts,
  private.pandora_base44_identity_links,
  private.pandora_google_workspace_oauth_states,
  private.pandora_google_workspace_connections,
  private.pandora_external_worker_dispatches,
  private.pandora_coordinator_gate_decisions,
  private.pandora_coordinator_gate_state,
  private.pandora_coordinator_repository_fence,
  private.pandora_coordinator_snapshot_promotions,
  private.pandora_coordinator_snapshot_revocations,
  private.pandora_ci_rescue_jobs,
  private.phone_local_ai_acceptance_challenges,
  private.phone_local_ai_acceptance_receipts,
  private.plp_staff_task_action_receipts,
  private.pandora_meta_oauth_states,
  private.pandora_meta_connections,
  private.pandora_meta_page_tokens
from public,anon,authenticated;
