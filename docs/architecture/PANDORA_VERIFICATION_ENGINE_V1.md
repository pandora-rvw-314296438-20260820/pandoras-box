# Pandora Verification Engine V1

Status: implemented, durably integrated, and independently live-verified on `packages/pandora-verification/`. Worker E live closure is PASS with immutable fail/repair history, exact preview/production artifact evidence, database rollback evidence, and a real Vercel production rollback/restore exercise.

## Independence principle

Pandora verification is authoritative only when an independent verifier evaluates an exact immutable identity. Builder output, model claims, client writes, deployment-provider status, or project tests alone cannot create authoritative `PASS`.

The implemented engine requires an opaque executor capability reference for authoritative lifecycle writes. Knowing the verifier name is not sufficient. Verification run state is private to the engine and returned as snapshots.

## Exact verification identity

`VerificationRequest` fails closed unless it binds:

- organization
- project
- ProjectSpec identity and optional version
- project version
- exact 40-hex source commit
- source digest
- artifact digest
- optional migration-set digest
- optional preview deployment identity
- target environment
- optional runtime-target digest
- verification profile
- requester

The identity is canonicalized and SHA-256 hashed. A changed spec, project version, source, artifact, migration set, deployment, environment, runtime target, or profile produces a different verification identity. A previously passing run therefore cannot authorize a changed artifact.

## Run states

The canonical engine supports:

`PENDING → RUNNING → PASS | FAIL | BLOCKED | INCONCLUSIVE`

and `STALE` after invalidation.

Retries create new verification runs and preserve historical failures.

`BLOCKED` is distinct from a product failure. It is used when the verifier cannot complete a required check because verification infrastructure or a provider is unavailable. Missing required evidence results in `INCONCLUSIVE`, never `PASS`.

## Check registry

The registry currently defines provider-independent checks across:

- SOURCE: format, lint, static analysis, typecheck
- TESTS: unit, integration, browser/E2E
- BUILD: reproducibility and artifact identity
- SECURITY: dependencies, secret scan, unsafe configuration, auth, permissions, headers
- ACCESSIBILITY: semantics, keyboard, contrast, scaling, touch targets
- DATABASE: migration preflight, postflight, policy state
- VISUAL: baseline and responsive integrity
- RUNTIME: health, routes, auth flow
- ACCEPTANCE: ProjectSpec requirements and business metric readiness
- PRODUCTION: exact version, domain, runtime

## Profiles

Profiles are fixed policy inputs rather than model-selected downgrades:

- `static_site`
- `web_application`
- `mobile_application`
- `backend_service`
- `business_system`
- `automation`
- `database_change`
- `production_release`

Every required profile check must have authoritative evidence before a run can become publish eligible.

## Evidence and lineage

Evidence objects carry a SHA-256 digest so later modification is detectable. Check results record identity digest, evidence references, tool metadata, duration, failure class, optional security severity, requirement ID, acceptance criterion ID, and freshness/cache metadata.

Large evidence binaries are intentionally not stored in ordinary engine state. Worker A remains the owner of durable artifact/evidence persistence.

## Requirement traceability

Acceptance results can bind to `requirement_id` and `acceptance_criterion_id`. Release reports expose coverage as `PASS`, `FAIL`, `BLOCKED`, `INCONCLUSIVE`, or `NOT TESTABLE` per ProjectSpec requirement rather than hiding product coverage behind an aggregate test count.

## Security verification

The foundation implements deterministic redacted secret detection with fingerprints rather than secret plaintext, migration-risk inspection, security-severity policy signals, and exact artifact comparison. Secret fixtures use fake Pandora canaries; real credentials are not embedded in tests or evidence.

Worker E reports findings and severity. Worker C remains the publish authorization and risk-policy owner.

## Migration verification

The implemented preflight detects destructive drops, truncation, incompatible type changes, RLS disablement, policy removal, uniqueness changes, and missing recovery context for high-risk changes. Worker A/F remain responsible for durable schema state and migration execution. Post-migration provider adapters must compare actual schema/policy state against the intended migration identity before production eligibility.

## Visual and runtime verification

Visual differences are classified as `EXPECTED CHANGE`, `UNEXPECTED CHANGE`, `BROKEN LAYOUT`, or `REVIEW REQUIRED`; a pixel difference does not automatically fail a project.

Runtime probes distinguish application failures from verification-infrastructure blockage. A deployment-provider `READY` response is not treated as application health.

## Freshness and invalidation

Check cache keys are bound to the exact verification identity and freshness scope. Deployment/environment changes therefore cannot reuse prior runtime/browser evidence. Verification can be invalidated to `STALE`; release readiness then becomes false while historical evidence remains available.

Production drift classification supports:

- `verified_current`
- `drift_detected`
- `verification_expired`
- `unknown`

## Release readiness

`get_release_readiness()` returns a machine-safe summary with:

- verification run identity
- ProjectSpec/project version identity
- exact source and artifact identity
- required checks
- failed, blocked, and missing checks
- requirement coverage
- evidence references
- `publish_eligible`

This is factual verification input. Worker C remains the authorization decision-maker.

## Service boundary

`createVerificationService()` exposes:

- `request_verification()`
- `get_verification()`
- `get_verification_summary()`
- `get_requirement_coverage()`
- `get_release_readiness()`
- `get_repair_feedback()`
- trusted lifecycle operations for start/check/finalize/invalidate
- retry and exact-identity invalidation

Provider, browser, build-sandbox, database, and deployment execution stay behind adapters and are not embedded into these contracts.

## Worker interfaces

