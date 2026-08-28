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

`mbanatao/*` is historical evidence only. `banataosystems/Pandoras-box` is a recovery-era sibling name, not the operational Git remote.

## Canonical Vercel identity (preserve, do not recreate)

| Field | Value |
| --- | --- |
| Project name | `mcpmaster` |
| Project ID | `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk` |
| Team ID | `team_IcdJUnzLi5wUN1GD8ALHyjF7` |
| Production origin | `https://mcpmaster.vercel.app` |
| Memory origin | `https://pandorasbox-memory.vercel.app` |

Keep this project ID and production alias. Relink Git to `pandora-rvw-314296438-20260820/pandoras-box` `main`. Do not create a replacement production identity unless a separately reviewed migration is approved.

Stale provider metadata `githubOrg=mbanatao` / `githubRepo=mcpmaster` is evidence of incomplete Git relink. It is not source authority.

## Canonical Supabase identity

Governed Edge functions and migrations in this repository are the source contract. Live project refs remain provider-authoritative only when bound to this exact source SHA/tree by an immutable receipt.

## Required control-plane repairs (outside Git)

1. Disconnect Vercel `mcpmaster` from any `mbanatao/*` Git source.
2. Connect the same project to `pandora-rvw-314296438-20260820/pandoras-box` `main`.
3. Enable Protection Bypass for Automation for machine MCP without making the app public.
4. Keep Vercel OIDC at the application layer.
5. Capture exact production deployment + distinct rollback receipts before calling production verified.

Never commit bypass secrets, access tokens, service-role keys, or OIDC tokens.
