# Operations Room Runtime V1 — Implementation and release handoff

Task: `OPS-UPGRADE-V1-001`
Owner decision: Memory PR #104, `OPERATIONS_ROOM_MAXIMUM_THROUGHPUT_ARCHITECTURE_V1.md` at `d074e9e089c22740f4dcb0218f0ce2dcc7fbb04c`.
Implementation base: `6f20780765001d1a90ee31800a3948d043551afa`.
Implementation owner: ChatGPT / OPS-UPGRADE-20260925.
Coordination authority: canonical Box issue #714; this work does not replace its incumbent global coordinator.

## Status and claim boundary

This is a tested **source candidate for the execution foundation**, not a declaration that all 42 upgrades are live. No production migration, Edge activation, production promotion, new ChatGPT worker, independent approval, or physical-device acceptance is created by these files.

ChatGPT authored the implementation and tests on an isolated authorized RDP checkout. Antigravity was invoked for bounded read-only review but failed authentication with zero completed turns; it supplied **no review evidence**. The emulator host was reachable, but ADB reported the guest offline; no APK install, guest reset or Android acceptance was performed.

## Components

| Component | Implemented source behavior | Activation boundary |
| --- | --- | --- |
| Task contracts | Strict task schemas, exact canonical source identity, dependency DAG, resource paths, budgets and canonical verification profiles. | Inputs remain untrusted task intent, not authority or execution proof. |
| Scheduler | Priorities, aging, dependency-unlock ordering, acknowledged ChatGPT worker availability, compatible lanes/capabilities, current and cross-project resource conflicts, budgets and bounded capacity. | Produces proposals; database claims recheck constraints. It is a deterministic heuristic, not a mathematical claim of globally optimal scheduling. |
| Adaptive concurrency | Evidence-based bounded increase and backpressure reduction. | Requires trustworthy measurements and a caller applying a separately authorized concurrency policy. No unlimited workers are spawned. |
| Durable state | Private RLS-enabled workspaces, tasks, dependencies, workers, leases, outbox and append-only coordination events. | No rows or workers are seeded. Workspaces initialize paused with production disabled. |
| Claim/dispatch | Serialized resource claims, budget reservation, generation fencing, idempotent claim replay, persisted dispatch intent and one admitted sender. | Missing or ambiguous worker acknowledgement retains resources for reconciliation. |
| Handoff/release | A builder hands off its exact source/tests/PR; cost is settled and implementation resources released. | Handoff is not completion. A distinct registered release principal must consume an existing exact-source canonical verification PASS and task-bound acceptance receipt. |
| Recovery | Failed/unknown dispatch is retained; bounded retry only after known outcome and old-worker fencing. Cancellation does not pretend an in-flight operation stopped. | Reconciliation requires a trusted provider/worker adapter. Expiry alone cannot free an unknown in-flight mutation. |
| Spreadsheet adapter | Decoded row ingestion, input-only fingerprints, dependency validation and machine-column-only literal RAW writeback plans. | Google Sheets/XLSX I/O is not implemented by this adapter. A connector must re-read cells, preserve native structure and write literal values. Spreadsheet writes are not claimed to provide transactional CAS. |
| Provider action bridge | Explicit GitHub/Supabase/Vercel/ARES operation catalogue, exact task/source/target binding, secret rejection, governed execution and authoritative readback ports. | These are integration interfaces, not a new unrestricted provider gateway or proof that all live adapters are connected. Existing M3 authority must authorize and execute actual actions. |
| ARES | Bounded ADB argv for health, boot/ABI checks, install, launch, force-stop, package/crash evidence, tap/swipe/type/back, screenshot and clear-data classification. | Host execution, APK bytes/realpath checks, host/emulator lifecycle and machine enrollment require trusted adapters and a live exclusive resource lease. No shell strings, credentials or protected-app access are admitted. |
| Owner Edge API | Authenticated owner/admin project scope, bounded JSON, exact CORS, overview/ingest/pause/resume/no-production/cancel. Membership is rechecked transactionally by SQL. | No owner-browser worker registration, lease issuance, approval creation, verification submission, raw SQL or deployment action is exposed. |
| Operations projection | Real durable task states and fresh acknowledged worker availability. | This is a projection for UI integration, not a replacement live screen. It generates no synthetic Build Theatre events. |
| Learning | Review-gated high-signal outcome/failure candidates with deterministic identity. | A candidate is not canonical Memory. Existing review/persistence and privacy boundaries remain mandatory. |

## Integration contract

The existing trusted service constructs `SupabaseOperationsStore` with a server-side Supabase client and `OperationsRuntime` with a real authenticated `workerDispatch` transport. A worker must have a real acknowledgement/registration receipt, principal, capabilities and current heartbeat before it can receive work. SQL rechecks the current non-archived project before claiming, preparing dispatch or accepting an ACK. The trusted transport must also recheck current project scope, workspace controls, cancellation and lease generation at the actual send boundary; a database check cannot make a later network send atomic. If delivery outcome is uncertain, retain the lease and reconcile it before retrying.

A dispatch proposal contains task identity, worker identity, expected task/control revisions and budget reservation. SQL atomically decides whether it may be claimed. `beginDispatch` returns `canSend=true` once; duplicate coordinators must not deliver again. The worker acknowledgement is bound to dispatch ID, worker, task and generation. Unknown network outcomes enter reconciliation without automatic replay.

The engine label `chatgpt` is a trusted enrollment constraint, not evidence that an arbitrary model or an unacknowledged chat session was started. Provider adapters must establish real identity and execution capacity. This change does not transfer this ChatGPT conversation's connectors or credentials into the application.

