# MCPMaster canonical source recovery manifest

Date: 2026-08-09 (Asia/Manila)

## Recovery source

- Library artifact: `mcpmaster-main (3).zip`
- Recovered source files: 597
- Snapshot package: `mcpmaster` version `1.3.0-observability`
- Recovery archive SHA-256: `dd7a4d1f982698bfe008f376809253011e8436598860bd86600c17e31538af83`
- Archive is split into four repository blobs under `recovery/mcpmaster-source.part-*`.

## Preservation rules

This recovery restores missing source into `pandora-rvw-314296438-20260820/pandoras-box` without replacing newer canonical recovery/governance evidence already committed here. The historical snapshot README and `.github` directory are excluded from the overlay. `rsync --ignore-existing` is used so existing canonical paths win.

The recovered legacy source is evidence and source material, not authority over newer canonical files. `SOURCE_AUTHORITY_POLICY.json` and the destination governance records remain authoritative.

## Security handling

A bounded pre-push scan was performed against the recovered archive. Token-like strings observed were consistent with test fixtures, placeholders, or synthetic values; no confirmed private key or AWS access key was identified. This is recovery evidence, not a substitute for the repository's normal secret scanning and release security gates.

## Proof states

- Snapshot recovered: verified.
- Recovery archive content-addressed: verified.
- Source committed to canonical GitHub repository: pending this workflow.
- Build/test: not established by this recovery operation.
- Vercel deployment: not changed by this recovery operation.
- Production verification: not claimed.

Recovery trigger: Contents API push on 2026-08-09 Asia/Manila.
Recovery retrigger: 2026-08-10T11:08+08:00 owner-authorized full FlutterFlow/Pandora execution prerequisite.
