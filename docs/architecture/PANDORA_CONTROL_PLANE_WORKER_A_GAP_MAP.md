# Pandora Worker A — Control Plane Gap Map

Baseline inspected: 2026-08-28  
Repository baseline: `main` at `3ec9f18bc7d283a9f06aac2f23f5959f780fb9a8`  
Supabase control plane: `jcyqixttuebxqqfkjonq`

## Canonical structures to reuse

- `organizations` + `memberships` are the organization/user authority boundary.
- `projectos_projects` is the canonical internal project record. Worker A does not create a competing project table.
- `projectos_decisions` is the canonical durable decision history and already supports supersession.
- `projectos_project_resources` is the canonical provider-resource binding registry.
- `approvals` + `audit_events` remain the existing generic governance/audit foundation.
- `pandora_project_versions`, `pandora_project_deployments`, and `pandora_project_domains` are the customer project-runtime lineage introduced by `20260828132500_pandora_project_runtime.sql`.

## Confirmed gaps before Worker A implementation

| Contract | Baseline | Worker A action |
| --- | --- | --- |
| Customer intent receipts | Missing | Add append-only `pandora_project_intents` |
| Canonical ProjectSpec | Missing | Add immutable/versioned `pandora_project_specs` |
| Requirements/objectives/constraints/acceptance | Missing | Add queryable relational child contracts |
| Decision → ProjectSpec/intent provenance | Partial | Extend `projectos_decisions` with optional lineage references |
| Durable build jobs/events/leases/attempts | Missing | Next bounded milestone |
| Provider-independent model runs | Missing | Later bounded milestone |
| Tool-call lineage | No canonical Worker A contract | Later bounded milestone; do not take over provider execution |
| Artifact lineage | Missing | Later bounded milestone |
| Project version richness/rollback links | Partial | Extend existing `pandora_project_versions`; do not replace it |
| Verification contracts | Missing | Later bounded milestone |
| Policy action/approval binding | Partial | Reuse `approvals`, add action-target contract where required |
| Cost/budget accounting | No canonical project/job contract | Later bounded milestone |
| Project semantic relationships | Partial via ProjectOS resources/decisions | Add typed relationships later |
| Generated-app runtime isolation metadata | Partial via ProjectOS resources | Add explicit runtime metadata later |
| Secret reference metadata | Missing | Add references only; Vault remains secret holder |
| Generated-app DB migration safety | Missing | Add durable migration-plan lineage later |
| Build Theatre Realtime projection | Missing | Add customer-safe projection after job engine |
| Worker A audit history | Generic audit exists | Add project-scoped append-only event contract later |
| Worker A RLS regression coverage | Missing | Add per-milestone regression tests |
| Query-driven Worker A indexes | Missing because contracts missing | Add with each contract |
| Canonical Control Plane V1 document | Missing | Produce after implementation reflects source truth |

## Source-chain constraint

Several recovery-era production migrations in the repository are intentionally represented as history-only `select 1` receipts. Worker A migrations from this point forward must be replayable source migrations and must pass the repository migration replay gate.

## Ownership boundary

Worker A persists durable state and contracts only. It does not implement model-provider SDK calls, build sandboxes, Flutter/Build Theatre presentation, Vercel/GitHub/GitLab execution, verifier execution, or optimization UI.
