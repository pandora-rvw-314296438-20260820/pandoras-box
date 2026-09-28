# Merged Facebook source reconciliation and verification

When a handed-off source task refers to an earlier commit of a PR that later
merged, the task must not inherit a PASS for the final PR head. Reconciliation
adopts the provider-confirmed final head into a new verification generation and
preserves the original handoff and verification receipts. A separate, narrowly
scoped action can then complete FB-025 source acceptance from GitHub evidence.

## Scope and production hold

- Canonical repository: `pandora-rvw-314296438-20260820/pandoras-box`, base `main`.
- Reconciliation rejects FB-012, any task with risk `production`, and any task
  with verification profile `production_release` before provider reads or mutation.
- Source verification supports only FB-025, PR 786, final head
  `3e38b571ae963cc663e622fc1a75d5578b6fb7a2`, generation 5, and profile
  `backend_service`. The audited specification digest is
  `a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc`.
- The pinned source base is `f4675344f99a3d2cc23a9c360c9512826e921c5c`.
  The exact acceptance criterion is: "Schema distinguishes verified fact, user
  decision, provider evidence, inference, assumption, and superseded information."
  A changed specification or acceptance list requires a separate review.
- Squash/rebase merges are unsupported and retain the hold.
- Neither action merges code, deploys a service, authorizes spend, promotes
  Memory, or proves delivery of dependent Facebook tasks.

FB-012 deliberately retains its previous native state and head. Production
reconciliation must wait for a separately reviewed path that binds genuine owner
approval and rollback evidence to the exact task generation and head. The older
generic verification RPC's nonempty reference checks do not establish that
binding. Do not call it manually to bypass this hold or broaden the generic
gateway task allowlist.

## Preconditions

The operations require an active organization/project binding and an unpaused
workspace. Reconciliation also requires:

- Exact current task generation, revision, specification digest, and prior head.
- No unreleased task lease and a genuine completed handoff for the same task,
  generation, builder, head, and PR.
- A connected, acknowledged release worker with a fresh heartbeat, provider
  readback capability, and a principal distinct from the builder.
- GitHub confirmation of the merged PR, merge event, final-head parent of the
  merge commit, original-head and base ancestry, and merge ancestry in main.

Deploy the reviewed migration, matching `mcpmaster-supabase-control` source,
and `api/operations-native-worker.ts` through the existing release process. The gateway
verifies production Vercel OIDC, pins organization/project scope and the native
release worker identity, and rejects caller-selected identities. The underlying
RPCs are service-role-only. Do not register or impersonate a worker from an
owner/model route; use the existing authenticated native release execution path.

## Normal native-worker execution

The existing `/api/operations-native-worker` entrypoint remains authenticated by
its existing cron secret, signed wake, or pre-authorized manual wake. After its
ordinary workload-identity and paused-workspace checks, it selects a handed-off
or verifying FB-025 from the native snapshot, refreshes the release heartbeat,
and submits exactly:

```json
{ "action": "operations_merged_release_source_step" }
```

The gateway fixes the native release identity and calls
`pandora_ops_merged_release_source_step_v1`. The database selects the live task
and immutable receipt. It reconciles the pinned generation-4/revision-12 old
head and verifies generation 5 in one transaction, or reuses an already adopted
receipt. Provider failure rolls back both adoption and verification.

The runner validates the complete response's task, generation, final head,
reconciliation receipt ID, and nested acceptance result. It skips tasks already
complete so FB-026 and unrelated work can proceed. Explicit idle/held results
allow unrelated work to continue; unknown responses or provider failures return
an error. The source step is now part of normal authenticated wakes after the
reviewed deployment; it does not require a new identity or a model to forge a
worker call. The release process must verify the deployed source and the actual
native task/receipt after a wake before claiming live completion.

## Lower-level reconciliation action

The request contains exactly these fields:

```json
{
  "action": "operations_merged_release_reconcile",
  "requestId": "<unique UUID; reuse for an exact retry>",
  "taskId": "FB-025",
  "generation": 4,
  "revision": 12,
  "taskSpecDigest": "a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc",
  "expectedHeadSha": "5448f61715b139dff7bbedf9d3056ca80cadb585"
}
```

These values are pinned to the audited historical FB-025 release. The native
runner uses the atomic source-step action above; the lower-level actions also
accept no caller-supplied provider evidence.

Success returns `state: verifying`, the new generation, final head, immutable
receipt ID, and `completionGranted: false`. Exact replay is accepted only while
the adopted task generation/head remain current. Reusing a request ID with
different inputs is rejected. The append-only receipt records the entire prior
task and bounded provider readbacks; historical handoffs and reviews remain intact.

## Lower-level FB-025 source verification

Use the new task generation, digest, head, and reconciliation receipt from the
successful reconciliation. The request contains exactly:

```json
{
  "action": "operations_merged_release_verify_source",
  "taskId": "FB-025",
  "generation": 5,
  "taskSpecDigest": "a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc",
  "expectedHeadSha": "3e38b571ae963cc663e622fc1a75d5578b6fb7a2",
  "reconciliationReceiptId": "<UUID returned by reconciliation>"
}
```

The action `operations_merged_release_verify_source` calls
`pandora_ops_verify_merged_release_source_v1`. It binds the live task's scope,
generation, pinned specification/acceptance, source risk/profile and head to the immutable
reconciliation receipt. It then fetches its own provider evidence:

- PR 786 is merged with the expected repository, base, and head. Its merge event
  and commit parents bind the reconciliation receipt's merge identity. The broker
  omits `merge_commit_sha` from PR responses, so that missing field is not proof.
- The exact-head check set is complete and bounded to 100 runs, has no duplicate
  names, and contains only completed success/neutral/skipped results. The five
  required source checks must succeed, including the pinned coordinator check.
- Full-review comment 5854323698 and final-head carry-forward comment 5855325039
  have the pinned CodeRabbit bot/app identity, timestamps, UTF-8 byte lengths,
  body SHA-256 digests, and review/head/blob anchors.
- The three FB-025 source files at the final head retain the reviewed blob SHAs.
- A final PR readback confirms the expected head, state, and merged status.
  The merge event and commit-parent proof establish merge identity.

The caller supplies no verdict, review reference, checks, approval or rollback
references. Only after these checks does the action construct normalized
provider evidence and atomically record and consume a native verification
receipt for the current generation. Existing native verifier admission still
applies. Inspect the returned native state and fresh provider/task readback;
successful reconciliation alone never means completion.

The pinned review evidence is intentionally specific to this historical
FB-025 release. A changed comment, absent check, another head, or another task
retains the hold and requires review; it is not an invitation to replace the
pinned evidence with caller-selected data.

## Validation, failures, and recovery

Tests use synthetic workers and a GET-only GitHub fixture inside PGlite. They
are not live worker registration or production verification evidence. Run
`node --test test/pandora-operations-merged-release-reconciliation-db.test.js`
`node --test test/pandora-operations-merged-release-native-worker.test.js`,
and the surrounding Operations Room tests, then run ARTEMIS at the immutable
PR head. ARTEMIS machine checks do not replace independent release review.

Unknown provider outcomes, divergent ancestry, active leases, scope changes,
stale inputs, and changed final readback retain the hold. Reconciliation
timeline lookup is bounded to ten pages of 100 events. Verification rejects an
incomplete or oversized check set. A failed RPC transaction must not leave a
partial adoption or acceptance receipt; inspect current state before retrying.

To disable these actions, redeploy the previously approved gateway version.
Do not erase receipts or reverse task generations as a rollback. Any subsequent
attempt must use current task state and the ordinary independent release process.
