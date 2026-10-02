# Lane F #907 — live Bedrock verification evidence

Generated from provider readback on 2026-10-02. No secrets are included.

## Scope and source

- Pull request: #907, branch `chatgpt/lane-f-bedrock-live-catalog-v2`.
- Probe candidate semantics were taken from the Lane F live-catalog classifier/target-selection logic.
- Probe cycle: exactly one Bedrock Converse attempt per conversational candidate, prompt `OK`, no retries.
- Probe minute in CloudWatch: `2026-10-02T11:23:00Z`.
- No recurring schedule was enabled.
- Lane D Connections and Lane E global shell/composer were not changed.

## Production sync proof before merge

Production Supabase still has the pre-v2 catalog:
- 72 catalog rows, 15 providers.
- All catalog rows have `observed_at = 2026-09-27 07:07:52+00`.
- Runtime states: `provider_hold=57`, `onboarding_required=12`, `account_denied=3`.
- `private.pandora_bedrock_catalog_sync_state` does not exist.
- Migration `20261002102000_pandora_lane_f_bedrock_live_catalog_v2.sql` is not applied.

Live AWS `us-east-1` discovery at verification time:
- 120 foundation models.
- 93 system-defined inference profiles.
- 78 conversational candidates with an invocation target and ACTIVE/LEGACY lifecycle.

The v2 production sync was intentionally not applied from an unmerged PR.

## Probe result

- Attempts: 78.
- Passed: 48.
- Failed: 30.
- Exact CloudWatch token totals for the probe minute: 735 input, 49 output, 784 total.
- Rejected failures show zero Bedrock input/output tokens.
- One deterministic source defect was found: `moonshotai.kimi-k3` rejects `maxTokens=1`; its minimum is 16.
- The branch fix makes Kimi K3 use 16 while every other model remains at 1. Kimi K3 was not re-probed because the owner approved one attempt per model and no retries.

## Per-call metered inference charge

The charge below is exact observed token usage multiplied by the current applicable AWS Bedrock token rate. It is metered inference charge, not an invoice/CUR posting; AWS billing export is delayed. Claude Sonnet 4.5 used the US geographic inference profile rate ($3.30/M input, $16.50/M output).

| Model | Result | Input tokens | Output tokens | Metered USD |
|---|---:|---:|---:|---:|
| `nvidia.nemotron-nano-12b-v2` | PASS | 17 | 1 | $0.000004000 |
| `qwen.qwen3-coder-next` | PASS | 9 | 1 | $0.000005700 |
| `moonshotai.kimi-k2.5` | PASS | 28 | 1 | $0.000019800 |
| `openai.gpt-oss-120b-1:0` | PASS | 68 | 1 | $0.000010800 |
| `qwen.qwen3-next-80b-a3b` | PASS | 9 | 1 | $0.000002550 |
| `deepseek.v3.2` | PASS | 5 | 1 | $0.000004950 |
| `nvidia.nemotron-nano-3-30b` | PASS | 17 | 1 | $0.000001260 |
| `minimax.minimax-m2` | PASS | 23 | 1 | $0.000008100 |
| `zai.glm-4.7-flash` | PASS | 6 | 1 | $0.000000820 |
| `amazon.nova-pro-v1:0` | PASS | 1 | 1 | $0.000004000 |
| `amazon.nova-2-lite-v1:0` | PASS | 47 | 2 | $0.000021010 |
| `minimax.minimax-m2.5` | PASS | 39 | 1 | $0.000012900 |
| `google.gemma-3-12b-it` | PASS | 10 | 1 | $0.000001190 |
| `moonshot.kimi-k2-thinking` | PASS | 8 | 1 | $0.000007300 |
| `mistral.mistral-large-3-675b-instruct` | PASS | 4 | 1 | $0.000003500 |
| `mistral.devstral-2-123b` | PASS | 4 | 1 | $0.000003600 |
| `minimax.minimax-m2.1` | PASS | 39 | 1 | $0.000012900 |
| `nvidia.nemotron-super-3-120b` | PASS | 17 | 1 | $0.000003200 |
| `qwen.qwen3-32b-v1:0` | PASS | 13 | 1 | $0.000002550 |
| `mistral.ministral-3-14b-instruct` | PASS | 4 | 1 | $0.000001000 |
| `nvidia.nemotron-nano-9b-v2` | PASS | 14 | 1 | $0.000001070 |
| `mistral.ministral-3-8b-instruct` | PASS | 4 | 1 | $0.000000750 |
| `zai.glm-5` | PASS | 6 | 1 | $0.000009200 |
| `openai.gpt-oss-20b-1:0` | PASS | 68 | 1 | $0.000005060 |
| `google.gemma-3-4b-it` | PASS | 10 | 1 | $0.000000480 |
| `google.gemma-3-27b-it` | PASS | 10 | 1 | $0.000002680 |
| `anthropic.claude-sonnet-4-5-20250929-v1:0` | PASS | 8 | 1 | $0.000042900 |
| `qwen.qwen3-vl-235b-a22b` | PASS | 9 | 1 | $0.000007430 |
| `zai.glm-4.7` | PASS | 6 | 1 | $0.000005800 |
| `writer.palmyra-vision-7b` | PASS | 5 | 1 | $0.000001350 |
| `mistral.magistral-small-2509` | PASS | 4 | 1 | $0.000003500 |
| `mistral.ministral-3-3b-instruct` | PASS | 4 | 1 | $0.000000500 |
| `qwen.qwen3-coder-30b-a3b-v1:0` | PASS | 9 | 1 | $0.000001950 |
| `amazon.nova-lite-v1:0` | PASS | 1 | 1 | $0.000000300 |
| `amazon.nova-micro-v1:0` | PASS | 1 | 1 | $0.000000175 |
| `deepseek.r1-v1:0` | PASS | 6 | 1 | $0.000013500 |
| `meta.llama3-8b-instruct-v1:0` | PASS | 15 | 1 | $0.000005100 |
| `meta.llama3-70b-instruct-v1:0` | PASS | 15 | 1 | $0.000043250 |
| `meta.llama3-1-8b-instruct-v1:0` | PASS | 16 | 1 | $0.000003740 |
| `meta.llama3-1-70b-instruct-v1:0` | PASS | 16 | 1 | $0.000012240 |
| `meta.llama3-3-70b-instruct-v1:0` | PASS | 36 | 1 | $0.000026640 |
| `meta.llama4-scout-17b-instruct-v1:0` | PASS | 36 | 1 | $0.000006780 |
| `meta.llama4-maverick-17b-instruct-v1:0` | PASS | 36 | 1 | $0.000009610 |
| `mistral.mistral-7b-instruct-v0:2` | PASS | 10 | 1 | $0.000001700 |
| `mistral.mixtral-8x7b-instruct-v0:1` | PASS | 10 | 1 | $0.000005200 |
| `mistral.mistral-large-2402-v1:0` | PASS | 4 | 1 | $0.000028000 |
| `mistral.mistral-small-2402-v1:0` | PASS | 4 | 1 | $0.000007000 |
| `mistral.pixtral-large-2502-v1:0` | PASS | 4 | 1 | $0.000014000 |

