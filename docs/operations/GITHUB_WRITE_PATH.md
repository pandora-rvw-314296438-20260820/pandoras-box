
# Canonical GitHub write path

## Purpose

Pandora must never fall back to editing `main` directly when a connected GitHub App lacks write permission.

## Provider evidence observed on 2026-10-01

The ChatGPT GitHub connector could read the public canonical repository `pandora-rvw-314296438-20260820/pandoras-box` but its visible installation was attached to a different GitHub account. A direct create-ref attempt therefore returned `403 Resource not accessible by integration`.

The canonical Supabase Vault transport was independently verified against the same repository: it read the exact `main` SHA, created a temporary `chatgpt/*` ref with HTTP 201, and deleted it with HTTP 204. No write to `main` occurred.

## Permanent governed fallback

Use:

`private.pandora_github_governed_write_v1(expected_base_sha, branch_suffix, files, commit_message, idempotency_key, pr_title, pr_body)`

Properties:

- service-role only;
- fixed to the canonical Pandora repository;
- uses `Github_supabase` only inside Supabase Vault;
- requires the exact current `main` SHA and fails on a stale base;
- accepts bounded UTF-8 create/update/delete operations;
- supports optional exact blob-SHA fencing;
- rejects common credential material and secret-file paths;
- creates a new `chatgpt/*` branch without force;
- creates a pull request against `main`;
- verifies branch and PR provider readback;
- stores an idempotent durable receipt;
- never merges, deploys, or claims CI success.

Direct GitHub App permission repair remains desirable for native connector writes, but it is no longer a blocker for governed Pandora source work.
