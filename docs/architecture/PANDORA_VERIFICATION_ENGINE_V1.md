# Pandora Verification Engine V1

Status: implemented foundation on `packages/pandora-verification/`.

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

At the time this foundation was implemented, live `main` and the live Pandora Supabase project did not yet contain Worker A-owned `verification_runs`, `verification_checks`, or `verification_evidence` durable contracts. This module therefore deliberately implements the independent domain/service boundary without inventing competing persistence. A later adapter must bind these APIs to Worker A's canonical tables after those contracts are present on current main.

Likewise, production/provider execution remains outside Worker E. Live preview, browser, domain and production verification adapters must consume exact Worker D/F receipts/provider truth and then write evidence through Worker A.

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

This document describes implemented source truth only; it does not claim Worker A persistence, Worker D execution, Worker F provider adapters, Playwright infrastructure, or production proof until those components exist and have independent live evidence.


## Freshness, repair, rollback and worker adapters

Environment-bound verification evidence expires automatically. Exact-source, exact-artifact and exact-migration-set checks remain reusable only while their immutable identity stays unchanged. Deployment/schema evidence is time bounded, production evidence has the shortest window, and expired required evidence immediately makes `publish_eligible=false` without rewriting the historical PASS run.

Worker D is used only as a bounded sandbox execution substrate. Project/builder receipts are evidence only unless Worker E requested and independently observed the execution; Worker E still owns the authoritative result. The adapter sends exact project/source identity, deny-by-default network policy and no credential leases. Worker F provider facts are normalized into exact preview, production and domain evidence before runtime verification.

Release reports expose machine and owner-safe summaries, explicit failed/blocked/missing/expired checks, exact version/source/artifact identity and evidence references. Repair always creates a new run. Rollback targets are independently re-verified after rollback, and production state distinguishes `verified_current`, `drift_detected`, `verification_expired` and `unknown`.
