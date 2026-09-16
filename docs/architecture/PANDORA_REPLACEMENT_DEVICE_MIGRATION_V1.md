# Pandora Replacement-Device Migration v1

Status: M8-004 implementation contract. Source/CI acceptance is separate from a physical replacement-device drill.

## Goal

Restore useful Pandora context on a replacement Android device without treating the old device as a credential source. The migration package is portable state only: remote Memory references, currently-active standing-policy references, and user capability preferences. It is not a phone clone and never transfers protected-app private data or Android authority.

## Required trust sequence

1. Install Pandora through the authorized app/release path.
2. Authenticate the owner freshly on the replacement device.
3. Parse the migration package with exact schema allowlists.
4. Verify the canonical SHA-256 payload digest before reading any restore instruction.
5. Require the authenticated user to match the package subject binding.
6. Revalidate every standing-policy reference against current authority before any local restore mutation.
7. Re-fetch referenced Memory from the authoritative remote Memory plane; do not trust copied record contents.
8. Restore only portable user capability preferences.
9. Rediscover current hardware compatibility, OEM adapter, Android roles and runtime permissions on the new device.
10. Persist the migration receipt only after successful completion so exact replay is idempotent.

## Explicitly non-transferable state

The migration package must never contain provider access/refresh tokens, user passwords, OTPs, authenticator seeds, private keys, signing keys, Android Keystore material, Supabase service-role credentials, AWS/GitHub/OpenAI/Gemini credentials, cookies, bearer/session credentials, financial-app or e-wallet private data, password-manager vaults, or protected-app application data.

Pandora's current owner-test Supabase session is memory-only and is intentionally not migrated. The replacement device re-authenticates. Authenticator/password-manager/GCash/bank recovery remains owned by those protected systems and the user; Pandora does not scrape, export or reconstruct their secrets.

## Local-state policy

Device-local recovery hints are discarded rather than cloned. In particular, pending project-creation idempotency state and build-stream cursors are not authoritative portable state. After migration Pandora re-reads server truth and establishes new local cursors/recovery hints from verified provider state.

## Memory boundary

The bundle transports only `recordId`, typed record class, and expected revision. Record content is re-fetched from the authoritative Memory plane after authentication. A copied Memory reference grants no authority. Missing, revoked, superseded, inaccessible or revision-mismatched Memory must fail closed or reconcile to current remote truth rather than forcing stale content onto the new device.

## Standing-policy boundary

Only a reference that was active at export may appear in the package, and every reference carries its authorization fingerprint plus `requiresRevalidation=true`. Import never activates a policy. Current policy authority is revalidated before restoration proceeds. Revoked, expired, narrowed or fingerprint-mismatched authority stops the migration before portable local state is changed. Prediction, patterns and prior successful actions never become permission during migration.

## Capability boundary

Only preference intent is portable. Measured hardware facts, OEM facts, Android roles, runtime permissions, Device Owner state, telephony state and protected-app state are never restored from the old device. The replacement device must refresh the compatibility profile and OEM adapter from current public/runtime truth and request roles/permissions normally when capabilities are invoked.

## Integrity and replay

The bundle schema is `pandora-replacement-device-migration-v1`. The canonical JSON payload is SHA-256 bound. Unknown or missing fields fail closed, preventing arbitrary extension payloads from becoming a secret-smuggling channel. Successful application records `migrationId -> payloadSha256`; exact replay returns an already-applied receipt with no duplicate restore side effects, while the same migration identity with different content is rejected.

## Failure recovery

Policy revalidation occurs before any restore mutation. Memory restore is a remote refetch. Portable capability preferences are snapshotted before write; if capability/device-truth refresh fails, prior preferences are restored and no success receipt is written. Retrying after failure must reuse the same migration identity and digest.

## Acceptance

Source/CI acceptance requires digest-tamper rejection, exact-schema enforcement, reauthentication/owner binding, protected-secret exclusion, policy revalidation, new-device capability rediscovery, idempotent replay, rollback-on-failure, focused Flutter tests, full Flutter tests, analyzer, mobile source/security tools and exact-head repository CI.

Physical acceptance remains separate: use an authorized replacement/test device to export or obtain a migration package, install the exact intended signed APK, authenticate freshly, perform the migration, verify Memory/policy/config restoration and fresh capability discovery, reboot, recheck normal operation, and verify protected apps remain intact and require their own legitimate reauthentication. Do not mark physical acceptance from emulator/CI evidence.
