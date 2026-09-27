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

insert into private.pandora_bedrock_reasoning_catalog(
  model_id,model_name,provider_name,invocation_target,input_modalities,inference_types,
  risk_tier,capability_classes,observed_at,source_ref
) values
(
  'amazon.nova-2-lite-v1:0',
  'Nova 2 Lite',
  'Amazon',
  'us.amazon.nova-2-lite-v1:0',
  array['TEXT','IMAGE','VIDEO']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'amazon.nova-lite-v1:0',
  'Nova Lite',
  'Amazon',
  'amazon.nova-lite-v1:0',
  array['TEXT','IMAGE','VIDEO']::text[],
  array['ON_DEMAND','INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'amazon.nova-micro-v1:0',
  'Nova Micro',
  'Amazon',
  'amazon.nova-micro-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND','INFERENCE_PROFILE']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'amazon.nova-pro-v1:0',
  'Nova Pro',
  'Amazon',
  'amazon.nova-pro-v1:0',
  array['TEXT','IMAGE','VIDEO']::text[],
  array['ON_DEMAND','INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-fable-5',
  'Claude Fable 5',
  'Anthropic',
  'us.anthropic.claude-fable-5',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-fable-5-1',
  'Claude Fable 5.1',
  'Anthropic',
  'us.anthropic.claude-fable-5-1',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-haiku-4-5-20251001-v1:0',
  'Claude Haiku 4.5',
  'Anthropic',
  'us.anthropic.claude-haiku-4-5-20251001-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'anthropic.claude-opus-4-5-20251101-v1:0',
  'Claude Opus 4.5',
  'Anthropic',
  'us.anthropic.claude-opus-4-5-20251101-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-opus-4-6-v1',
  'Claude Opus 4.6',
  'Anthropic',
  'us.anthropic.claude-opus-4-6-v1',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-opus-4-7',
  'Claude Opus 4.7',
  'Anthropic',
  'us.anthropic.claude-opus-4-7',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-opus-4-8',
  'Claude Opus 4.8',
  'Anthropic',
  'us.anthropic.claude-opus-4-8',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-opus-5',
  'Claude Opus 5',
  'Anthropic',
  'us.anthropic.claude-opus-5',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-opus-5-5',
  'Claude Opus 5.5',
  'Anthropic',
  'us.anthropic.claude-opus-5-5',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-sonnet-4-5-20250929-v1:0',
  'Claude Sonnet 4.5',
  'Anthropic',
  'us.anthropic.claude-sonnet-4-5-20250929-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-sonnet-4-6',
  'Claude Sonnet 4.6',
  'Anthropic',
  'us.anthropic.claude-sonnet-4-6',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'anthropic.claude-sonnet-5',
  'Claude Sonnet 5',
  'Anthropic',
  'us.anthropic.claude-sonnet-5',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'deepseek.v3.2',
  'DeepSeek V3.2',
  'DeepSeek',
  'deepseek.v3.2',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'deepseek.r1-v1:0',
  'DeepSeek-R1',
  'DeepSeek',
  'us.deepseek.r1-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'google.gemma-3-12b-it',
  'Gemma 3 12B IT',
  'Google',
  'google.gemma-3-12b-it',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision']::text[]
),
(
  'google.gemma-3-27b-it',
  'Gemma 3 27B PT',
  'Google',
  'google.gemma-3-27b-it',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision']::text[]
),
(
  'google.gemma-3-4b-it',
  'Gemma 3 4B IT',
  'Google',
  'google.gemma-3-4b-it',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision']::text[]
),
(
  'meta.llama3-70b-instruct-v1:0',
  'Llama 3 70B Instruct',
  'Meta',
  'meta.llama3-70b-instruct-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'meta.llama3-8b-instruct-v1:0',
  'Llama 3 8B Instruct',
  'Meta',
  'meta.llama3-8b-instruct-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'meta.llama3-1-70b-instruct-v1:0',
  'Llama 3.1 70B Instruct',
  'Meta',
  'us.meta.llama3-1-70b-instruct-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'meta.llama3-1-8b-instruct-v1:0',
  'Llama 3.1 8B Instruct',
  'Meta',
  'us.meta.llama3-1-8b-instruct-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'meta.llama3-3-70b-instruct-v1:0',
  'Llama 3.3 70B Instruct',
  'Meta',
  'us.meta.llama3-3-70b-instruct-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'meta.llama4-maverick-17b-instruct-v1:0',
  'Llama 4 Maverick 17B Instruct',
  'Meta',
  'us.meta.llama4-maverick-17b-instruct-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'meta.llama4-scout-17b-instruct-v1:0',
  'Llama 4 Scout 17B Instruct',
  'Meta',
  'us.meta.llama4-scout-17b-instruct-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'minimax.minimax-m2',
  'MiniMax M2',
  'MiniMax',
  'minimax.minimax-m2',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification']::text[]
),
(
  'minimax.minimax-m2.1',
  'MiniMax M2.1',
  'MiniMax',
  'minimax.minimax-m2.1',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification']::text[]
),
(
  'minimax.minimax-m2.5',
  'MiniMax M2.5',
  'MiniMax',
  'minimax.minimax-m2.5',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification']::text[]
),
(
  'mistral.devstral-2-123b',
  'Devstral 2 123B',
  'Mistral AI',
  'mistral.devstral-2-123b',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'mistral.magistral-small-2509',
  'Magistral Small 2509',
  'Mistral AI',
  'mistral.magistral-small-2509',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'mistral.ministral-3-14b-instruct',
  'Ministral 14B 3.0',
  'Mistral AI',
  'mistral.ministral-3-14b-instruct',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'mistral.ministral-3-8b-instruct',
  'Ministral 3 8B',
  'Mistral AI',
  'mistral.ministral-3-8b-instruct',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'mistral.ministral-3-3b-instruct',
  'Ministral 3B',
  'Mistral AI',
  'mistral.ministral-3-3b-instruct',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'mistral.mistral-7b-instruct-v0:2',
  'Mistral 7B Instruct',
  'Mistral AI',
  'mistral.mistral-7b-instruct-v0:2',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'mistral.mistral-large-2402-v1:0',
  'Mistral Large (24.02)',
  'Mistral AI',
  'mistral.mistral-large-2402-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'mistral.mistral-large-3-675b-instruct',
  'Mistral Large 3',
  'Mistral AI',
  'mistral.mistral-large-3-675b-instruct',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'mistral.mistral-small-2402-v1:0',
  'Mistral Small (24.02)',
  'Mistral AI',
  'mistral.mistral-small-2402-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'mistral.mixtral-8x7b-instruct-v0:1',
  'Mixtral 8x7B Instruct',
  'Mistral AI',
  'mistral.mixtral-8x7b-instruct-v0:1',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'mistral.pixtral-large-2502-v1:0',
  'Pixtral Large (25.02)',
  'Mistral AI',
  'us.mistral.pixtral-large-2502-v1:0',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'moonshot.kimi-k2-thinking',
  'Kimi K2 Thinking',
  'Moonshot AI',
  'moonshot.kimi-k2-thinking',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'moonshotai.kimi-k2.5',
  'Kimi K2.5',
  'Moonshot AI',
  'moonshotai.kimi-k2.5',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'moonshotai.kimi-k3',
  'Kimi K3',
  'Moonshot AI',
  'us.moonshotai.kimi-k3',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'nvidia.nemotron-super-3-120b',
  'NVIDIA Nemotron 3 Super 120B A12B',
  'NVIDIA',
  'nvidia.nemotron-super-3-120b',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'nvidia.nemotron-nano-12b-v2',
  'NVIDIA Nemotron Nano 12B v2 VL BF16',
  'NVIDIA',
  'nvidia.nemotron-nano-12b-v2',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'nvidia.nemotron-nano-9b-v2',
  'NVIDIA Nemotron Nano 9B v2',
  'NVIDIA',
  'nvidia.nemotron-nano-9b-v2',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'nvidia.nemotron-nano-3-30b',
  'Nemotron Nano 3 30B',
  'NVIDIA',
  'nvidia.nemotron-nano-3-30b',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'openai.gpt-5.4',
  'GPT 5.4',
  'OpenAI',
  'us.openai.gpt-5.4',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'openai.gpt-5.5',
  'GPT 5.5',
  'OpenAI',
  'us.openai.gpt-5.5',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'openai.gpt-5.6-luna',
  'GPT-5.6 Luna',
  'OpenAI',
  'us.openai.gpt-5.6-luna',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding']::text[]
),
(
  'openai.gpt-5.6-sol',
  'GPT-5.6 Sol',
  'OpenAI',
  'us.openai.gpt-5.6-sol',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'openai.gpt-5.6-terra',
  'GPT-5.6 Terra',
  'OpenAI',
  'us.openai.gpt-5.6-terra',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'openai.gpt-6-astra',
  'GPT-6 Astra',
  'OpenAI',
  'us.openai.gpt-6-astra',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'openai.gpt-6-luna',
  'GPT-6 Luna',
  'OpenAI',
  'us.openai.gpt-6-luna',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'openai.gpt-6-sol',
  'GPT-6 Sol',
  'OpenAI',
  'us.openai.gpt-6-sol',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'openai.gpt-oss-120b-1:0',
  'gpt-oss-120b',
  'OpenAI',
  'openai.gpt-oss-120b-1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'openai.gpt-oss-20b-1:0',
  'gpt-oss-20b',
  'OpenAI',
  'openai.gpt-oss-20b-1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'qwen.qwen3-32b-v1:0',
  'Qwen3 32B (dense)',
  'Qwen',
  'qwen.qwen3-32b-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'qwen.qwen3-coder-next',
  'Qwen3 Coder Next',
  'Qwen',
  'qwen.qwen3-coder-next',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'qwen.qwen3-next-80b-a3b',
  'Qwen3 Next 80B A3B',
  'Qwen',
  'qwen.qwen3-next-80b-a3b',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'qwen.qwen3-vl-235b-a22b',
  'Qwen3 VL 235B A22B',
  'Qwen',
  'qwen.qwen3-vl-235b-a22b',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'qwen.qwen3-coder-30b-a3b-v1:0',
  'Qwen3-Coder-30B-A3B-Instruct',
  'Qwen',
  'qwen.qwen3-coder-30b-a3b-v1:0',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'twelvelabs.pegasus-1-2-v1:0',
  'Pegasus v1.2',
  'TwelveLabs',
  'twelvelabs.pegasus-1-2-v1:0',
  array['TEXT','VIDEO']::text[],
  array['INFERENCE_PROFILE','ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification']::text[]
),
(
  'writer.palmyra-x4-v1:0',
  'Palmyra X4',
  'Writer',
  'us.writer.palmyra-x4-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification']::text[]
),
(
  'writer.palmyra-x5-v1:0',
  'Palmyra X5',
  'Writer',
  'us.writer.palmyra-x5-v1:0',
  array['TEXT']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','deep_reasoning']::text[]
),
(
  'writer.palmyra-vision-7b',
  'Writer Palmyra Vision 7B',
  'Writer',
  'writer.palmyra-vision-7b',
  array['TEXT','IMAGE']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision']::text[]
),
(
  'zai.glm-4.7',
  'GLM 4.7',
  'Z.AI',
  'zai.glm-4.7',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  2,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'zai.glm-4.7-flash',
  'GLM 4.7 Flash',
  'Z.AI',
  'zai.glm-4.7-flash',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  1,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding']::text[]
),
(
  'zai.glm-5',
  'GLM 5',
  'Z.AI',
  'zai.glm-5',
  array['TEXT']::text[],
  array['ON_DEMAND']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','fast_coding','deep_reasoning','complex_coding']::text[]
),
(
  'xai.grok-4.6',
  'Grok 4.6',
  'xAI',
  'us.xai.grok-4.6',
  array['TEXT','IMAGE']::text[],
  array['INFERENCE_PROFILE']::text[],
  3,
  array['research','structured_extraction','cheap_bulk','independent_verification','vision','fast_coding','deep_reasoning','complex_coding']::text[]
)
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

