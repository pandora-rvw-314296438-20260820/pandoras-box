# Pandora Tax & Compliance Foundation V1

This is the first implementation slice of the owner-approved Tax & Compliance Operating System plan.

## Implemented in this slice

- Organization-scoped tax evidence/data model.
- Versioned jurisdiction and deterministic rule-pack authority, with approval provenance, reviewer identity, per-rule source references, immutable approved history, and same-jurisdiction approved supersession.
- Philippines jurisdiction placeholder with **no hard-coded tax rates** and no approved production rules.
- Canonical tax periods, source objects, documents, ledger entries, reconciliation runs, exceptions, calculation runs/lines, obligations, reviews, approvals, and append-only audit events.
- RLS isolation for authenticated users.
- Direct authenticated table writes are denied; service-side writes remain privileged.
- Owner/admin-only `pandora_tax_prepare_period_v1` command boundary.
- Read-only `pandora_tax_workspace_v1` command-center projection.
- Filing and tax payment are explicitly disabled until separately verified adapters and approval controls exist.

## Deliberately not implemented yet

- Current Philippine tax rates or filing formulas.
- BIR filing integration.
- Tax payment execution.
- Customer accounting/bank connectors.
- OCR/document extraction.
- UI pages.

Those capabilities require their own evidence, tests, source provenance, and professional review gates. This foundation must not be treated as proof that Pandora can already calculate or file a real tax return.

## Next build slice

1. Evidence inbox and source hashing.
2. Controlled ingestion adapters.
3. Reconciliation engine and exception creation.
4. Versioned Philippines rule-pack governance/test harness using current authoritative sources.
5. Tax command-center UI and persistent chat orchestration.
