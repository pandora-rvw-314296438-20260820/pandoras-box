# FB-003 — Pandora acquisition outcome contract

**Status: proposed; owner review required. No activation or spending authority.**

Task: FB-003, Facebook/Growth. Source base inspected:
`pandora-rvw-314296438-20260820/pandoras-box@6f20780765001d1a90ee31800a3948d043551afa`.
This proposal adds a pure validator and an in-memory regression helper. It does
**not** change the existing tracking routes, ingest events, resolve credentials,
query business records, send CAPI events, change dashboards, or modify campaigns.
It is not a second tracking service, database, token store, or identity resolver.

## 1. Decisions to approve

The owner must approve the outcome meanings, qualification policy, activation
counting entity, reporting revenue basis, contribution-cost inventory, and
retention policy. No approval, budget, launch date, retention interval, or target
conversion rate is invented here. FB-003 stays open until that review is recorded.
FB-005 independently controls scope and spending. Merge does not imply either approval.

Recommended counting entity for **paid activation** is one acquiring billing
account/workspace's first settled nonzero payment **and** confirmed usable paid
entitlement. A signed contract, free trial, checkout click, pending payment, or
provider redirect alone does not qualify. An owner must ratify this counting
entity before implementation; do not quietly change it to individual users.
Renewals and upsells remain payment events, not new acquisitions. Reactivation
needs a separately approved definition rather than inflating first acquisitions.

## 2. Separate acquisition paths

Self-serve: landing → signup → project → verified preview → verified publish →
paid activation → policy-defined retention, with settled refunds tracked separately.

Enterprise: landing/inquiry → persisted lead → evidenced qualification → completed
demo → delivered proposal → signed contract → paid activation → retention/refund.

These are **analytical paths**, not claims that every customer must traverse every
stage. Imported/offline enterprise leads may lack a landing or click. Preserve
missing stages; never synthesize a visit, signup, or earlier event to complete a
funnel. The shared payment, refund, activation, and retention events retain their
`acquisition_path`, so self-serve and enterprise denominators cannot be blended
without an explicitly labelled aggregate.

## 3. Event dictionary (14 outcomes)

All references below must be opaque, workspace-scoped business/evidence IDs,
not customer names, email addresses, phone numbers, credentials, or raw payloads.
“Required evidence” means a **verified lookup requirement for a future adapter**;
the included validator checks only presence/format, not the underlying evidence.

| Event | Path | Actual occurrence / required evidence | Counting identity (`outcome_id`) |
|---|---|---|---|
| `landing_view` | Both | An actual admitted landing capture; `capture_ref`. Browser/server captures are not a paid outcome or proof of a human visitor. | One captured view, not each delivery retry. |
| `signup_completed` | Self-serve | Persisted eligible account creation; `account_ref`. Not form open or failed signup. | Account-creation occurrence. |
| `project_created` | Self-serve | Persisted new project; `project_ref`. Not request submission. | Actual project identity. |
| `preview_ready` | Self-serve | Preview exists and verification passes; `preview_ref`, `verification_ref`. | Preview/version verification milestone. |
| `publish_verified` | Self-serve | Deployment readback confirms intended published version; `deployment_ref`, `verification_ref`. | Published deployment/version milestone. |
| `lead_submitted` | Enterprise | A real lead is persisted; `lead_ref`. Not form start or anonymous CTA click. | Persisted lead identity. |
| `lead_qualified` | Enterprise | Authorized qualification decision with evidence; `lead_ref`, `qualification_ref`, `qualification_policy_ref`. | First qualifying decision for lead/policy; retries are not new leads. |
| `demo_completed` | Enterprise | Evidence the demonstration happened; `meeting_ref`, `completion_ref`. Not merely booked. | Completed meeting occurrence. |
| `proposal_sent` | Enterprise | Persisted proposal and delivery evidence; `proposal_ref`, `delivery_ref`. Not generated draft. | Proposal/version delivery occurrence. |
| `contract_signed` | Enterprise | Confirmed signature; `contract_ref`, `signature_ref`. This is not collected revenue. | Executed contract identity. |
| `paid_activation` | Both | First eligible settled payment plus active paid access; `activation_ref`, `payment_ref`, `entitlement_ref`. | First acquisition activation of approved counting entity. |
| `payment_settled` | Both | Verified settled collection; `payment_ref`, `settlement_ref`; positive integer amount in minor units and currency. | Settlement occurrence, not invoice or retry. |
| `refund_settled` | Both | Verified settled refund linked to original payment; `refund_ref`, `payment_ref`, `settlement_ref`; positive minor-unit refund amount and currency. | Refund transaction; distinct partial refunds have distinct identities. |
| `retention_observed` | Both | Confirmed eligible use in a completed policy/cohort window; `observation_ref`, `usage_ref`, explicit `retention` policy, cohort, start/end. | Approved entity + policy + observation window. |

