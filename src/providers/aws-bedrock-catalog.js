"use strict";

const BEDROCK_REGION = "us-east-1";
const BEDROCK_ROLE_ARN = "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2";
const BEDROCK_CATALOG_OBSERVED_AT = "2026-09-27T07:07:52Z";
const BEDROCK_CATALOG_SOURCE = "aws:bedrock:us-east-1:list-foundation-models+list-inference-profiles";

const BEDROCK_REASONING_MODELS = Object.freeze([
  {
    "modelId": "amazon.nova-2-lite-v1:0",
    "modelName": "Nova 2 Lite",
    "providerName": "Amazon",
    "inputModalities": [
      "TEXT",
      "IMAGE",
      "VIDEO"
    ],
    "invocationTarget": "us.amazon.nova-2-lite-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "amazon.nova-lite-v1:0",
    "modelName": "Nova Lite",
    "providerName": "Amazon",
    "inputModalities": [
      "TEXT",
      "IMAGE",
      "VIDEO"
    ],
    "invocationTarget": "amazon.nova-lite-v1:0",
    "inferenceTypes": [
      "ON_DEMAND",
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "amazon.nova-micro-v1:0",
    "modelName": "Nova Micro",
    "providerName": "Amazon",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "amazon.nova-micro-v1:0",
    "inferenceTypes": [
      "ON_DEMAND",
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "amazon.nova-pro-v1:0",
    "modelName": "Nova Pro",
    "providerName": "Amazon",
    "inputModalities": [
      "TEXT",
      "IMAGE",
      "VIDEO"
    ],
    "invocationTarget": "amazon.nova-pro-v1:0",
    "inferenceTypes": [
      "ON_DEMAND",
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-fable-5",
    "modelName": "Claude Fable 5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-fable-5",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-fable-5-1",
    "modelName": "Claude Fable 5.1",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-fable-5-1",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-haiku-4-5-20251001-v1:0",
    "modelName": "Claude Haiku 4.5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-4-5-20251101-v1:0",
    "modelName": "Claude Opus 4.5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-4-5-20251101-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-4-6-v1",
    "modelName": "Claude Opus 4.6",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-4-6-v1",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-4-7",
    "modelName": "Claude Opus 4.7",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-4-7",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-4-8",
    "modelName": "Claude Opus 4.8",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-4-8",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-5",
    "modelName": "Claude Opus 5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-5",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-opus-5-5",
    "modelName": "Claude Opus 5.5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-opus-5-5",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-sonnet-4-5-20250929-v1:0",
    "modelName": "Claude Sonnet 4.5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-sonnet-4-6",
    "modelName": "Claude Sonnet 4.6",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-sonnet-4-6",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "anthropic.claude-sonnet-5",
    "modelName": "Claude Sonnet 5",
    "providerName": "Anthropic",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.anthropic.claude-sonnet-5",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "deepseek.v3.2",
    "modelName": "DeepSeek V3.2",
    "providerName": "DeepSeek",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "deepseek.v3.2",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "deepseek.r1-v1:0",
    "modelName": "DeepSeek-R1",
    "providerName": "DeepSeek",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.deepseek.r1-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "google.gemma-3-12b-it",
    "modelName": "Gemma 3 12B IT",
    "providerName": "Google",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "google.gemma-3-12b-it",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "google.gemma-3-27b-it",
    "modelName": "Gemma 3 27B PT",
    "providerName": "Google",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "google.gemma-3-27b-it",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "google.gemma-3-4b-it",
    "modelName": "Gemma 3 4B IT",
    "providerName": "Google",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "google.gemma-3-4b-it",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "meta.llama3-70b-instruct-v1:0",
    "modelName": "Llama 3 70B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "meta.llama3-70b-instruct-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "meta.llama3-8b-instruct-v1:0",
    "modelName": "Llama 3 8B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "meta.llama3-8b-instruct-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "meta.llama3-1-70b-instruct-v1:0",
    "modelName": "Llama 3.1 70B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.meta.llama3-1-70b-instruct-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "meta.llama3-1-8b-instruct-v1:0",
    "modelName": "Llama 3.1 8B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.meta.llama3-1-8b-instruct-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "meta.llama3-3-70b-instruct-v1:0",
    "modelName": "Llama 3.3 70B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.meta.llama3-3-70b-instruct-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "meta.llama4-maverick-17b-instruct-v1:0",
    "modelName": "Llama 4 Maverick 17B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.meta.llama4-maverick-17b-instruct-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "meta.llama4-scout-17b-instruct-v1:0",
    "modelName": "Llama 4 Scout 17B Instruct",
    "providerName": "Meta",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.meta.llama4-scout-17b-instruct-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "minimax.minimax-m2",
    "modelName": "MiniMax M2",
    "providerName": "MiniMax",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "minimax.minimax-m2",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "minimax.minimax-m2.1",
    "modelName": "MiniMax M2.1",
    "providerName": "MiniMax",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "minimax.minimax-m2.1",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "minimax.minimax-m2.5",
    "modelName": "MiniMax M2.5",
    "providerName": "MiniMax",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "minimax.minimax-m2.5",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.devstral-2-123b",
    "modelName": "Devstral 2 123B",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "mistral.devstral-2-123b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.magistral-small-2509",
    "modelName": "Magistral Small 2509",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "mistral.magistral-small-2509",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.ministral-3-14b-instruct",
    "modelName": "Ministral 14B 3.0",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "mistral.ministral-3-14b-instruct",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.ministral-3-8b-instruct",
    "modelName": "Ministral 3 8B",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "mistral.ministral-3-8b-instruct",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.ministral-3-3b-instruct",
    "modelName": "Ministral 3B",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "mistral.ministral-3-3b-instruct",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.mistral-7b-instruct-v0:2",
    "modelName": "Mistral 7B Instruct",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "mistral.mistral-7b-instruct-v0:2",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.mistral-large-2402-v1:0",
    "modelName": "Mistral Large (24.02)",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "mistral.mistral-large-2402-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.mistral-large-3-675b-instruct",
    "modelName": "Mistral Large 3",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "mistral.mistral-large-3-675b-instruct",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.mistral-small-2402-v1:0",
    "modelName": "Mistral Small (24.02)",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "mistral.mistral-small-2402-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.mixtral-8x7b-instruct-v0:1",
    "modelName": "Mixtral 8x7B Instruct",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "mistral.mixtral-8x7b-instruct-v0:1",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "mistral.pixtral-large-2502-v1:0",
    "modelName": "Pixtral Large (25.02)",
    "providerName": "Mistral AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.mistral.pixtral-large-2502-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "moonshot.kimi-k2-thinking",
    "modelName": "Kimi K2 Thinking",
    "providerName": "Moonshot AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "moonshot.kimi-k2-thinking",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "moonshotai.kimi-k2.5",
    "modelName": "Kimi K2.5",
    "providerName": "Moonshot AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "moonshotai.kimi-k2.5",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "moonshotai.kimi-k3",
    "modelName": "Kimi K3",
    "providerName": "Moonshot AI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.moonshotai.kimi-k3",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "nvidia.nemotron-super-3-120b",
    "modelName": "NVIDIA Nemotron 3 Super 120B A12B",
    "providerName": "NVIDIA",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "nvidia.nemotron-super-3-120b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "nvidia.nemotron-nano-12b-v2",
    "modelName": "NVIDIA Nemotron Nano 12B v2 VL BF16",
    "providerName": "NVIDIA",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "nvidia.nemotron-nano-12b-v2",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "nvidia.nemotron-nano-9b-v2",
    "modelName": "NVIDIA Nemotron Nano 9B v2",
    "providerName": "NVIDIA",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "nvidia.nemotron-nano-9b-v2",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "nvidia.nemotron-nano-3-30b",
    "modelName": "Nemotron Nano 3 30B",
    "providerName": "NVIDIA",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "nvidia.nemotron-nano-3-30b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "openai.gpt-5.4",
    "modelName": "GPT 5.4",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-5.4",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-5.5",
    "modelName": "GPT 5.5",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-5.5",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-5.6-luna",
    "modelName": "GPT-5.6 Luna",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-5.6-luna",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-5.6-sol",
    "modelName": "GPT-5.6 Sol",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-5.6-sol",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-5.6-terra",
    "modelName": "GPT-5.6 Terra",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-5.6-terra",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-6-astra",
    "modelName": "GPT-6 Astra",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-6-astra",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-6-luna",
    "modelName": "GPT-6 Luna",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-6-luna",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-6-sol",
    "modelName": "GPT-6 Sol",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.openai.gpt-6-sol",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "openai.gpt-oss-120b-1:0",
    "modelName": "gpt-oss-120b",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "openai.gpt-oss-120b-1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "openai.gpt-oss-20b-1:0",
    "modelName": "gpt-oss-20b",
    "providerName": "OpenAI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "openai.gpt-oss-20b-1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "qwen.qwen3-32b-v1:0",
    "modelName": "Qwen3 32B (dense)",
    "providerName": "Qwen",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "qwen.qwen3-32b-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "qwen.qwen3-coder-next",
    "modelName": "Qwen3 Coder Next",
    "providerName": "Qwen",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "qwen.qwen3-coder-next",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "qwen.qwen3-next-80b-a3b",
    "modelName": "Qwen3 Next 80B A3B",
    "providerName": "Qwen",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "qwen.qwen3-next-80b-a3b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "qwen.qwen3-vl-235b-a22b",
    "modelName": "Qwen3 VL 235B A22B",
    "providerName": "Qwen",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "qwen.qwen3-vl-235b-a22b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "qwen.qwen3-coder-30b-a3b-v1:0",
    "modelName": "Qwen3-Coder-30B-A3B-Instruct",
    "providerName": "Qwen",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "qwen.qwen3-coder-30b-a3b-v1:0",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "twelvelabs.pegasus-1-2-v1:0",
    "modelName": "Pegasus v1.2",
    "providerName": "TwelveLabs",
    "inputModalities": [
      "TEXT",
      "VIDEO"
    ],
    "invocationTarget": "twelvelabs.pegasus-1-2-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE",
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "writer.palmyra-x4-v1:0",
    "modelName": "Palmyra X4",
    "providerName": "Writer",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.writer.palmyra-x4-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "writer.palmyra-x5-v1:0",
    "modelName": "Palmyra X5",
    "providerName": "Writer",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "us.writer.palmyra-x5-v1:0",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  },
  {
    "modelId": "writer.palmyra-vision-7b",
    "modelName": "Writer Palmyra Vision 7B",
    "providerName": "Writer",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "writer.palmyra-vision-7b",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "zai.glm-4.7",
    "modelName": "GLM 4.7",
    "providerName": "Z.AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "zai.glm-4.7",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "zai.glm-4.7-flash",
    "modelName": "GLM 4.7 Flash",
    "providerName": "Z.AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "zai.glm-4.7-flash",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "zai.glm-5",
    "modelName": "GLM 5",
    "providerName": "Z.AI",
    "inputModalities": [
      "TEXT"
    ],
    "invocationTarget": "zai.glm-5",
    "inferenceTypes": [
      "ON_DEMAND"
    ]
  },
  {
    "modelId": "xai.grok-4.6",
    "modelName": "Grok 4.6",
    "providerName": "xAI",
    "inputModalities": [
      "TEXT",
      "IMAGE"
    ],
    "invocationTarget": "us.xai.grok-4.6",
    "inferenceTypes": [
      "INFERENCE_PROFILE"
    ]
  }
]);

const BEDROCK_REASONING_MODEL_MAP = new Map(
  BEDROCK_REASONING_MODELS.map((entry) => [entry.modelId, Object.freeze({...entry})]),
);

function getBedrockReasoningModel(modelId) {
  return BEDROCK_REASONING_MODEL_MAP.get(String(modelId || "")) || null;
}

function isBedrockReasoningModel(modelId) {
  return BEDROCK_REASONING_MODEL_MAP.has(String(modelId || ""));
}

module.exports = {
  BEDROCK_REGION,
  BEDROCK_ROLE_ARN,
  BEDROCK_CATALOG_OBSERVED_AT,
  BEDROCK_CATALOG_SOURCE,
  BEDROCK_REASONING_MODELS,
  getBedrockReasoningModel,
  isBedrockReasoningModel,
};
