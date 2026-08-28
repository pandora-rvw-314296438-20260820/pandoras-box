# Current recovery posture

Observed: 2026-08-28  
Classification: **current recovery posture**  
Historical snapshot: `RECOVERY_STATUS.md` (integrity-bound, observed through 2026-08-12)

## What is restored

- Replacement operating Git repository exists and is protected: `pandora-rvw-314296438-20260820/pandoras-box`.
- Source authority policy fail-closes `mbanatao/*`.
- Exact-head CI on `main@cc0421f4461219bd6a9e864295d70743e8cd32dc` is green for:
  - ProjectOS security regression (`node24`)
  - Canonical release source contract
  - Windows worker contract
  - Pandora mobile exact-source gate
- Native Android working UI (screenshot-faithful Simple Mode) landed via PR #6.
- Zip-synced authority files landed via PR #23 without breaking lockfile/CI contracts.

## What remains recovery, not production-complete

- Vercel Git metadata may still name the suspended `mbanatao` account.
- Machine MCP may still be intercepted by Vercel Deployment Protection.
- Canonical pack `productionVerified` still requires bound Vercel production + rollback receipts and physical Android Wi-Fi/mobile-data receipts.
- Historical 1,379-file tree completeness is not claimed.

## Rules

1. Do not rewrite `RECOVERY_STATUS.md` to look current. Quarantine it.
2. Do not treat a green CI SHA as a production release.
3. Do not select `mbanatao/*` or a new Vercel project as the operational identity.
4. Next recovery work is Git relink + protection bypass + receipt capture, then product screens on this green foundation.
