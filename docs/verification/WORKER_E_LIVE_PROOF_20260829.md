# Worker E live proof — 2026-08-29

Worker E has now completed the live deterministic, durable, preview, and production portions of the verification proof on an internal disposable project. The overall closure remains intentionally **BLOCKED**, not PASS, for one narrow reason: Vercel requires a second production history entry before a real rollback-and-restore exercise can be performed, and the canonical Hobby team exhausted the current 100-deployments/24h rolling window after the exact preview proof sequence.

## Proven live

- Worker A durable verification state is active in the canonical Pandora control plane.
- An intentionally failing exact version was executed in a nonpersistent Vercel Sandbox with deny-all network access and produced an acceptance FAIL. Its historical run remains immutable.
- The repaired source commit `fbe1de002808d35d3ff57293ebf4585a3461c711` and artifact SHA-256 `34327d36984024bbae4f0d36829d91c9b1694d493f9e39506d5eae901fe7fc60` independently pass source, acceptance, accessibility, responsive-layout, reduced-motion, touch-target, and secret-scan checks.
- The disposable Vercel project now contains an exact known-good preview (`dpl_HqtbFJSzd8sE3h1aRLGuaxHjZ6Zk`), an intentional failing preview (`dpl_GWQdmamWVnBxX4Ptzey8zJL6BsF4`), and the repaired preview (`dpl_1nNyH9kyif88xeghvaH4JJKJeSSP`). The repaired preview is READY on the canonical Vault-backed team/project and is intentionally protected by Vercel SSO.
- Worker A now contains a new authoritative preview PASS run `1ed8a28a-5e83-424a-a2bb-89909862be7a`, preserving the older quota-blocked preview run as historical evidence.
- The disposable production deployment `dpl_AYi7Q9KGMYJ8kRRa8qqPvcW569Ju` is READY/PROMOTED and provider metadata binds it to the exact repaired Git commit.
- Independent HTTPS readback of `pandora-worker-e-proof-20260829.vercel.app` returned HTTP 200 and exactly 1005 bytes whose SHA-256 is the repaired artifact digest `34327d36984024bbae4f0d36829d91c9b1694d493f9e39506d5eae901fe7fc60`. The production response contains the PASS marker, `aria-live`, and reduced-motion contract.
- The default disposable Vercel domain is verified, belongs to the exact proof project, is not misconfigured, and successfully serves the verified artifact over HTTPS.
- Worker A now contains authoritative production PASS run `bc2b410d-3feb-461f-ae9a-7875df40589c` with source/artifact/runtime/domain/freshness evidence.
- The disposable database migration proof remains PASS with schema/constraints/indexes/RLS/policy verification and full rollback.
- All five GitHub Actions on closure head `41589b47172c9cf6aa9f7b70a00a132166008ec6` passed before this receipt update. The Vercel commit statuses remain red solely because the team build-rate limit was exhausted.

## Remaining release-closure proof

Vercel reports the current repaired production deployment as a valid rollback candidate. Because it is the only production history entry on the disposable proof project, a preview cannot be used as a rollback target: the provider correctly rejects a deployment that has never served production traffic. A fresh Vault-backed Worker F provider attempt now proves the remaining boundary exactly: `POST /v13/deployments` for the second exact repaired Production returns HTTP 402 `payment_required` with limit code `api-deployments-free-per-day` and `Retry-After: 86400`. Reusing the existing repaired Preview does not satisfy this requirement: the production promote endpoint returns HTTP 422 because that deployment is a Preview rather than a staged Production deployment. The next safe sequence remains to create a second real Production deployment from the exact repaired source/artifact once Vercel permits it, verify it, roll back to `dpl_AYi7Q9KGMYJ8kRRa8qqPvcW569Ju`, reverify, restore the second Production, and reverify again.

The earlier estimated rolling slot is no longer release authority. The latest provider response is the authority and currently returns `Retry-After: 86400` for new API deployments. Until Vercel permits the second real Production deployment and the exact rollback/restore sequence passes, publish eligibility remains false and PR #107 must not merge. Worker A records this narrow release blocker in run `bb249a11-20f8-4a1d-9bd3-2c8c82d37ec7`.

The machine-readable receipt is `docs/verification/WORKER_E_LIVE_PROOF_20260829.json`. It contains only safe identifiers, digests, statuses, and Vault reference names; no credential value is recorded.