Failed/rejected requests had no metered model tokens:

| Model | Result | Input | Output | Metered USD | Provider result |
|---|---:|---:|---:|---:|---|
| `openai.gpt-6-astra` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `openai.gpt-5.6-terra` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-sonnet-4-20250514-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `anthropic.claude-haiku-4-5-20251001-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `anthropic.claude-opus-5-5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `moonshotai.kimi-k3` | FAIL | 0 | 0 | $0.000000000 | validation_min_output_tokens_16 |
| `anthropic.claude-fable-5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-sonnet-4-6` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `xai.grok-4.7` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `xai.grok-4.6` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `openai.gpt-6.1-sol` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-opus-4-6-v1` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `writer.palmyra-x5-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `anthropic.claude-opus-5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-opus-4-8` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-opus-4-7` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `openai.gpt-6-sol` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `writer.palmyra-x4-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `openai.gpt-6-luna` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-fable-5-1` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `openai.gpt-5.6-luna` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-sonnet-5-5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-sonnet-5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-opus-4-1-20250805-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `openai.gpt-5.6-sol` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `openai.gpt-5.4` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `anthropic.claude-opus-4-5-20251101-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `openai.gpt-5.5` | FAIL | 0 | 0 | $0.000000000 | access_denied_or_account_unavailable |
| `ai21.jamba-1-5-large-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |
| `ai21.jamba-1-5-mini-v1:0` | FAIL | 0 | 0 | $0.000000000 | INVALID_PAYMENT_INSTRUMENT |

**Total metered Bedrock token charge: $0.000391035.**

## Phone-AI OFF evidence

- `apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart` defaults `usePhoneAi = false`.
- The same router returns `phone_ai_disabled` when the explicit opt-in is absent.
- `apps/pandora-mobile/test/core/local_ai/pandora_local_ai_router_test.dart` asserts phone AI is OFF by default.
- `apps/pandora-mobile/test/core/local_ai/plp_local_router_test.dart` asserts the Ask Pandora screen does not force `usePhoneAi: true`.

## Exact-SHA CI trigger note

The initial Git Database fast-forward did not fan out the normal pull-request workflows. This evidence-only Contents API commit was made through the same Vault-backed GitHub transport to produce a normal PR synchronize event; it does not alter runtime behavior.

## Cost-source note

AWS Bedrock Price List / official Bedrock pricing was used for token rates. CloudWatch was used for exact token quantities. Immediate per-request billed USD is not emitted by Converse; invoice/CUR posting remains a later billing readback.
