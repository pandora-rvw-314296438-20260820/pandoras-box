# Pandora Multi-Provider Operations v1

**Program lane:** Kimi Chat F — production convergence and operating baseline  
**Applies to:** Gemini, Kimi/Moonshot, and future providers behind Pandora's provider-neutral intelligence layer  
**Primary Supabase:** `jcyqixttuebxqqfkjonq`  
**Memory Supabase:** `ivmvufhcsezyhczzondn`  
**Pandora Vercel:** project `mcpmaster` / `mcpmaster.vercel.app`  
**Memory Vercel:** project `memory` / `pandorasbox-memory.vercel.app`  
**Current Kimi secret identifier:** `moonshot_api_key` in primary Supabase Vault; never expose its value  

## Operating invariants

1. Provider choice is server-controlled. Ordinary clients never choose a provider, model, traffic percentage, circuit state, or secret.
2. Gemini remains a first-class independent alternative even when Kimi is preferred for a proven task class.
3. Security failures do not become fallback opportunities. Authentication, authorization, missing-secret, invalid trusted-host/configuration, spend denial, policy denial, and redaction failures fail closed.
4. Kimi production expansion is task-class-specific and evidence-gated. No global provider flip is permitted from a single benchmark or smoke test.
5. Prefer a routing/configuration kill switch over infrastructure rollback. Do not destructively reverse additive telemetry schema during an application rollback.
6. Production claims require exact source, provider deployment, active alias, runtime behavior, telemetry, and rollback evidence.
7. Raw prompts, provider responses, credentials, customer content, and secret-bearing errors do not belong in operations evidence or Pandora Memory.

## Actual Pandora control/evidence surfaces

The following are the current authoritative operational surfaces and should be used rather than ad-hoc logs:

- Kimi trusted transport RPC: `public.pandora_kimi_chat_request_v1(text,jsonb)` backed by `private.pandora_kimi_chat_api_v1(text,jsonb)`.
- Kimi Vault identifier: `moonshot_api_key` in the primary Pandora Supabase Vault.
- Model run ledger: `public.pandora_model_runs`.
- Provider attempt ledger: `public.pandora_model_attempts`.
- Versioned pricing: `public.pandora_model_pricing_versions`.
- Cost estimator: `public.pandora_estimate_model_cost_v1(...)`.
- Provider health views: `public.pandora_provider_attempt_health_hourly_v1` and `public.pandora_provider_outcome_health_hourly_v1`.
- Runtime provider configuration/event surfaces: `public.pandora_runtime_provider_configs` and `public.pandora_runtime_provider_events`.
- Thread/session routing state: `private.pandora_intelligence_thread_routing_state` once the routing lane is fully source-converged.
- Governed Memory outcome/evidence path in `ivmvufhcsezyhczzondn`; Memory is not a model-execution secret boundary.
- Vercel production identity must be read from the active aliases, not inferred from the newest READY preview.

At the Chat F observation point on 2026-09-02, Kimi/model routing keys were not yet present in `pandora_runtime_provider_configs`. Therefore a Kimi production kill-switch invocation is not considered verified merely because this runbook exists. The safe current state is **no Kimi production routing** until Chat C's server-controlled controls land and are read back.

---

# Task 130 — Provider incident runbook

## Detection

Classify the incident before changing routing:

- **Provider infrastructure:** 429, 5xx, timeout, network/provider unavailable.
- **Provider quality:** schema failures, verifier disagreement, severe task-quality regression.
- **Security/auth:** 401/403, credential unavailable, redaction failure, unexpected data exposure, host/configuration anomaly.
- **Downstream/tool:** model succeeded but governed tool or external dependency failed.
- **Economics:** unexpected cost spike, retry amplification, verifier/shadow spend anomaly.

Use `pandora_model_runs`, `pandora_model_attempts`, the two provider-health views, runtime provider events, and deployment readback. Do not collapse these failure domains into one generic error count.