`GovernedProviderActions` uses an injected `executeGoverned` action-and-authorization boundary. It must be implemented with the existing M3/Tool Gateway; a standalone allow/deny boolean followed by arbitrary SQL/shell is not an acceptable adapter. A registered action name alone is not an executable capability.

## Source and tenant authority

GitHub remains canonical for source. The RDP workspace is an isolated exact-source working copy, not a second repository authority. The current `pandora_projects` object is a security-invoker identity view, not a table. The new orchestration state therefore does not declare an invalid foreign key to that view: initialization, claim and authenticated owner admission revalidate scope through the current view. Child state is tied to the private workspace with composite organization/project foreign keys. Historical task/evidence identity survives without promoting legacy implementation names into a retired execution authority.

Resource keys must be normalized consistently across projects sharing infrastructure. Claims take an organization-level transaction advisory lock and retain conflicting resources even after timeout. This is intentionally conservative. Cross-organization machine allocation belongs to the trusted infrastructure broker; an untrusted task cannot allocate a globally shared host simply by guessing its identifier.

## Verification performed

Focused tests execute the scheduler, contracts, safe ADB argument construction, owner API denial cases and actual new SQL in disposable PGlite. The SQL fixture mirrors the active identity-view shape and uses real PostgreSQL SHA-256 through a test-only pgcrypto compatibility function.

The focused suite includes:

- independent jobs and synthetic 500-task planning; no claim of 128 real workers;
- stale/offline/unacknowledged worker rejection;
- hierarchical and cross-project resource conflicts;
- atomic reservations and idempotent replay;
- unique dispatch sender and bound acknowledgements;
- cancellation and ambiguous-outcome lease retention;
- builder handoff versus independent canonical verification;
- bounded retry only after outcome readback and fencing;
- owner/tenant and anonymous/authenticated-role denials;
- immutable coordination events;
- literal spreadsheet writes and owner-input change detection;
- no model SQL/shell, credential material, or physical-acceptance fabrication.

PGlite is one connection. These tests prove logical SQL state-machine behavior, **not** simultaneous network-client races, production load or live provider execution. A new dedicated GitHub workflow includes seven independent-connection PostgreSQL race tests for competing claims, hierarchical/cross-project resources, budgets, replay and one-sender dispatch. That suite is not claimed passed until the provider-hosted job actually executes. Real worker outage drills remain rollout gates.

Standard source verification commands:

```text
node --test test/pandora-operations-room-runtime*.test.js
npm test
npm run check
npx --yes deno-bin@2.2.7 check --node-modules-dir=none --frozen supabase/functions/pandora-operations-runtime/index.ts
```

Exact final counts, source hashes and provider readback belong in the PR handoff and evidence record. Earlier failed test runs are superseded by later exact-source results, not erased.

## Corrections learned during implementation

1. Windows OpenSSH rejected use of the Administrator-owned SSH key from the SYSTEM SSM context. Its owner-only ACL was preserved; no private key was read, copied or weakened. Publication must use the preauthorized Vault-backed GitHub path unless an appropriate authenticated owner context is available.
2. A PowerShell native-stderr warning is not a failed npm install. Native commands use explicit exit-code checks and bounded redirected logs.
3. PostgreSQL regex repetition limits, PL/pgSQL alias shadowing and JSON operator precedence required executable tests, not static source assertions.
4. The initial isolated fixture treated the canonical project view as a table. Full source replay exposed the mismatch; both migration and fixture were corrected.
5. The one-sender dispatch fence and independent verifier principal must be checked in durable state, not inferred from role names.
6. Spreadsheet fingerprints must exclude machine-owned status values while retaining owner input and row/header identity.

## Rollout and remaining plan coverage

The 42-item owner plan remains the target. This change supplies substantial source foundations for scheduling/contracts, durable state, claims/recovery, handoffs, capability ports, owner controls, ARES argv and learning/projection boundaries. It does not mark those complete as deployed features.

Required next integrations, separately claimed through Operations Room:

- actual authenticated ChatGPT worker transport, enrollment and event-driven scheduler wake-up;
- complete Google Sheets/XLSX ingestion and safe two-way connector synchronization;
- approved M3 bindings for each live GitHub, Supabase and Vercel operation, including provider-native idempotency, release and rollback proof;
- ARES host adapter, exact APK verification, emulator lifecycle and connected guest acceptance;
- mobile/web Operations Theatre and ARES roster integration after incumbent area handoff;
- event inbox/webhook authentication, recovery sweeper and measured adaptive-concurrency application;
- richer owner reprioritization/lane allocation controls without widening production or spend authority;
- approved Memory retrieval and candidate-persistence bridge, not direct self-promotion;
- independent exact-head review, applicable CI, source/provider migration parity and staged deployment;
- multi-connection database race/load tests, cancellation/reconnect drills and physical-device-only gates where applicable.

Source areas owned by other workers were not edited, including the existing Operations Room/mobile surface, #709 auth/navigation, Memory #93, #721 owner runtime and #723 cancellation truth work.

## Safe activation and rollback

The migration creates no scheduler cron, worker, active workspace, provider approval or production permission. First deployment must remain paused/no-production, use an authenticated canary worker, and prove two independent jobs, conflicting-resource serialization, cancelled/expired jobs and known-outcome recovery before increasing capacity.

If the canary fails, pause scheduling and disable the new Edge route. Preserve task/event/lease history and reconcile already-started actions; do not drop audit tables, erase receipts or release an ambiguous provider mutation just to clear a dashboard. Production promotion and database rollback remain governed by the existing release owner.
