-- Pandora Operations reasoning fleet: Bedrock catalog + model-attested ChatGPT Astra slot.
-- Generated from live AWS Bedrock us-east-1 model/profile readback on 2026-09-27.
-- Paid provider execution remains fenced by parent Operations lease budgets.

create table if not exists private.pandora_ops_worker_model_bindings (
  organization_id uuid not null,
  project_id uuid not null,
  worker_key text not null,
  required_provider text not null check(required_provider ~ '^[a-z][a-z0-9._-]{0,119}$'),
  required_model text not null check(length(required_model) between 1 and 180),
  state text not null check(state in ('required','verified','rejected')),
  evidence_ref text,
  verified_by text,
  verified_at timestamptz,
  expires_at timestamptz,
  primary key (organization_id,project_id,worker_key),
  foreign key (organization_id,project_id,worker_key)
    references private.pandora_ops_workers(organization_id,project_id,worker_key),
  check (
    (state='required' and evidence_ref is null and verified_by is null and verified_at is null and expires_at is null)
    or
    (state in ('verified','rejected') and evidence_ref is not null and length(evidence_ref) between 8 and 500
      and verified_by is not null and length(verified_by) between 3 and 180
      and verified_at is not null and expires_at is not null and expires_at>verified_at)
  )
);

alter table private.pandora_ops_worker_model_bindings enable row level security;
revoke all on private.pandora_ops_worker_model_bindings from public,anon,authenticated,service_role;

create or replace function private.pandora_ops_worker_model_binding_fence_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $body$
begin
  if new.worker_key='chatgpt-astra-worker-v1' and new.connected then
    perform 1
    from private.pandora_ops_worker_model_bindings b
    where b.organization_id=new.organization_id
      and b.project_id=new.project_id
      and b.worker_key=new.worker_key
      and b.required_provider='openai'
      and b.required_model='gpt-6-astra'
      and b.state='verified'
      and b.expires_at>clock_timestamp()
    for share;
    if not found then
      raise exception 'OPS_WORKER_MODEL_ATTESTATION_REQUIRED' using errcode='42501';
    end if;
  end if;
  return new;
end;
$body$;

drop trigger if exists pandora_ops_worker_model_binding_fence_v1 on private.pandora_ops_workers;
create trigger pandora_ops_worker_model_binding_fence_v1
before insert or update of connected,health,heartbeat_at on private.pandora_ops_workers
for each row execute function private.pandora_ops_worker_model_binding_fence_v1();

create or replace function public.pandora_ops_verify_worker_model_binding_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_provider text,
  p_model text,
  p_verifier_principal text,
  p_evidence_ref text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare b private.pandora_ops_worker_model_bindings%rowtype;
begin
  perform 1
  from private.pandora_ops_workers w
  where w.organization_id=p_organization_id
    and w.project_id=p_project_id
    and w.worker_key=p_worker_key
    and w.principal_key=p_principal_key
  for share;
  if not found then raise exception 'OPS_WORKER_MODEL_IDENTITY_DENIED' using errcode='42501'; end if;
  if p_verifier_principal is null or p_verifier_principal=p_principal_key
     or p_evidence_ref is null or length(p_evidence_ref) not between 8 and 500
     or p_expires_at<=clock_timestamp() or p_expires_at>clock_timestamp()+interval '24 hours'
  then raise exception 'OPS_WORKER_MODEL_ATTESTATION_INVALID' using errcode='22023'; end if;

  select * into b
  from private.pandora_ops_worker_model_bindings
  where organization_id=p_organization_id and project_id=p_project_id and worker_key=p_worker_key
  for update;
  if not found
     or b.required_provider is distinct from p_provider
     or b.required_model is distinct from p_model
  then raise exception 'OPS_WORKER_MODEL_BINDING_MISMATCH' using errcode='42501'; end if;

  update private.pandora_ops_worker_model_bindings
  set state='verified',evidence_ref=p_evidence_ref,verified_by=p_verifier_principal,
      verified_at=clock_timestamp(),expires_at=p_expires_at
  where organization_id=p_organization_id and project_id=p_project_id and worker_key=p_worker_key;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'worker-model:'||p_worker_key,null,
    'worker_model_verified',p_evidence_ref
  );

  return jsonb_build_object(
    'verified',true,'workerId',p_worker_key,'provider',p_provider,'model',p_model,
    'expiresAt',p_expires_at
  );
