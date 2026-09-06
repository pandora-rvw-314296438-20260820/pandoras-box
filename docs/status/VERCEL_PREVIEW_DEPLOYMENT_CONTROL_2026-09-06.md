# Vercel preview deployment control — 2026-09-06

Provider project: `mcpmaster` (`prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`).

The Vercel project was patched through the Vault-backed provider control path with `previewDeploymentsDisabled=true`. The provider returned HTTP 200 and readback returned the setting as enabled.

Production branch remains `main`; this change stops PR/feature-branch preview builds from consuming the Hobby build-rate quota.