create table if not exists private.pandora_ops_worker_model_attestations (
  organization_id uuid not null,
  project_id uuid not null,
  worker_key text not null,
  principal_key text not null,
  provider text not null,
  model text not null,
  model_revision text,
  attestation_ref text not null check(length(attestation_ref) between 8 and 500),
  attested_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  primary key(organization_id,project_id,worker_key),
  foreign key(organization_id,project_id,worker_key)
    references private.pandora_ops_workers(organization_id,project_id,worker_key)
);

alter table private.pandora_ops_worker_model_attestations enable row level security;
revoke all on private.pandora_ops_worker_model_attestations from public,anon,authenticated,service_role;

create or replace function public.pandora_ops_attest_worker_model_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_provider text,
  p_model text,
  p_model_revision text,
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
     or nullif(btrim(p_attestation_ref),'') is null
     or length(p_attestation_ref) not between 8 and 500
     or p_expires_at<=clock_timestamp()
     or p_expires_at>clock_timestamp()+interval '1 hour'
  then raise exception 'OPS_WORKER_MODEL_ATTESTATION_INVALID' using errcode='22023'; end if;

  insert into private.pandora_ops_worker_model_attestations(
    organization_id,project_id,worker_key,principal_key,provider,model,model_revision,
    attestation_ref,attested_at,expires_at
  ) values (
    p_organization_id,p_project_id,p_worker_key,p_principal_key,p_provider,p_model,
    nullif(btrim(p_model_revision),''),p_attestation_ref,clock_timestamp(),p_expires_at
  )
  on conflict(organization_id,project_id,worker_key) do update
  set principal_key=excluded.principal_key,
      provider=excluded.provider,
      model=excluded.model,
      model_revision=excluded.model_revision,
      attestation_ref=excluded.attestation_ref,
      attested_at=excluded.attested_at,
      expires_at=excluded.expires_at;

  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,
    'worker-model:'||p_worker_key||':'||extract(epoch from clock_timestamp())::bigint,
    null,'worker_model_attested',p_attestation_ref
  );

  return jsonb_build_object(
    'attested',true,
    'workerKey',p_worker_key,
    'provider',p_provider,
    'model',p_model,
    'expiresAt',p_expires_at
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

revoke all on function public.pandora_ops_attest_worker_model_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_ops_attest_worker_model_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) to service_role;

