# Vercel legacy preview projects disabled — 2026-09-06

Two legacy proof projects were still emitting failing Vercel commit statuses for `pandoras-box` after `mcpmaster` previews were disabled:

- `pandora-worker-e-preview-proof-20260829`
- `pandora-task85-git-proof-20260901`

Both were patched through the Vault-backed Vercel control path with `previewDeploymentsDisabled=true`, with provider HTTP 200 readback. This preserves the production `main` deployment while stopping obsolete preview proof projects from consuming Hobby build quota or poisoning PR status.
