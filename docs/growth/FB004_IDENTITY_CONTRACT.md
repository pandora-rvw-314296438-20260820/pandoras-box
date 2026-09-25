# FB-004 — Platform growth identity contract

Status: implementation candidate; independent review and merge are separate. Task #715.
Owner: Backend/AI. Final acceptance: Release/Verification with THEMIS.

## Purpose and authority

Make the existing organization, tracking, Meta and Memory identity chain inspectable without inventing a second tenant registry or changing production authorization. This batch adds an **offline inventory auditor**, two read-only SQL probes, an observed evidence fixture, and behavioral regression tests. It does not implement or replace an HTTP authorization boundary.

The auditor's manifest is a reviewed operator input, never client/model-selected authority. Every report has `authorizationEffect: none`, `snapshotOnly: true` and `productionVerified: false`. Even a `consistent_snapshot` means only that the supplied references agree. It cannot grant a scope, validate a JWT/token, select a customer, approve a lesson, authorize spend, or prove runtime isolation. A spoofed snapshot is not provider evidence.

## Explicit platform identity map

| Identity domain | Observed platform identity | Required relationship |
| --- | --- | --- |
| Primary Supabase project | `jcyqixttuebxqqfkjonq` | Primary database, not Memory database |
| Organization | `2270b266-59da-4c39-bfd9-9f8d08352af0` | Server-validated organization context |
| Primary project | `ee282126-3f61-4058-8c92-2fedbfcecf1f`, key `mcpmaster` | Project and canonical registry agree on organization and repository |
| Canonical source | `pandora-rvw-314296438-20260820/pandoras-box` | Repository provenance, not unique tenant identity |
| Tracking tenant | `326b51af-0445-4e96-bf31-d346bab05220`, key `pandora-platform` | Exact primary organization/project binding |
| First-party campaign | `pandora-meta-main` | Campaign belongs to that tracking tenant |
| Meta connection / selected Page / ad account | **Not connected or verified in this readback** | Organization-owned connection plus separately verified selected provider assets |
| Memory Supabase project | `ivmvufhcsezyhczzondn` | Separate database and project-ID domain |
| Memory project | `7c686cbd-d968-49d5-86cc-918f5e777bd2`, key `mcpmaster-pandoras-box` | Explicit UUID and key; do not reuse primary project UUID |
| Selected Memory service principal | `pandora-mcpmaster-production` | Active principal and exact production project grant |
| Environment / namespace | `production` / `real_life` | Both must match principal, project and grant where represented |

These are dated observations, not permission to provision or rebind them. The fixture retains non-secret resource IDs for reproducibility but excludes personal records, token values, secret UUIDs, OIDC subjects, request bodies and raw customer content.

**Repository-only lookup is ambiguous.** Memory also has project `enterprise-eurofish` (`7123981b-6106-4e04-8edd-6894756ab481`) using this same canonical repository. Select the explicit authorized Memory project, not the first repository match. Conversely, do not reject a correct exact project merely because another customer shares the source repository.

The separate `pandora-tracking-smoke` tenant is unbound to organization/project. Its existence is not proof of a platform binding and it must not become a fallback tenant or be merged into business measurement. Its presence does not invalidate a correctly selected platform tenant.

## Read, write and retrieval boundaries

**Client to primary database.** Resolve the authenticated caller, active membership and permitted organization on the server. Client-supplied IDs are requested selectors, not evidence of access. Join the selected tracking tenant to the primary project's canonical organization; the committed `pandora_tracking_validate_tenant_scope_v2` trigger enforces the project/organization pairing on tenant writes. Do not modify its owning migration in this batch.

Catalog readback found RLS enabled on tracking tenants/campaigns and the verified-learning outbox, with no `anon`/`authenticated` direct SELECT or INSERT grants. Connector installations have authenticated SELECT with RLS. The private Meta connection/Page-token tables have no direct SELECT/INSERT grants for those client roles; RLS is false on those private tables. This describes catalog posture, **not behavioral RLS proof**. Do not blindly enable RLS or broaden grants based on the catalog flags alone.

**Meta credential ownership.** OAuth material and commit RPCs are service-role executable, not anonymous/authenticated executable. The server callback obtains one-time state and commits through `pandora_meta_oauth_commit_v1`; connection and Page-token records carry organization ownership. User/Page credentials remain referenced in Vault and handled only server-side. App credentials configure the integration; they are not permission to use another organization's assets. Do not place token values or full secret-bearing provider responses in this inventory. A secret-reference-present boolean does not prove token validity.

**Meta assets and attribution.** First-party campaign slug, provider label and UTM fields do not establish a real Meta campaign/ad-account/Page association. Provider campaign IDs must be observed, and asset selection, consent, granted permissions, expiry, health, and any paid actions require their own gates. This auditor checks reference presence only; it intentionally does not report `canUseNow` or claim full Meta readiness.

