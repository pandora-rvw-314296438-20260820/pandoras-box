-- Operations reasoning fleet v1.
-- Generated from live AWS Bedrock us-east-1 account authorization/profile readback.
-- No AWS static credentials are stored. Paid inference remains fenced by the parent Operations lease budget.

create table if not exists private.pandora_bedrock_reasoning_catalog (
  model_id text primary key,
  model_name text not null,
  provider_name text not null,
  invocation_target text not null,
  input_modalities text[] not null,
  inference_types text[] not null,
  risk_tier integer not null check (risk_tier between 0 and 3),
  capability_classes text[] not null,
  observed_at timestamptz not null,
  source_ref text not null
);
alter table private.pandora_bedrock_reasoning_catalog enable row level security;
revoke all on private.pandora_bedrock_reasoning_catalog from public,anon,authenticated,service_role;

do $catalog_block$
declare
  v_catalog jsonb := $catalog$[{"modelId":"amazon.nova-2-lite-v1:0","modelName":"Nova 2 Lite","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"us.amazon.nova-2-lite-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"amazon.nova-lite-v1:0","modelName":"Nova Lite","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"amazon.nova-lite-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"amazon.nova-micro-v1:0","modelName":"Nova Micro","providerName":"Amazon","inputModalities":["TEXT"],"invocationTarget":"amazon.nova-micro-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"amazon.nova-pro-v1:0","modelName":"Nova Pro","providerName":"Amazon","inputModalities":["TEXT","IMAGE","VIDEO"],"invocationTarget":"amazon.nova-pro-v1:0","inferenceTypes":["ON_DEMAND","INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-fable-5","modelName":"Claude Fable 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-fable-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-fable-5-1","modelName":"Claude Fable 5.1","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-fable-5-1","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-haiku-4-5-20251001-v1:0","modelName":"Claude Haiku 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-haiku-4-5-20251001-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-5-20251101-v1:0","modelName":"Claude Opus 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-5-20251101-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-6-v1","modelName":"Claude Opus 4.6","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-6-v1","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-7","modelName":"Claude Opus 4.7","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-7","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-4-8","modelName":"Claude Opus 4.8","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-4-8","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-5","modelName":"Claude Opus 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-opus-5-5","modelName":"Claude Opus 5.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-opus-5-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-4-5-20250929-v1:0","modelName":"Claude Sonnet 4.5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-4-5-20250929-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-4-6","modelName":"Claude Sonnet 4.6","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-4-6","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"anthropic.claude-sonnet-5","modelName":"Claude Sonnet 5","providerName":"Anthropic","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.anthropic.claude-sonnet-5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"deepseek.v3.2","modelName":"DeepSeek V3.2","providerName":"DeepSeek","inputModalities":["TEXT"],"invocationTarget":"deepseek.v3.2","inferenceTypes":["ON_DEMAND"]},{"modelId":"deepseek.r1-v1:0","modelName":"DeepSeek-R1","providerName":"DeepSeek","inputModalities":["TEXT"],"invocationTarget":"us.deepseek.r1-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"google.gemma-3-12b-it","modelName":"Gemma 3 12B IT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-12b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"google.gemma-3-27b-it","modelName":"Gemma 3 27B PT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-27b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"google.gemma-3-4b-it","modelName":"Gemma 3 4B IT","providerName":"Google","inputModalities":["TEXT","IMAGE"],"invocationTarget":"google.gemma-3-4b-it","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-70b-instruct-v1:0","modelName":"Llama 3 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"meta.llama3-70b-instruct-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-8b-instruct-v1:0","modelName":"Llama 3 8B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"meta.llama3-8b-instruct-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"meta.llama3-1-70b-instruct-v1:0","modelName":"Llama 3.1 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-1-70b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama3-1-8b-instruct-v1:0","modelName":"Llama 3.1 8B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-1-8b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama3-3-70b-instruct-v1:0","modelName":"Llama 3.3 70B Instruct","providerName":"Meta","inputModalities":["TEXT"],"invocationTarget":"us.meta.llama3-3-70b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama4-maverick-17b-instruct-v1:0","modelName":"Llama 4 Maverick 17B Instruct","providerName":"Meta","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.meta.llama4-maverick-17b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"meta.llama4-scout-17b-instruct-v1:0","modelName":"Llama 4 Scout 17B Instruct","providerName":"Meta","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.meta.llama4-scout-17b-instruct-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"minimax.minimax-m2","modelName":"MiniMax M2","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2","inferenceTypes":["ON_DEMAND"]},{"modelId":"minimax.minimax-m2.1","modelName":"MiniMax M2.1","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2.1","inferenceTypes":["ON_DEMAND"]},{"modelId":"minimax.minimax-m2.5","modelName":"MiniMax M2.5","providerName":"MiniMax","inputModalities":["TEXT"],"invocationTarget":"minimax.minimax-m2.5","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.devstral-2-123b","modelName":"Devstral 2 123B","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.devstral-2-123b","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.magistral-small-2509","modelName":"Magistral Small 2509","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.magistral-small-2509","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-14b-instruct","modelName":"Ministral 14B 3.0","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-14b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-8b-instruct","modelName":"Ministral 3 8B","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-8b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.ministral-3-3b-instruct","modelName":"Ministral 3B","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.ministral-3-3b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-7b-instruct-v0:2","modelName":"Mistral 7B Instruct","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-7b-instruct-v0:2","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-large-2402-v1:0","modelName":"Mistral Large (24.02)","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-large-2402-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-large-3-675b-instruct","modelName":"Mistral Large 3","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"mistral.mistral-large-3-675b-instruct","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mistral-small-2402-v1:0","modelName":"Mistral Small (24.02)","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mistral-small-2402-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.mixtral-8x7b-instruct-v0:1","modelName":"Mixtral 8x7B Instruct","providerName":"Mistral AI","inputModalities":["TEXT"],"invocationTarget":"mistral.mixtral-8x7b-instruct-v0:1","inferenceTypes":["ON_DEMAND"]},{"modelId":"mistral.pixtral-large-2502-v1:0","modelName":"Pixtral Large (25.02)","providerName":"Mistral AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.mistral.pixtral-large-2502-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"moonshot.kimi-k2-thinking","modelName":"Kimi K2 Thinking","providerName":"Moonshot AI","inputModalities":["TEXT"],"invocationTarget":"moonshot.kimi-k2-thinking","inferenceTypes":["ON_DEMAND"]},{"modelId":"moonshotai.kimi-k2.5","modelName":"Kimi K2.5","providerName":"Moonshot AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"moonshotai.kimi-k2.5","inferenceTypes":["ON_DEMAND"]},{"modelId":"moonshotai.kimi-k3","modelName":"Kimi K3","providerName":"Moonshot AI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.moonshotai.kimi-k3","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"nvidia.nemotron-super-3-120b","modelName":"NVIDIA Nemotron 3 Super 120B A12B","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-super-3-120b","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-12b-v2","modelName":"NVIDIA Nemotron Nano 12B v2 VL BF16","providerName":"NVIDIA","inputModalities":["TEXT","IMAGE"],"invocationTarget":"nvidia.nemotron-nano-12b-v2","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-9b-v2","modelName":"NVIDIA Nemotron Nano 9B v2","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-nano-9b-v2","inferenceTypes":["ON_DEMAND"]},{"modelId":"nvidia.nemotron-nano-3-30b","modelName":"Nemotron Nano 3 30B","providerName":"NVIDIA","inputModalities":["TEXT"],"invocationTarget":"nvidia.nemotron-nano-3-30b","inferenceTypes":["ON_DEMAND"]},{"modelId":"openai.gpt-5.4","modelName":"GPT 5.4","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.4","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.5","modelName":"GPT 5.5","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.5","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-luna","modelName":"GPT-5.6 Luna","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-luna","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-sol","modelName":"GPT-5.6 Sol","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-sol","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-5.6-terra","modelName":"GPT-5.6 Terra","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-5.6-terra","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-astra","modelName":"GPT-6 Astra","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-astra","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-luna","modelName":"GPT-6 Luna","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-luna","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-6-sol","modelName":"GPT-6 Sol","providerName":"OpenAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.openai.gpt-6-sol","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"openai.gpt-oss-120b-1:0","modelName":"gpt-oss-120b","providerName":"OpenAI","inputModalities":["TEXT"],"invocationTarget":"openai.gpt-oss-120b-1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"openai.gpt-oss-20b-1:0","modelName":"gpt-oss-20b","providerName":"OpenAI","inputModalities":["TEXT"],"invocationTarget":"openai.gpt-oss-20b-1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-32b-v1:0","modelName":"Qwen3 32B (dense)","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-32b-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-coder-next","modelName":"Qwen3 Coder Next","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-coder-next","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-next-80b-a3b","modelName":"Qwen3 Next 80B A3B","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-next-80b-a3b","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-vl-235b-a22b","modelName":"Qwen3 VL 235B A22B","providerName":"Qwen","inputModalities":["TEXT","IMAGE"],"invocationTarget":"qwen.qwen3-vl-235b-a22b","inferenceTypes":["ON_DEMAND"]},{"modelId":"qwen.qwen3-coder-30b-a3b-v1:0","modelName":"Qwen3-Coder-30B-A3B-Instruct","providerName":"Qwen","inputModalities":["TEXT"],"invocationTarget":"qwen.qwen3-coder-30b-a3b-v1:0","inferenceTypes":["ON_DEMAND"]},{"modelId":"twelvelabs.pegasus-1-2-v1:0","modelName":"Pegasus v1.2","providerName":"TwelveLabs","inputModalities":["TEXT","VIDEO"],"invocationTarget":"twelvelabs.pegasus-1-2-v1:0","inferenceTypes":["INFERENCE_PROFILE","ON_DEMAND"]},{"modelId":"writer.palmyra-x4-v1:0","modelName":"Palmyra X4","providerName":"Writer","inputModalities":["TEXT"],"invocationTarget":"us.writer.palmyra-x4-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"writer.palmyra-x5-v1:0","modelName":"Palmyra X5","providerName":"Writer","inputModalities":["TEXT"],"invocationTarget":"us.writer.palmyra-x5-v1:0","inferenceTypes":["INFERENCE_PROFILE"]},{"modelId":"writer.palmyra-vision-7b","modelName":"Writer Palmyra Vision 7B","providerName":"Writer","inputModalities":["TEXT","IMAGE"],"invocationTarget":"writer.palmyra-vision-7b","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-4.7","modelName":"GLM 4.7","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-4.7","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-4.7-flash","modelName":"GLM 4.7 Flash","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-4.7-flash","inferenceTypes":["ON_DEMAND"]},{"modelId":"zai.glm-5","modelName":"GLM 5","providerName":"Z.AI","inputModalities":["TEXT"],"invocationTarget":"zai.glm-5","inferenceTypes":["ON_DEMAND"]},{"modelId":"xai.grok-4.6","modelName":"Grok 4.6","providerName":"xAI","inputModalities":["TEXT","IMAGE"],"invocationTarget":"us.xai.grok-4.6","inferenceTypes":["INFERENCE_PROFILE"]}]$catalog$::jsonb;
