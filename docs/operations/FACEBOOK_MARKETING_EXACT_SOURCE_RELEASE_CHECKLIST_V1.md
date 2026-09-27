# Facebook Marketing Exact-Source Release Checklist v1

**Tracker task:** FB-008  
**Canonical repository:** `pandora-rvw-314296438-20260820/pandoras-box`  
**Baseline main SHA at checklist creation:** `2bbf80a544e46aa7a8a3d7ff41abea52b1a8b7de`  
**Meta Business Login merge:** `f4675344f99a3d2cc23a9c360c9512826e921c5c`  
**Operations generic-worker merge:** `74e7849f4e58c9d9dccbac50b106d4bde9c76e8e`  
**Operations builder-capacity merge:** `2bbf80a544e46aa7a8a3d7ff41abea52b1a8b7de`

This checklist is a release gate, not permission to spend, connect a customer, publish a Meta app, or bypass owner/privacy/security approval.

## 1. Exact-source identity

Every release candidate must record and independently read back:

- exact PR number and exact head SHA;
- exact base branch and base SHA;
- canonical repository name;
- merge SHA after merge, if merged;
- deployed source SHA for every runtime changed by the release;
- migration names and applied migration history for database changes;
- immutable provider deployment/function identifiers.

A candidate fails this gate if the provider reports a different head, base, merge SHA, deployment SHA, project, organization, or runtime target.

## 2. Current runtime targets

As of this checklist's creation:

- Vercel project: `mcpmaster` / `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`.
- Vercel production deployment: `dpl_6Ahggpr2HTenQ32diQxkuAUedbLn`.
- That deployment is bound to source SHA `74e7849f4e58c9d9dccbac50b106d4bde9c76e8e`.
- Canonical production alias: `mcpmaster.vercel.app`.
- Supabase main project: `jcyqixttuebxqqfkjonq`.
- Supabase control Edge Function: `mcpmaster-supabase-control`, verified live at version 72 after merge `2bbf80a544e46aa7a8a3d7ff41abea52b1a8b7de`.
- Supabase Memory project: `ivmvufhcsezyhczzondn`.
- Meta OAuth callback: `https://mcpmaster.vercel.app/oauth/meta/callback`.

When a release changes only one runtime, evidence must say so explicitly; unchanged runtimes must not be falsely claimed redeployed.

## 3. Required source and CI gates

The exact candidate head must have terminal acceptable results for every applicable required workflow. The standard Pandora set includes:

- Pandora Node 24;
- Engineering toolchain, including Gitleaks;
- Dependency Review;
- Operations Runtime Seams;
- Operations Room cloud connectors;
- Operations inference and live Theatre;
- Windows Worker Contract;
- Canonical release evidence;
- Pandora Edge source artifact;
- Pandora mobile exact-source gate;
- PLP Pandora Enterprise Android exact-source when the branch triggers it;
- Pandora audit behavioral regression when the branch triggers it.

The FB-008 checklist contract test itself must pass:

`node --test test/facebook-marketing-exact-source-release-checklist.test.js`

No required check may be inferred from a different SHA.

## 4. Meta-specific verification

For changes touching Meta/Facebook integration, verify all applicable items:

- OAuth preparation resolves Vault-backed app metadata without exposing secret values;
- authorization URL uses the deployed callback and Business Login configuration ID;
- invalid/missing/expired OAuth state fails closed;
- organization-admin authorization remains enforced;
- tenant isolation and cross-tenant denial are tested;
- app mode, requested permissions, and any Meta App Review requirements are recorded from provider truth;
- Page, ad-account, campaign, insight, webhook, and conversion reads are claimed only when live provider readback proves them;
- disconnect/revocation behavior is tested before declaring connection health complete;
- no external-customer authorization is claimed while the Meta app is unpublished or required permissions remain unapproved.

## 5. Database and security gates

For database or Edge Function changes:

- apply/rehearse the exact migration;
- confirm migration history and function definition readback;
- run Supabase security advisors;
- preserve RLS/tenant boundaries;
- keep service-role, OAuth secrets, API tokens, and provider credentials server-side only;
- reject secret values from logs, Sheets, PR bodies, Memory, browser storage, and generated evidence.

A security-definer function must be explicitly denied to `anon` and `authenticated` unless a reviewed public API contract says otherwise.

## 6. Reviewers and release authority

Implementation and verification are separate roles.

- Builder: the worker that makes the source change.
- Security/privacy review: THEMIS for auth, tenant, privacy, Vault, or consequential-action changes.
- Independent release verification: ARTEMIS or another acknowledged release worker whose identity differs from the builder.
- Owner authorization: required for exact-PR/head release when the release policy requires it, and always required for privacy-policy changes, interactive OAuth, ad spend, customer/client activation, or other explicitly human gates.

A builder may never self-verify a consequential release.

## 7. Stop conditions

Stop and do not merge, deploy, or mutate the provider when any of these is true:

- exact head/base/source identity cannot be read back;
- required CI is pending, failed, or belongs to another SHA;
- an unresolved review thread or substantive review finding remains;
- secret scanning fails or credential material appears in output/evidence;
- provider outcome is unknown or reconciliation is required;
- Supabase/Vercel/Meta readback disagrees with intended target;
- required migration, rollback evidence, or security advisor evidence is missing;
- tenant isolation or privacy controls are unverified;
- required owner/privacy/OAuth/client authorization is missing;
- spend authorization is missing for any paid action;
- the Meta app/permission state is insufficient for the claimed external capability;
- the candidate is behind/diverged from the required canonical source and the release contract does not explicitly permit that ancestry.

Unknown is not success. A timeout or ambiguous provider response is reconciliation work, not a retryable success.

## 8. Release sequence

1. Read current canonical `main` and provider runtime state.
2. Bind the task to exact repository/base SHA and immutable acceptance criteria.
3. Create a dedicated branch/PR.
4. Run exact-head tests and security checks.
5. Obtain substantive independent review where required.
6. Obtain exact owner release authorization where required.
7. Merge through the governed coordinator/Vault path.
8. Apply database/Edge changes from the exact merged source.
9. Deploy/promote only the required runtime.
10. Read back provider state, source SHA, aliases/function version, and runtime health.
11. Record immutable evidence in the tracker and Operations event ledger.
12. Send only verified, minimized learning to Pandora Memory.

## 9. Spend and customer-data boundary

This checklist does **not** authorize ad spend. Paid actions remain denied until a later explicit spend authorization is bound to the exact action scope and budget. It also does not authorize interactive Meta OAuth or client activation.

FB-003 outcome definitions and FB-007 privacy/data-use rules are the governing definitions for this Facebook tracker and must remain attached to downstream evidence.