## Immediate response — Kimi degraded

1. Stop Kimi eligibility using the server-side router/kill switch supplied by Chat C. If that control is not present or cannot be read back, do not attempt a canary; remain Gemini-only.
2. Preserve the current routing policy/config version, source SHA, Supabase function/migration identities, Vercel active deployment ID, and affected model-run IDs.
3. Verify Kimi is absent from new eligible production selections; do not infer this solely from a config write.
4. Verify Gemini remains operational for classes where policy permits it.
5. Preserve sticky-session semantics. Do not silently move an incompatible Kimi thread to Gemini mid-session; use the controlled recovery boundary.
6. Monitor 429/5xx/timeout/fallback/circuit evidence until recovery criteria are met.

## Immediate response — Gemini degraded

1. Identify which task classes have already passed Kimi benchmark, verifier, security, cost, latency, and reliability gates.
2. Only those proven classes may absorb traffic. Unsupported/high-risk classes remain held rather than automatically redirected.
3. Preserve cross-provider verifier independence. Do not make Kimi both builder and verifier merely because Gemini is unavailable.
4. Preserve spend ceilings and session boundaries.

## Both providers degraded

1. Fail safely for model-dependent actions that cannot meet quality/reliability/security floors.
2. Reduce nonessential shadow/verifier/model traffic first.
3. Protect spend and avoid retry storms.
4. Keep deterministic/non-model product functions available where possible.
5. Record an explicit degraded-service decision rather than recursively cycling providers.

## Security incident

1. Disable the affected provider immediately at the routing layer.
2. If credential compromise is suspected, rotate/revoke the provider credential at its authority. For Kimi, replace the Vault value **in place under `moonshot_api_key`** only after a governed provider-side key replacement; never copy it to Vercel, source, Memory, or logs.
3. Preserve sanitized evidence and identify any exposed scope without reproducing the secret.
4. Verify redaction and no-leak gates before re-enable.
5. Rerun adapter, transport, routing, verifier, and production-smoke prerequisites before any traffic resumes.

## Re-enable criteria

Re-enable only after:

- root cause is identified or bounded;
- security regressions = 0;
- provider health has sufficient fresh sample evidence;
- circuit/probe behavior is healthy;
- source/runtime parity is known;
- the relevant benchmark/promotion gate is not FAIL;
- rollback remains immediately available.

Re-enable at the last known safe task-class weight, not at a larger percentage.

---

# Task 131 — Provider pricing-change runbook

1. Verify the new price from the provider's authoritative published source and timestamp the verification.
2. Add a **new versioned row** in `pandora_model_pricing_versions`; do not overwrite historical price records that explain prior estimates.
3. Record provider, model, model revision where applicable, pricing version, currency, effective time, expiry if known, source reference, verification timestamp/status, and input/cached-input/output rates supported by the estimator schema.
4. Run `pandora_estimate_model_cost_v1(...)` against representative token profiles for every materially affected task class.
5. Recalculate canary/project/provider cost ceilings and cost per successful verified outcome. Include fallback double-spend and verifier/shadow spend.
6. If the change can alter provider preference or violate budgets, rerun the affected economics/promotion gates before changing routing.
7. Change routing only through governed server policy. Never hard-code new prices into adapters, UI, prompts, or multiple subsystems.
8. Preserve old pricing for historical runs. Do not retroactively rewrite prior estimated/billed records as if the new rate had applied.
9. Record sanitized evidence in the tracker and governed Memory path when the change becomes production-relevant.

A stale or unverified pricing version is a HOLD for cost-based promotion decisions.

---

# Task 132 — Model deprecation/change runbook

Trigger this runbook for model retirement, rename, capability removal, material version change, context/reasoning change, pricing change, or API response-contract change.

