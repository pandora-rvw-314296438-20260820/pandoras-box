# Pandora Universal Activity Theatre Contract v1

Status: **Frozen**  
Effective date: **2026-09-13**  
Machine contract: `docs/architecture/pandora-activity-theatre-contract-v1.json`

## Purpose

Activity Theatre is Pandora's universal truthful activity substrate. It is not a cosmetic progress animation, not a build-only surface, and not a place to invent reassuring stages. Every visible event must correspond to a real admitted runtime, device, provider, model, tool, verification, policy or user-control event with durable identity and privacy-safe provenance.

Build Theatre is a specialized projection of this same substrate. It may use build/edit/publish labels, but it may not create a second truth model or fabricate progress.

## Meaningful-event admission

Only meaningful real events are admitted. Fake percentages, invented stages, synthetic progress and UI-only success are forbidden. Every event carries stable job identity, event identity, canonical sequence, writer epoch, occurrence time, admission time and real-source provenance. A provider attempt ID or build attempt ID never substitutes for the Pandora job ID.

Admission is single-writer per job epoch. An authoritative local writer may continue while offline when the capability permits. Writer handoff requires a newer epoch, and reconnect/offline synchronization preserves original occurrence time and event identity. Duplicate identities are rejected or idempotently collapsed rather than replayed as new work.

## Ordering, clocks and lineage

`sequence` is the canonical order within a job. `occurredAt` records when the underlying event happened. `admittedAt` records when Pandora accepted it into the canonical Theatre stream. `provenance.observedAt` records when Pandora observed the source. Occurrence may precede admission, but admission may not precede occurrence.

Parent/child lineage is explicit when an event derives from another event. Attempts remain children of the same overall job instead of becoming independent completion claims.

## Provenance and evidence

Every admitted event names its source type and source identity and carries either a source event identity or one or more typed privacy-safe evidence references. Allowed evidence classes include runtime events, provider receipts, device events, tool receipts, test receipts, artifacts, verification receipts, policy decisions and user controls.

Provider-attempt success is attempt-scoped evidence only. It does not make the whole Pandora job a Result. A Result requires overall-job verification evidence or equivalent authoritative readback.

## Public states

The universal public states are:

`understanding`, `planning`, `acting`, `checking`, `needs_you`, `retrying`, `fallback`, `verifying`, `paused`, `resuming`, `result`, `failed`, `cancelled`.

`result`, `failed` and `cancelled` are terminal. No later Theatre event may be admitted after a terminal state for the same job epoch.

A successful provider call, model response, generated artifact or authorized action is not enough to emit `result` when further verification applies. `failed` requires real failure evidence. `cancelled` requires accepted cancellation or authoritative cancellation evidence.

## Interruption and control acceptance

Pandora may receive `pause`, `resume`, `cancel`, `redirect` and `constraint` controls while work is active. A requested control is not considered accepted until the runtime admits evidence of acceptance. Ambiguous acceptance requires readback before a consequential retry or duplicate side effect.

`paused` represents an actually paused job, not a generic waiting state. `resuming` requires a prior paused state. `cancelled` is terminal and must reflect accepted cancellation or an authoritative runtime cancellation event.

## Needs You

`needs_you` exists only for a genuine user boundary and must identify the exact blocker and exact required user action. Its reasons must remain compatible with the frozen M0-003 standing-authority policy.

Routine reads, ordinary model/tool work, waiting for CI/cloud work, bounded retry, provider/model fallback inside authority, verification and voluntary pause are not Needs You reasons.

## Retry and fallback truth

Retry requires evidence of the prior attempt. Fallback requires prior attempt or capability evidence explaining why another route is needed. Fallback may not expand authority, privacy exposure, cost ceiling or side-effect scope.

Consequential retry reuses the same idempotency identity. Ambiguous effects require provider/runtime readback before retry. Provider success remains attempt-scoped until overall-job verification succeeds.

## Durable replay and reconnect

The canonical Theatre stream is durable enough to replay from a known cursor or checkpoint. Replay detects gaps, preserves event identity and chronology, and never invents missing events. Reconnect does not transform missing history into synthetic progress.

## Privacy and redaction

Public Theatre projections must never expose raw prompts, raw tool arguments, credentials, secrets, tokens, OTPs, private keys, private provider payloads or other protected material. Public fields fail closed on credential-like material. Evidence references are privacy-safe pointers, not secret-bearing payloads.

Advanced Mode may show more evidence, IDs and timestamps, but the same redaction boundary still applies.

## Verification and completion

Authorization is not completion. Model claims are not completion. Provider success is not completion. Artifact creation alone is not completion when verification is required.

A Result requires a verified overall-job outcome or equivalent authoritative readback. Physical-device success requires physical evidence; CI/emulator evidence may not be relabeled as physical acceptance.

## Ownership and handoffs

The neutral contract owner is `@pandora/activity-theatre`. Project runtime may consume the contract but does not own universal Theatre truth. M1 owns realtime transport, control execution and reconnect/checkpoint implementation. M2 owns event schema enforcement, rendering/projection, provenance truth, Needs You semantics and Build Theatre compatibility.

M2-001 must implement this frozen contract before merge. M2-002 remains blocked on M1-004 realtime transport. M2-003 enforces provenance/truth-state invariants. M2-005 enforces Needs You as a real user boundary. M2-006 maps Build Theatre onto the same canonical substrate.