begin
  insert into private.pandora_bedrock_reasoning_catalog(
    model_id,model_name,provider_name,invocation_target,input_modalities,inference_types,
    risk_tier,capability_classes,observed_at,source_ref
  )
  select
    entry->>'modelId',
    entry->>'modelName',
    entry->>'providerName',
    entry->>'invocationTarget',
    array(select jsonb_array_elements_text(entry->'inputModalities')),
    array(select jsonb_array_elements_text(entry->'inferenceTypes')),
    case
      when entry->>'modelId' ~ '(gpt-6-|gpt-5\.6-(sol|terra)|claude-(opus|sonnet|fable)|deepseek\.(r1|v3)|kimi-k2-thinking|kimi-k2\.5|kimi-k3|grok-4\.6|nova-(pro|2-lite)|devstral|magistral|mistral-large|llama3-3-70b|llama4-maverick|qwen3-(coder|next-80b|vl-235b)|glm-5|nemotron-super|palmyra-x5)' then 3
      when entry->>'modelId' ~ '(gpt-5\.[45]|gpt-5\.6-luna|gpt-oss|nova-lite|haiku|llama3-1-70b|llama4-scout|minimax|ministral-3-14b|mistral-small|mixtral|qwen3-32b|nemotron-nano-3-30b|palmyra-x4|glm-4\.7)' then 2
      else 1
    end,
    case
      when (entry->'inputModalities') ? 'IMAGE' then
        array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
      else
        array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
    end,
    '2026-09-27T07:07:52Z'::timestamptz,
    'aws:bedrock:us-east-1:list-foundation-models+list-inference-profiles'
  from jsonb_array_elements(v_catalog) entry
  on conflict (model_id) do update
  set model_name=excluded.model_name,
      provider_name=excluded.provider_name,
      invocation_target=excluded.invocation_target,
      input_modalities=excluded.input_modalities,
      inference_types=excluded.inference_types,
      risk_tier=excluded.risk_tier,
      capability_classes=excluded.capability_classes,
      observed_at=excluded.observed_at,
      source_ref=excluded.source_ref;

  if (select count(*) from private.pandora_bedrock_reasoning_catalog)<>72 then
    raise exception 'BEDROCK_REASONING_CATALOG_COUNT_MISMATCH';
  end if;
  if not exists(
    select 1 from private.pandora_bedrock_reasoning_catalog
    where model_id='openai.gpt-6-astra' and invocation_target='us.openai.gpt-6-astra'
  ) then raise exception 'BEDROCK_ASTRA_MISSING'; end if;
