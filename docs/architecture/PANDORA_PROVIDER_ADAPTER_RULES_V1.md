# Pandora Provider Adapter Rules v1

## Purpose

Pandora model providers are replaceable adapters behind the provider-neutral intelligence contract. A provider integration must not create a second router, orchestration system, credential path, tool executor, telemetry ledger, or customer-facing provider UX.

Canonical path:

`Pandora ModelRequest -> Capability Registry -> Model Router / Routing Policy -> Provider Adapter -> Trusted Server Transport -> Provider API -> Normalized Pandora Result/Error`

Current implementation locations:

- provider-neutral model request/error/usage contract: `packages/pandora-intelligence/src/contracts/model.js`
- capability registry: `packages/pandora-intelligence/src/capabilities/registry.js`
- router/policy: `packages/pandora-intelligence/src/routing/model-router.js`, `packages/pandora-intelligence/src/routing/policy.js`
- secret boundary: `packages/pandora-intelligence/src/security/secret-boundary.js`
- Gemini adapter: `packages/pandora-intelligence/src/providers/gemini.js`
- Kimi/Moonshot adapter: `packages/pandora-intelligence/src/providers/kimi.js`
- provider exports: `packages/pandora-intelligence/src/index.js`

## Responsibility boundaries

### Provider-neutral contract

Owns Pandora task names, output modes, context/input/schema, budgets, required capabilities, normalized usage and normalized errors. Provider wire vocabulary must not be added to the shared contract merely because one provider needs it.

### Capability declaration

A model declaration is evidence-backed, additive and conservative. Only capabilities confirmed by current authoritative provider documentation and actually serialized/normalized by the adapter may be declared. Capability metadata is not a production traffic switch.

### Provider adapter

The adapter may:

- translate a Pandora request into the provider wire envelope;
- map provider-specific reasoning controls from a provider-neutral Pandora policy value;
- validate provider-specific message continuity supplied by the caller;
- normalize text, structured output, tool calls, usage, finish state and safe provider identifiers;
- classify provider failures into Pandora's existing error taxonomy;
- expose a provider-level stream-normalization seam;
- reject unsupported combinations before network execution.

The adapter must not:

- read Vault or environment secrets;
- create `Authorization` headers;
- choose arbitrary provider URLs;
- perform cross-provider fallback;
- own provider/model routing weights or circuit-breaker policy;
- execute model-requested tools;
- globally enable itself in production;
- write raw provider prompts/responses to Memory or telemetry.

### Trusted transport

The transport owns the secret-bearing network boundary. For Kimi, Chat A consumes only:

`createChatCompletion({ model, requestId, body }) -> Promise<{ status, ok, body?, attempts?, error? }>`

The deployed primary-Supabase boundary is `public.pandora_kimi_chat_request_v1(p_model, p_body)`, backed by `private.pandora_kimi_chat_api_v1`. The adapter-side wrapper passes `model` separately and sends a body that deliberately omits `model`; the trusted transport injects the model itself. Its current safety envelope defaults `max_completion_tokens` to 8,192, caps it at 16,384, bounds messages to 256 and tools to 128, enforces 1 MiB request / 2 MiB response limits, and performs at most two bounded same-provider attempts. These are Pandora transport limits, not claims about the larger K3 provider limits.

Kimi's upstream API supports streaming, but the current trusted Supabase transport rejects `stream=true`. Accordingly, the Kimi model metadata distinguishes upstream provider support from current Pandora transport support and reports streaming unavailable for routing today. `normalizeKimiStreamEvent()` remains a tested future seam only. The transport implementation owns Vault retrieval, fixed-host enforcement, authentication headers, HTTP timeout enforcement, bounded same-provider retry/backoff and response-size controls. It must never expose raw credentials to the adapter.

### Router and routing policy

The router owns provider/model choice and cross-provider fallback. Provider adapters classify retryability; they do not silently call another provider. Authentication/authorization, malformed trusted requests, missing secrets and other security failures must remain non-retryable at the cross-provider layer unless an explicit security policy says otherwise.

### Tool execution

Adapters return normalized tool intent only. Pandora's existing governed tool gateway remains the only execution authority. A provider adapter must never execute a function call itself.

### Session continuity

The session/routing layer owns provider stickiness and recovery boundaries. An adapter must not invent unseen state or reconstruct hidden reasoning. If same-provider continuity is supplied, the adapter serializes it exactly as required by that provider. Provider continuation artifacts are internal execution state: do not surface them in Simple Mode, ordinary telemetry, or Pandora Memory.

## Kimi K3 implementation contract

As revalidated on 2026-09-02, Pandora's Kimi adapter targets the standard Kimi Open Platform, not Kimi Membership/Kimi Code credentials.

Authoritative provider facts used by the implementation:

- standard API base: `https://api.moonshot.ai/v1`
- chat endpoint family: OpenAI-compatible `/v1/chat/completions`
- direct API model ID: `kimi-k3`
- context window: 1,048,576 tokens (1M)
- K3 thinking: always enabled
- top-level `reasoning_effort`: `low`, `high`, `max`; provider default is `max`
- K3 assistant continuity: preserve the complete returned assistant message for compatible multi-turn/tool continuation, including `reasoning_content` and `tool_calls`
- structured output: Chat Completions `response_format` supports JSON mode and JSON Schema mode
- tools: Chat Completions function/tool calling is supported; Pandora does not execute tools inside the adapter
- multimodal input: Open Platform Chat Completions supports text/image/video content parts; K3 is documented as native visual/multimodal
- streaming: Chat Completions streaming is supported; Kimi stream deltas can include content, reasoning and tool-call fragments
- usage: response usage includes prompt, completion and total token counts; cache-token metadata may also be present
- Kimi API keys and Kimi Code/Membership credentials are different products and must not be interchanged

Provider provenance:

- `https://platform.kimi.ai/docs/llms.txt`
- `https://platform.kimi.ai/docs/api/overview`
- `https://platform.kimi.ai/docs/api/chat`
- `https://www.kimi.ai/help/kimi-api/api-model-selection`
- `https://www.kimi.ai/help/kimi-api/api-troubleshooting`
- `https://github.com/MoonshotAI/Kimi-K3`

The code centralizes K3 model/config/capability data in `providers/kimi.js`; callers must not scatter `kimi-k3` strings across product code. It records both the upstream K3 completion defaults/capabilities and the stricter currently deployed Pandora transport envelope so routing code cannot confuse provider capability with production-safe availability.

## Reasoning mapping

Pandora stays provider-neutral. The Kimi adapter reads the non-provider-specific request metadata value `reasoningLevel` and maps it deterministically:

- `low` -> Kimi `low`
- `standard` -> Kimi `high`
- `high` -> Kimi `max`

K3 cannot disable reasoning. Unknown Pandora values are rejected rather than silently coerced. Adaptive selection of `reasoningLevel` belongs to routing policy, not the adapter.

## Request serialization

Kimi serialization preserves supplied message order and only accepts supported roles/content. When compatible `context.messages` are present, they are serialized without fabricating state. Assistant `reasoning_content` and `tool_calls` are retained only for same-provider continuation. Tool results preserve `tool_call_id`.

For callers that do not supply message history, the adapter constructs the same bounded Pandora envelope pattern used by the existing provider layer: task/input/context/metadata become provider input while secrets are rejected before transport.

Sampling parameters are intentionally not injected by default. Provider-specific defaults remain at the provider unless Pandora has an explicit, tested, provider-neutral reason to control them.

## Structured output and tool calls

For `json` and `tool_proposals`, the Kimi adapter requests JSON object output. For `structured`, it sends the requested JSON Schema using strict schema output and then independently parses and validates the returned JSON against the adapter's supported schema subset before declaring success. Schema constraints outside that independently validated subset are rejected before transport rather than silently ignored. Malformed JSON or schema mismatch becomes `structured_output_invalid`.

Native tool calls normalize to `{ id, name, arguments }`. Arguments must parse as a JSON object and pass the central credential boundary. The adapter never invokes the tool.

## Multimodal input

The Kimi adapter accepts the provider-neutral message content forms currently needed by Pandora: text, `image_url`, and `video_url`. URLs/file references are serialized only as content; the adapter does not perform media fetches. Transport/request-size policy remains server-side.

## Streaming

The upstream Kimi Chat Completions API supports streaming, but Pandora's currently deployed trusted Supabase transport intentionally disables it. `normalizeKimiStreamEvent()` provides only the provider-level future normalization seam for content deltas, tool-call deltas, completion reasons and usage. Raw reasoning text is not emitted through the ordinary normalized stream payload. Routing must treat streaming as unavailable until the trusted transport and session-continuation path are explicitly upgraded and verified.

## Error normalization

Kimi failures map into Pandora's existing error taxonomy. Key behavior:

- 401/403 -> `authentication_failed`, non-retryable across providers
- 429 -> `rate_limited`, retryable with safe retry metadata
- 408/504 -> `timeout`, retryable
- 5xx/transport network availability failure -> `provider_unavailable`, retryable
- model/resource not found -> `unsupported_capability`, non-retryable
- context/token-limit rejection -> `context_too_large`, non-retryable
- other 400 -> `invalid_request`, non-retryable
- malformed provider/tool/structured output -> normalized provider/structured error with no raw secret-bearing payload

Raw provider error bodies, authorization data and request content are not propagated as error details.

## Secret boundary

Production provider credentials are transport-only. Kimi provider source/config/tests/docs must contain no API key, Vault value or Authorization header. The shared secret boundary explicitly rejects `moonshot_api_key` and `kimi_api_key` (including camel-case key spellings after key normalization).

## Testing requirements for every provider

A provider adapter is not complete without deterministic mocked transport tests covering construction, serialization, response normalization, usage, finish/truncation, structured output, tool calls, multimodal input where declared, streaming seam where declared, authentication/rate-limit/timeout/5xx/context/network failures, malformed responses, secret exclusion, export compatibility and existing-provider regression.

Live provider credentials are not required for unit tests. Production activation is a separate convergence/canary decision.

## Backward compatibility and production state

Adding Kimi is additive. Gemini remains a first-class provider and its adapter/request/result/error behavior must remain green. Exporting or registering the Kimi adapter/capability declaration does not route production traffic to Kimi. Production credentials, trusted transport deployment, routing enablement, canary promotion and runtime parity remain separate governed workstreams.