revoke all on function public.pandora_ops_worker_model_attestation_read_v1(
  uuid,uuid,text
) from public,anon,authenticated;
grant execute on function public.pandora_ops_worker_model_attestation_read_v1(
  uuid,uuid,text
) to service_role;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('bedrock','enabled','true',true,now()),
  ('bedrock','routing_eligible','true',true,now()),
  ('bedrock','region','us-east-1',true,now()),
  ('bedrock','role_arn','arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2',true,now()),
  ('bedrock','transport','bedrock_converse',true,now()),
  ('bedrock','default_model','openai.gpt-6-astra',true,now()),
  ('bedrock','allowed_models','["amazon.nova-2-lite-v1:0","amazon.nova-lite-v1:0","amazon.nova-micro-v1:0","amazon.nova-pro-v1:0","anthropic.claude-fable-5","anthropic.claude-fable-5-1","anthropic.claude-haiku-4-5-20251001-v1:0","anthropic.claude-opus-4-5-20251101-v1:0","anthropic.claude-opus-4-6-v1","anthropic.claude-opus-4-7","anthropic.claude-opus-4-8","anthropic.claude-opus-5","anthropic.claude-opus-5-5","anthropic.claude-sonnet-4-5-20250929-v1:0","anthropic.claude-sonnet-4-6","anthropic.claude-sonnet-5","deepseek.v3.2","deepseek.r1-v1:0","google.gemma-3-12b-it","google.gemma-3-27b-it","google.gemma-3-4b-it","meta.llama3-70b-instruct-v1:0","meta.llama3-8b-instruct-v1:0","meta.llama3-1-70b-instruct-v1:0","meta.llama3-1-8b-instruct-v1:0","meta.llama3-3-70b-instruct-v1:0","meta.llama4-maverick-17b-instruct-v1:0","meta.llama4-scout-17b-instruct-v1:0","minimax.minimax-m2","minimax.minimax-m2.1","minimax.minimax-m2.5","mistral.devstral-2-123b","mistral.magistral-small-2509","mistral.ministral-3-14b-instruct","mistral.ministral-3-8b-instruct","mistral.ministral-3-3b-instruct","mistral.mistral-7b-instruct-v0:2","mistral.mistral-large-2402-v1:0","mistral.mistral-large-3-675b-instruct","mistral.mistral-small-2402-v1:0","mistral.mixtral-8x7b-instruct-v0:1","mistral.pixtral-large-2502-v1:0","moonshot.kimi-k2-thinking","moonshotai.kimi-k2.5","moonshotai.kimi-k3","nvidia.nemotron-super-3-120b","nvidia.nemotron-nano-12b-v2","nvidia.nemotron-nano-9b-v2","nvidia.nemotron-nano-3-30b","openai.gpt-5.4","openai.gpt-5.5","openai.gpt-5.6-luna","openai.gpt-5.6-sol","openai.gpt-5.6-terra","openai.gpt-6-astra","openai.gpt-6-luna","openai.gpt-6-sol","openai.gpt-oss-120b-1:0","openai.gpt-oss-20b-1:0","qwen.qwen3-32b-v1:0","qwen.qwen3-coder-next","qwen.qwen3-next-80b-a3b","qwen.qwen3-vl-235b-a22b","qwen.qwen3-coder-30b-a3b-v1:0","twelvelabs.pegasus-1-2-v1:0","writer.palmyra-x4-v1:0","writer.palmyra-x5-v1:0","writer.palmyra-vision-7b","zai.glm-4.7","zai.glm-4.7-flash","zai.glm-5","xai.grok-4.6"]',true,now()),
  ('bedrock','catalog_count','72',true,now()),
  ('bedrock','catalog_observed_at','2026-09-27T07:07:52Z',true,now()),
  ('bedrock','catalog_source','aws:bedrock:us-east-1:list-foundation-models+list-inference-profiles',true,now()),
  ('bedrock','policy_version','bedrock-reasoning-fleet-v1',true,now()),
  ('chatgpt_worker','enabled','true',true,now()),
  ('chatgpt_worker','allowed_models','["gpt-6-astra"]',true,now()),
  ('chatgpt_worker','attestation_required','true',true,now()),
  ('chatgpt_worker','routing_eligible','false',true,now()),
  ('chatgpt_worker','routing_hold_reason','awaiting_live_model_attestation',true,now())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=excluded.active,updated_at=excluded.updated_at;

do $block$
declare v_policy jsonb;
begin
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
        'modalities',to_jsonb(
          case when 'IMAGE'=any(input_modalities) then array['text','image']::text[]
               else array['text']::text[] end
        ),
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
        'maxCostMicros',5000000,
        'maxConcurrency',1
      ) order by provider_name,model_name,model_id
    ),
    'maxAttempts',3,
    'maxHealthAgeMs',2592000000,
    'minHistorySamples',3,
    'maxHistoryAgeMs',2592000000,
    'minimumRiskTier',jsonb_build_object(
      'read',0,'source',2,'preview',2,'production',3,'destructive',3
    ),
    'allowedBoundaries',jsonb_build_array('cloud'),
    'allowedProviders',jsonb_build_array('bedrock'),
    'allowedFallbackCodes',jsonb_build_array(
      'rate_limit','unavailable','invalid_output','verification_failed'
    ),
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
end;
$block$;

comment on table private.pandora_bedrock_reasoning_catalog is
  'Exact 2026-09-27 AWS account Bedrock text-reasoning catalog. Catalog admission is not spending authority.';
comment on table private.pandora_ops_worker_model_attestations is
  'Short-lived provider/model identity attestations for actual ChatGPT workers. No worker is seeded or assumed to be Astra.';
