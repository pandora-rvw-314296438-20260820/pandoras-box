# ADR 001 — Universal Enterprise Core and ProjectOS Retirement

Status: Accepted / Locked  
Date: 2026-09-30

## Context

Pandora already contains mature capability routing, execution, verification, tax evidence, hospitality, provider, and learning infrastructure. The convergence risk is therefore duplication: a second router, a second execution ledger, a second tenant root, or a generic enterprise object store could fragment the platform.

The existing `public.enterprise_source_connections` table is hospitality/property-specific, so silently redefining it as the universal integration contract would also create semantic breakage.

## Decision

1. `public.organizations` remains the tenant/business organization root.
2. Universal Core uses a thin enterprise entity identity spine plus explicitly typed business tables.
3. The entity spine may contain identity, organization, type, schema version, and lifecycle metadata only. It may not contain arbitrary business payload.
4. Phase 1A begins with a typed Person table and shared source/provenance/authority infrastructure. Additional Core nouns arrive as additive typed slices.
5. The universal source connector table is `enterprise_integration_connections`. The existing `enterprise_source_connections` table is not renamed or repurposed in Phase 1A.
6. External source records are preserved separately from canonical business state.
7. Identity merges require evidence-backed resolution; Phase 1A requires a shared verified keyed-HMAC identity signal for MERGE acceptance.
8. Field provenance and source authority are separate contracts.
9. Source authority vocabulary is separate from provider selection. AUTO/PREFERRED/REQUIRED remains provider routing only.
10. Existing capability registry, routing, Tool Gateway, execution, verification, reconciliation, and learning mechanisms are reused or generalized before any replacement is considered.
11. ProjectOS is retired. Historical ProjectOS-named artifacts remain evidence only and do not authorize new ProjectOS-dependent architecture.

## Consequences

- Cross-industry identity and provenance can converge without flattening domain semantics.
- Hospitality and tax implementations remain usable while universal contracts are introduced additively.
- Cross-tenant foreign keys use organization-bound composite references.
- Raw email/phone identity evidence is not duplicated into identity-resolution evidence ledgers; verified signal hashes and evidence references are used.
- Provenance history is append-oriented and source replay is explicitly deduplicated.
- The first migration does not claim the entire Universal Core is implemented; it establishes the foundation and Person slice.
