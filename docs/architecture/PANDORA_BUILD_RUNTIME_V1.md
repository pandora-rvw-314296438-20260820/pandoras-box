# Pandora Build Runtime v1

Status: Worker D architecture and runtime contract
Owner: Worker D — Build Runtime / Sandbox / Workspace / Repair Execution

## Purpose

Pandora Build Runtime turns an already-authorized, exact-version build request into bounded, reproducible build execution. Worker D executes work; it does not decide customer intent, authorize privileged actions, independently verify the result, or publish production deployments.

Core flow:

`AUTHORIZED REQUEST -> CLAIM DURABLE JOB -> ADMISSION -> TEMPORARY CREDENTIAL LEASES -> DISPOSABLE WORKSPACE/SANDBOX -> EXACT MATERIALIZATION -> DEPENDENCIES -> BUILD -> TEST -> ARTIFACTS -> MANIFEST -> READY FOR WORKER E`

Repairs use a separate bounded flow:

`FAILED BUILD -> AUTHORIZED REPAIR -> DISTINCT WORKSPACE/ATTEMPT -> CHANGED-FILE MANIFEST -> REBUILD/RETEST -> NEW MANIFEST -> READY FOR WORKER E`

## Hard boundaries

Worker D never:

- infers customer intent or owns ProjectSpec;
- grants its own privileged authorization;
- accepts raw long-lived provider credentials in build requests;
- runs arbitrary model/user shell strings;
- treats a builder result as independently verified;
- performs production publish/deployment;
- rewrites Worker A durable control-plane semantics;
- persists provider master credentials into source, logs, cache, artifacts, or build manifests.

## Runtime components

### Existing build runtime

- `contracts/build-execution.mjs` — typed build request/result contract, exact project/version/source scope, bounded resources, non-production environments, credential lease references only.
- `workspace/workspace-manager.mjs` and `filesystem/workspace-filesystem.mjs` — disposable project-scoped workspaces with traversal/realpath containment.
- `sandbox/sandbox-manager.mjs` — provider-independent sandbox boundary.
- `sandbox/vercel-sandbox-provider.mjs` — Vercel Sandbox implementation using bounded CPU/memory/runtime settings and explicit network policy.
- `source/source-materializer.mjs` — exact Git commit or artifact-snapshot materialization; hooks/submodules/credential persistence fail closed.
- `dependencies/dependency-plan.mjs` — lockfile-first dependency plans and lifecycle-script suppression.
- `adapters/adapter-registry.mjs` — trusted build adapters for static web, Node/Vite/Next, Flutter web, and Flutter Android APK.
- `execution/operation-executor.mjs` and `execution/build-pipeline.mjs` — typed trusted-command execution, build/test pipeline, stage events, artifacts, and build manifest.
- `artifacts/artifact-collector.mjs` and `manifest/build-manifest.mjs` — deterministic source/artifact/build lineage.
- `network/network-policy.mjs`, `environment/environment-policy.mjs`, `process/process-supervisor.mjs`, `limits/resource-limits.mjs` — network, environment, process, output, timeout, and resource boundaries.
- `cache/cache-key.mjs` and `cache/cache-integrity.mjs` — project-scoped deterministic cache identity and tamper detection.
- `logs/log-records.mjs` — bounded structured logs and secret redaction.

### Durable execution closure

- `control/worker-a-control-plane.mjs` — adapter for Worker A `pandora_claim_build_job`, `pandora_heartbeat_build_job`, and `pandora_requeue_expired_build_jobs`. Lease tokens are hashed before RPC transport. Optional load/checkpoint hooks keep persistence owned by Worker A.
- `idempotency/durable-step-journal.mjs` — exact input digest, safe duplicate replay, conflict rejection, and fail-closed `LEASE_EXPIRED_OUTCOME_UNKNOWN` handling.
- `credentials/credential-lease-manager.mjs` — resolves only temporary scoped lease references, validates expiry/revocation/scope, builds child-only environment values, supplies redaction values, and releases leases in `finally` paths.
- `execution/managed-build-runtime.mjs` — admission, durable claim, heartbeat, cancellation polling, credential lifecycle, idempotent execution, stage checkpointing, and result journaling around the trusted build pipeline.
- `repair/repair-controller.mjs` — repair attempt/time/change/cost/deadline budgets and distinct repair workspace lineage.
- `repair/repair-runtime.mjs` — authorized changed-file application and rebuild in a distinct disposable repair workspace with cleanup.
- `admission/admission-controller.mjs` — global, organization, project, memory, disk, provider-health, and draining admission gates.
- `health/worker-health.mjs` — safe worker capacity/readiness snapshot.
- `recovery/crash-recovery.mjs` — pre-execution lease requeue, running-outcome quarantine, cancellation recovery, and orphan-sandbox cleanup planning.

## Worker A durable contract

The live control plane provides:

- `public.pandora_build_jobs`
- `public.pandora_build_job_steps`
- `public.pandora_build_job_attempts`
- `public.pandora_build_job_events`
- `private.pandora_claim_build_job(...)`
- `private.pandora_heartbeat_build_job(...)`
- `private.pandora_requeue_expired_build_jobs(...)`

