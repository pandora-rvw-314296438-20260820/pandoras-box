# Pandora Core mobile shell execution envelope

## Scope and authority

This work remediates the generic Pandora Core mobile chat shell represented by
`6548.mp4`. The retained app-level conversation must become a deterministic
projection of conversation, turn, request, preference and presentation state.
Customer workspace redesign is outside this change.

The owner authorized implementation, testing, merge to main and live deployment
after the required checks pass in the execution-session instruction recorded at
2026-10-03 16:12 UTC. That authorization does not establish that any evidence gate
has passed. Production readiness requires the installed-artifact user journey.

The approved detailed plan remains
`Pandora_Core_Mobile_Shell_Remediation_Plan_2026-10-03.md`, especially sections
9–11 and the coverage table for all 49 requirements. Its recorded SHA-256 is
`4c931195284dbffb235a8ee0ca892bf826b05827ac1ca8344f7cbc4f2360208a`.
This envelope binds execution ownership and release evidence to that plan; it
does not replace the plan's acceptance criteria.

## Source and deployment baseline

| Resource | Bound baseline / treatment |
|---|---|
| Application repository | `pandora-rvw-314296438-20260820/pandoras-box` |
| Initial audited main | `593d8f5db34da6fc727c0449e807174cd3d9835a` |
| Reconciled integration base | `614d11bee20928075545c411dc5799537778127d`; includes merged #946 and #947 |
| Implementation branch | `chatgpt/core-mobile-shell-production-remediation` |
| Memory repository/main | `pandora-rvw-314296438-20260820/pandoras-box-memory` at `aeef12b3fa20e18cee7e2d735055c7caba3464c4` |
| Main Supabase | `jcyqixttuebxqqfkjonq` |
| Memory Supabase | `ivmvufhcsezyhczzondn` |
| Core Vercel project | `mcpmaster`, `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk` |
| Baseline Vercel deployment | `dpl_9CTGq1Qn8YWzppZ5DcR3UAkWE9oT`, baseline source `593d8f5db34da6fc727c0449e807174cd3d9835a` |
| Baseline chat Edge function | `pandora-intelligence-chat` v84; recorded bundle SHA-256 `983067ede1247b314c98725e7374985dee82a3609c46b6aa2ffa32b269d86e9c` |
| Pending audit candidate | [Memory PR #142](https://github.com/pandora-rvw-314296438-20260820/pandoras-box-memory/pull/142), pending review; no M5 approval or promotion implied |

[PR #946](https://github.com/pandora-rvw-314296438-20260820/pandoras-box/pull/946)
merged while remediation was in progress, from head
`a47a0f6a6a149f414b8f279054283172f6719536`. Integration preserves its resolved
dark theme, scoped owner navigation, explicit read-only inspection affordances,
and existing capabilities while replacing overlapping chat/presentation flags
with the authoritative lifecycle. Its two already applied migrations now appear
in the canonical main source ledger. The PLP changes in that main commit remain
baseline changes, not evidence for this Core mobile journey.

The latest observed production-target Vercel deployment during integration was
`dpl_E8Va4KNvkUyKUoUEgQzCAbt7BBne`, READY at source
`5e7e5f72aac9744614dd549f2cde8a0f3917fdfe`. That deployment was made by the other
lane and is not a remediation deployment. The initial baseline above remains a
historical reference. Re-read source, migration ledger, deployment and aliases
immediately before promotion.

Use direct GitHub, Supabase and Vercel authority. Vault-backed credentials remain
server-side. Retired ProjectOS and the blacklisted repository are excluded from
execution and verification authority. Refresh mutable provider state immediately
before each release action.

## Fresh scoped Memory context

Read-only `memory_task_context_v1` succeeded at
`2026-10-03T16:21:09.321628Z` with the following binding:

| Field | Value |
|---|---|
| User / namespace | Server-bound project principal / `real_life` |
| Project / principal | `7c686cbd-d968-49d5-86cc-918f5e777bd2` / `pandora-mcpmaster-production` |
| Environment / intent | `production` / `coding_building` |
| Task action mode | `state_change`, consequential; describes the planned work, not a write performed by retrieval |
| Result | `available`, `degraded=false`, 0 policy items and 2 advisory items; 4,370 bytes |
| Context SHA-256 | `41dc3acffea31b11fca52204ff3abcc336f2bce806038a436186c4500f42abf0` |

The retrieved lessons were artifact-quota recovery
(`7f8aa968-cc5b-4212-a100-424709bbd937`) and native evidence routing before
reauthentication (`901d5e0f-aaaa-4936-a958-1d2095ec5d71`). Their applicable lessons
are to keep artifact publication as a separate provider gate and verify the
actual native routing path before altering authentication. This retrieval
contained no current shell-acceptance record and granted no execution authority.
Keep the current owner requirement and the pending audit candidate distinct from
approved M5 knowledge. Save only significant verified outcomes after execution.

## File ownership

Paths below are repository-relative. One integrator owns the shared screen/API
seams. Agents must coordinate changes outside their assigned paths.

| Owner | Assigned paths / responsibility |
|---|---|
| Root integrator | Flutter intelligence API/wire transport, integration tests, dependency manifests/locks, final source reconciliation and provider release actions |
| `mobile_source_audit` | `apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart`, `apps/pandora-mobile/lib/core/chat/**`, `lib/core/local/pandora_local_state_cache.dart`, `test/core/chat/**`, new `test/core/local/pandora_local_state_cache_test.dart` within the mobile app |
| `mobile_presentation` | `lib/app/pandora_chat_shell.dart`, model picker, composer, viewport, presentation controller and associated navigation/widget coverage |
| `backend_audit` | `supabase/functions/pandora-intelligence-chat/**`, new forward Supabase migrations/RPCs, chat-lifecycle Node/SQL tests and fixtures |
| `backend_audit/provider_streaming` | `src/providers/aws-bedrock-runtime.js`, `src/providers/aws-bedrock-chat-http.js`, distinct provider-stream tests |
| `release_audit` | `.github/workflows/pandora-core-mobile-journey.yml`, `apps/pandora-mobile/tool/core_*` runtime/provenance helpers and focused tests; exact-artifact runtime evidence |
| `guard_regressions` | Native calendar/communication effect-boundary cancellation, device Activity cancellation projection, corresponding meaningful regressions and forward migration |
| `memory_capture_path` | This execution envelope, scoped Memory readback, review-path discovery and coordinated significant-outcome candidate preparation |

## Phase exit gates

### Current implementation boundary

The candidate adds protocol v2 with atomic admission, logical turn and attempt
identity, same-attempt transport replay, generation-fenced retry, cancellation,
negative admission receipts, safe history reconstruction and native provider
streaming. A local delivery epoch rejects obsolete callbacks even when an
unacknowledged request is resent with its original server identifiers. Native
actions check cancellation immediately before the OS mutation boundary; known
effects retain their verified outcome after a later Stop.

The mobile screen projects immutable conversation state. The persistent composer
and presentation coordinator own mutually exclusive picker, drawer and context
routes; the viewport retains deliberate reading anchors. Activity details and
advanced model controls remain available without becoming ordinary transcript
events. Auto preference is independent of the executed provider/model receipt.

These are implementation descriptions. Passing source/unit/widget checks do not
establish installed-artifact acceptance. Exact stage and test receipts belong in
the final verification manifest.

### Native acceptance prerequisites

Read-only provider inventory found no established Core staging stack, protected
Core QA environment, or sanctioned automated Core login. The existing APK defaults
to canonical production Supabase. Consequently, authenticated premerge acceptance
requires a reviewed backward-compatible backend candidate and a real protected
login handoff. No identity, password, membership, owner role or authentication
policy was changed to bypass that prerequisite.

The new PR platform lane receives no login secret. It downloads the successful
canonical mobile build, verifies the actual compiled SHA/tree and archive/APK
digests, installs those exact bytes on accelerated Android, and exercises small
and tall viewports. Authenticated acceptance additionally binds a reviewed source
SHA and checks actual environment reviewer protection. Public artifacts contain
content-free receipts; authenticated screenshots and raw transcripts are excluded.

Local software emulation reached ADB availability but did not establish completed
boot, installation or runtime acceptance. Flutter analytics are explicitly disabled
for local checks. Full local Deno checking remains dependent on registry access;
that environmental failure cannot be reported as a passing type check.

Each phase below requires its own evidence. This document does not mark a phase
complete merely because work was assigned or source exists.

| Phase | Required exit evidence |
|---|---|
| P0 — Reconcile and reproduce | Exact baseline and active ownership; overlap/ledger reconciliation; reproducible failure fixtures; Android ABI, installation and real IME capability established or the remaining device gate stated explicitly |
| P1 — Turn contract and continuity | Atomic admission and digest conflict tests; one user row/completion per logical turn; same-turn retry; role-aware history, restart/cache identity and cross-scope rejection |
| P2 — Unified shell | Legal/illegal transition and race tests; immutable snapshots; stale callback fencing; stable composer; contained model controls; coordinated viewport/IME/drawer/Back and deliberate history anchoring |
| P3 — Response and performance | Legacy/new contract compatibility; negotiated real streaming; provider context/schema conformance; natural capability responses; propagated timing/receipt fields; verified Memory correction and evidence-backed work reduction |
| P4 — Runtime qualification | Exact candidate APK installed; uninterrupted 39-step journey plus failure/race/accessibility/device cases; video/assertions/persisted outcomes; measured frame, request and resource performance with device/network identity |
| P5 — Release verification | Reviewed final main SHA; required checks and APK build at that SHA; compatible backend readback; final installed/distributed-byte identity; authenticated canary, upgrade/resume, monitoring and recovery evidence |

The evidence ladder is **Documented → Implemented → Tested → Built → Installed →
Runtime Verified → Production Verified**. The final manifest must bind source
SHA/tree, CI run/job/checks, dependencies/toolchains, APK and archive digests,
package/version/ABI/signing fingerprint, installed identity, backend versions,
device/OS/IME, journey evidence and measured outcomes. Preserve PR-head versus
synthetic-merge identities explicitly; final acceptance is repeated on resulting
main and the actual delivery bytes. A rebuilt test application is supplemental
evidence, not proof for an uninstalled delivery APK.

## Review and deployment order

Independent review remains an explicit gate; the builder cannot self-certify it.
CodeRabbit is an existing external review integration. At the current #946
snapshot it reported a skipped review requiring a manual trigger, and GitHub
returned no submitted reviews. A success status for that skip is not acceptance.
Request review only after the remediation candidate is frozen, using the existing
supported integration within its existing entitlement; bind the actual verdict
to the exact head and resolve findings. Do not infer provider authentication from
CLI installation, introduce new paid review resources, or use retired reviewer
authority.

1. Freeze the candidate and run the phase-specific source, state, widget, SQL,
   compatibility and release checks. Preserve failed evidence and correct causes.
2. Verify backward-compatible Vercel dependencies in the existing core project;
   validate additive migrations against old and new clients.
3. Apply only reviewed additive schema changes and read back the exact live
   migration/RPC/constraint/RLS state. Explicitly deploy compatible Vercel
   dependencies before any Edge bundle that requires them. Merge alone is not a
   deployment.
4. Use the bounded authenticated candidate cohort for protocol/provider recovery
   checks. Do not disable providers globally to manufacture a failure or sweep
   the provider catalog as an incidental test.
5. Merge under required checks and independent review, then rebuild and rerun
   mandatory acceptance at the actual resulting main SHA. Install the final
   artifact without deleting conversations or changing signing identity to
   force an upgrade.
6. Promote/distribute only the qualified source and artifact. Record exact
   Supabase versions, Vercel deployment/aliases, installation and production
   journey readbacks. Keep unmet evidence gates visible.

## Recovery baseline and stop conditions

Retain Vercel deployment `dpl_9CTGq1Qn8YWzppZ5DcR3UAkWE9oT` and the source for
chat Edge v84 as baseline recovery candidates; re-read their availability and
compatibility before deployment. Their presence is not a rehearsed rollback.
Keep additive conversation/audit data and preserve old-client compatibility.
Disable the new protocol for the affected cohort if necessary, then restore
compatible dependencies in the rehearsed order. Android recovery must preserve
the signer, user data and version constraints, normally by a compatible forward
build. Reverting Vercel does not update an installed APK.

Stop promotion for wrong-thread content, duplicate/ghost turns, accepted stale
callbacks, unresolved-error/success contradictions, lost drafts/history,
IME/overlay/Back regressions, scope or execution-authority regressions, missing
artifact identity, or any failed mandatory continuous journey. Preserve evidence,
repair, and rerun the affected gates before advancing.
