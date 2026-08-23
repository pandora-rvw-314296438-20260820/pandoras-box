# Customer interviews and first paid pilot — dated snapshot

**Snapshot as-of date:** 2026-08-23

**Live operational status authority:** authenticated `/api/operator/status`

**Commercial evidence state:** problem validation, willingness to pay, payment, retention, and unit economics are not currently proven

**Outbound/customer-contact activity performed by this consolidation:** none

**Read-only provider activity:** one operator-observed Gmail mailbox query at 2026-08-23T14:54:20.692Z; it sent no message, contacted no customer, and produced no persisted opaque provider receipt

This file is a dated commercial-evidence handoff, not a live technical status surface. Use authenticated `/api/operator/status` for current operational state. The snapshot preserves the 2026-08-23 discovery and paid-pilot baseline while retaining PR 61 as historical evidence.

## Snapshot context

| Surface | State observed in this snapshot | Meaning for this lane |
|---|---|---|
| Canonical source | protected `main@5a630893f2102064dcb2c7c72a3374042e6b4542` | New evidence must bind to this lineage or an exact reviewed successor. |
| Pull requests | the 41-PR decision triage is complete | This records land/consolidate/archive decisions; it does not claim every provider-side close or merge action is complete. |
| Production | still on source `bbfb769d475107badb5d7beafede6c775325e98a` | A new exact deployment, rollback binding, and production readback remain pending. |
| Android | physical Wi-Fi and mobile-data journey proof pending | Do not represent the new owner journey as production-verified. |
| Commercial | an operator-observed Gmail query at 2026-08-23T14:54:20.692Z counted 11 labeled threads, 11 outbound invitations, one automated hard-bounce response, and zero substantive replies | No opaque provider receipt was persisted, so these counts are an unverified dated observation—not an interview, consent, interest, or proof that no offline contact occurred. |

The machine-readable snapshot provenance and privacy transformation record is in `SOURCE_PROVENANCE.json`.

## Historical evidence retained

PR 61 exact head `48dc181db42ed8459f604911b93a6339a1514059` recorded 11 research-invitation attempts: 10 had no immediate hard bounce observed and one hard-bounced. At that snapshot it recorded zero substantive replies and zero completed interviews. “No hard bounce observed” is not delivery, interest, or customer evidence.

`historical-outreach-ledger.json` keeps the pseudonymous account code, subsegment, observation, evidence digest, and timestamp. Public business names, source URLs, mailbox details, message bodies, and free-text notes were intentionally omitted. The original bytes remain content-addressed at the PR head.

An operator-observed Gmail query found no substantive reply in the 11 labeled threads, but no opaque provider receipt was persisted. Treat the counts as unverified. Offline contact and the present state of the businesses remain unknown. Do not follow up, retry the hard bounce, or treat a prior invitation as continuing consent without owner authorization and source revalidation.

## Interview handoff

The first cohort is 10 qualified interviews in one narrow hypothesis: owner-operated appointment or field-service businesses whose inquiry-to-completion work may be delayed, duplicated, or invisible across chat, phone, paper, or spreadsheets. This is a recruiting hypothesis, not a validated market fact.

A qualified interview is with the buyer, daily workflow owner, or direct user; covers a real case handled in the prior 30 days; and identifies the decision and budget process. Do not demo or pitch during the first 20 minutes.

Ask neutrally:

1. Walk me through the last inquiry that became a completed job.
2. Where did it arrive, and who first owned it?
3. What had to be known before it could be accepted or scheduled?
4. Describe the last delay, loss, duplicate, or misunderstanding.
5. How often does that happen?
6. What did it cost in revenue, time, rework, or trust?
7. What workaround is used today, and what has already been tried?
8. Who approves a change and who uses it daily?
9. What has the business previously spent on this problem?
10. What outcome would justify staff time, budget, continuation, or expansion?
11. What would make a new system fail or be abandoned?
12. May I record a de-identified structured summary, and is my summary accurate?

Capture only records conforming to `evidence.schema.json`. Never commit names, contact details, raw transcripts, message bodies, credentials, customer records, financial documents, or confidential workflow content.

Before accepting a record, run `node src/projectos/business-validation-evidence.js <evidence.json>` so cross-field commercial bindings and the PII linter fail closed as well as the JSON schema. That CLI deliberately cannot self-verify an offer-ready or paid technical gate: gated intake must additionally supply a trusted verifier that independently resolves the provider-backed `AUTHENTICATED_CANONICAL_STATUS` receipt. Receipt-shaped IDs or hashes in a local file are insufficient.

Interview gate:

- target: 10 qualified interviews;
- repeat signal: at least 3 independent businesses describe the same weekly-or-more-frequent problem without prompting;
- commitment signal: at least 2 make a concrete behavioral commitment such as workflow walkthrough, staff time, buyer introduction, or detailed pilot discussion;
- preserve refusals, weak signals, and disconfirming evidence;
- compliments, link requests, and free interest do not pass the gate.

## First paid-pilot handoff

Do not send an offer until both the interview gate and technical gate pass.

Technical gate:

- one current provider-backed canonical status/release receipt for the exact source SHA and tree, with all five required checks in canonical order and a separately authorized independent-review receipt;
- one production deployment, one distinct rollback transition, and the restoration receipt/time bound back to that exact source by provider readback;
- the exact Supabase source-byte chain plus matching expected/provider-applied ordered-version-chain digests, and the CI-built Android APK/artifact digest, bound to the same source/tree;
- separate physical Android owner-journey receipts over Wi-Fi and mobile data, both after restoration and bound to that same deployment and APK;
- authenticated inquiry-to-terminal-state workflow with no critical security, privacy, isolation, data-loss, or authorization defect;
- retries, manual rescue, support time, and direct variable costs measurable.

Commercial gate:

- explicit owner authorization for the exact offer and recipient;
- approved scope, price, support boundary, data handling, cancellation/refund terms, billing method, and any legal terms;
- payment evidence kept in an approved provider or restricted store, with only an opaque reference committed here.

Bounded pilot design:

- one independent business, one location, and one inquiry-to-completion workflow;
- one owner/approver and at most five operating users;
- 30 live measurement days after activation;
- no payment processing, paid messaging purchase, regulated action, broad CRM/ERP replacement, or unsupported integration;
- activation means the first eligible real inquiry reaches an agreed terminal state and appears correctly in the owner's live queue without developer intervention during that journey;
- record eligible attempts, terminal-state correctness, time to decision, failures, retries, manual rescues, support minutes, direct costs, and the customer's continuation decision.

The inherited starting price hypothesis is **PHP 15,000 once** for the bounded pilot. It is untested, unquoted, unaccepted, and not authorized by this document. The owner may approve, change, or reject it after interview evidence.

## External or owner-authorized work still required

- complete and read back the exact deployment/rollback and physical Android gates;
- select and revalidate lawful interview candidates;
- authorize each outreach batch and sender identity;
- send invitations, obtain consent, schedule, and conduct interviews;
- approve any price, commercial/legal terms, invoice, payment collection, refund, customer onboarding, or production-data handling;
- verify provider-side payment and customer acceptance before upgrading evidence state.

The immediate evidence sequence remains:

`10 qualified interviews → repeated problem and commitments → one authorized offer → one real payment or refusal → one measured outcome → D30 continuation decision`
