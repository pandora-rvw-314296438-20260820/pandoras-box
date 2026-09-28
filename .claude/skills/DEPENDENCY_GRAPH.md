# Pandora Skill System — Dependency Graph

Skills declare which upstream proof must exist before downstream execution. An arrow means *the upstream must be satisfied first*, not merely that the skills are related.

## Entry

```
any request
    │
    ├── Band A (single read)      → call the tool directly, load nothing
    ├── Band B (scoped, 1 domain) → pandora-router → the one domain skill
    ├── Band C (vague / stateful) → pandora-router → pandora-control-tower → …
    └── Band D (multi-stage)      → pandora-router → pandora-control-tower → delivery chain
```

`pandora-governance-contract` is loaded on demand by any skill that classifies risk, mutates, or claims completion. It is a shared library, not a stage.

## Recovery chain

```
pandora-project-recovery
    └── pandora-memory-context          (canonical state, contradictions)
            └── pandora-source-control  (provider truth for source)
            └── pandora-supabase        (provider truth for data)
            └── pandora-mcp-discovery   (what is actually possible)
                    └── pandora-control-tower  (reconcile → select next action)
```

## Delivery chain — the core proof ladder

Each stage requires the previous stage's proof. Skipping a stage means the proof state cannot advance.

```
pandora-requirements                    → acceptance criteria exist
    └── pandora-architecture            → design + ADRs
        └── pandora-implementation      → PROOF: implemented (exact SHA)
            └── pandora-testing         → PROOF: tested (named runs on that SHA)
                └── pandora-security-review     → PASS, no open CRITICAL/HIGH
                    └── pandora-exact-head-review → PASS at exact head
                        └── pandora-deployment-release
                             ├── preview acceptance    → capability exercised
                             ├── rollback proof        → artifact PROVEN
                             └── production release gate  ⟵ OWNER AUTHORIZATION
                                  └── PROOF: production_verified
                                       └── pandora-runtime-observability
```

Every mutation in this chain routes through `pandora-governed-execution`, and every established fact routes to `pandora-evidence-ledger`.

## Governed mutation (crosscuts everything)

```
any state change
    └── pandora-governed-execution
            ├── pandora-governance-contract/references/risk-classification.md
            ├── pandora_create_plan / pandora_plan_<tool>
            ├── pandora_approve_plan        ⟵ owner/admin, if risk != read
            ├── pandora_execute_plan        (one-time claim)
            ├── provider readback
            └── pandora-evidence-ledger
```

## Independence boundary

```
pandora-implementation ──╳──> pandora-exact-head-review
pandora-implementation ──╳──> pandora-security-review
```

The reviewer skills must not be invoked to repair their own findings and then pass the result. A FAIL returns to the implementer; a new candidate at a new head gets a new review.

## Risk gates

```
pandora-requirements
    └── risk class = regulated
            └── pandora-regulated-activation     [FAILS CLOSED]
                    ├── build permitted (sandbox only)
                    └── activation ⟵ SEPARATE OWNER AUTHORIZATION + qualified review

any personal/sensitive data
    └── pandora-privacy-data-governance

any provider integration
    └── pandora-provider-adapter
            └── pandora-governed-execution
```

## Commercial chain (independent of engineering)

```
pandora-commercial-validation      → ICP · wedge · WTP · paid pilot
    └── pandora-unit-economics     → margin · LTV/CAC · credit economics
        └── SCALE GATE             ⟵ evidence authorizes scale, dates only begin experiments
            └── pandora-gtm-customer
                └── pandora-ecosystem   [evidence-gated; document and defer by default]
```

Technical progress never satisfies this chain. `production_verified` and "customers pay repeatedly" are independent facts.

## Support skills

| Skill | Invoked by |
|---|---|
| `pandora-cicd` | testing, deployment-release, security-review |
| `pandora-performance` | implementation, supabase, runtime-observability, unit-economics |
| `pandora-ui-ux` | implementation, mobile-flutter |
| `pandora-mobile-flutter` | implementation, deployment-release |
| `pandora-auth` | architecture, security-review, supabase |
| `pandora-ai-routing` | implementation, performance, unit-economics |
| `pandora-documentation` | any stage producing a durable artifact |
| `pandora-disaster-recovery` | project-recovery, source-control, supabase |

## Proof-state preconditions

| To reach | Requires |
|---|---|
| `implemented` | exact commit SHA + tree SHA |
| `tested` | named runs on **that exact SHA**, with counts |
| `deployed` | artifact bound to that SHA, verified binding, environment named |
| `production_verified` | observed capability behavior + monitoring + **proven** rollback |

Downgrade rules apply: head advances past the tested SHA → back to `implemented`; deployment replaced → `deployed`/`production_verified` revert; broken source/provider parity caps a capability at `deployed`.
