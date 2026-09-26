
# Coordinator zero-approval policy alignment

Owner decision: 2026-09-26. Task: `OPS-COORDINATOR-APPROVAL-POLICY-20260926`.

GitHub's active repository ruleset requires zero approving reviews. The coordinator previously added a second, unsatisfiable requirement for an independent exact-head APPROVED review. The only write-authorized repository collaborator is the PR-author account, so that coordinator-only requirement could not be satisfied without changing repository access merely to manufacture an approval.

This change removes only that second approval requirement. It does not remove review safety or release controls.

Preserved gates:

- current PR/head/base identity and exact-source binding;
- canonical snapshot and coordinator decision fencing;
- required CI, security and dependency checks;
- unresolved review-conversation protection in the GitHub ruleset;
- a current write-authorized independent `CHANGES_REQUESTED` review still blocks PASS and merge;
- repository mergeability and exact provider check identity;
- merge claim fencing and provider merge readback;
- no self-approval fabrication, reviewer impersonation or branch-protection bypass.

Approvals may still be submitted and retained as evidence, but the coordinator does not require one when GitHub itself requires zero.

Rollback: restore the prior coordinator source only if GitHub's approval policy changes and the repository has a genuinely satisfiable independent-review model. Do not silently reintroduce an approval requirement without updating this policy and its tests.