end;
$body$;

revoke all on function public.pandora_ops_verify_worker_model_binding_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_ops_verify_worker_model_binding_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) to service_role;

insert into private.pandora_ops_workers(
  organization_id,project_id,worker_key,principal_key,engine,lanes,capabilities,
  capacity,acknowledged,connected,health,heartbeat_at,registration_receipt
) values(
  '2270b266-59da-4c39-bfd9-9f8d08352af0',
  'ee282126-3f61-4058-8c92-2fedbfcecf1f',
  'chatgpt-astra-worker-v1',
  'chatgpt:interactive:astra-worker-v1',
  'chatgpt',
  array['backend','reliability','web']::text[],
  array['inference.route','reasoning.deep','coding.reason','provider.readback','model.attestation.required']::text[],
  1,true,false,'offline',null,
  'configured:astra-worker:model-attestation-required:20260927'
)
on conflict (organization_id,project_id,worker_key) do update
set lanes=excluded.lanes,capabilities=excluded.capabilities,capacity=1,acknowledged=true,
    connected=false,health='offline',heartbeat_at=null,registration_receipt=excluded.registration_receipt
where private.pandora_ops_workers.principal_key=excluded.principal_key
  and private.pandora_ops_workers.engine='chatgpt';

insert into private.pandora_ops_worker_model_bindings(
  organization_id,project_id,worker_key,required_provider,required_model,state
) values(
  '2270b266-59da-4c39-bfd9-9f8d08352af0',
  'ee282126-3f61-4058-8c92-2fedbfcecf1f',
  'chatgpt-astra-worker-v1','openai','gpt-6-astra','required'
)
on conflict (organization_id,project_id,worker_key) do update
set required_provider='openai',required_model='gpt-6-astra',state='required',
    evidence_ref=null,verified_by=null,verified_at=null,expires_at=null;

