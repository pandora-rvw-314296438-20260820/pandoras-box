# FB-025 — Tenant-scoped growth learning schema v1

## Purpose

FB-025 defines a **source-only, review-gated envelope** for growth learnings before they enter Pandora Memory. It does not create a new Memory database, widen a Memory grant, promote canonical records, or let a model choose tenant scope.

The schema is implemented by `src/pandora-growth-learning-schema.js`. A trusted caller supplies `organization_id` and `project_id` separately from the candidate payload; mismatches fail closed.

## Epistemic classes

Every learning carries exactly one `claim_kind`:

- `verified_fact` — a factual claim backed by provider, independent verification, or an authoritative record.
- `user_decision` — an explicit owner/authorized-user decision. A decision is not converted into provider evidence.
- `provider_evidence` — a claim about what a provider actually returned or acknowledged. Provider provenance is mandatory.
- `inference` — model-derived interpretation. It remains explicitly labeled and reviewable.
- `assumption` — an unverified planning assumption. Confidence is capped at 0.5 and it cannot carry evidence as if that evidence made it factual.
- `superseded` — a historical claim retained for lineage after newer evidence replaces it. An explicit supersession reference and reason are required.

These classes must never be silently collapsed. A Memory consumer may choose a canonical Memory record type only after checking the live project grant and Memory review policy.

## Required fields

The envelope binds:

- `schema_version = growth-learning-v1`
- stable `learning_id`
- trusted `organization_id` and `project_id`
- `subject_key`
- `claim_kind`
- bounded human-readable `statement`
- `observed_at`
- validity window: `effective_at`, `review_due_at`, nullable `expires_at`
- numeric `confidence` plus textual `confidence_basis`
- typed `authority.kind` and `authority.ref`
- structured `provenance`
- bounded `evidence_refs`
- nullable `supersession` lineage

Secret-bearing field names are rejected. Raw customer records, prompts, API tokens, passwords, service-role keys, private keys and unrestricted provider responses do not belong in this envelope.

## Pandora Memory compatibility

The live canonical Memory store already has project identity, confidence, confidence basis, provenance, evidence refs, authority kind/ref, effective/review timestamps, correction/supersession fields and draft/canon status. FB-025 therefore maps to those existing concepts rather than introducing a competing store.

`projectGrowthLearningCandidate()` emits a **draft-only candidate projection** with:

- `review_required: true`
- `canonical_memory_written: false`
- content hash
- exact project/organization scope
- epistemic class
- authority/provenance/evidence lineage
- validity and supersession metadata

It intentionally does **not** choose a canonical Memory `record_type` or promote itself. FB-026 owns validation against the existing learning outbox/intake contract and the currently active Memory project grants.

## Validity and supersession

Freshness is explicit. `effective_at <= review_due_at <= expires_at` when an expiry exists. A claim that becomes stale is not silently deleted; it is reviewed, corrected, revoked or superseded through Memory's existing review lineage.

Superseded information remains historical evidence. New authoritative evidence can replace it without erasing the prior claim.

## Authority boundaries

This schema provides structure, not authority:

- tenant scope comes from trusted runtime context, never model-selected IDs;
- provider evidence does not authorize provider mutation;
- a user decision is preserved as a decision, not reclassified as fact;
- inference and assumptions cannot self-promote;
- validation does not mean Memory accepted, reviewed or canonized the candidate;
- no ad spend, OAuth, client activation or other consequential action is granted by a learning record.

## Verification

Run:

`node --test test/pandora-growth-learning-schema.test.js`

The suite covers all six epistemic classes, tenant mismatch rejection, evidence requirements, assumption confidence limits, supersession lineage, draft-only Memory projection and secret-shaped field rejection.