Verified business events require a **server** evidence adapter. Browser delivery
is allowed only for `landing_view` in this proposal. An authorized server can later
emit a matching browser/CAPI projection after evidence and consent checks; that is
not permission to trust browser assertions about payments or qualified leads.

## 4. Envelope and scope boundary

The proposed validator requires:

- `schema_version: 1`, a dictionary `event_name`, stable `event_id`, stable
  `outcome_id`, and explicit `acquisition_path` (`self_serve` or `enterprise`).
- `organization_id`, `tracking_tenant_id`, explicit nullable `project_id`, and an
  opaque `journey_id`. Business events also require opaque `subject_id`.
- `occurred_at` in canonical UTC `YYYY-MM-DDTHH:mm:ss.sssZ`, `delivery_source`,
  exact event-specific evidence references, and explicit attribution classification.

A separate trusted scope argument is mandatory. The validator compares the three
scope fields; it **does not authenticate the caller, validate membership/RLS,
resolve a Meta asset owner, or prove those mappings exist**. FB-004/Backend owns
that resolution and the business-reference lookups. Supplying the request's own
scope as the trusted argument is prohibited in a future integration.

The adapter must additionally verify evidence references belong to that scope,
subject, and actual business occurrence, reject future/dishonest occurrence times
under an approved clock policy, validate the permitted currency and minor-unit
exponent, and prevent cumulative refunds exceeding the original eligible payment.
The contract only checks uppercase three-letter currency *format*, not membership
in a live ISO currency registry. No such integration protections are claimed here.

## 5. Attribution is evidence, not a guess

Keep four explicitly different classifications:

`observed`: a first-party `pdc_` click reference plus linkage evidence; campaign
metadata may be added only after a trusted hierarchy lookup.

`platform_reported`: a provider report and campaign ID. Keep its attribution
window, reporting timezone, currency, and report period in the referenced report.
This is not a claim that Pandora observed an individual click-to-customer journey.
Do not invent user-level allocations from an aggregate report.

`inferred`: explicit method reference, evidence reference and candidate campaign.
Never relabel model inference as observed data or silently include it in directly
observed ROAS. Correlation is not causal lift.

`unattributed`: no attribution claims. A conversion with missing linkage remains
unattributed, including offline and imported leads. No “last active campaign” fallback.

Provider IDs remain strings, preserving large integer identity. When an ad or
creative is supplied, include the campaign/ad-set/ad hierarchy as appropriate.
Presence of those IDs does not verify their parent-child relation; the provider
hierarchy lookup and workspace mapping are separate integration gates. This
proposal deliberately does not ingest raw UTMs, URLs, fbclid, PII, or customer journeys.
Those belong to the existing tracking pipeline under reviewed retention controls.

## 6. Idempotency and duplicate conflicts

`event_id` is created once for a business occurrence and reused on retries.
`outcome_id` is its stable business/milestone key. Do not create either from a retry
attempt, current time, or a new page reload when replaying an existing outcome.

The regression helper scopes semantic identity by organization + tracking tenant +
event name + outcome ID, and delivery identity by organization + tracking tenant +
event name + event ID. Identical normalized claims count once; browser/server
transport may differ only for permitted capture events. Conflicting money,
currency, subject, timestamp, attribution, journey or event IDs **fail the batch**
instead of overwriting prior truth. Corrections need a separately reviewed,
audited correction path, not mutation disguised as a retry.

The helper is bounded to 1,000 inputs and is in-memory only. It provides **no**
cross-process or durable database idempotency. A future single-owner backend
migration must enforce persistent uniqueness/concurrency with appropriate scope.
A linked payment and a paid activation are different outcomes, but only the
payment carries money. A refund is a separate positive amount that reporting
subtracts exactly once; it must not be inserted as another sale.

For future Meta delivery, the corresponding browser `eventID`/event and server
`event_id`/`event_name` must match for the same Pixel/dataset. Meta documents a
receipt-time deduplication window; Pandora's durable first-party idempotency must
not depend on that window. No Meta event-name mapping or transmission is activated
here, and no live deduplication or CAPI acceptance is claimed.

## 7. Growth metrics and money definitions to ratify

