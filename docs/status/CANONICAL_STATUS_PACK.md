# Canonical status pack

The only current status surface for Pandora's-box is the authenticated `GET /api/operator/status` endpoint. It refreshes Memory, GitHub, Vercel, Supabase, and the separately authoritative physical-Android receipt concurrently on every request and sends `Cache-Control: no-store`.

The endpoint returns the same structured pack with:

- HTTP `200` only when every authority is fresh, consistent, and fully bound;
- HTTP `503` when evidence is stale, conflicted, unavailable, or incomplete.

No cached or checked-in projection is promoted when a provider is unavailable. The former Control Tower JSON snapshots were removed from their public paths and preserved under `docs/status/historical`; every surface in `HISTORICAL_STATUS_SURFACES.json` is forbidden as a current-state input.

The JSON contract is structurally closed. `authoritative: true` and `status: current` are valid only when the generated-to-expiry window is positive, every proof-ladder stage is true, all seven exact evidence authorities are available, the 41-item registry matches, and `blockers`, `conflicts`, and `unknowns` are empty. A semantic verifier recomputes the freshness relation and canonical JSON SHA-256; shape-valid but reversed-time or rehashed-forgery claims fail closed.

## Live goals

Every refreshed pack carries exactly six ordered goal records with bounded `state`, `evidence`, `blockers`, `owner`, and `nextAction` fields:

1. one authenticated automatically refreshed status pack with stale surfaces historical;
2. the exact 41-PR land/consolidate/archive/close registry;
3. the owner-command/Worker-01 path rebuilt and green from protected `main`;
4. every required check plus one exact source SHA, production deployment, and distinct rollback;
5. one bound physical Android build completing the journey on Wi-Fi and mobile data;
6. the immediate commercial return to real interviews and the first paid pilot.

The commercial goal is `blocked` until production proof completes, then `ready`; repository content never marks interviews, payment, or a pilot complete. The first five technical/governance goals must be complete before a pack may be current.

## Proof ladder

The pack keeps these states separate:

`documented → implemented → tested → deployed → productionVerified`

`tested` requires four exact repository workflow/job identities, pinned to GitHub Actions and green on the literal canonical source SHA, plus the logical `external-review` gate bound to the dedicated Pandora Main Gate GitHub App (`appId: 4658204`, producer `pandora_main_gate_github_app`) using provider context `external-review`. Candidate workflows cannot publish or impersonate either review identity. App `15368` is GitHub Actions and is explicitly rejected as independent review authority. Pull-request and merge-queue runs test GitHub's synthetic integration SHA; push-to-`main` runs bind the canonical release SHA. `deployed` additionally requires a fresh Supabase Management API ordered-version match and an immutable database receipt captured after deployment that binds the exact GitHub source artifact, source SHA/tree, source-byte-chain digest, and then-live ordered version chain. This combination does not claim that Supabase reconstructed the original migration file bytes. Vercel proof requires two immutable phase receipts: transition to a distinct source/deployment and restoration to the candidate. Each phase live-reads the fixed production alias before and after fixed-host route probes. `productionVerified` additionally requires separate physical-observer receipts binding the same APK, source SHA/tree, and production deployment across Wi-Fi and mobile data.

## Current convergence snapshot

The initial registry is bound to protected `main@5a630893f2102064dcb2c7c72a3374042e6b4542` and the complete 41-PR inventory observed at `2026-08-23T13:30:00Z`. That inventory is 1 conditional land, 9 consolidate, and 31 archive. Refresh reads open and closed PR records so executing an archive decision does not invalidate its own registry. A missing registry item or changed immutable head makes the pack stale until reconciled; the live open count is reported separately.

Vercel runtime identity is cross-checked against Vercel's deployment API; it is not provider proof by itself. Supabase project health or version names alone are not source-artifact parity. The immutable database receipt plus a fresh ordered-version read makes the source-to-version binding operationally verifiable, while `exactAppliedBytesProven` remains `false` and `providerReadback` is never assigned to the stored source-byte digest.

## External receipt intake

The status endpoint is read-only and never manufactures missing proof. The independent evidence store must contain passing, non-invalidated records bound to the exact repository and source SHA:

- `canonical_vercel_production`: production deployment ID, exact source, production route probes, and the same provider-verified deployment ID;
- `capture_canonical_vercel_rehearsal_receipt`: one service-role-only call for `rollback_transition` and a later call for `rollback_restoration`; each call resolves only the fixed Vercel alias, verifies project/repository/source/READY/production identity, probes only the fixed `/health`, `/mcp`, and OAuth metadata URLs, re-reads the alias to close the probe window, and stores immutable response/probe digests with database times;
- `capture_canonical_supabase_release_receipt`: a service-role-only post-deploy call that records the exact GitHub source-artifact locator/hash, source SHA/tree and source-chain SHA-256 together with the live ordered migration-version chain. A fresh Management API version read must still match that captured chain on every status refresh;
- `canonical_physical_android_wifi` and `canonical_physical_android_mobile_data`: two distinct observer receipts for one device hash, source SHA/tree, production deployment, package, APK SHA-256, and the full owner-to-proof journey.

Both receipt tables are append-only through their capture functions; direct table access is denied even to `service_role`, and update/delete triggers reject mutation. The service-role-only status projection validates the receipt sequence, re-reads the current Vercel alias plus both deployment identities, and returns only bounded receipt identities and digests. Missing, malformed, source-controlled, mismatched, or provider-unreadable evidence leaves the canonical pack non-authoritative.

The authenticated Supabase control Edge endpoint exposes the capture functions through two exact-key actions. `canonical_supabase_receipt_capture` accepts only the canonical repository, exact source/tree SHA, three SHA-256 bindings, and a matching numeric GitHub artifact ID/API URL; it returns a non-null `supabaseReceipt`. `canonical_vercel_rehearsal_capture` accepts only the canonical repository, one of the two fixed phases, distinct candidate/rollback deployment IDs (bounded to 128 provider characters), and distinct exact source SHAs; it returns a non-null `vercelRehearsalReceipt`. Route URLs and expected probe semantics are never caller input.
