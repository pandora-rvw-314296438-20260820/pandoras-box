# Pandora Kimi Chat F — Production Convergence HOLD

**Observation date:** 2026-09-02 Asia/Manila  
**Decision:** `PRODUCTION PARTIALLY VERIFIED / HOLD`  
**Reason:** the trusted Kimi transport exists and is reachable, but the full provider/routing/evaluation source is not converged and the active Vercel production aliases do not match current authoritative main.

## Canonical source observed

- `pandoras-box` main: `17674e2131efcb4dd8625cbf9ddc22ebfa35f593`.
- `pandoras-box-memory` main: `99d9ef1099a647e4e4564e666ed1fb8a6c92e95a`.

These are observation identities, not a release declaration.

## Parallel-lane source state

### Chat A — provider adapter

- PR #251 is open.
- Kimi adapter/capability/normalization source exists on the PR branch and CI has produced green deterministic intelligence/integration/security/release workflows on the inspected head.
- The PR was not mergeable at the Chat F observation point, so the adapter is not authoritative main source.

### Chat B — Vault/security transport

- PR #250 is open and mergeable on its refreshed head `c4d104b5ccbf2786efd53db60157cbbd8bb55e2e`.
- All inspected refreshed-head workflows were green except the mobile exact-source gate, which was still running at the observation point.
- The GitHub App merge call was denied with `403 Resource not accessible by integration`.
- The Vault-backed `Github_supabase` recovery path was then used server-side. Its first exact-head merge attempt correctly returned `409 Head branch was modified`; no credential was returned or logged.
- Do not merge until the refreshed exact head's required checks are complete.

### Chat C — routing/session/fallback/circuit

- No current Kimi Chat C source branch/PR was visible in the inspected branch/PR set.
- Primary Supabase does contain remote migration `20260901183204_pandora_intelligence_thread_routing_state_v1` and table `private.pandora_intelligence_thread_routing_state`.
- Remote schema is therefore ahead of authoritative main source for at least part of the routing lane. Source provenance/convergence is unresolved.
- No Kimi/model server routing keys were present in `public.pandora_runtime_provider_configs` at observation time.

### Chat D — telemetry/economics

- Primary Supabase contains remote migration `20260901184000_pandora_model_telemetry_economics_v1`.
- Remote model-run/attempt/pricing/health schema includes provider/model usage, cost, latency, fallback, structured-output, tool, verifier, routing, cohort and outcome evidence fields.
- A Kimi Chat D branch name was visible, but authoritative main did not contain the inspected remote migration identity. Source provenance/convergence remains unresolved.

### Chat E — evaluation/verification

- The canonical tracker still showed Tasks 67–90 as Not Started at the observation point.
- No current Kimi Chat E source branch/PR or promotion-gate result was visible in the inspected source set.
- Therefore no valid evaluation PASS exists for production canary promotion.

## Primary Supabase runtime evidence

Project `jcyqixttuebxqqfkjonq` is `ACTIVE_HEALTHY`.

Remote applied Kimi-related migrations include:

- `20260901173359 pandora_kimi_vault_transport_v1`
- `20260901183204 pandora_intelligence_thread_routing_state_v1`
- `20260901184000 pandora_model_telemetry_economics_v1`

### Kimi credential boundary

- Vault contains a secret named `moonshot_api_key`.
- The value was not read or exposed.
- `public.pandora_kimi_chat_request_v1(text,jsonb)` and its private backing transport are executable by `service_role`/postgres only, not public/anon/authenticated.
- The private/public transport functions have a 90-second statement timeout; the transport uses the fixed Moonshot endpoint and bounded same-provider retry policy from the deployed migration.

### Safe live transport probe

A bounded server-side `kimi-k3` health request returned:

- HTTP status: `200`
- transport `ok`: `true`
- attempts: `1`
- provider model: `kimi-k3`
- prompt tokens: `101`
- completion tokens: `32`
- total tokens: `133`

The 32-token probe did **not** satisfy the literal exact-output assertion. This proves the trusted transport can execute successfully; it does not count as a Kimi quality/promotion PASS.

### Deterministic error classification

Readback of the deployed classifier produced:

- 401 -> authorization, non-retryable
- 403 -> authorization, non-retryable
- 429 -> rate_limit, retryable
- 503 -> provider_unavailable, retryable
- 504 -> timeout, retryable

This is consistent with the security requirement that auth failures must not silently fall back.

### Production traffic evidence

In the inspected recent `pandora_model_runs` window, only Gemini `gemini-3.5-flash-lite` runs were recorded; no Kimi production run was present. This is evidence that the 5% Kimi production canary has **not** been executed by Chat F.

## Vercel production identity

### Pandora / mcpmaster

Active lookup of `mcpmaster.vercel.app` resolved to:

- deployment: `dpl_Aoqa9hqccSgzmsNC9iJMvuzQHxS4`
- state: READY
- target: production
- source repository: `pandoras-box`
- source SHA: `4b28ca1548033c38bf97625aeb76c335afdad5b5`

This does not match current `pandoras-box` main `17674e2131efcb4dd8625cbf9ddc22ebfa35f593`.

### Memory / memory

Active lookup of `pandorasbox-memory.vercel.app` resolved to:

- deployment: `dpl_38nGUZgS8Bd13sr4HfvCFABfCTpF`
- state: READY
- target: production
- source repository: `pandoras-box-memory`
- source SHA: `9da819876037aa6427e745189f7b3949747b3bef`

This does not match current Memory main `99d9ef1099a647e4e4564e666ed1fb8a6c92e95a`.

The connector could not HTTP-fetch either root Vercel URL, so no page-level smoke pass is claimed from this run.

## Hard-gate decision

Task 101 — 5% production canary — is **HOLD**. It must not start until all of the following are proven:

1. Chat A adapter source is merged/converged.
2. Chat B secure transport source is merged and exact source/runtime parity is restored.
3. Chat C routing, deterministic cohort, session stickiness, kill switch, fallback loop protection, circuit breaker, and cost/latency/reliability controls are merged and read back.
4. Chat D telemetry/economics source is merged and runtime provenance is known.
5. Chat E benchmark/promotion/verifier gates produce an explicit PASS for the eligible task class.
6. A clean intended release commit is established; do not deploy arbitrary latest main merely to remove Vercel drift.
7. The exact release is deployed and active Vercel aliases are verified against its SHA.
8. Safe production smoke and rollback controls pass before Kimi receives eligible production traffic.

## Current safe baseline

- Preserve Gemini as the active production provider path.
- Keep Kimi out of production selection until Chat C policy controls and Chat E gates are proven.
- Keep the Kimi credential in primary Supabase Vault only.
- Do not copy the credential to Vercel, source, Memory, tracker, CI, or client code.
- Do not destructively reverse additive telemetry/routing schema solely because runtime routing remains disabled.

## Next exact convergence point

1. Re-read PR #250 refreshed head CI and merge exact checked head through the Vault-backed GitHub path when green.
2. Repair/rebase Chat A PR #251 against the resulting main without losing Chat B secret-boundary hardening.
3. Locate/converge Chat C/D source corresponding to already-applied remote migrations.
4. Obtain Chat E evaluation/promotion result.
5. Build a reviewed release commit and only then address Vercel exact-source parity and production smoke.

No canary percentage, quality score, cost metric, or production-promotion result is asserted beyond the evidence above.
