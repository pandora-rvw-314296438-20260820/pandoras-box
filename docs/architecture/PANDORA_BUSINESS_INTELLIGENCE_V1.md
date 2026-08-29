# Pandora Business Intelligence V1

Status: implemented contract package for Worker H. This document describes code and invariants, not unmeasured business success.

## Purpose

Worker H turns durable Pandora project/business truth into scoped measurements, economics, experiments, recommendations, alerts, and owner-safe business summaries. It does not authorize tools, build software, verify builds, deploy applications, or mutate production directly.

The governing rule is:

`ProjectSpec objective -> verified instrumentation -> provider data -> bounded measurement -> outcome/economics assessment -> governed recommendation -> ordinary Pandora change lifecycle`

Missing evidence is represented as `not_measured`, `awaiting_data`, `unknown`, or `inconclusive`. Missing values are never silently converted to zero, success, ROI, revenue, or margin.

## Durable control-plane truth

Worker H consumes Worker A durable records rather than creating competing state:

- `pandora_project_business_objectives`
- `pandora_cost_entries`
- `pandora_budget_limits`
- exact project/version/build/model/tool lineage carried by those records

The Worker H control-plane adapter preserves free-text objective/baseline/target fields and parses numeric baseline/target values only when they are unambiguous numeric or percentage strings.

## Analytics and PostHog boundary

The provider-independent analytics interface supports metrics, funnels, retention, cohorts, timeseries, experiments, event capture validation, freshness, and data-quality checks. The PostHog adapter requires organization/project/environment scope and optional exact project-version scope.

Generated customer apps may emit only customer-app business events. Pandora authority events such as build, verification, cost, publish, or rollback truth must originate from trusted server boundaries. Analytics payload validation rejects sensitive-key patterns and oversized/unbounded properties.

The connected PostHog project must not be treated as Pandora business proof unless the canonical Pandora event taxonomy and required scope/version properties are actually observed. If canonical Pandora events are absent, Worker H returns `not_measured`/`awaiting_data`.

## Economics

`economics.js` normalizes Worker A cost entries and preserves three cost-confidence states:

- `actual`: provider-billed cost is present
- `estimated`: a versioned estimate is present but billing is absent
- `unknown`: neither billed nor estimated cost is present

Customer charge, credits, and internal cost remain separate values. Gross margin is emitted only when both net customer revenue and internal cost are known.

### Total cost to verified result

The default verified-result cost requires evidence for:

- model
- build compute
- verification

The calculation is exact-version scoped. A version-scoped calculation fails closed on unattributed or cross-version cost records. Missing required categories or unknown required-entry costs produce `totalCostMicros = null` with explicit completeness details.

Retry and repair spend are included when cost lineage marks those entries as retries/repair attempts.

### Model economics

Worker H can normalize token usage against an explicit pricing version and pricing source, compare verified-pass rates, compute cost per verified result, and produce quality-per-dollar rankings. Candidates with unknown cost do not win a cost-efficiency recommendation.

These are advisory routing signals for Worker B; they do not select or invoke a model by themselves.

## Budgets and Worker C

Worker H projects durable budget limits into Worker C's existing policy shape:

- `exhausted`
- `remaining_units`
- `requires_approval_for_extra_spend`

Worker C remains the authorization authority. Worker H does not approve additional spend or execute expensive actions.

## Experiments

Experiment contracts require explicit objective, hypothesis, control, variant, primary metric, minimum sample size, and guardrails.

A result may only claim the bounded `randomized_exposure_verified` causal state when all of these are true:

- experiment was randomized
- exposure assignment is verified
- minimum sample is satisfied in both arms
- confidence threshold is satisfied
- no guardrail failed
- the requested minimum effect is satisfied

Non-randomized or insufficient-sample results remain non-causal/inconclusive even when the observed variant value is higher.

Pricing tests report observed leaders only when sample/confidence requirements are met and remain non-causal.

## Pilots, unit economics, and ROI

Pilot validation requires a paid pilot, sufficient observation window, target outcome evidence, complete cost/revenue inputs, and positive observed margin. Retention can explicitly be `not_applicable` for projects where retention is not a meaningful outcome.

ROI and manual-hours value preserve evidence/assumption labels and are non-causal unless an independent experimental design establishes causality. Unknown benefit or cost keeps ROI unknown.

## Recommendations and optimization loop

Recommendations remain evidence-backed proposals. An accepted recommendation can be converted into a normal Pandora `change` intent with provenance linking objective, metric, measurement window, recommendation, and exact project version.

The generated intent always states:

- direct execution is not authorized
- production mutation is not authorized
- the ordinary Worker B/C/D/E/F lifecycle is required

Version comparisons are temporal associations by default, not causal claims.

## Owner-safe APIs

Worker H exports owner-safe projections equivalent to:

- `getProjectBusinessSummary`
- `getProjectMetric`
- `getProjectFunnel`
- `getProjectRecommendations`
- `getProjectEconomics`
- `getPortfolioBusinessSummary`
- `getBudgetStatus`
- `getExperimentResult`

Every projection enforces organization/project isolation. Provider query internals, raw provider responses, idempotency/tool/model lineage details, secret-like keys, credentials, and raw analytics queries are removed from owner-facing output.

Professional detail projections may include technical measurement/funnel/cohort/version/experiment information, but still strip credentials and raw provider internals.

## Alerts

Worker H produces bounded alert contracts for:

- exhausted/near-limit budgets
- stale/broken measurements
- analytics attribution/schema/data-quality failures
- material outcome regressions or target attainment

Alerts are advisory signals. They do not execute repairs or production changes.

## E2E proof contract

The Worker H E2E proof checks:

1. business objective has a measurement definition
2. instrumentation is independently verified
3. scoped provider data is actually received
4. measurement is fresh
5. outcome/economics evidence is present when claimed
6. budget signal matches Worker C's policy contract
7. accepted recommendations route through a governed change intent
8. Worker H never authorizes a production mutation

Cross-organization/project records are rejected. Exact-version economics rejects unattributed/cross-version costs.

## Credential boundary

Worker H source contains no provider credentials. Repository mutations and provider operations must use the platform's existing Vault-backed provider boundaries. Provider secret values must never be committed, logged, copied into generated applications, or surfaced in owner/admin API responses.

## Worker J handoff

Worker J can consume:

- scoped analytics and measurement readiness contracts
- total-cost-to-verified-result and unit-economics projections
- Worker C budget-policy signals
- experiment/pilot result contracts
- governed recommendation change intents
- owner/professional business API projections
- fail-closed no-data proof

A release claim for Worker H must be based on exact-head CI and integrated E2E evidence, not this document alone.