do $body$
declare
  v_catalog jsonb := $catalog$[{"modelId":"amazon.nova-2-lite-v1:0","modelName":"Nova 2 Lite","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"us.amazon.nova-2-lite-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"amazon.nova-lite-v1:0","modelName":"Nova Lite","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"amazon.nova-lite-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"amazon.nova-micro-v1:0","modelName":"Nova Micro","providerName":"Amazon","inputModalities":["TEXT"],"invocationTarget":"amazon.nova-micro-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"amazon.nova-pro-v1:0","modelName":"Nova Pro","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"amazon.nova-pro-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-fable-5","modelName":"Claude Fable 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-fable-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-fable-5-1","modelName":"Claude Fable 5.1","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-fable-5-1","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-haiku-4-5-20251001-v1:0","modelName":"Claude Haiku 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-haiku-4-5-20251001-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-5-20251101-v1:0","modelName":"Claude Opus 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-5-20251101-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-6-v1","modelName":"Claude Opus 4.6","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-6-v1","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-7","modelName":"Claude Opus 4.7","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-7","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-8","modelName":"Claude Opus 4.8","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-8","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-5","modelName":"Claude Opus 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-5-5","modelName":"Claude Opus 5.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-5-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-4-5-20250929-v1:0","modelName":"Claude Sonnet 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-4-5-20250929-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-4-6","modelName":"Claude Sonnet 4.6","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-4-6","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-5","modelName":"Claude Sonnet 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"deepseek.v3.2","modelName":"DeepSeek V3.2","providerName":"DeepSeek","inputModalities":["TEXT"],"invocationTarget":"deepseek.v3.2","inferenceTypes":["ON_DEMAND"]},{"modelId":"deepseek.r1-v1:0","modelName":"DeepSeek-R1","providerName":"DeepSeek","inputModalities":["TEXT"],"invocationTarget":"us.deepseek.r1-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"google.gemma-3-12b-it","modelName":"Gemma 3 12B IT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-12b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"google.gemma-3-27b-it","modelName":"Gemma 3 27B PT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-27b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"google.gemma-3-4b-it","modelName":"Gemma 3 4B IT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-4b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-70b-instruct-v1:0","modelName":"Llama 3 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"meta.llama3-70b-instruct-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-8b-instruct-v1:0","modelName":"Llama 3 8B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"meta.llama3-8b-instruct-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-1-70b-instruct-v1:0","modelName":"Llama 3.1 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-1-70b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama3-1-8b-instruct-v1:0","modelName":"Llama 3.1 8B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-1-8b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama3-3-70b-instruct-v1:0","modelName":"Llama 3.3 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-3-70b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama4-maverick-17b-instruct-v1:0","modelName":"Llama 4 Maverick 17B Instruct","providerName":"Meta","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.meta.llama4-maverick-17b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama4-scout-17b-instruct-v1:0","modelName":"Llama 4 Scout 17B Instruct","providerName":"Meta","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.meta.llama4-scout-17b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"minimax.minimax-m2","modelName":"MiniMax M2","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2","inferenceTypes":["ON_DEMAND"]},{"modelId":"minimax.minimax-m2.1","modelName":"MiniMax M2.1","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2.1","inferenceTypes":["ON_DEMAND"]},{"modelId":"minimax.minimax-m2.5","modelName":"MiniMax M2.5","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2.5","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.devstral-2-123b","modelName":"Devstral 2 123B","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.devstral-2-123b","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.magistral-small-2509","modelName":"Magistral Small 2509","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.magistral-small-2509","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-14b-instruct","modelName":"Ministral 14B 3.0","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-14b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-8b-instruct","modelName":"Ministral 3 8B","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-8b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-3b-instruct","modelName":"Ministral 3B","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-3b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-7b-instruct-v0:2","modelName":"Mistral 7B Instruct","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-7b-instruct-v0:2","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-large-2402-v1:0","modelName":"Mistral Large (24.02)","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-large-2402-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-large-3-675b-instruct","modelName":"Mistral Large 3","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.mistral-large-3-675b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-small-2402-v1:0","modelName":"Mistral Small (24.02)","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-small-2402-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mixtral-8x7b-instruct-v0:1","modelName":"Mixtral 8x7B Instruct","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mixtral-8x7b-instruct-v0:1","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.pixtral-large-2502-v1:0","modelName":"Pixtral Large (25.02)","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.mistral.pixtral-large-2502-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"moonshot.kimi-k2-thinking","modelName":"Kimi K2 Thinking","providerName":"Moonshot AI","inputModalities":["TEXT"],"invocationTarget":"moonshot.kimi-k2-thinking","inferenceTypes":["ON_DEMAND"]},{"modelId":"moonshotai.kimi-k2.5","modelName":"Kimi K2.5","providerName":"Moonshot AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"moonshotai.kimi-k2.5","inferenceTypes":["ON_DEMAND"]},{"modelId":"moonshotai.kimi-k3","modelName":"Kimi K3","providerName":"Moonshot AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.moonshotai.kimi-k3","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"nvidia.nemotron-super-3-120b","modelName":"NVIDIA Nemotron 3 Super 120B A12B","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-super-3-120b","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-12b-v2","modelName":"NVIDIA Nemotron Nano 12B v2 VL BF16","providerName":"NVIDIA","inputModalities":["TEXT","IMAGE"],"invocationTarget":"nvidia.nemotron-nano-12b-v2","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-9b-v2","modelName":"NVIDIA Nemotron Nano 9B v2","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-nano-9b-v2","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-3-30b","modelName":"Nemotron Nano 3 30B","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-nano-3-30b","inferenceTypes":["ON_DEMAND"]},{"modelId":"openai.gpt-5.4","modelName":"GPT 5.4","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.4","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.5","modelName":"GPT 5.5","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-luna","modelName":"GPT-5.6 Luna","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-luna","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-sol","modelName":"GPT-5.6 Sol","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-sol","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-terra","modelName":"GPT-5.6 Terra","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-terra","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-astra","modelName":"GPT-6 Astra","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-astra","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-luna","modelName":"GPT-6 Luna","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-luna","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-sol","modelName":"GPT-6 Sol","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-sol","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-oss-120b-1:0","modelName":"gpt-oss-120b","providerName":"OpenAI","inputModalities":["TEXT"],"invocationTarget":"openai.gpt-oss-120b-1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"openai.gpt-oss-20b-1:0","modelName":"gpt-oss-20b","providerName":"OpenAI","inputModalities":["TEXT"],"invocationTarget":"openai.gpt-oss-20b-1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-32b-v1:0","modelName":"Qwen3 32B (dense)","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-32b-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-coder-next","modelName":"Qwen3 Coder Next","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-coder-next","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-next-80b-a3b","modelName":"Qwen3 Next 80B A3B","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-next-80b-a3b","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-vl-235b-a22b","modelName":"Qwen3 VL 235B A22B","providerName":"Qwen","inputModalities":["TEXT","IMAGE"],"invocationTarget":"qwen.qwen3-vl-235b-a22b","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-coder-30b-a3b-v1:0","modelName":"Qwen3-Coder-30B-A3B-Instruct","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-coder-30b-a3b-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"twelvelabs.pegasus-1-2-v1:0","modelName":"Pegasus v1.2","providerName":"TwelveLabs","inputModalities":["TEXT","VIDEO"],"invocationTarget":"twelvelabs.pegasus-1-2-v1:0","inferenceTypes":["INFERENCE_PROFILE","ON_DEMAND"]},{"modelId":"writer.palmyra-x4-v1:0","modelName":"Palmyra X4","providerName":"Writer","inputModalities":["TEXT"],"invocationTarget":"us.writer.palmyra-x4-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"writer.palmyra-x5-v1:0","modelName":"Palmyra X5","providerName":"Writer","inputModalities":["TEXT"],"invocationTarget":"us.writer.palmyra-x5-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"writer.palmyra-vision-7b","modelName":"Writer Palmyra Vision 7B","providerName":"Writer","inputModalities":["TEXT","IMAGE"],"invocationTarget":"writer.palmyra-vision-7b","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-4.7","modelName":"GLM 4.7","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-4.7","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-4.7-flash","modelName":"GLM 4.7 Flash","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-4.7-flash","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-5","modelName":"GLM 5","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-5","inferenceTypes":["ON_DEMAND"]},{"modelId":"xai.grok-4.6","modelName":"Grok 4.6","providerName":"xAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.xai.grok-4.6","inferenceTypes":["INFERENCE_PROFILE"]}]$catalog$::jsonb;
  v_models jsonb;
  v_policy jsonb;
