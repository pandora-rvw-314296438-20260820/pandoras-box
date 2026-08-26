# MCPMaster TOTP owner-account binding repair

Date: 2026-08-08 (Asia/Manila)

> Superseded for ordinary ProjectOS approvals on 2026-08-12. This document records the historical incident and its then-current response. The current owner decision is documented in `docs/PROJECTOS_APPROVAL_SECURITY_MODEL.md`: authenticated owners and admins may approve without AAL2/TOTP. Supabase MFA may remain available, and separately classified destructive or connection operations may retain independent controls.

## Verified root cause

The OAuth application is reachable and executes in the observed mobile authorization flow. Supabase authentication evidence showed successful TOTP challenges for `markjohnsonbanatao888@gmail.com` at 15:37:01Z, 15:37:15Z, and 15:38:06Z. The later failing authorization flow around 15:45Z authenticated as `lawbatalla@gmail.com` and created three challenges against that separate TOTP factor, none verified.

Therefore the screenshot error is an account/factor mismatch, not a broken TOTP generator.

## Required flow

1. Establish Supabase session.
2. Call `/api/operator/session` and resolve active organization membership.
3. Display the authenticated account on the authorization page.
4. Require role `owner` for owner approval.
5. Compare authenticated email to the configured Pandora owner email.
6. On mismatch, fail closed and clear the local Supabase session before any MFA challenge.
7. Only then call `getAuthenticatorAssuranceLevel`, `listFactors`, and `challengeAndVerify`.
8. Only an AAL2 owner session may proceed to OAuth approval.

## Implemented patch

Canonical patch: `patches/2026-08-08-owner-account-binding.patch`.

The patch adds `ownerEmail` to the public same-origin auth configuration, displays `Signed in as <email>`, checks membership and owner identity before MFA, signs the wrong local session out, and adds a source-level regression test proving the membership check occurs before `getAuthenticatorAssuranceLevel()`.

## Verification

- Browser ESM syntax check: PASS.
- Owner-binding static assertions: PASS.
- New regression subtest `owner identity is bound before MFA challenge`: PASS.
- Six other source/package tests in the same test file: PASS.
- The final container smoke in that isolated recovery tree could not run because `dist/projectos-container-server.js` is absent; this is a missing-build-artifact condition, not an owner-binding assertion failure.

## Production gate

The currently observed production deployment is `dpl_8ZyJBv7oR4gC4krdo2eYfj6DKVMX`, sourced historically from commit `6faf1dd25cb12f6ff20aa4f9500658c285d3025f`. Under `SOURCE_AUTHORITY_POLICY.json`, that `mbanatao` repository is historical-only and cannot be used as the operational deployment source.

Do not replace production with the older preserved recovery snapshot merely to land this patch. The patch must be applied to a source tree reconciled into `pandora-rvw-314296438-20260820/pandoras-box`, built, preview-tested with positive owner and negative wrong-account paths, independently reviewed where required, and only then released with rollback evidence.

State: **implemented and source-tested; not deployed; not production-verified**.
