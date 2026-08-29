# Pandora Worker H — Live Business / Economics Gap Map

Audit base: `main` at `789eae5869363499c5bbafd63d1f2660200abde9` on 2026-08-28.

## Reusable truth

- Worker A PR #43 introduces immutable ProjectSpec-scoped business objectives with `objective`, `desired_outcome`, `success_metric`, `baseline`, and `target`. Worker H treats those records as durable intent and does not create competing objective persistence.
- Worker B foundation is merged on main at PR #42 and establishes provider-independent intelligence/model contracts. Worker H will supply economic/quality evidence to routing; it will not own routing.
- Existing project/runtime/verification work on main already carries organization/project/version lineage that Worker H can consume through adapters.
- Pandora Supabase Vault contains the established GitHub integration credential boundary; Worker H source contains no provider credential.
- Connected PostHog is live, but the observed event taxonomy currently represents another product domain. It is not evidence that Pandora project/business instrumentation is complete.

## Gaps confirmed on the audited base

| Area | Live state | Worker H action |
| --- | --- | --- |
| Business Intelligence package | Missing | Add bounded provider-independent package |
| Objective normalization | Free-text durable fields arriving in Worker A | Normalize measurement semantics without replacing durable truth |
| Metric registry | Missing | Add canonical definitions with aggregation/unit/freshness/sample/version rules |
| Generated-app taxonomy | Missing | Add bounded outcome-oriented events |
| Pandora-product taxonomy | Missing | Add separate internal events and authority boundary |
| Tenant/version event attribution | Not standardized | Require organization/project/version/environment scope |
| Measurement readiness | Missing | Add explicit not_configured/configured/receiving/stale/broken/ready states |
| Statistical caution | Missing | Enforce minimum samples/windows and inconclusive states |
| Funnel/retention/cohort contracts | No Worker H boundary | Add provider-independent contracts incrementally |
| Recommendation lineage | Missing | Require observed fact, evidence, affected metric, hypothesis, confidence, cost/risk |
| Governed optimization loop | Missing | Convert accepted recommendations to normal change intent only |
| PostHog adapter | Missing | Next bounded milestone; never couple business logic to raw responses |
| Canonical cost accounting | Missing | Separate Worker H economics package milestone |
| Credits/gross margin/budgets | Fragmented/absent as Worker H truth | Converge after Worker A publishes durable cost/budget contracts |
| Live Pandora business outcome data | Not established | Never fabricate; report Not measured/No data yet/Inconclusive |

## Security / privacy baseline

- Customer-app events cannot emit Pandora authority events such as build/publish completion.
- Event payloads use an allowlist, scalar size bounds, schema versions, and mandatory tenant/project/version/environment attribution.
- Email, phone, credentials, secrets, raw prompts, source code, stack traces, and arbitrary documents are excluded from canonical business event payloads.
- Analytics provider reads must match the requested organization/project/version scope before results are accepted.
