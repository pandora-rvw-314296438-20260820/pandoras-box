# Pandora Tax Evidence Inbox V1

This slice continues the owner-approved Tax & Compliance Operating System after the live foundation rollout.

## What this slice adds

- Tenant-scoped ingestion batches.
- SHA-256 evidence registry with one canonical document per organization/content hash.
- Multiple source objects can link to one canonical document, allowing exact duplicate detection without duplicating tax records.
- Tax document extraction attempts with provider/model/parser provenance.
- Mandatory human review: provider/model extraction is always committed as `review_required`, even at 100% confidence.
- Owner/admin review RPC for verified/rejected extraction decisions.
- Evidence inbox summary that deliberately excludes raw extracted fields.
- Audit events for evidence registration, extraction, and review.
- Sensitive tax read access now fails closed to owner/admin until explicit Finance Admin / Accountant / Auditor roles are introduced.

## Raw evidence boundary

The RPCs in this slice do not accept raw file bytes.

A trusted ingestion runtime is expected to:
1. persist the authorized object in approved private storage;
2. compute SHA-256 and byte size;
3. call `pandora_tax_register_evidence_v1` with the storage pointer and digest;
4. invoke an approved parser/OCR/model;
5. commit structured output with `pandora_tax_commit_document_extraction_v1`;
6. wait for human review before treating extracted data as verified.

This prevents an LLM or OCR provider from promoting its own interpretation into verified tax evidence.

## Duplicate behavior

Evidence identity is scoped to `organization_id + content_sha256`.

When the same bytes arrive from a second authorized source:
- a new source object may be recorded;
- the existing canonical document is reused;
- a `duplicate_source` link is created;
- no second canonical tax document is created.

## Security boundaries

- Registration and extraction commit RPCs: `service_role` only.
- Human review RPC: authenticated owner/admin only.
- Evidence/extraction tables: direct authenticated writes denied.
- Read policies: owner/admin only for now.
- Cross-tenant access: denied.
- Audit payloads contain IDs/status/provenance summaries, not extracted financial fields.

## Deliberately not included yet

- Storage upload/signed-upload UI.
- Gmail/Drive/accounting/bank connectors.
- OCR/model routing policy.
- Ledger-entry creation from verified documents.
- Automated reconciliation.
- Philippine tax rule calculations.
- Filing or payment.

Those remain later slices with separate provider/security evidence.
