# Pandora Model Telemetry & Economics v1

Chat D owns the evidence layer, not routing policy or provider transport.

## Operational source of truth

`public.pandora_model_runs` remains the provider-neutral logical run ledger for Gemini, Kimi, and future providers. The v1 extension is additive and keeps legacy Gemini rows valid. Unknown legacy metrics remain `NULL`/`unavailable`; they are not backfilled with invented values.

`public.pandora_model_attempts` is the append-only provider-attempt/fallback ledger. It exists because one logical model run can have several provider attempts while `pandora_model_runs` preserves one logical request identity.

## Evidence dimensions

Execution facts include provider/model/revision, provider request id, provider-reported usage source, cached/reasoning tokens when actually reported, latency dimensions, normalized failure class and safe HTTP status class.

Routing facts include decision id, policy version, bounded candidate/exclusion/score JSON, confidence/sample context, stickiness, recovery state and cohort. Chat C owns the meaning and selection logic; Chat D persists the evidence.

Outcome facts include structured-output stages, governed tool execution result, independent verifier identity/outcome, downstream outcome linkage, and causal failure domain.

No field stores raw prompts, raw model responses, Authorization headers, provider credentials, or raw HTTP payloads.

## Cost interface

`public.pandora_model_pricing_versions` is the versioned pricing authority.

`public.pandora_estimate_model_cost_v1(...)` returns either:
- `status=estimated` with pricing version/source and `billedCostMicros=null`, or
- `status=unavailable` when no verified price applies.

Kimi K3 pricing was revalidated on 2026-09-02 from the official Kimi API platform: USD 0.30/MTok cached input, USD 3.00/MTok uncached input, USD 15.00/MTok output. The seeded pricing version is `kimi-k3-usd-2026-09-02`.

Estimated cost never overwrites billed cost. `billing_reconciliation_status` and `billed_cost_source` exist for later authoritative billing reconciliation.

## Provider health interfaces

`pandora_provider_attempt_health_hourly_v1` exposes provider/runtime component metrics including retryable failures, rate limiting, timeout, availability, security failures, non-provider failures, fallback triggers, sample count, freshness, and latency percentiles.

`pandora_provider_outcome_health_hourly_v1` exposes final run quality/economics evidence including structured-output validity, tool success, verifier results, fallback frequency, known estimated cost, sample count, freshness, model revision, routing policy and cohort.

Sparse percentiles fail soft:
- p90 requires at least 10 latency samples;
- p95 requires at least 20;
- p99 requires at least 100.

These views expose components, not a fabricated universal health score.

## Cross-lane consumption

Chat A: populate provider/model/revision and normalized usage; `metadata.cachedInputTokens` can map to `cached_input_tokens` only when provider-reported.

Chat B: provide only safe timing/status/error metadata; never raw authorization or provider payloads.

Chat C: persist routing/fallback evidence and consume the hourly health views plus the cost estimator. Chat D does not mutate routing policy.

Chat E: persist verifier identity/outcome and evidence references; builder self-checks must not be labeled independent verification.

Chat F: compare cohorts using the outcome health view; production promotion remains Chat F ownership.
