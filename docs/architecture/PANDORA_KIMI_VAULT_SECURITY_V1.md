# Pandora Kimi/Moonshot Vault & Server Transport Security v1

**Lane:** Kimi multi-provider Chat B — Wave 2 Tasks 25–39  
**Authoritative project:** primary Pandora Supabase `jcyqixttuebxqqfkjonq`  
**Credential boundary:** primary Pandora Supabase Vault only  
**Last revalidated:** 2026-09-02 Asia/Manila

## Provider contract evidence

The standard Kimi Open Platform API currently uses:

- service host: `https://api.moonshot.ai`
- OpenAI-compatible base URL: `https://api.moonshot.ai/v1`
- chat endpoint: `POST /v1/chat/completions`
- authentication: `Authorization: Bearer <MOONSHOT_API_KEY>`
- current documented chat model identifiers include `kimi-k3`, `kimi-k2.7-code`, `kimi-k2.6`, `kimi-k2.5`, and `moonshot-v1`
- non-streaming JSON and SSE streaming are supported by the provider; Pandora's v1 SQL transport deliberately uses non-streaming only
- provider error JSON uses `error.type` / `error.message`
- 429 overload/rate-limit responses may supply `Retry-After`; provider guidance calls for bounded exponential backoff
- 401/403 are credential/permission failures; quota exhaustion is not treated as a transient retry
- provider 500/503/504 classes are retryable only within Pandora's bounded attempt/deadline policy

Provider documentation is external authority and must be revalidated before changing the transport contract.

## Standard API credential decision

Pandora requires a **standard Kimi Open Platform / Moonshot API key**, not a Kimi Membership or Kimi Code subscription credential.

The live credential already present in the primary Pandora Vault was validated server-side against the standard API `/v1/models` endpoint without returning or logging its value. It was normalized in place to the canonical Vault identifier below; no second credential was created.

## Canonical Vault policy

| Property | Policy |
|---|---|
| Secret identifier | `moonshot_api_key` |
| Provider | Kimi Open Platform / Moonshot |
| Purpose | Pandora server-side standard API execution only |
| Environment | Primary Pandora production Supabase plane |
| Operator owner | Pandora Security / Runtime |
| Storage | Supabase Vault only |
| Rotation | Create replacement provider key, replace the Vault value **in place under the same identifier**, verify standard API access, then revoke the superseded provider key |
| Revocation | Revoke provider-side immediately on suspected compromise and remove/replace the Vault value |
| Failure | Missing, blank, unreadable, invalid, or revoked secret fails closed |
| Forbidden copies | client/Flutter, repository, GitHub metadata, Vercel env, Memory, Drive, logs, telemetry, prompts, fixtures |

The Memory Supabase project is not a model-execution credential boundary. Vercel does not receive this key.

## Trusted service boundary

The only supported v1 caller interface is:

`public.pandora_kimi_chat_request_v1(p_model text, p_body jsonb) -> jsonb`

It is executable only by Supabase `service_role`. `public`, `anon`, and `authenticated` have no execute permission. The wrapper delegates to:

`private.pandora_kimi_chat_api_v1(p_model text, p_body jsonb)`

The private function retrieves `moonshot_api_key` from Vault and performs exactly one class of provider operation: a Kimi/Moonshot Chat Completions request. It is not a generic HTTP proxy and accepts no URL, host, scheme, or arbitrary transport target.

## Security bounds

- Destination is hard-coded to `https://api.moonshot.ai/v1/chat/completions`.
- Redirect following is disabled; any 3xx is normalized as a non-retryable rejected redirect.
- Serialized outbound request body: maximum **1 MiB**.
- Messages: 1–256.
- Tools: maximum 128, matching the current provider contract.
- Provider output budget: `max_completion_tokens` defaults to 8,192 and is capped at **16,384** by this transport.
- Streaming: disabled in v1 to prevent unbounded stream accumulation inside the SQL HTTP transport.
- Provider response body: maximum **2 MiB** for application consumption, rejected before JSON parsing/caller return; generated output is independently capped by `max_completion_tokens`. Supabase pgsql-http does not expose a runtime max-file cURL option, so this bound is enforced immediately after the fixed-host response is received.
- Connect timeout: 5 seconds.
- Provider I/O timeout: 85 seconds.
- PostgreSQL function deadline: 90 seconds.
- Internal transport attempts: maximum 2.
- Retry delay: capped at 2 seconds inside the transport. Longer `Retry-After` values are returned as sanitized metadata for higher-level router policy instead of sleeping in the database.
- Retryable internal classes: transient network/timeout, retryable 429, and provider 5xx.
- Non-retryable classes: auth/permission, quota exhaustion, invalid request/model, redirect, malformed response, response-size violation.
- The transport never invokes Gemini or any router/fallback path.

Higher-level provider choice and fallback remain the routing lane's responsibility.

## Error and secret handling

Provider error messages and raw non-2xx bodies are not returned to callers. Returned error metadata is bounded to:

- normalized kind
- sanitized `error.type` as `providerCode` when available
- retryable boolean
- bounded `retryAfterMs`
- attempt count
- HTTP status

The actual Vault value is checked as a response canary. If the provider ever echoes the credential, the transport raises a fail-closed security error instead of returning the response.

Central redaction additionally covers:

- `moonshot_api_key` / `kimi_api_key` structured fields
- `MOONSHOT_API_KEY=...` / `KIMI_API_KEY=...`
- `Authorization: Bearer ...`
- `sk-...` token-shaped strings
- API-key/token query parameters
- builder/runtime log paths

Production secrets are never fixtures. Regression tests use deterministic fake canaries.

## Adapter convergence contract

Chat A can bind `KimiProviderAdapter` to the service-role RPC above. The adapter supplies:

- a validated Kimi/Moonshot model identifier in `p_model`
- an OpenAI-compatible Chat Completions body in `p_body`
- no `model` field inside `p_body`
- no deprecated `max_tokens`; use `max_completion_tokens`
- no `stream: true`
- no host/URL/authentication fields

The RPC returns either:

- success: `{ status, ok: true, attempts, contentType, body }`
- sanitized failure: `{ status, ok: false, attempts, error: { kind, providerCode?, retryable, retryAfterMs? } }`

Chat A remains responsible for provider-neutral normalization. Chat C remains responsible for routing/session/fallback policy and must not duplicate transport retries or create provider recursion.

## Rotation runbook

1. Create a new standard Kimi Open Platform API key using the governed provider account.
2. Replace the existing Vault value under `moonshot_api_key`; do not create a second steady-state secret name.
3. Run a server-side `/v1/models` or bounded chat health probe that returns status/capability evidence only.
4. Verify the Kimi transport succeeds and no credential canary appears in response/log/telemetry/Memory evidence.
5. Revoke the superseded provider key.
6. If any validation fails, restore/reissue the Vault value and keep Kimi routing disabled. Never fall back around a missing/invalid credential as a security bypass.

## Deployment rule

A repository migration is not proof of Supabase deployment. Completion requires remote migration/function readback, grants, timeout settings, negative security tests, and a successful bounded provider call. Kimi production traffic remains outside this lane and requires the later evaluation/canary/convergence gates.
