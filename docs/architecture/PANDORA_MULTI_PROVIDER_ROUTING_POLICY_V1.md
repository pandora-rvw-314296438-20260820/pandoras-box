# Pandora Multi-Provider Routing Policy v1

This document defines the Chat C implementation boundary for Pandora's provider-neutral model router. It does not activate Kimi traffic and does not own provider adapters, secrets, transport retries, telemetry persistence, evaluation, or production rollout.

## Eligibility order

The router applies hard constraints before soft optimization:

1. request secret boundary
2. capability/output/context compatibility
3. adapter availability
4. provider/model allow-deny, quarantine and kill switches
5. session/thread compatibility
6. circuit/health state
7. reliability and quality hard floors when sufficient evidence exists
8. request/policy cost ceilings using an injected estimator or canonical evidence
9. latency ceiling when sufficient rolling evidence exists
10. server-owned task/provider/model preference
11. empirical weighted score with confidence, recency and model-version weighting
12. deterministic canary preference and bounded exploration only when explicitly configured

No hard constraint is bypassed by preference, traffic weight, exploration, historical score, or fallback.

## Fallback boundary

Cross-provider fallback is allowed only for normalized retryable `provider_unavailable`, `timeout`, and `rate_limited` failures. Authentication, authorization/configuration, invalid request, capability, structured-output/schema, budget and generic programmer/provider errors do not silently downgrade to a different provider.

The router carries provider/model attempt history and obeys the request attempt budget. Already-attempted provider/model pairs are excluded so Gemini↔Kimi loops cannot recur. Same-provider HTTP retry/backoff remains transport-owned.

## Session continuity and recovery

A provider/model selection becomes sticky for the thread/session. Preference cannot silently move a sticky session to a different provider/model. A cross-provider transition requires an explicit recovery boundary, increments a recovery epoch and returns the new continuity state for service-owned persistence.

The primary database stores provider-neutral continuity metadata in `private.pandora_intelligence_thread_routing_state`, keyed 1:1 to the existing public intelligence thread. It stores only provider/model/version/policy/reasoning/stickiness/recovery metadata and an optional compatible message reference. It does not duplicate conversation content and is service-role-only.

## Circuit and immediate-disable behavior

`closed` is eligible. `open` is ineligible. `half_open` is ineligible unless the caller explicitly authorizes a probe and the circuit policy permits it. Provider/model kill switches, disabled state and quarantine are hard filters and therefore override all soft policy.

Authoritative health observations are produced outside Chat C; the router consumes them without inventing health evidence. When explicit breaker thresholds are configured, sanitized health aggregates can deterministically open the circuit, keep it open through cooldown, move it to half-open, and close/reopen it from an explicit probe result. Unrelated validation/auth/policy failures are not health signals.

## Canary and adaptive routing

Traffic weights are task-aware and deterministic when a stable cohort key is supplied. They do not activate any traffic by default. Exploration is disabled by default, capped when configured, deterministic, and excluded from configured high-risk tasks.

Adaptive score influence is bounded by rolling windows, recency decay, sample confidence and model-version compatibility. Quality/success/latency/cost weights can be versioned globally or overridden per task class; neither form can override hard eligibility. Sparse or stale evidence has reduced or zero influence. Hard reliability/quality/cost/latency rules remain separate from the soft score.

Reasoning selection and cache-aware cost are hooks only: the router consumes server-owned reasoning policy and injected/canonical cost estimation. It does not embed Kimi-specific reasoning values or provider pricing formulas.

## Audit evidence

Every successful route can return bounded decision evidence containing policy version, selected provider/model, reasoning policy, eligible and excluded candidates with reasons, score components, stickiness/recovery decision and normalized attempt chain. Raw prompts, responses, credentials and raw cohort identifiers are excluded.

Persistence of model-run telemetry remains Chat D-owned.

## Production state

This implementation is mechanism-only. Kimi traffic weight, global exploration and adaptive production routing remain disabled until the evaluation, verification and controlled-canary gates are satisfied and Chat F performs production convergence.
