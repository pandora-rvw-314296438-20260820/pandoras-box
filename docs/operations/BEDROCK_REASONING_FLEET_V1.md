# Bedrock reasoning fleet v1

## Purpose

Pandora exposes the AWS account's governed Bedrock reasoning/generative text fleet to the Operations Intelligence Router without giving models scheduler, release, credential, approval, spending, or Memory authority.

This fleet is separate from the Windows RDP worker. Models reason. Operations schedules. The RDP executes bounded Windows/toolchain work. Independent verification remains required for consequential outcomes.

## Live AWS inventory

Observed: 2026-09-27T07:07:52Z in `us-east-1`.

The canonical catalog contains **72 ACTIVE account-authorized text-input/text-output Bedrock models** across 15 providers. Each entry is either directly on-demand or has a resolved system inference profile. The generated catalog is `src/providers/aws-bedrock-catalog.js`.

Excluded from the reasoning fleet are embedding-only, image/video generation-only, reranking, safeguard, speech-first, and provisioned-only duplicate entries. They remain AWS capabilities but are not truthfully represented as general reasoning workers.

The catalog includes GPT-6 Astra, GPT-6 Sol/Luna, GPT-5.6 Sol/Terra/Luna, Claude Opus/Sonnet/Fable families, Grok 4.6, Kimi K2/K3, DeepSeek, Qwen, Nova, Llama, Mistral, Nemotron, GLM, Gemma, Palmyra and other account-authorized text-generative models.

## AWS authority boundary

Production Bedrock calls use Vercel workload OIDC and the dedicated role:

`arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2`

Trust is limited to the mcpmaster production Vercel subject. The role has no managed policies and its only runtime permissions are Bedrock model invocation actions. Static AWS credentials are not stored.

The older `PandoraVercelBedrockRuntime` role was observed to carry broad unrelated authority. It is not used by the new runtime even if a legacy Vercel environment variable still names it. Source code hard-pins the narrow role and catalog.

## Routing and cost

The Vercel Operations inference runtime adds `bedrock_converse` beside the existing Gemini transport. The Supabase Edge inference runtime remains Gemini-only because it cannot impersonate Vercel workload identity.

The active Bedrock policy admits the 72 models with conservative context/output ceilings and per-model reservation ceilings. Catalog admission is **not spending authority**. A provider call still requires a real Operations lease whose reserved inference budget is large enough. Existing Operations leases were observed with zero reserved inference cost, so adding the fleet does not silently start paid model traffic.

Provider receipts record output digest, provider receipt digest, usage when reported, latency and nullable billing. Unknown transport outcomes remain reconciliation-required; no zero-cost result is fabricated.

## Astra ChatGPT worker

Astra is available immediately as the Bedrock model `openai.gpt-6-astra` through `us.openai.gpt-6-astra`.

A separate ChatGPT-worker lane is installed but is deliberately not self-certified. Pandora stores short-lived worker model attestations only after a live acknowledged ChatGPT worker with a fresh heartbeat proves provider/model identity. The permitted model for this lane is currently `openai:gpt-6-astra`.

Until such an attestation exists, `chatgpt_worker.routing_eligible=false`. This prevents a generic ChatGPT worker from being mislabeled Astra.

## Verification

Before production activation:
- exact-head CI must pass;
- the branch must be current with canonical main;
- coordinator PASS and merge claim are required;
- migration readback must confirm 72 catalog entries and active policy;
- AWS readback must confirm the narrow IAM role;
- at least one bounded provider canary should prove Bedrock invocation without exposing credentials.

A single provider canary proves the transport and identity path, not the quality of every model. Model availability for the rest of the fleet comes from the account-scoped AWS Bedrock authorization/profile inventory and remains subject to circuit-breaker/fallback handling at runtime.