Worker D consumes those semantics through an adapter and does not create a second durable job database.

Recovery rules are intentionally asymmetric:

- expired `claimed` work can be requeued before execution;
- expired `running` work is **not** replayed automatically because the external outcome may be unknown;
- exact completed duplicates can replay their prior safe receipt;
- changed input under the same idempotency identity is rejected;
- cancellation is checked before execution and during heartbeat polling.

## Credential rules

Build requests contain credential lease references, never raw credentials. A lease must be temporary, scoped, unexpired, and not revoked. Provider-master environment names are rejected unless the lease is explicitly classified by the credential broker as `temporary_scoped`; long-lived standing provider credentials are not a Worker D runtime input.

Credential values:

- exist only in the process memory needed to construct a child execution environment;
- are added to structured-log redaction values;
- are not included in stage-event payloads or manifests;
- are released after success, failure, cancellation, or exception;
- are not copied into project caches.

GitHub repository mutations for Pandora itself use the Supabase Vault-backed `Github_supabase` integration path. Vercel Sandbox calls use the Worker D Vault-backed Vercel integration. No PAT or provider token belongs in source control.

## Repair contract

Worker D may execute a repair only when it has an external authorization identity. Repair attempts have:

- a distinct attempt number and workspace key;
- the original source digest;
- a bounded changed-file manifest;
- maximum attempts;
- maximum changed file count and changed bytes;
- maximum wall-clock duration;
- optional deadline;
- maximum estimated cost;
- cancellation support;
- cleanup after the attempt.

The repair runtime does not authorize its own patch and does not declare the repaired result verified. The new build returns to Worker E.

## Admission and health

Admission is fail-closed on:

- global concurrency capacity;
- per-organization capacity;
- per-project capacity;
- memory pressure;
- disk pressure;
- sandbox-provider health;
- Worker A control-plane health;
- draining mode.

Worker health exposes only safe capacity metadata and no credential material.

## Security and recovery proof map

| Requirement | Proof |
| --- | --- |
| Path traversal / realpath escape | `workspace-filesystem.test.mjs`, `contracts.test.mjs` |
| Symlink artifact escape | `materialize-runtime.test.mjs` |
| Exact source / disabled Git credential persistence | `materialize-runtime.test.mjs` |
| Metadata endpoint block | `materialize-runtime.test.mjs`, network policy tests |
| Secret redaction | `materialize-runtime.test.mjs`, process/environment tests |
| Raw shell injection resistance | typed sandbox/process/operation executor tests |
| Timeout / runaway process cleanup | process/sandbox tests |
| Resource-limit enforcement | `sandbox-limits.test.mjs`, Vercel provider tests |
| Vercel disposable runtime | `vercel-sandbox-provider.test.mjs`; live bounded disposable sandbox proof was recorded in merged PR #108 |
| Idempotent duplicate replay | `worker-d-closure.test.mjs` |
| Idempotency conflict rejection | `worker-d-closure.test.mjs` |
| Ambiguous running lease expiry | `worker-d-closure.test.mjs` |
| Heartbeat and cancellation | `worker-d-closure.test.mjs` |
| Temporary credential cleanup / stale credential rejection | `worker-d-closure.test.mjs` |
| Repair budgets and distinct attempt lineage | `worker-d-closure.test.mjs` |
| Broken build -> authorized repair -> successful rebuild mechanics | `worker-d-closure.test.mjs` |
| Concurrent independent project credential isolation | `worker-d-closure.test.mjs` |
| Admission / pressure / health | `worker-d-closure.test.mjs` |
| Orphan sandbox cleanup | `worker-d-closure.test.mjs` |
| Exact source -> artifact -> build manifest lineage | `build-pipeline.test.mjs`, `materialize-runtime.test.mjs` |
| Build Theatre technical event ordering | `build-pipeline.test.mjs` |

## Cross-worker contracts

- **Worker A** owns durable job/state semantics. Worker D claims, heartbeats, checkpoints, and reports execution facts.
- **Worker B** produces intelligence/ProjectSpec. Worker D consumes exact approved build inputs only.
- **Worker C** authorizes privileged build/repair actions and brokers scoped temporary credential leases.
- **Worker E** independently verifies exact build artifacts/manifests. Worker D never self-verifies.
- **Worker F** owns preview/production deployment and domain/provider runtime. Worker D stops at build artifacts ready for verification.
- **Worker G** consumes safe build-stage events for Build Theatre; Worker D does not own customer UX.
- **Worker H** consumes safe cost/resource/outcome telemetry; Worker D does not decide economics.
- **Worker I** supplies trusted primitive versions; Worker D materializes/builds exact selected inputs.
- **Worker J** owns cross-worker E2E/release convergence and production-readiness declaration.

## Completion condition

Worker D is complete when these runtime modules and their tests are merged on current `main`, repository CI is green at the exact merged source, the live Worker A build-job contract remains present, the bounded live Vercel Sandbox path remains healthy, and no unresolved Worker-D-owned defect remains. Production publish remains deliberately outside Worker D.
