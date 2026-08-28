# Pandoras-box

Canonical recovery repository for MCPMaster / Pandora's-box.

## Source authority

Pandora Memory hard-canon records are the contextual authority consumed by the live status pack; they are not a standalone current-status surface. The canonical source repository for MCPMaster / Pandora's-box is `pandora-rvw-314296438-20260820/pandoras-box`; the canonical Memory source repository is `banataosystems/pandoras-box-memory`.

Every repository under the legacy `mbanatao/*` owner namespace is **operationally blacklisted**. Those repositories may be read only for historical provenance, source recovery, hash comparison, parent lineage, deployment evidence, and rollback evidence. They must not determine current state, become a default Git remote, receive normal new work, or authorize a new release.

Machine-readable enforcement policy: `SOURCE_AUTHORITY_POLICY.json`  
Human governance record: `docs/governance/DEPRECATED_SOURCE_DENYLIST.md`

Legacy Vercel hostnames or deployment metadata containing `mbanatao` do not make the old Git repositories canonical. Existing network aliases may remain temporarily for OAuth, runtime continuity, or rollback until separately migrated and verified.

## Current status

The only current status surface is the authenticated `GET /api/operator/status` canonical pack. It refreshes provider evidence on demand, is never cached as current, and returns HTTP `503` with explicit blockers whenever Memory freshness, GitHub integration-SHA checks, separately trusted external review, Vercel source/deployment/rollback binding, Supabase parity, or production journey proof is missing.

Pack contract: `docs/status/CANONICAL_STATUS_PACK.md`
Exact 41-PR convergence registry: `docs/status/OPEN_PR_TRIAGE.json`
Preserved stale surfaces: `docs/status/HISTORICAL_STATUS_SURFACES.json`

`RECOVERY_STATUS.md`, `DEPLOYMENT_TARGET.md`, the checked-in Control Tower status/release JSON files, and dated roadmap execution sections are historical evidence. They must not determine current state or authorize work.

## Recovery rules

- Preserve source history and recovery evidence; do not overwrite evidence to make state look cleaner.
- Never store credentials, tokens, private keys, OIDC material, customer data, or other secrets here.
- Distinguish documented, implemented, tested, deployed, and production-verified state.
- Production deployment and Pandora Memory health must be independently verified before being marked complete.
- Fail closed if any tool tries to restore operational authority to a blacklisted legacy source without a new explicit owner decision.

## FlutterFlow readiness provider

MCPMaster includes a read-only FlutterFlow Project API provider. The non-secret production binding is pinned to project `pandoras-box-gj9hnb`; its bearer token must be supplied only through the protected `FLUTTERFLOW_API_TOKEN` runtime secret. The provider registers no update, export, deploy, or release operation and never interprets Project API access alone as deployment readiness.

See `docs/integrations/FLUTTERFLOW_READINESS_PROVIDER.md` for configuration, evidence gates, and rollback.
