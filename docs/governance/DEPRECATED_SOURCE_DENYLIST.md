# Deprecated Source Denylist

**Effective:** 2026-08-28  
**Project:** `mcpmaster-pandoras-box`  
**Mode:** fail closed

This file is the current denylist. It is not a historical status surface. `RECOVERY_STATUS.md` remains an integrity-bound snapshot and must not be rewritten to look current.

## Canonical authority

- Operating source of truth: Pandora Memory hard-canon state.
- Canonical source repository: `pandora-rvw-314296438-20260820/pandoras-box`.
- Canonical Memory source repository: `banataosystems/pandoras-box-memory`.
- Canonical Vercel project: `mcpmaster` / `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`.
- Canonical production origin: `https://mcpmaster.vercel.app`.
- Live status: authenticated `GET /api/operator/status`.

`banataosystems/Pandoras-box` is a recovery-era sibling name. Keep it as evidence. Do not select it as the operational Git remote.

Current identity and recovery posture live in:

- `docs/status/CURRENT_OPERATING_IDENTITY.md`
- `docs/status/CURRENT_RECOVERY_POSTURE.md`

## Operationally blacklisted legacy sources

The following owner namespace is **historical evidence only** and must never be automatically selected as the current source, default remote, build source, release source, or project-status authority:

- every repository matching `mbanatao/*`, case-insensitively;
- all Vercel Git metadata identifying `githubOrg=mbanatao`, regardless of repository name.

This owner-wide rule supersedes the earlier named-repository denylist for `mbanatao/mcpmaster` and `mbanatao/Memory`.

Legacy hostnames containing `mbanatao` may remain reachable during migration or for OAuth/rollback continuity. A hostname is **not** proof that the legacy Git repository is canonical. Stale Vercel Git metadata is evidence of incomplete Git relink, not source authority.

Do not recreate the canonical Vercel project or production alias. Relink Git on the existing project.

## Forbidden uses

Legacy sources must not:

1. determine current project state;
2. become the canonical/default Git source;
3. receive new normal development work;
4. trigger or authorize a new production release;
5. be treated as proof of current source parity;
6. overwrite newer `banataosystems` or Pandora evidence;
7. be cited from integrity-bound historical status surfaces as if they were current.

## Permitted uses

Legacy sources and their preserved snapshots may be read only for:

- forensic comparison;
- content-hash verification;
- source recovery;
- parent-lineage preservation;
- rollback evidence;
- deployment provenance.

## Conflict rule

When evidence conflicts, resolve in this order:

1. newer verified evidence, after correcting Pandora;
2. Pandora hard-canon current state;
3. exact committed source/manifests in `pandora-rvw-314296438-20260820/pandoras-box`;
4. exact verified provider runtime evidence;
5. deprecated `mbanatao` sources as historical evidence only.

## Preservation rule

Do **not** delete old commits, deployment records, hashes, or recovery snapshots merely to remove confusion. They are quarantined from operational authority, not erased.

Any tool, agent, or human process that attempts to use a deprecated source operationally must fail closed and require an explicit, separately recorded owner decision to reverse this policy. Direct reads may remain available only when the caller deliberately names a repository for one of the permitted historical purposes above; discovery, routing, and every mutation exclude the owner namespace.