1. Detect the change from authoritative provider documentation/runtime evidence.
2. If continued use could be unsafe or unsupported, disable the affected model at server policy immediately.
3. Do **not** silently alias the old model name to a new one.
4. Select a candidate replacement.
5. Update the provider adapter/capability declaration and wire-contract fixtures only after current provider behavior is verified.
6. Rerun deterministic adapter/security/Gemini-non-regression tests.
7. Rerun the matched benchmark and independent-verifier gates for affected task classes.
8. Reset or materially down-weight adaptive routing confidence derived from the superseded model/version; old evidence remains historical, not automatically transferable.
9. Ensure telemetry records the new model/revision/pricing/policy identity.
10. Start a controlled task-class canary for the replacement.
11. Promote only if the replacement meets the same hard gates.
12. Retire the old model from candidate routing while retaining historical evidence required for audit/replay.

The same process applies to Gemini model changes; Kimi does not receive a weaker standard.

---

# Task 133 — Monthly provider review

## Evidence window

Run once per month using the previous complete calendar month plus a short current-health check. Consume authoritative structured evidence, not arbitrary log scraping.

## Required review inputs

- task-class quality/outcome evidence from `pandora_model_runs`;
- provider attempt/retry/fallback evidence from `pandora_model_attempts`;
- hourly health views for success, 429, 5xx, timeout, latency, and outcome health;
- estimated versus billed cost status and active pricing versions;
- structured-output and tool-execution validity;
- verifier outcomes and builder/verifier separation;
- circuit openings and kill-switch/provider-disable events;
- routing distribution and task-class/provider concentration;
- provider incidents and recovery receipts;
- model/version/pricing changes;
- governed Memory observations and stale/revoked provider knowledge;
- unresolved regressions or insufficient sample classes.

## Required output

Create one bounded decision record containing:

- evidence window and sample counts;
- task classes reviewed;
- keep/expand/hold/reduce/disable recommendations;
- provider concentration assessment;
- unresolved defects and owners;
- pricing/model/version changes;
- follow-up tasks;
- governed Memory candidate updates where justified.

The monthly review does **not** automatically mutate production routing. Policy changes remain separately governed and canaried.

## Automation readiness

A future scheduler may invoke this procedure only if it reads these authoritative tables/views and writes a review candidate rather than directly changing provider policy. Scheduling authority is outside Chat F; no uncontrolled production automation is created by this runbook.

---

# Task 134 — Quarterly architecture review

Review once per quarter, or after a major provider/runtime architecture change.

Inspect:

- provider-neutral contract health;
- provider-specific exceptions leaking outside adapters/transports;
- capability-registry accuracy;
- router/policy complexity and fallback-loop safety;
- session stickiness/recovery behavior;
- Vault and trusted-server security boundary;
- telemetry schema and pricing authority;
- independent-verifier separation;
- Memory learning quality/provenance/freshness/revocation;
- provider concentration and outage blast radius;
- cost architecture and retry/verifier amplification;
- model/provider deprecations;
- credible new provider candidates.

Produce one concise decision record with one of these dispositions for each material issue:

- keep architecture;
- adjust provider abstraction;
- change routing policy;
- add/remove provider candidate;
- modify verifier policy;
- update Memory learning contract;
- mitigate concentration risk.

Every change recommendation must cite evidence. A quarterly review is not permission to redesign for novelty or to bypass normal implementation, evaluation, canary, and rollback gates.

---

# Verification checklist for these runbooks

Before declaring the operating-baseline tasks complete, prove that the referenced runtime surfaces still exist and that the final release uses the intended source. In particular:

- read back Kimi Vault **presence only**, never value;
- read back Kimi RPC grants/timeouts;
- read back active pricing/health/telemetry schema;
- verify Chat C server-controlled provider enable/disable and circuit controls after they land;
- verify Chat E promotion-gate result after it lands;
- verify active Vercel aliases point to the intended release SHA;
- execute safe production smoke and rollback proof;
- record sanitized evidence through the governed Memory review path.

Until those checks pass, these runbooks are operational source artifacts but do not constitute proof that Kimi production canary or v1 baseline is complete.
