# Canonical deployment target

Updated: 2026-08-08 (Asia/Manila)

## Source of truth

- Canonical GitHub repository: `pandora-rvw-314296438-20260820/pandoras-box`
- Canonical branch: `main`
- The suspended `mbanatao/mcpmaster` repository is recovery provenance only and MUST NOT be used as an operational deployment source.

## Vercel target

- Existing Vercel project: `mcpmaster`
- Project ID: `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`
- Team ID: `team_IcdJUnzLi5wUN1GD8ALHyjF7`
- Production resource origin: `https://mcpmaster.vercel.app`

The Vercel project ID and project name should remain unchanged during Git relinking so the existing Vercel OIDC workload identity remains stable. The Git source must be changed to `pandora-rvw-314296438-20260820/pandoras-box` rather than creating a new production identity unless a separately reviewed migration is approved.

## Verified stale linkage

Observed historical/current Vercel deployment metadata still references `githubOrg=mbanatao` and `githubRepo=mcpmaster`. This stale Git linkage can prevent reliable source-triggered deployments while that GitHub account is suspended.

It is not, by itself, the cause of the current MCP 401: Vercel Deployment Protection is intercepting the request before MCPMaster application authentication executes.

## Required production repair

1. Disconnect the Vercel `mcpmaster` project from the suspended Git repository.
2. Connect the same Vercel project to `pandora-rvw-314296438-20260820/pandoras-box`, branch `main`.
3. Preserve the existing Vercel project ID and production aliases.
4. Enable Vercel Protection Bypass for Automation for machine-to-machine MCP access.
5. Configure the ChatGPT/Pandora MCP transport to send `x-vercel-protection-bypass` without storing the secret in GitHub or Pandora Memory.
6. Retain Vercel OIDC validation at the application/Pandora bridge layer.
7. Verify `/mcp`, Pandora `memory.health`, retrieval, exact production deployment, and rollback evidence before declaring recovery complete.

## Safety

Never commit the Vercel automation bypass secret, Vercel access tokens, Supabase service-role keys, OIDC tokens, or any other credentials to this repository or semantic memory.