end;
$catalog_block$;

create table if not exists private.pandora_ops_worker_model_attestations (
  organization_id uuid not null,
  project_id uuid not null,
  worker_key text not null,
  principal_key text not null,
  provider text not null,
  model text not null,
  model_revision text,
  verifier_principal text not null,
  attestation_ref text not null check(length(attestation_ref) between 8 and 500),
  attested_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  primary key(organization_id,project_id,worker_key),
  foreign key(organization_id,project_id,worker_key)
    references private.pandora_ops_workers(organization_id,project_id,worker_key)
);
alter table private.pandora_ops_worker_model_attestations enable row level security;
revoke all on private.pandora_ops_worker_model_attestations from public,anon,authenticated,service_role;

create or replace function public.pandora_ops_verify_worker_model_attestation_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_provider text,
  p_model text,
  p_model_revision text,
  p_verifier_principal text,
  p_attestation_ref text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare w private.pandora_ops_workers%rowtype;
begin
  select * into w
  from private.pandora_ops_workers
  where organization_id=p_organization_id
    and project_id=p_project_id
    and worker_key=p_worker_key
  for update;

  if not found
     or w.engine<>'chatgpt'
     or w.principal_key is distinct from p_principal_key
     or not w.acknowledged
     or not w.connected
     or w.health<>'ready'
     or w.heartbeat_at is null
     or w.heartbeat_at<clock_timestamp()-interval '60 seconds'
  then raise exception 'OPS_WORKER_MODEL_ATTESTATION_DENIED' using errcode='42501'; end if;

  if p_provider<>'openai'
     or p_model<>'gpt-6-astra'
     or p_verifier_principal is null
     or p_verifier_principal=p_principal_key
     or nullif(btrim(p_attestation_ref),'') is null
     or length(p_attestation_ref) not between 8 and 500
     or p_expires_at<=clock_timestamp()
     or p_expires_at>clock_timestamp()+interval '1 hour'
  then raise exception 'OPS_WORKER_MODEL_ATTESTATION_INVALID' using errcode='22023'; end if;

  insert into private.pandora_ops_worker_model_attestations(
    organization_id,project_id,worker_key,principal_key,provider,model,model_revision,
    verifier_principal,attestation_ref,attested_at,expires_at
  ) values (
    p_organization_id,p_project_id,p_worker_key,p_principal_key,p_provider,p_model,
    nullif(btrim(p_model_revision),''),p_verifier_principal,p_attestation_ref,clock_timestamp(),p_expires_at
  )
  on conflict(organization_id,project_id,worker_key) do update
  set principal_key=excluded.principal_key,
      provider=excluded.provider,
      model=excluded.model,
      model_revision=excluded.model_revision,
      verifier_principal=excluded.verifier_principal,
      attestation_ref=excluded.attestation_ref,
      attested_at=excluded.attested_at,
      expires_at=excluded.expires_at;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'worker-model:'||p_worker_key||':'||extract(epoch from clock_timestamp())::bigint,
    null,'worker_model_attested',p_attestation_ref
  );

  return jsonb_build_object(
    'attested',true,'workerKey',p_worker_key,'provider',p_provider,'model',p_model,
    'verifierPrincipal',p_verifier_principal,'expiresAt',p_expires_at
  );
