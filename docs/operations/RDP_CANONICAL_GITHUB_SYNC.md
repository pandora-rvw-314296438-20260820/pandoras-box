# Pandora RDP canonical GitHub sync

## Purpose
The Windows RDP is an execution workstation, not durable source authority. GitHub remains canonical. A completed worker checkpoint must be published and read back before more source work proceeds.

## Write authority
Repository mutation attempts the installed GitHub App first. If GitHub returns a permission denial, the RDP publisher uses the service-role-only Supabase transport `pandora_rdp_github_request_v1`, which calls the existing Vault-backed `Github_supabase` integration. No GitHub PAT, OAuth write credential, API key, or Vault secret is returned to the RDP.

## RDP machine authentication
The RDP publisher authenticates to the bounded Edge bridge with a random machine proof stored only as a Windows DPAPI CurrentUser blob at `C:\Pandora\security\rdp-sync-machine-proof.dpapi`. Only its SHA-256 digest is server-side. The proof is never committed.

## Hard boundaries
The transport cannot mutate `main`, cannot force-update refs, cannot write outside the canonical `pandoras-box` repository, rejects secret-shaped source material, requires an exact parent head, verifies the resulting Git tree, and performs provider readback after ref update.

## Worker flow
For managed branches (`chatgpt/*`, `fix/*`, `repair/*`, `recovery/*`, and Enterprise UI branches), the shared post-commit hook invokes `C:\Pandora\tools\pandora-rdp-sync-client.ps1 -Action publish-head`. If GitHub normalizes commit metadata and creates a different commit SHA, the client reconstructs the canonical provider commit locally, preserves the original local commit under `refs/pandora-local/...`, then moves the local branch to the provider SHA. The Git tree must remain exact.

A failed publication writes a per-worktree `PANDORA_SYNC_FAILED` marker. The pre-commit hook blocks subsequent commits until the failed checkpoint is repaired. Native `git push` from the RDP is blocked; source publication must use the governed transport.

## Recovery evidence
Before convergence work on 2026-09-17, an all-refs local bundle was created at `C:\Pandora\recovery\rdp-sync-20260917\pandoras-box-all-refs-20260917.bundle`. Its SHA-256 is `0668c9fe6ff1253c3f919bd2d215fab7f68eebc0831e1c191ee6f7811c59ee8b` and its size is 22,055,050 bytes. The bundle is local recovery evidence and must not be committed because historical Git objects may contain superseded or sensitive material.

## Smoke verification
The isolated branch `recovery/rdp-sync-smoke-20260917` was created from canonical main `7eb4898cb1e200cfb44c4a2120ebd89ab395b1dd`. The installed post-commit hook published a third checkpoint through the Vault-backed transport and read back canonical provider SHA `f836d1e9db9c0c6675200b08003eaa0a58c66b7d` with `exact_tree=true`.
