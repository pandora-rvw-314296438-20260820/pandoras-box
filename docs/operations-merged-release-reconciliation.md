# Merged Facebook release reconciliation

When a handed-off Facebook task refers to an earlier commit of a PR that later
merged, the task must not inherit a PASS for the final PR head. This adapter
adopts the provider-confirmed final head into a new verification generation and
preserves the original handoff and verification receipts.

## Preconditions and scope

- Canonical repository: `pandora-rvw-314296438-20260820/pandoras-box`, base `main`.
- Active organization/project binding, unpaused workspace, no unreleased task lease.
- Exact task generation, revision, specification digest, and prior head.
- A genuine completed handoff for that task, generation, builder, head, and PR.
- A connected, acknowledged release worker with a fresh heartbeat, provider
  readback capability, and a principal distinct from the builder.
- GitHub confirms the merged PR, merge event, final-head parent of the merge
  commit, original-head and base ancestry, and merge ancestry in current main.
- Squash/rebase merges are intentionally unsupported and retain the hold.

## Authenticated operation

Deploy the reviewed migration and matching `mcpmaster-supabase-control` source
through the existing release process before invoking the action. The control
gateway verifies production Vercel OIDC, pins organization/project scope and
the native release worker identity, and rejects caller-selected identities.

The request contains exactly:

```json
{
  "action": "operations_merged_release_reconcile",
  "requestId": "<unique UUID; reuse for an exact retry>",
  "taskId": "<existing task key>",
  "generation": 4,
  "revision": 12,
  "taskSpecDigest": "<live 64-character specification digest>",
  "expectedHeadSha": "<live 40-character old head>"
}
```

Values above are illustrative. Read the live task immediately before preparing
the request. Do not register or impersonate a worker from an owner/model route.
No automatic cron reconciliation or caller-supplied provider evidence is added.

Success returns `state: verifying`, the new generation, final head, immutable
receipt ID, and `completionGranted: false`. Exact replay is accepted only while
the adopted task generation/head remain current. Reusing a request ID with
different inputs is rejected.

## Verification and release

The append-only receipt records the entire prior task and bounded provider
readbacks. Existing handoff and historical verification records are unchanged.
A fresh independent verification receipt for the new generation and final head
is required before normal completion. Production tasks still require their
existing approval, deployment, and rollback evidence.

Tests use synthetic workers and a GET-only GitHub fixture inside PGlite. Those
fixtures are not live worker registration or production verification evidence.
Run `node --test test/pandora-operations-merged-release-reconciliation-db.test.js`
and the surrounding Operations Room tests, then run ARTEMIS at the immutable
PR head. ARTEMIS machine checks do not replace independent release review.

## Failure and recovery

Unknown provider outcomes, divergent ancestry, active leases, scope changes,
stale inputs, and changed final readback leave the original task unchanged.
Timeline lookup is bounded to ten pages of 100 events. Missing evidence retains
the hold. The function performs GET requests only and cannot merge or deploy.

To disable the adapter, redeploy the previously approved gateway version.
Do not erase receipts or reverse a task generation as a rollback. Any later
reconciliation must use current task state and the ordinary independent
verification/release process.
