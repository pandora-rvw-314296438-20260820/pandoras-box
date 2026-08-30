# Pandora Intelligence Reviewer Gateway v1

This boundary closes the gap between independent Worker-E authority and durable intelligence trust.

An intelligence asset can become `TRUSTED` only when all of the following remain true at finalization time:

1. The reviewer has a fresh independent reviewer runtime proof with `projectos.intelligence.verify` on the canonical Pandora repository.
2. The reviewer is enrolled with an exact Ed25519 public key. Enrollment grants no review scope.
3. A database administrator explicitly grants a short-lived scope. Global review is never granted by migration and is capped at 30 minutes.
4. The reviewer signs an exact source/content/evidence/scope/nonce/timestamp basis.
5. The Edge gateway verifies that Ed25519 signature and the reviewer key fingerprint.
6. A short-lived independently issued JWT is bound to the exact certification request, reviewer, and scope.
7. The database consumes the JWT jti once, rechecks the reviewer proof and scope grant, and only then performs the Worker-E `TRUSTED` transition.

The legacy direct reviewer-role certification RPC is revoked. Service-role components may resolve targets and record already-verified pending attestations, but cannot finalize trust. Models and imported repository content never receive certification authority.
