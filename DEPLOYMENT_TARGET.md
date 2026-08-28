# Canonical deployment target

Updated: 2026-08-28 (Asia/Manila)

## Source of truth

- Canonical GitHub repository: `pandora-rvw-314296438-20260820/pandoras-box`
- Canonical branch: `main`
- `mbanatao/mcpmaster` is recovery provenance only and MUST NOT be used as an operational deployment source.
- Production changes must be traceable to merged canonical source and provider readback.

## Vercel target

- Existing Vercel project: `mcpmaster`
- Project ID: `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`
- Team ID: `team_IcdJUnzLi5wUN1GD8ALHyjF7`
- Canonical customer-facing production origin: `https://pandoras-box-system.vercel.app`
- Compatibility alias: `https://mcpmaster.vercel.app`
- Additional project aliases may remain while they resolve to the same Vercel project identity.

The Vercel project ID and project name remain unchanged so the existing workload identity and rollback history remain stable. The Git source is the canonical Pandora repository and `main`; do not create a replacement Vercel project merely to rename the product-facing domain.

## Supabase targets

Pandora intentionally uses two Supabase projects with separate responsibilities:

- Primary application/control plane: `jcyqixttuebxqqfkjonq`
- Pandora Memory/runtime boundary: `ivmvufhcsezyhczzondn`

Do not collapse these projects into one database. Application and Edge Function changes for the primary control plane belong to `jcyqixttuebxqqfkjonq`; Memory-specific schema and runtime changes belong to `ivmvufhcsezyhczzondn` and its source repository.

Canonical governed Edge Functions defined by repository configuration must keep their declared JWT boundary. `mcpmaster-supabase-control` is the documented custom-workload-auth exception and validates Vercel OIDC in the function path rather than using a user JWT at the Supabase gateway.

## Current provider truth

As verified on 2026-08-28:

- Vercel is linked to `pandora-rvw-314296438-20260820/pandoras-box`.
- Source-triggered deployments from `main` are working on the existing `mcpmaster` Vercel project.
- `pandoras-box-system.vercel.app` and `mcpmaster.vercel.app` resolve within that same project identity.
- The prior suspended-repository linkage described in older recovery notes is historical and no longer an active repair instruction.
- `pandora-user-admin` is deployed from canonical merged source with `verify_jwt=true`.

## Deployment rules

1. Merge significant source changes through an independently reviewable PR/checkpoint.
2. Preserve the existing Vercel project ID, Supabase project refs, and intentional two-project boundary.
3. Deploy Edge Functions from merged canonical source; do not hand-edit production-only copies.
4. Keep service-role keys, PATs, Vercel tokens, OIDC tokens, and protection-bypass values out of Git and semantic memory.
5. Treat temporary recovery transports/functions as noncanonical unless a current source dependency proves they are still required.
6. Verify exact source SHA, required GitHub checks, Supabase migration/function parity, provider deployment state, and runtime health before declaring a release converged.

## Safety

Never commit GitHub PATs, Vercel access tokens, Supabase service-role keys, OIDC tokens, automation-bypass secrets, or any other credentials to this repository or semantic memory.