Store monetary events in integer minor units with explicit currency. Do not sum
currencies, coerce missing values to zero, or treat a requested/refunded/pending
amount as settled income. Retain both occurrence and receipt time in eventual
storage, and reconcile late events under a declared reporting policy.

Proposed **net collected value** = eligible settled receipts minus linked settled
refunds, for one currency and declared cohort/reporting window. This is a growth
cash-collection measure, **not automatically accounting revenue**. A dashboard
labelled “Revenue” must explicitly declare whether it uses collected value or
recognized business-ledger revenue; owner/accounting review must decide that basis.
Invoice face value, signed-contract value, booking value, margin and cash received
are different measures and must not share an ambiguous “revenue” total.

Proposed contribution before advertising = approved net collected value less the
same-scope variable fulfilment/service costs and payment fees. Contribution after
advertising additionally subtracts matched acquisition spend. The cost inventory,
refund treatment, exclusions, and allocation policy need approval. Missing cost
inputs mean contribution is unavailable, not equal to revenue or profit.

CPL = matched spend / distinct persisted leads. Cost per qualified lead uses
distinct evidenced qualified leads. CAC uses the approved **new paying acquisition
entity**, not clicks, signups, contracts, renewals, or individual payment count.
A zero denominator means unavailable, not zero cost. ROAS uses the declared value
basis / matched spend, preserving currency, attribution definition/window, and
cohort/period basis. Do not mix today's ad spend with lifetime customer value.

Funnel conversion rate = distinct eligible cohort entities reaching a specified
stage / distinct eligible entities admitted to that stage's denominator. Counts of
event deliveries are not customers; stages may be skipped and cohorts may still
be immature. Retention requires an approved eligible cohort, qualifying use,
observation interval, and refund/churn treatment; no default day count is installed.

## 8. Compatibility and release gates

Current inspected tracking routes accept `lead`, `qualified_lead`, `booking`,
`sale`, `refund`. This proposal does not replace or reinterpret them. A later
adapter must explicitly map legacy conversions and lifecycle events, with dual
read/reconciliation tests. `paid_activation` must never be mapped to `sale` when
`payment_settled` already produced that monetary event. Event receipts, provider
acknowledgements, and business outcome verification remain separate evidence.

Before runtime integration: owner review (FB-003), trusted identity contract
(FB-004), scope/spend policy (FB-005), privacy/retention approval (FB-007), release
checklist (FB-008), persistent deduplication and verified producer adapters. All
Meta outbound actions additionally require genuine app credentials, authorized
OAuth/assets, consent controls, provider acknowledgement and appropriate readback.
No schema migration, deployment, CAPI delivery or paid action belongs to this patch.

## 9. Verification and handoff

Run `node --test test/pandora-growth-outcomes.test.js` from the repository root.
The existing `test/*.test.js` glob discovers the suite without a package or CI edit.
Tests are synthetic, offline contract tests. They do not prove live authentication,
RLS, linked business-record truth, provider state, production persistence, financial
accuracy, owner approval, or an accepted end-to-end acquisition funnel.

Release must attach exact committed head/source identity and run the repository's
Node 24 build/test/check and required protected-branch checks. Keep this contract
marked proposed unless the owner review is separately recorded. Do not bypass
GitHub write permissions or independent review gates. No production rollback is
needed for an unintegrated helper; rollback before integration is reverting the
three new files through the normal reviewed path.

## Sources inspected

- Canonical tracking definitions and first-party click format:
  https://github.com/pandora-rvw-314296438-20260820/pandoras-box/blob/6f20780765001d1a90ee31800a3948d043551afa/src/pandora-tracking-http.js
- Canonical test command/Node 24 requirement:
  https://github.com/pandora-rvw-314296438-20260820/pandoras-box/blob/6f20780765001d1a90ee31800a3948d043551afa/package.json
- Verified Memory recovery lesson (currency isolation; UI deferred; evidence before closure):
  https://github.com/pandora-rvw-314296438-20260820/pandoras-box-memory/blob/2d193c0667a037e815f50a1c1c81fd578eaf9d92/docs/capabilities/evidence/FB002_ATTRIBUTION_RECOVERY_2026-09-25.json
- Tracker task FB-003 and its owner-review acceptance gate:
  https://docs.google.com/spreadsheets/d/18JgJd9VD9-k9hPduUegqMKJAkeblZc_YRmx1Qr2q6xg/edit
- Meta primary documentation retrieved 2026-09-25 (provider contract must be rechecked before live integration):
  https://developers.facebook.com/docs/marketing-api/conversions-api/deduplicate-pixel-and-server-events
