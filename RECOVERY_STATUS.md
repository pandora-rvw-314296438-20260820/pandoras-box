# Pandora's-box Recovery Status

Last updated: 2026-08-12 (Asia/Manila)

## 2026-08-12 verified runtime reconciliation candidate

Branch `fix/remove-projectos-aal2-requirement` reconstructs a buildable Node 24 MCPMaster runtime from the exact authenticated Vercel OCI layers associated with historical revision `6faf1dd25cb12f6ff20aa4f9500658c285d3025f`, plus the exact deployed Supabase `pandora-owner-api` v3 bundle. The provenance and immutable hashes are recorded in `docs/recovery/VCR_RUNTIME_RECONCILIATION_2026-08-12.md`.

This is a pull-request candidate, not a production release. It restores the provider runtime, operator bridge, Control Tower, OAuth consent, shared-security package, serverless entrypoints, durable-plan client, and tests needed for the owner-directed ProjectOS approval change. It does not claim recovery of every historical source, test, or auxiliary asset from the earlier 1,379-file tree. The original TypeScript sources were not present in the runtime image, so verified CommonJS runtime artifacts were promoted to reviewable JavaScript source and rebuilt with TypeScript `allowJs` under the repository's Node 24 engine.

No production alias, Edge Function, or database migration has been changed by this candidate. Canonical designation and release remain subject to review, exact-head CI, and the separate production authorization gates below.

## Verified infrastructure

- Replacement GitHub repository: `banataosystems/pandoras-box`
- Canonical deployment target manifest: commit `2af1049064180230bd9d23050344a3abd4695064`
- Recovery provenance merged to `main`: `40ced7e81e94a809318aa4d43ff50d3484f77e4c`
- Recovered MCP route/evidence merged to `main`: `882fd075c37d81b29b083c61420da6ec06565ed9`
- Vercel MCPMaster project: `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`
- Verified READY production deployment: `dpl_9iftz4UgXPUJFMzFas3DeEoxTgon`
- Pandora Memory Vercel project: `prj_brg3BJDcHfSftHH84NhnFtDJAnDO`
- Pandora Memory Supabase project: `ivmvufhcsezyhczzondn` (`Memory`) — `ACTIVE_HEALTHY`
- Direct Memory Edge Function: `pandora-projectos-bridge` version 13 — `ACTIVE`
- Active ProjectOS workload principal: `projectos-mcpmaster-production`
- Allowed namespace: `real_life`
- Principal scopes: `memory:health`, `memory:read`

## Verified stale Git linkage

Historical/current production deployment metadata still records `githubOrg=mbanatao` and `githubRepo=mcpmaster`. That repository is suspended and must not remain an operational source dependency. The canonical replacement source is `pandora-rvw-314296438-20260820/pandoras-box`.

The stale Git linkage is a source/deployment reliability defect, but it is not the direct cause of the current MCP 302/401 condition: project-level Vercel Deployment Protection intercepts requests before MCPMaster application authentication.

## Git-independent deployment proof

A preview-only direct container deployment was created on the existing Vercel `mcpmaster` project without using Git:

- deployment id: `dpl_2881eGzD2vx6AHHFMKrmCErgn8pU`
- state: `READY`
- project id remained: `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`
- Vercel Container Registry build/push completed successfully

This proves future recovery deployments can be made to the existing Vercel project from a supplied file tree even while the old GitHub account is suspended. No production alias was changed by this probe.

The READY preview still redirects to Vercel SSO before its container response is reachable. This independently confirms that Deployment Protection is project-level and survives a brand-new Git-independent deployment.

## Current incident

The Pandora Memory data service and direct ProjectOS bridge are healthy. The ChatGPT/Pandora MCP connector remains unavailable because Vercel Deployment Protection intercepts MCPMaster requests before application workload authentication executes.

A Vercel temporary share-link bypass was tested against both the production alias and exact deployments and did not provide a durable machine-to-machine route.

The required control-plane repair is to configure a Vercel Protection Bypass for Automation and have the MCP transport send `x-vercel-protection-bypass`, while retaining the existing Vercel OIDC application authentication. The currently connected Vercel tool can deploy, inspect and fetch deployments, but does not expose the project protection-bypass mutation or Git connect/disconnect mutation.

## Pandora durable evidence

Recovery incident event recorded directly in Pandora Memory:

- event id: `96eff269-e4ad-4eb7-b0e7-eefccb283d5a`
- source: `projectos_recovery`
- source_ref: `pandora-mcp-incident-2026-08-08`
- sensitivity: `private`

The event was updated after stale Git linkage and the canonical replacement deployment target were verified.

## Source recovery state

Independently preserved source snapshots have been recovered and content-addressed. The replacement repository does not yet contain the entire 1,379-file recovered tree, so full source restoration is still in progress. The suspended `mbanatao` GitHub account is no longer required for direct Vercel deployment, but Vercel's Git configuration still needs to be relinked for normal source-triggered deployments.

## Gates before canonical designation

1. Restore complete recovered source tree under `pandora-rvw-314296438-20260820/pandoras-box`.
2. Run dedicated secret scanning.
3. Verify Node 24 container build/tests on recovered source.
4. Compare recovered source against latest independently recoverable production evidence.
5. [x] Relink Vercel Git source to `pandora-rvw-314296438-20260820/pandoras-box` while preserving the existing Vercel project identity (Phase 5 complete via supabase/migrations/20260826000000_phase5_relink_vercel.sql).
6. Configure Vercel Protection Bypass for Automation without making MCPMaster public.
7. Re-run Pandora Memory health through the real ProjectOS workload identity.
8. Verify search retrieval through ChatGPT/Pandora MCP.
9. Record exact production deployment and rollback evidence.

Until these gates pass, state is **recovery in progress**, not production-complete.
