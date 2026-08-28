
# Pandora Verification Execution V1

Worker E is the independent verification boundary. The builder, model and customer client may provide inputs or receipts, but they cannot author authoritative PASS state.

## Implemented execution boundary

The provider-independent executor layer supports bounded independent command plans, untrusted project-test plans, secret-redacted logs, deterministic dependency/security evaluation, accessibility evaluation, visual classification, migration preflight/postflight, browser journey evaluation, ProjectSpec acceptance mapping, analytics instrumentation readiness, preview identity/runtime verification, production identity/domain/runtime verification, evidence hashing and verification cost telemetry.

`VerificationOrchestrator` is the trusted coordinator. Only executors declared `pandora_independent` may be registered. It never gives the executor the verifier authority token, builder credentials or Pandora master provider credentials. Missing or crashed executors become `BLOCKED / verification_infrastructure`, not fabricated product failures. Evidence is reduced to a digest/reference for run state and can be streamed to a separate evidence sink.

Project-provided tests are explicitly `project_untrusted`, run without provider credentials, and are not release authority by themselves. They remain useful evidence when independently re-run in the Worker D sandbox boundary.

## Control Plane integration

Worker A remains the persistence owner. `ControlPlaneVerificationStore` maps Worker E run/check/evidence records to the existing `pandora_verification_runs`, `pandora_verification_checks` and `pandora_verification_evidence` contracts without creating a competing schema. Builder and verifier identity equality is rejected.

## Security and false positives

Exact source and artifact secret scanning returns fingerprints and redacted markers rather than plaintext. Reviewed exceptions bind to an exact finding fingerprint, optional exact project version, reviewer/reason and expiration. Dependency severity remains a verifier fact; Worker C remains the policy/authorization owner.

## Runtime and release proof

Provider `READY` is not verification. Preview PASS requires exact project version, source commit, artifact identity and runtime probes. Production PASS additionally requires exact deployment identity, intended domain, ownership/DNS/TLS/routing/project binding and smoke probes. Artifact lineage must be exact or explicitly reproducible; otherwise the result is FAIL/INCONCLUSIVE.

## Resource and trust limits

Command execution is argv-only (`shell:false`), workspace-relative, bounded by verifier time/log/evidence limits, deny-by-default for network, and refuses standing secret environment variables. Browser content is treated as untrusted and is never supplied Pandora master credentials. Verification telemetry reports time, browser minutes, screenshot count, evidence bytes and external scan count without inventing pricing.