**Memory.** Match the exact project UUID/key, active principal, production environment, allowed namespace and non-revoked project grant. Match the requested record class exactly. `memory:write` and `can_propose` are not class-independent permission, canonical approval or spend authority. M5-003 accepts only `fact`, `procedure`, `failure_lesson` or `outcome` through verified evidence intake; proposals then require independent review. Keep raw execution events out of canonical lessons. Historical/retired principal aliases are not a fallback authorization path.

## Actual findings and downstream ownership

Primary probe: **2026-09-25 08:51:38.735895 UTC**. Memory probe: **08:51:51.415094 UTC**. These are separate database snapshots, not one distributed transaction. The supplemental Meta inventory was observed at 08:45:50.707921 UTC.

The selected primary project, canonical registry and platform tracking tenant agree. However:

1. `pandora-meta-main` has no provider campaign ID. The earlier bounded inventory also found no ad-set/ad IDs. Do not infer them from the slug. Facebook/Growth: FB-011/FB-018 after required prerequisites.
2. No organization-owned Meta OAuth connection exists. The integration installation is pending with zero scopes, and the inventory found zero Page-token records. Owner consent, credentials/configuration and real provider verification remain FB-009 through FB-016. This work does not bypass those gates.
3. The selected Memory grant permits read/propose, but its eleven allowed classes are project/architecture/integration metadata; they do **not** include `fact`, `procedure`, `failure_lesson` or `outcome`. An `integration_state` read-class check passes while an `outcome` proposal-class check fails. Coordinate any approved class changes with the existing Memory PR #93 owner and FB-025/FB-026; do not widen live grants here.

An accepted learning-outbox row from a different workspace is not proof that the platform growth Memory loop works. Acceptance, review, promotion and approved retrieval remain separate milestones.

## Reproduce the audit

On the respective existing Supabase projects, run only:

- `scripts/sql/fb004-primary-readback.sql` on the primary database.
- `scripts/sql/fb004-memory-readback.sql` on Memory.

Copy the returned objects into `primary` and `memory` of a **new** evidence snapshot retaining an explicitly reviewed `expected` manifest. Both scripts were executed successfully as reads during this batch. Do not rewrite the historical fixture to look fresh. Do not add provider credentials or customer payloads. Collect a fresh source/deployment identity separately when assessing release/runtime claims.

```sh
node --test test/pandora-fb004-identity-contract.test.js
node scripts/audit-fb004-identity.cjs path/to/fresh-snapshot.json
```

Exit 0 means reference consistency only; exit 1 means findings, including missing links or observations older than the auditor's one-hour diagnostic window; exit 2 means unusable input. The historical fixture is expected to return blocked. Tests pin their observation clock; they never relabel historical data as current. The one-hour audit window is a diagnostic default, not a deployed authorization/retention policy.

Tests cover actual validator behavior: cross-organization/project/campaign links; primary-vs-Memory UUID confusion; explicit selection despite shared repositories; duplicate matches/grants; inactive/revoked/malformed grants; exact read/propose classes; approval separation; namespace/environment; missing, old, future and timezone-free evidence; bounded/secret-bearing input; CLI exit states and non-disclosure. Positive completion fixtures are deliberately synthetic.

## Source, release and learning provenance

Inspected Box source: `6f20780765001d1a90ee31800a3948d043551afa`. Inspected Memory source: `2d193c0667a037e815f50a1c1c81fd578eaf9d92`. Neither identity is presented as a deployed runtime SHA.

Source anchors:
- Box `supabase/migrations/20260925072000_pandora_tracking_dashboard_recovery_v1.sql`: canonical-registry FK, organization trigger, reporting grants.
- Box `supabase/migrations/20260925061000_pandora_meta_oauth_marketing_read_v1.sql` and `20260925070000_pandora_meta_oauth_vercel_callback_v1.sql`: Meta boundary/migration provenance.
- Box `src/pandora-meta-oauth-http.js`: existing server callback/material/commit path.
- Memory `docs/architecture/M5_003_VERIFIED_EXECUTION_LEARNING.md` at the inspected SHA: exact class/project grant, terminal verification, review-only intake and no execution authority.
- Evidence: `docs/growth/evidence/fb004-20260925.json`; Task #715; linked implementation PR and its exact head/test receipt.

No production data/schema, RLS, RPC contract, auth/provider setting, Edge Function, Vercel runtime or shared CI file is changed. Migration replay is not applicable to these new non-migration files. Node 24 repository CI and independent review are release gates; local Node 22 tests are supplemental evidence, not a substitute. No production deployment is required for the offline tool itself. Existing auth/Memory remediation remains with Box #709 / Memory #93.

Durable lesson for reviewed Memory: use typed identity domains and exact record-class grants. Shared source repositories, a broad write scope and another workspace's accepted learning are each insufficient evidence of a correct growth-learning route. Preserve the dated failure evidence and supersede it only with fresh authoritative readback. The lesson does not authorize grant changes or mark the end-to-end loop complete.