end;
$body$;

create or replace function public.pandora_ops_worker_model_attestation_read_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text
) returns jsonb
language sql
security definer
set search_path=''
as $body$
  select case when a.worker_key is null then
    jsonb_build_object('attested',false,'workerKey',p_worker_key)
  else
    jsonb_build_object(
      'attested',a.expires_at>clock_timestamp(),
      'workerKey',a.worker_key,
      'provider',a.provider,
      'model',a.model,
      'modelRevision',a.model_revision,
      'verifierPrincipal',a.verifier_principal,
      'attestationRef',a.attestation_ref,
      'attestedAt',a.attested_at,
      'expiresAt',a.expires_at
    )
  end
  from (select 1) seed
  left join private.pandora_ops_worker_model_attestations a
    on a.organization_id=p_organization_id
   and a.project_id=p_project_id
   and a.worker_key=p_worker_key;
$body$;

revoke all on function public.pandora_ops_verify_worker_model_attestation_v1(
  uuid,uuid,text,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_ops_verify_worker_model_attestation_v1(
  uuid,uuid,text,text,text,text,text,text,text,timestamptz
) to service_role;
revoke all on function public.pandora_ops_worker_model_attestation_read_v1(uuid,uuid,text)
from public,anon,authenticated;
grant execute on function public.pandora_ops_worker_model_attestation_read_v1(uuid,uuid,text)
to service_role;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('bedrock','enabled','true',true,now()),
  ('bedrock','routing_eligible','true',true,now()),
  ('bedrock','region','us-east-1',true,now()),
  ('bedrock','role_arn','arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2',true,now()),
  ('bedrock','transport','bedrock_converse',true,now()),
  ('bedrock','default_model','openai.gpt-6-astra',true,now()),
  ('bedrock','fast_model','openai.gpt-6-luna',true,now()),
  ('bedrock','catalog_count','72',true,now()),
  ('bedrock','catalog_observed_at','2026-09-27T07:07:52Z',true,now()),
  ('bedrock','catalog_source','aws:bedrock:us-east-1:list-foundation-models+list-inference-profiles',true,now()),
  ('bedrock','policy_version','bedrock-reasoning-fleet-v1',true,now()),
  ('bedrock','auth_mode','vercel_oidc_sts',true,now()),
  ('chatgpt_worker','enabled','true',true,now()),
  ('chatgpt_worker','allowed_models','["gpt-6-astra"]',true,now()),
  ('chatgpt_worker','attestation_required','true',true,now()),
  ('chatgpt_worker','routing_eligible','false',true,now()),
  ('chatgpt_worker','routing_hold_reason','awaiting_live_model_attestation',true,now())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=excluded.active,updated_at=excluded.updated_at;

do $policy_block$
declare v_policy jsonb;
begin
  -- Fresh migration replay has schema but intentionally no production workspace seed.
  -- Install the catalog/contract everywhere; seed the live policy only where the
  -- canonical Operations workspace actually exists.
  if not exists(
    select 1 from private.pandora_ops_workspaces
    where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  ) then
    raise notice 'BEDROCK_POLICY_SEED_SKIPPED_NO_CANONICAL_WORKSPACE';
  else
    if exists(
      select 1 from private.pandora_ops_inference_policies
      where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
        and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
        and active
    ) then
      raise exception 'INFERENCE_POLICY_RECONCILIATION_REQUIRED';
    end if;

  select jsonb_build_object(
    'version','bedrock-reasoning-fleet-v1',
    'models',jsonb_agg(
      jsonb_build_object(
        'provider','bedrock',
        'model',model_id,
        'modelRevision',null,
        'configurationDigest',encode(extensions.digest(
          convert_to(model_id||'|'||invocation_target||'|arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2|us-east-1','UTF8'),'sha256'
        ),'hex'),
        'classes',to_jsonb(capability_classes),
        'modalities',to_jsonb(case when 'IMAGE'=any(input_modalities) then array['text','image']::text[] else array['text']::text[] end),
        'executionBoundary','cloud',
        'riskTier',risk_tier,
        'contextTokens',32768,
        'maxInputBytes',131072,
        'maxOutputTokens',4096,
        'imageTokenUpperBound',case when 'IMAGE'=any(input_modalities) then 8192 else 0 end,
        'transport','bedrock_converse',
        'approved',true,
        'approvalRef','owner:chat:2026-09-27:add-bedrock-reasoning-fleet',
        'approvalExpiresAt','2026-10-27T07:07:52Z',
        'available',true,
        'healthObservedAt','2026-09-27T07:07:52Z',
        'estimatedLatencyMs',null,
        -- Reservation ceiling, not a pricing claim. Parent Operations budgets remain authoritative.
        'maxCostMicros',5000000,
        'maxConcurrency',1
      ) order by provider_name,model_name,model_id
    ),
    'maxAttempts',3,
    'maxHealthAgeMs',2592000000,
    'minHistorySamples',3,
    'maxHistoryAgeMs',2592000000,
    'minimumRiskTier',jsonb_build_object('read',0,'source',2,'preview',2,'production',3,'destructive',3),
    'allowedBoundaries',jsonb_build_array('cloud'),
    'allowedProviders',jsonb_build_array('bedrock'),
    'allowedFallbackCodes',jsonb_build_array('rate_limit','unavailable','invalid_output','verification_failed'),
    'override',null,
    'requireMemoryContext',false
  )
  into v_policy
  from private.pandora_bedrock_reasoning_catalog;

  if jsonb_array_length(v_policy->'models')<>72 then
    raise exception 'BEDROCK_REASONING_CATALOG_COUNT_MISMATCH';
  end if;

  insert into private.pandora_ops_inference_policies(
    organization_id,project_id,revision,policy,active,approval_ref
  ) values (
    '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
    'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
    1,v_policy,true,
    'owner:chat:2026-09-27:add-bedrock-reasoning-fleet'
  );
  end if;
end;
$policy_block$;

comment on table private.pandora_bedrock_reasoning_catalog is
  'Exact 2026-09-27 AWS account Bedrock text-reasoning catalog. Catalog admission is not spending authority.';
comment on table private.pandora_ops_worker_model_attestations is
  'Short-lived independently verified model identity attestations for actual ChatGPT workers. No worker is seeded or assumed to be Astra.';
