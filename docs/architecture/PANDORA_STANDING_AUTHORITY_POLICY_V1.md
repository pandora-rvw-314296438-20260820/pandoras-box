# Pandora Standing Authority & Consequential Action Policy v1

Status: **Frozen**  
Effective date: **2026-09-13**  
Machine contract: `docs/architecture/pandora-standing-authority-policy-v1.json`

## Purpose

This document freezes the **M0-003** authority boundary. Pandora should continue working without repetitive approval prompts when it already has enough authority, while stopping at real user authorization boundaries for consequential actions.

The governing rule is:

**Autonomous by default inside established authority; approval-gated only when genuinely consequential and not already authorized.**

This is a policy contract, not the downstream enforcement implementation. M3 and M7 own the runtime/tool/protected-app enforcement described in the handoffs below.

## 1. Authority is explicit, not inferred

Authority may be granted by:

1. the user's explicit current instruction; or
2. an active explicit standing policy that matches the action.

Models, Memory patterns, predictions, recommendations, provider capabilities, and prior successful actions may help Pandora reason, but **they never create or expand permission**.

Safety, security, protected-app, organization, and provider constraints may narrow what Pandora can do. They do not grant new user authority.

A newer narrower explicit instruction overrides a broader standing policy. Revocation is effective immediately.

## 2. Four policy decisions

Pandora resolves each proposed action to one of four decisions:

- **auto_execute** — proceed without a new prompt because the action is non-consequential or is already authorized by the user's current instruction.
- **standing_authorized** — proceed without a new prompt because an active explicit standing policy matches every applicable scope dimension.
- **needs_approval** — stop at a real authorization boundary because a consequential action is not sufficiently authorized, or authority is ambiguous, stale, expired, revoked, or out of scope.
- **deny** — do not execute because the request crosses a non-overridable security/safety/protected-app boundary or attempts credential/OTP/security bypass.

A write is **not automatically consequential**. A read is **not automatically harmless** if it would disclose sensitive information outside its authorized boundary. Classification is about material effect and authority, not HTTP verb.

## 3. What is consequential

Signals that normally make an action consequential include:

- destructive or irreversible effect;
- production/public release;
- external communication or commitment;
- money movement, purchase, or financial commitment;
- account, permission, identity, or security change;
- protected-app sensitive action;
- privacy-sensitive disclosure;
- material cost commitment;
- legal or regulated commitment; or
- creation of a persistent external resource with material impact.

Consequential does **not** mean Pandora must always ask again. If the user's current instruction clearly authorizes the exact action, that is already authorization. If a sufficiently specific active standing policy covers it, Pandora should not repeatedly ask.

## 4. Routine work should continue

Routine reads, searches, inspections, analysis, model calls, model selection, tests, builds, dry-runs, verification, and other non-consequential work should continue without unnecessary approval interruptions.

Reversible local work and bounded repair work should also continue when they are already inside the user's current request or standing authority.

Provider/model fallback can happen automatically when it remains inside the same capability, privacy, cost, and side-effect authority. Fallback never expands authority.

## 5. Standing policy must be bounded

A standing policy is not a blanket "do anything" permission. It must bind the applicable action scope, including:

- principal;
- capability and operation;
- environment;
- provider/execution boundary;
- resource/account scope;
- data-sensitivity ceiling;
- cost ceiling;
- validity window; and, when applicable,
- destination/audience;
- protected-app scope;
- destructive permission;
- production permission;
- financial limit;
- legal/regulated scope.

Every applicable binding must match. Expired or revoked policies do not authorize. Ambiguous scope fails closed to **needs_approval**.

Consequential authorization must be bound to a normalized action fingerprint so a prior approval cannot be silently replayed for a materially different action.

## 6. Needs You is a real user boundary

Use **Needs You** only when a user action is genuinely required, such as:

- authorization is required;
- a consequential choice is missing;
- account connection or re-authentication is required;
- a protected app requires user presence;
- only the user can perform recovery/conflict resolution; or
- an external blocker can only be resolved by the user.

Do **not** use Needs You merely because Pandora is reading, searching, choosing a model, planning, testing, building, waiting for CI/cloud work, performing a bounded retry, or using an authorized fallback.

Needs You is not the same as a voluntary Pause/Resume control. Detailed pause/resume semantics remain owned by M0-004/M1.

## 7. Consequential retries and ambiguous writes

Authorization does not imply success. Pandora still needs post-action verification.

Consequential side effects require idempotency or an equivalent duplicate-side-effect guard. If the result of a write is ambiguous, Pandora must assume it may already have happened and **read back provider state before retrying**.

A retry must not gain broader authority simply because an earlier attempt failed.

## 8. Financial, protected-app, and security boundaries

Financial and security-critical actions require either explicit current authority or a sufficiently specific standing policy, and all protected-app/security controls still apply.

Pandora must never treat authority as permission to:

- scrape credentials;
- bypass OTP/authenticator protections;
- weaken protected-app security; or
- bypass device-integrity/security controls.

Credential or OTP bypass is denied even if requested. Downstream M7 work defines the protected zones and concrete enforcement.

## 9. Learning cannot silently become policy

Facts, patterns, provider-performance history, predictions, and recommendations may inform suggestions and routing.

They cannot create, broaden, or renew a standing policy. Pandora may propose automation or standing authority, but it becomes policy only through explicit authorization.

## 10. Downstream handoffs

- **M3-005** implements continuous routine tool-chain execution using this authority decision contract.
- **M7-001** defines and enforces protected-app zones.
- **M7-003** keeps secrets off-device and issues scoped authority without treating credentials as permission.
- **M7-004** implements financial action risk tiers and protected execution.

Current Pandora implementation details such as `read` / `write` / `destructive` execution-plan risk labels are implementation evidence, not the universal semantic policy. Downstream enforcement may map those labels to this contract but must not collapse **all writes** into "ask again" or silently let risk labels expand authority.

## Acceptance boundary

M0-003 is accepted when this explanatory policy, the machine-readable approval matrix, and executable policy-contract tests are reconciled against current `main`; focused and full repository checks pass; exact-head CI passes; an independent review finds no high/critical contract defect; the change is merged through the governed path; and `main` is independently read back.

No production policy-engine, protected-app, APK, provider, or deployment mutation is claimed by this freeze.
