# FB-026 — Growth learning outbox adapter contract

## Scope

This source-only adapter projects the reviewed FB-025 growth-learning envelope into the existing Pandora Box `private.execution_learning_outbox` transport shape. It does not insert an outbox row, dispatch HTTP, modify Memory, approve a review, promote a canonical item, or make an item retrievable.

The adapter remains runtime-held because the current `pandora-projectos-learning` endpoint accepts only ordinary ProjectOS events and `visible_creation_evidence_v1`. It rejects any other present `learning_kind` as `unsupported_learning_kind`. The current `submitEvidenceCandidate` path is also unsuitable: it accepts only five build/preview/publish/repair/failure evidence kinds and normalizes them to one business-fact candidate, which would collapse FB-025 semantics.

## Existing transport reused

The adapter emits the existing outbox columns:

- `event_key`: deterministic identity over tenant, source project, learning ID and FB-025 content hash;
- `organization_id`: trusted source tenant;
- `request_id`: deterministic UUID derived from the bound payload hash;
- `project_id`: trusted source project;
- `project_key = mcpmaster-pandoras-box`;
- `payload`: the existing signed ProjectOS learning envelope with `learning_kind = growth_learning_v1`;
- `delivery_status = pending`.

The current identity shape comes from
`supabase/migrations/20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql`,
which adds `event_key`, makes `plan_id` nullable, and requires either a plan ID
or a nonblank event key. A live catalog read at `2026-09-28T17:13:36.348823Z`
confirmed `event_key text`, nullable `plan_id uuid`, the validated identity
check, and the partial unique event-key index. This adapter uses that established
lifecycle-event path; it does not weaken the plan foreign key or create a queue.

The payload targets the existing Memory project `7c686cbd-d968-49d5-86cc-918f5e777bd2`, namespace `real_life`, principal `projectos-mcpmaster-production`, and production environment. These target values are constants rather than model or candidate input. The current Box dispatcher authenticates with timestamp and HMAC headers and sends no caller-selected principal. Deployed Memory function `pandora-projectos-learning` version 8 (`ezbr_sha256 415a56273824f4edf62747eef51a3c2da0c32d446bf707a8ab2519585949a8e2`) imports immutable Memory source `27cf80b18d8c5861805641accc1afaeffe584e16`; that source fixes its existing visible-creation proposal path to `VISIBLE_PRINCIPAL_KEY = projectos-mcpmaster-production`. A live Memory catalog read at `2026-09-28T17:15:32.771561Z` confirmed that exact production principal and project grant are active and non-revoked with `can_read = true`, `can_propose = true`, and `can_approve = false`. The future growth branch must keep this principal server-owned and independently re-read the grant; no caller may select or widen it.

The complete FB-025 candidate and source/target scope are canonical-JSON hashed into `context_hash`. This follows the existing visible-creation pattern: the outer HMAC signature already covers `context_hash`, and the future Memory parser must independently reconstruct the growth binding and constant-time compare its hash. No semantic field may sit outside that basis.

## Lossless epistemic contract

The signed binding preserves exactly one of:

- `verified_fact`
- `user_decision`
- `provider_evidence`
- `inference`
- `assumption`
- `superseded`

It also preserves the statement, subject, confidence and basis, authority kind/ref, provenance, evidence refs, observed/effective/review/expiry timestamps, and supersession reference/reason. The adapter does not choose a canonical Memory `record_type`.

This is required because the live Memory grant allows the existing principal to read and propose, but not approve. Its allowed record types are the established project record types; there is no blanket permission to canonize an inference or assumption. A human review must select an allowed record type or reject the candidate. No grant widening is part of FB-026.

## Four separate states

1. **Delivery** — Box outbox `pending | submitted | delivered | failed`. `delivered` means a bound Memory intake response was verified.
2. **Review** — Memory candidate and review-item UUIDs exist with `status = pending_review`.
3. **Promotion** — remains `not_promoted` and `canonical_memory_written = false` until a separate authenticated human approval and persistence transaction succeeds.
4. **Retrieval** — remains `not_retrievable` until a separately promoted, approved, active, non-revoked, non-superseded and validity-eligible Memory item is returned by the canonical retrieval gate.

Pending delivery or pending review is never canonical or retrievable.

A valid growth intake response must bind the exact source event, learning ID and content hash; return candidate and review UUIDs; and explicitly state `review_required = true`, `canonical_memory_written = false`, `promotion_status = not_promoted`, and `retrieval_status = not_retrievable`. Before accepting that response, the source validator revalidates the candidate semantics, reconstructs the candidate content hash, recomputes the complete binding hash and deterministic request identity, and checks the fixed source/target envelope. A generic HTTP 200/202 or a response matched to tampered payload fields is insufficient.

## Runtime prerequisites

Before dispatch can be enabled:

1. Extend the existing Memory `pandora-projectos-learning` parser with an exact-key `growth_learning_v1` branch.
2. Recompute and compare the full growth binding hash before any insert.
3. Re-read the exact active Memory project and `projectos-mcpmaster-production` grant; require production, `can_propose = true`, `can_approve = false`, active and non-revoked.
4. Insert an immutable pending candidate and pending review item idempotently. Preserve every FB-025 field in the candidate/review evidence snapshot.
5. Return the exact response contract verified by `validateGrowthLearningIntakeAcceptance()`.
6. **Satisfied in the converged source:** `20260929040000_growth_learning_outbox_delivery_v1.sql` makes `execution_learning_response_is_valid` fail closed for unknown nonempty kinds and requires the strict twelve-field growth receipt. Production activation still requires deployed function readback.
7. Keep Box dispatch fenced until the deployed Memory parser version and response validator are both read back.
8. At human promotion, choose only an allowed record type, bind the approved semantic digest, and resolve an opaque `supersedes_ref` to one exact same-project Memory item transactionally.
9. Persist and enforce `expires_at`. The live canonical table has effective/review timestamps but no dedicated expiry column, so expiry must be added or enforced from a strictly typed canonical metadata field by every retrieval path.
10. Prove retrieval separately through the approved-canon gate. Intake acceptance and review creation cannot satisfy retrieval acceptance.

FB-025's native task remains separately verifying; that release bookkeeping does not prevent source preparation of this adapter. It does prevent claiming the FB-026 native task complete until the dependency and deployed runtime readbacks are satisfied.
