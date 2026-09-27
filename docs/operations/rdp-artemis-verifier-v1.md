# RDP ARTEMIS verifier v1

Pandora uses the authorized Windows RDP as an independent machine-verification node for source releases.

## Separation of duties

The existing worker `pandora-rdp-windows-01` remains an execution worker. It does not gain release verification authority.

The verifier is a separate logical Operations identity:

- worker: `pandora-rdp-artemis-01`
- principal: `rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1`
- engine: `rdp`
- lane: `release`
- capabilities: `release.verify`, `provider.readback`, `rdp.release.verify`
- capacity: 1

The verifier has no source-write, runtime-deploy, merge, spend, OAuth, client-activation or Memory-promotion capability.

A verifier receipt is admissible only when the Operations verifier principal differs from the task builder principal and worker identity. Existing `pandora_ops_record_verification_v1` and `pandora_ops_verify_v1` enforce that separation.

## Machine review contract

`scripts/operations/rdp-artemis-verifier.ps1` receives an already-created detached worktree plus an exact base SHA, exact head SHA, PR number, and explicit test paths.

It verifies:

1. detached worktree HEAD equals the requested head SHA;
2. the worktree is clean;
3. the requested base is an ancestor of the candidate head;
4. `git diff --check` passes;
5. every supplied Node test exits successfully;
6. every changed non-test JavaScript file passes `node --check`.

The script hashes the exact diff and combined test/syntax output and writes a JSON receipt outside the repository.

It does not commit, push, merge, rebase, deploy, authorize spend, write Memory, or mutate provider state.

## Review evidence

The receipt binds:

- machine identity;
- PR number;
- base SHA;
- head SHA;
- decision;
- diff SHA-256;
- stdout SHA-256;
- changed-file list;
- exact test results;
- explicit `sourceMutationPerformed=false`;
- explicit `releaseMutationPerformed=false`.

The receipt may be recorded through the canonical Operations verification receipt boundary. Recording a review does not itself merge or release a PR; owner release authorization and the governed coordinator path remain separate.

External model reviewers such as CodeRabbit, Gemini, Kimi, Nova, or Claude are supplemental. Their unavailability must not erase a valid RDP machine review, and an RDP review must not fabricate model review evidence.