- Worker A: owns durable verification runs/checks/evidence, artifacts, project versions, lineage and audit. This package does not create competing persistence.
- Worker B: may supply acceptance intent and repair reasoning but cannot author PASS.
- Worker C: consumes release-readiness facts and decides whether publish is authorized.
- Worker D: may execute project tests/builds; those receipts are evidence, not independent PASS by themselves.
- Worker F: supplies preview/production/domain provider truth; Worker E verifies it against exact identity.
- Worker G: may project only customer-safe states such as checking, fix needed, blocked, verified, ready to publish and live/verified.
- Worker H: receives verification cost inputs and owns business economics/outcome analysis.
- Worker I: trusted primitive identities may inform verification, but never blindly bypass required checks.
- Worker J: consumes deterministic verifier APIs for integrated E2E proof.

## Current integration boundary

Worker A-owned verification runs, checks, evidence, project versions, artifacts, and lineage are now live in the canonical Pandora control plane. Worker E writes authoritative verification facts through those canonical contracts and does not create competing persistence.

Production/provider execution remains outside Worker E. Live Worker D/F receipts and provider truth are normalized by Worker E and written as independent evidence through Worker A; provider READY alone never creates PASS.

## Regression guarantees

Repository tests prove at minimum:

- profiles cannot reference unknown checks
- incomplete identity fails closed
- a builder/model/client cannot forge PASS using a verifier name or lookalike authority object
- every required check is needed for authoritative PASS
- missing checks become INCONCLUSIVE
- product failure and verifier-infrastructure blockage differ
- artifact changes stale earlier eligibility
- repair creates a new run and preserves the failed run
- a fake secret canary is detected without leaking plaintext
- destructive migrations fail preflight without recovery context
- exact artifact equality is enforced across build/verification/preview/production inputs
- evidence digests are deterministic and tamper evident
- cached runtime evidence is not reused for a changed deployment identity
- acceptance coverage traces to ProjectSpec requirement IDs
- visual differences are classified
- production drift is explicit
- Simple Mode projections do not expose framework detail

This document now describes both implemented source truth and the independently observed live evidence recorded in Worker A. Historical BLOCKED and FAIL runs remain immutable and are not rewritten by later PASS evidence.


## Freshness, repair, rollback and worker adapters

Environment-bound verification evidence expires automatically. Exact-source, exact-artifact and exact-migration-set checks remain reusable only while their immutable identity stays unchanged. Deployment/schema evidence is time bounded, production evidence has the shortest window, and expired required evidence immediately makes `publish_eligible=false` without rewriting the historical PASS run.

Worker D is used only as a bounded sandbox execution substrate. Project/builder receipts are evidence only unless Worker E requested and independently observed the execution; Worker E still owns the authoritative result. The adapter sends exact project/source identity, deny-by-default network policy and no credential leases. Worker F provider facts are normalized into exact preview, production and domain evidence before runtime verification.

Release reports expose machine and owner-safe summaries, explicit failed/blocked/missing/expired checks, exact version/source/artifact identity and evidence references. Repair always creates a new run. Rollback targets are independently re-verified after rollback, and production state distinguishes `verified_current`, `drift_detected`, `verification_expired` and `unknown`.


## Live proof status — 2026-08-29

Worker E live closure is PASS.

Worker A durable verification persistence is live and preserves the intentional acceptance FAIL, the historical provider-quota BLOCKED run, authoritative repaired preview PASS, authoritative exact repaired production PASS, database-change PASS with full rollback, and final release-closure PASS. Builder and verifier identities remain distinct.

Worker D Vercel Sandbox proof used Node 24, nonpersistent storage, deny-all network policy and no credential environment. The intentional fixture failed as expected; the repaired exact artifact passed bounded acceptance/accessibility checks.

Worker F provider truth was consumed through the server-side Vault-backed Vercel broker. The repaired preview `dpl_1nNyH9kyif88xeghvaH4JJKJeSSP` is READY and independently PASS. The disposable exact production `dpl_AYi7Q9KGMYJ8kRRa8qqPvcW569Ju` is READY/PROMOTED, exact-source bound, and its public production domain returned HTTP 200 with body SHA-256 exactly equal to repaired artifact `34327d36984024bbae4f0d36829d91c9b1694d493f9e39506d5eae901fe7fc60`.

The Hobby team remained at the rolling deployment limit, so Worker E did not fabricate a second disposable Production deployment or bypass provider semantics. Instead, it independently proved the real Vercel rollback/restore mechanism using existing READY production history on canonical `mcpmaster` under the same Vault-backed team. Preflight independently probed the current deployment `dpl_DrCeQxFTY4ge9YfCNBhJ2x1wbwyq` and previous deployment `dpl_Aqv5fWGMVk4fj9KixPd3d56RyX2P`; both returned HTTP 200 and the same runtime body SHA-256 `7cd854e39d9cd7854921710eec09742a32e6834adecadc21b06ce88165a9d86a`. Vercel accepted rollback to the previous production with HTTP 201, provider readback and public HTTPS verification passed, then accepted restore to the original current production with HTTP 201 and the restored provider/runtime state was independently reverified.

Worker A final release-closure run is `e65a0e44-a9c6-44fe-8849-5c173ede24cb`. The repaired project version `9b49c111-2b60-48e4-8883-1146116904f0` is `verified` and bound to matching runtime target digest `f535b7c960e5c2e4c7af6d5669f4c5bc65bd7256adcedb88fd71324be558d8e3`.

The safe machine-readable receipt is `docs/verification/WORKER_E_LIVE_PROOF_20260829.json`. It explicitly distinguishes exact-artifact proof on the disposable project from the cross-project same-provider rollback/restore mechanism proof; it does not pretend Vercel created a deployment that the provider rejected. Repository merge remains independently gated by exact-head CI and provider statuses. PR #26 remains untouched.