begin
  select jsonb_agg(
    jsonb_build_object(
      'provider','bedrock',
      'model',entry->>'modelId',
      'modelRevision',null,
      'configurationDigest',
        encode(extensions.digest(convert_to(
          'bedrock-fleet-v1:'||(entry->>'modelId')||':'||(entry->>'invocationTarget'),'UTF8'
        ),'sha256'),'hex'),
      'classes',
        case when (entry->'inputModalities') ? 'IMAGE'
          then '["deep_reasoning","complex_coding","fast_coding","vision","long_context","research","structured_extraction","cheap_bulk","independent_verification"]'::jsonb
          else '["deep_reasoning","complex_coding","fast_coding","long_context","research","structured_extraction","cheap_bulk","independent_verification"]'::jsonb
        end,
      'modalities',
        case when (entry->'inputModalities') ? 'IMAGE'
          then '["text","image"]'::jsonb else '["text"]'::jsonb end,
      'executionBoundary','cloud',
      'riskTier',1,
      'contextTokens',65536,
      'maxInputBytes',131072,
      'maxOutputTokens',4096,
      'imageTokenUpperBound',case when (entry->'inputModalities') ? 'IMAGE' then 32768 else 0 end,
      'transport','bedrock_converse',
      'approved',true,
      'approvalRef','owner:2026-09-27:add-all-available-bedrock-reasoning-models',
      'approvalExpiresAt','2026-10-27T07:07:52Z',
      'available',true,
      'healthObservedAt','2026-09-27T07:07:52Z',
      'estimatedLatencyMs',null,
      -- This is a conservative reservation ceiling, not a pricing claim.
      -- Paid execution remains blocked by the parent Operations lease budget.
      'maxCostMicros',10000000,
      'maxConcurrency',1
    )
    order by entry->>'modelId'
  ) into v_models
  from jsonb_array_elements(v_catalog) entry;

  if jsonb_array_length(v_models)<>72 then
    raise exception 'BEDROCK_REASONING_CATALOG_COUNT_MISMATCH';
  end if;
  if not exists(
    select 1 from jsonb_array_elements(v_models) x
    where x->>'model'='openai.gpt-6-astra'
  ) then raise exception 'BEDROCK_ASTRA_MISSING'; end if;

  v_policy:=jsonb_build_object(
    'version','bedrock-fleet-v1',
    'models',v_models,
    'maxAttempts',3,
    'maxHealthAgeMs',2592000000,
    'minHistorySamples',5,
    'maxHistoryAgeMs',2592000000,
    'minimumRiskTier',jsonb_build_object(
      'read',0,'source',1,'preview',1,'production',2,'destructive',3
    ),
    'allowedBoundaries',jsonb_build_array('cloud'),
    'allowedProviders',jsonb_build_array('bedrock'),
    'allowedFallbackCodes',jsonb_build_array('rate_limit','unavailable','invalid_output','verification_failed'),
    'override',null,
    'requireMemoryContext',false
  );

  insert into private.pandora_ops_inference_policies(
    organization_id,project_id,revision,policy,active,approval_ref
  ) values(
    '2270b266-59da-4c39-bfd9-9f8d08352af0',
    'ee282126-3f61-4058-8c92-2fedbfcecf1f',
    1,v_policy,true,
    'owner:2026-09-27:add-all-available-bedrock-reasoning-models'
  )
  on conflict (organization_id,project_id) do update
  set revision=private.pandora_ops_inference_policies.revision+1,
      policy=excluded.policy,active=true,approval_ref=excluded.approval_ref;
end;
$body$;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('bedrock','enabled','true',true,clock_timestamp()),
  ('bedrock','routing_eligible','true',true,clock_timestamp()),
  ('bedrock','catalog_count','72',true,clock_timestamp()),
  ('bedrock','catalog_region','us-east-1',true,clock_timestamp()),
  ('bedrock','catalog_observed_at','2026-09-27T07:07:52Z',true,clock_timestamp()),
  ('bedrock','default_model','openai.gpt-6-astra',true,clock_timestamp()),
  ('bedrock','fast_model','openai.gpt-6-luna',true,clock_timestamp()),
  ('bedrock','policy_version','bedrock-fleet-v1',true,clock_timestamp()),
  ('bedrock','auth_mode','vercel_oidc_sts',true,clock_timestamp())
on conflict (provider,config_key) do update
set config_value=excluded.config_value,active=true,updated_at=clock_timestamp();
