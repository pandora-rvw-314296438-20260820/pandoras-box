# Pandora RDP canonical GitHub sync — RETIRED

## Status

This path was retired on 2026-09-19 because the former Windows/AWS RDP machine is no longer an accessible or authorized Pandora execution node.

Pandora must not depend on that machine for source publication, builds, Android verification, CI, or recovery. Canonical GitHub and Supabase provider paths remain authoritative.

## Enforced retirement

- The repository self-hosted runner `pandora-ci-windows-01` was removed from GitHub.
- The stale `rdp-ec2amaz-spae2vg` local-worker registration was deleted from Supabase.
- `pandora_rdp_github_request_v1` and `pandora_rdp_memory_github_request_v1` are retained only as fail-closed tombstones that raise `PANDORA_RDP_TRANSPORT_RETIRED`.
- Anonymous and authenticated execution privileges on those RPCs are revoked.
- `scripts/rdp-sync/pandora-rdp-sync-client.ps1` is a fail-closed tombstone and cannot publish.
- Active GitHub workflows must not use `self-hosted` runners.

Historical references below are evidence only and do not grant execution authority.

## Historical evidence

The retired RDP previously acted as a workstation while GitHub remained canonical. It used a bounded Vault-backed transport and local machine proof. A recovery bundle and prior smoke-validation records may still exist in history, but none of them are an active Pandora execution path after this retirement.
