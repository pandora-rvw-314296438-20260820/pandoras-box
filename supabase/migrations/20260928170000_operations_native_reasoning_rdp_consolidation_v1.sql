-- Consolidate model-first reasoning -> RDP execution into the existing native worker.
-- Source-only until explicitly applied. Does not change workspace budget or infer Astra identity.

alter table private.pandora_ops_reasoning_rdp_links
  add column if not exists learning_outbox_id uuid;

create or replace function public.pandora_ops_reasoning_rdp_queue_memory_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_parent_task_key text,
  p_parent_generation bigint,
  p_worker_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  l private.pandora_ops_reasoning_rdp_links%rowtype;
  parent private.pandora_ops_tasks%rowtype;
  child private.pandora_ops_tasks%rowtype;
  outbox_id uuid;
begin
  if p_worker_key<>'pandora-reasoning-rdp-bridge-v1'
     or p_principal_key<>'vercel:mcpmaster:reasoning-rdp-bridge-v1'
  then raise exception 'OPS_REASONING_RDP_BRIDGE_IDENTITY_DENIED' using errcode='42501'; end if;

  select * into l from private.pandora_ops_reasoning_rdp_links
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation
  for update;
  if not found then raise exception 'OPS_REASONING_RDP_LINK_MISSING'; end if;

  select * into parent from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id
    and task_key=l.parent_task_key;
  select * into child from private.pandora_ops_tasks
  where organization_id=p_organization_id and project_id=p_project_id
    and task_key=l.child_task_key;

  if parent.status<>'complete' or child.status<>'complete' or l.state<>'complete'
  then return jsonb_build_object('state','not_ready','parentStatus',parent.status,'childStatus',child.status); end if;

  if l.learning_outbox_id is not null then
    return jsonb_build_object('state','queued','replayed',true,'learningOutboxId',l.learning_outbox_id);
  end if;

  insert into public.pandora_verified_learning_outbox(
    organization_id,activity_job_id,thread_id,idempotency_key,memory_project_id,namespace,
    learning_kind,learning_summary,promotion_basis,confidence,execution,
    incident_verification_ref,additional_evidence_refs,state,attempt_count,created_at,updated_at
  ) values(
    p_organization_id,l.inference_request_id,null,
    'operations-reasoning-rdp:'||p_parent_task_key||':'||p_parent_generation::text,
    '7c686cbd-d968-49d5-86cc-918f5e777bd2'::uuid,'real_life',
    'outcome',
    'A governed reasoning route selected profile '||coalesce(l.profile,'unknown')||
      ' and the Windows RDP executor plus independent RDP ARTEMIS verifier completed successfully.',
    'Operations parent and RDP child both reached canonical PASS verification on exact source '||l.source_sha||
      '; this remains a review-gated learning candidate and is not self-promoted Memory.',
    1.0,
    jsonb_build_object(
      'schemaVersion','operations-reasoning-rdp-v2',
      'parentTaskId',l.parent_task_key,'parentGeneration',l.parent_generation,
      'childTaskId',l.child_task_key,'profile',l.profile,'sourceSha',l.source_sha,
      'inferenceRequestId',l.inference_request_id,'reasoningOutputDigest',l.output_digest,
      'providerReceipt',l.provider_receipt,
      'executorWorker','pandora-rdp-windows-01','verifierWorker','pandora-rdp-artemis-01',
      'parentVerificationRunId',parent.verification->>'verificationRunId',
      'childVerificationRunId',child.verification->>'verificationRunId',
      'canonicalMemoryWritten',false
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

  update private.pandora_ops_reasoning_rdp_links
  set learning_outbox_id=outbox_id,updated_at=clock_timestamp()
  where organization_id=p_organization_id and project_id=p_project_id
    and parent_task_key=p_parent_task_key and parent_generation=p_parent_generation;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'reasoning-rdp:memory:'||l.inference_request_id,l.parent_task_key,
    'verified_learning_queued','verified-learning-outbox:'||outbox_id::text
  );

  return jsonb_build_object(
    'state','queued','replayed',false,'learningOutboxId',outbox_id,
    'canonicalMemoryWritten',false
  );
end;
$body$;

revoke all on function public.pandora_ops_reasoning_rdp_queue_memory_v1(uuid,uuid,text,bigint,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_ops_reasoning_rdp_queue_memory_v1(uuid,uuid,text,bigint,text,text)
to service_role;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('operations_model_rdp_bridge','enabled','true',true,clock_timestamp()),
  ('operations_model_rdp_bridge','runtime_state','native_worker_consolidated',true,clock_timestamp()),
  ('operations_model_rdp_bridge','runtime_hold_reason','zero_workspace_budget_or_unattested_chatgpt_worker',true,clock_timestamp()),
  ('operations_model_rdp_bridge','wake_path','operations-native-worker-v1',true,clock_timestamp()),
  ('operations_model_rdp_bridge','standalone_vercel_function','false',true,clock_timestamp()),
  ('chatgpt_worker','required_thinking_effort','extra_high',true,clock_timestamp())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=true,updated_at=clock_timestamp();

comment on function private.pandora_ops_enable_reasoning_rdp_bridge_schedule_v1() is
  'Legacy standalone wake remains unscheduled. Model-first reasoning-to-RDP is advanced by the existing Operations native worker wake. Workspace budget and provider/model attestation remain authoritative.';
