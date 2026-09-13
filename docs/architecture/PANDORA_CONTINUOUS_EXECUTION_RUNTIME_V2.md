
# Pandora Continuous Execution Runtime v2 — M1-003

Status: M1 implementation candidate. This contract owns orchestration only. It does not replace M2 Activity Theatre truth, M3 model/tool routing and authority, M5 Memory, or Device/Security enforcement.

## Purpose

M1-003 makes Universal Chat continue a bounded `reason → act → observe → reason → verify` loop without requiring a new user prompt between routine intermediate steps. The loop stops only at a verified result, genuine user/policy boundary, cancellation, unrecoverable blocker, no-progress guard, or bounded iteration limit.

The runtime remains domain-neutral. Communications, research, files, business, travel, scheduling, device work, software work and future capabilities use the same orchestration contract. A selected Project does not turn unrelated work into a build.

## M1 → M3 execution seam

M1 never grants authority and never performs a consequential state change through a standalone `authorize → act` path.

- `read_only` actions may use the bounded read adapters `actRead` + `observeRead`.
- every `state_change` action must use the injected `executeGoverned` adapter backed by the current M3 governed ToolGateway/authority execution path;
- M1 consumes the governed outcome (`completed`, `needs_approval`, `denied`, `verification_required`, `failed`, `cancelled`) but does not manufacture authority receipts;
- `needs_approval` becomes a real `needs_you` terminal boundary; `denied` is blocked and never converted into an approval prompt;
- ambiguous mutation state (`verification_required`) stops immediately for authoritative readback/reconciliation and is never blindly retried;
- completed mutations require both a provider/runtime receipt and an authoritative readback reference before the loop may continue;
- a small in-process action/idempotency map is defense in depth only. M3/ToolGateway durable action identity, provider idempotency, leases, policy, secret/network boundaries and readback remain authoritative.

Legacy M1 adapters named `authorize`, `act`, or `observe` are rejected by v2 so a caller cannot accidentally restore the parallel authority path.

## M1 → M2 truth seam

M1 reasoning cannot declare completion.

A terminal `result` requires all of:

1. the verifier returns `verified=true`;
2. an exact `verificationReceiptRef` exists;
3. the injected `projectResult` adapter projects the result through the canonical M2 Activity Theatre contract;
4. that projection is `state=result`, belongs to the same `jobId`, and carries the exact receipt as `{type: verification_receipt, relation: verification}`.

If any condition is missing, M1 blocks rather than fabricating Result/Ready/Live. M1 consumes the M2 contract; it does not redefine Activity Theatre event semantics.

## Loop safety

- frozen M1-002 resolution is deeply immutable for the whole job;
- reasoning cannot widen `no_action` or `read_only` into `state_change`;
- accepted cancellation is checked before reasoning, before action, after observation and before verification;
- repeated no-progress cycles fail closed;
- total iterations are bounded;
- credential-like material is rejected from public evidence refs/summaries;
- stable action, receipt, readback and verification identities remain available for M1-004 realtime replay and M5 learning handoff.

## Current dependency gate

M1-003 must not merge against an M3 governed execution implementation that still permits trusted authority/security context to be widened by per-step context or a post-check mutable-context TOCTOU. The dedicated M3 repair lane owns those fixes. M1 may prepare and test its one-way governed seam while that repair is in progress, but merge acceptance requires final-source verification of the repaired M3 authority boundary on the exact main consumed by M1.

## Acceptance evidence

Source acceptance requires focused runtime tests plus an integration test using the real M2 `deriveActivityProjection`. Exact-head repository CI and independent final-source review are mandatory before merge. CI/source acceptance does not claim physical Android acceptance.
