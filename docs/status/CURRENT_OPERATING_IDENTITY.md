# Current operating identity

Observed: 2026-08-28  
Classification: **current operational identity** (not a historical status surface)

`RECOVERY_STATUS.md` and `DEPLOYMENT_TARGET.md` remain integrity-bound historical snapshots. They must not be cited as current project state. Live status is authenticated `GET /api/operator/status`.

## Canonical source

| Field | Value |
| --- | --- |
| GitHub repository | `pandora-rvw-314296438-20260820/pandoras-box` |
| Branch | `main` |
| Proven green SHA at capture | `cc0421f4461219bd6a9e864295d70743e8cd32dc` |
| Memory repository | `banataosystems/pandoras-box-memory` |
| Operating source of truth | Pandora Memory hard-canon + exact committed source on this repository |

mbanatao/* is historical evidence only. `banataosystems/Pandoras-box` is a recovery-era sibling name, not the operational Git remote.

## Canonical Vercel identity (preserve, do not recreate)

| Field | Value |
| --- | --- |
| Project name | `mcpmaster` |
| Project ID | `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk` |
| Team ID | `team_IcdJUnzLi5wUN1GD8ALHyjF7` |
| Production origin | `https://mcpmaster.vercel.app` |
| Memory origin | `https://pandorasbox-memory.vercel.app` |

Keep this project ID and production alias. Live Vercel provider readback on 2026-08-28 confirms the existing `mcpmaster` project is linked to `pandora-rvw-314296438-20260820/pandoras-box`; production deployment metadata binds `main` to this repository. Do not create a replacement production identity unless a separately reviewed migration is approved.

Legacy Vercel team or deployment URL slugs containing `mbanatao` are not Git source authority. Current deployment metadata must bind `githubOrg=pandora-rvw-314296438-20260820` and `githubRepo=pandoras-box` before it can contribute release evidence.

## Canonical Supabase identity

Governed Edge functions and migrations in this repository are the source contract. Live project refs remain provider-authoritative only when bound to this exact source SHA/tree by an immutable receipt.

## Remaining control-plane proof gates

1. Preserve the existing Vercel Git binding to `pandora-rvw-314296438-20260820/pandoras-box` `main` and fail closed on source drift.
2. Verify the required automation/protection posture without making the application public or weakening branch protection.
3. Keep Vercel OIDC at the application layer.
4. Capture exact production deployment + distinct rollback receipts before calling production verified.
5. Bind live Supabase migration/function evidence to the exact release source.
6. Capture the required physical Android Wi-Fi and mobile-data journey receipts.
7. Require separately trusted external review and the repository-defined final owner authorization before release authority is complete.

Never commit bypass secrets, access tokens, service-role keys, or OIDC tokens.
