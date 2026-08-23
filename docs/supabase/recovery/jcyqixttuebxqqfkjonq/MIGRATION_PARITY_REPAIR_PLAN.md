# MCPMaster Supabase migration-parity repair

## Outcome

Restore a reproducible, content-addressed migration chain for Supabase project
`jcyqixttuebxqqfkjonq`, preserve all 50 production ledger identities, and allow
the already-landed ordinary owner/admin AAL1 approval migration to be released
without rewriting or deleting production history.

## Exact starting state

- Canonical repository: `banataosystems/Pandoras-box`
- Starting main: `171b85c3012f053cfe2e531b82d8e495c5b8007e`
- Production ledger: 50 migrations through
  `20260810104737_reject_anonymous_org_membership_helpers`
- Production branch status: `MIGRATIONS_FAILED`
- Pending migration:
  `20260812034825_remove_projectos_approval_aal2.sql`
- Pending migration SHA-256:
  `8e9acf74b5ee5ea552697989768afc5aac938b92947e3495c2deecde30dadd31`
- Production schema and Edge Function still require AAL2 for ordinary owner
  approval at the start of this repair.

## 2026-08-23 immutable-identity reconciliation

The provider ledger now contains 59 immutable identities through
`20260821024500_projectos_owner_read_completion`. Source preserves all 59:

- the AAL1 migration uses its exact provider version,
  `20260813014555_remove_projectos_approval_aal2.sql`; the earlier
  `20260812034825` source identity remains recorded only as provenance;
- three temporary Vercel hotfix migrations are represented by comment-only,
  content-addressed alignment records because their live bodies exercised
  privileged Vault/token/network operations and must not be republished;
- the provider ledger was not deleted, rewritten, or repaired in place; and
- twelve newer source migrations remain forward-only production changes.

The original replay JSON files remain immutable evidence. The reconciled
71-file replay is recorded separately in
`pglite-replay-result-20260823-source-alignment.json`.

## Scope

1. Recover the canonical timestamp and executable semantics of all 48 SQL
   payloads recorded by the provider. Preserve only hashes/byte counts for
   three payloads that embedded live verifier or HMAC material; never copy
   those sensitive bytes back into active source.
2. Promote the two foundation recovery candidates only after deterministic
   clean replay and catalog-contract comparison.
3. Keep fixtures, provider-extension stubs, capture results, and rollback
   material outside the production migration stream.
4. Add exact checks that reject missing, duplicate, mistimestamped, or
   content-drifted migration files.
5. Release the AAL1 migration and matching `pandora-owner-api`/Vercel runtime
   only after exact-head CI, substantive different-vendor review, live
   resource binding, and callable rollback are proven.

## Non-goals

- Do not delete or rewrite any production migration record.
- Do not copy production rows, credentials, Vault values, OAuth tokens, or
  personal data into source or test fixtures.
- Do not recommit the historical Base64/plaintext recovery payloads: three of
  them contain verifier or HMAC material that remains live at the start of
  this repair.
- Do not remove AAL2 from connection changes, destructive actions, or other
  separately classified critical actions.
- Do not deploy unrelated FlutterFlow/mobile work from historical recovery
  branches.

## Required proof

- All 50 production identities map one-to-one to local filenames.
- The 48 recorded provider payload hashes/byte counts are retained as
  content-addressed evidence, while active replay source contains no live
  credentials or verifier material.
- A clean ordered replay passes with explicit non-production fixtures.
- The replayed authorization, RLS, privilege, function, trigger, and schema
  contracts match a redacted live catalog capture.
- Ordinary approval permits only permanent, active owner/admin accounts and
  retains expiry, assignment, separation-of-duty, one-time decision, exact
  action hash, and audit controls.
- Anonymous, member, viewer, operator, and machine identities remain denied.
- Exact rollback SQL and previous Edge/Vercel deployments remain available.
- The database rollback restores the exact prior AAL2 function body and the
  AAL1 migration can be reapplied cleanly after that rollback.
- Exact candidate CI and different-vendor review both pass.

## Release order

1. Freeze and re-read production database, Edge, Vercel, and audit baselines.
2. Rotate the two historically exposed HMAC credentials across their producers
   and database consumers, with old values retained only for bounded rollback.
3. Apply the additive AAL1 database migration transactionally.
4. Deploy the matching owner Edge Function.
5. Deploy the exact canonical Vercel container artifact.
6. Run authenticated positive and negative authorization smoke tests.
7. Roll back immediately if any security, data-integrity, health, or runtime
   check fails.

## Stop conditions

Stop before any production mutation if the exact head changes, replay or
catalog parity fails, independent review is absent or stale, production
rollback is not callable, provider bindings drift, or the owner authorization
no longer applies to the exact candidate.
