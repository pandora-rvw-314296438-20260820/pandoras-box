# Canonical release evidence contract

This directory defines the release gates; it does not claim that any gate has
passed. The checked-in source contract is intentionally and permanently
`not_ready`. Every provider, reviewer, owner, rollback, and physical-device
receipt is `pending_external_receipt` with a `null` receipt.

## Authority boundary

| Evidence | Only acceptable issuer | Required binding |
| --- | --- | --- |
| Candidate source | Integration-SHA, read-only CI | Synthetic PR/merge-group SHA or pushed main SHA, Git tree SHA, source requirements digest |
| Production deployment | Vercel provider read | Project ID, exactly one production deployment ID, target, exact source SHA |
| Rollback deployment | Vercel provider read | A deployment ID distinct from production and its provider-reported source SHA |
| Database state | Supabase Management API plus immutable database capture | Project ref, fresh exact ordered applied versions, and a post-deploy receipt binding the exact GitHub source artifact/source-chain digest to the then-live ordered version chain |
| Repository checks | GitHub provider read | Exact integration SHA, workflow/job identity, conclusion, completed time |
| External review check | Separately trusted provider | Exact reviewed source, non-Actions provider identity, conclusion, completed time |
| Rollback rehearsal | Vercel provider reads plus route observations | Candidate ID, distinct rollback ID, every transition, probes, and restoration |
| Android build | GitHub provider read | Dynamic artifact ID/name/digest, exact push-main workflow run/attempt/job/check, source SHA/tree, and APK SHA-256 |
| Android journey | Physical-device observer | The provider-read CI APK SHA-256, fixed production origin, production deployment ID, rollback-restoration receipt digest/time, device, observation time, and network |
| Review | Independent reviewer | Source, deployment, rollback, and migration-chain identities |
| Authorization | Owner | Source, production deployment, and independent-review receipt digest |

Source-controlled files may describe those requirements and compute source
hashes. They may not issue, embed, or upgrade external proof. Provider payloads,
independent review, and owner authorization belong in the independent status or
control plane. Do not commit fetched provider JSON or a hand-authored positive
status here.

## Exact candidate binding

For every pull request, merge-queue candidate, and push to protected `main`, the read-only workflow checks out `${{ github.sha }}`
with credentials disabled. After the required repository checks, it verifies
that the tree is still clean and emits an ephemeral source-only artifact outside
the checkout. That artifact contains:

- the full commit SHA and Git tree SHA;
- every `supabase/migrations/*.sql` file in timestamp order and its SHA-256;
- a byte-chain digest over `filename<TAB>file-sha256` records; and
- the expected provider chain digest over the ordered migration versions.

The artifact says `describes_candidate_only`, copies no external receipt, and
cannot authorize release. Generate it only in integration-SHA CI:

```text
node scripts/verify-canonical-release-evidence.mjs --mode source-binding \
  --expected-sha <40-character-integration-or-main-sha> \
  --output <path-outside-the-repository>
```

The verifier refuses a dirty checkout, a mismatched SHA, an in-repository
output, malformed or duplicate migration timestamps, mutable workflow actions,
write permissions, secrets, path-filtered candidate CI, and deployment or
repository mutation commands.

The exact-source gate also type-checks every governed Edge entrypoint named by
the package contract: `pandora-owner-api`, `pandora-worker-dispatch`,
`pandora-reviewer-attestation`, `pandora-release-review-attestation`,
`pandora-release-owner-authorization`, `pandora-physical-android-attestation`,
and `mcpmaster-supabase-control`. Adding
an authority-bearing Edge seam without adding its exact `index.ts` path to this
gate is a source-contract failure.

On pull requests, `${{ github.sha }}` is GitHub's synthetic merge commit; on a
merge-group event it is the synthetic group SHA. This proves integration with
the current protected base instead of testing only the unmerged PR head. On a
push to `main`, it is the literal canonical source SHA used by release evidence.

The candidate repository does not produce the logical `external-review` gate.
That gate is bound exactly to provider context `external-review` from the
dedicated Pandora Main Gate GitHub App (`appId: 4658204`, producer
`pandora_main_gate_github_app`). Candidate-controlled workflows may not declare
either identity or publish Checks/Statuses. A missing, pending, unsuccessful,
wrong-app, or wrong-context receipt leaves the pack non-authoritative. GitHub
Actions App `15368` is never accepted as independent review authority.
Runtime activation accepts only
`PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID=4658204`; the value remains provider
configuration and is not source-controlled in `vercel.json`.

The canonical status GitHub credential must be able to read Actions artifacts,
workflow runs/jobs, Checks, repository contents and pull requests, and the
protected-branch configuration. The provider uses the artifact REST
`digest` (`sha256:<hex>`) as the immutable uploaded-archive identity; the APK
SHA-256 remains a distinct inner-build identity recorded by the mobile manifest
and repeated by the physical observer.

## Release acceptance

A schema-valid requirements contract contains exactly these five checks, in
order: `node24`, `external-review`, `canonical-release-source-contract`,
`Windows worker contract`, and `Exact source / Flutter / Android`. A duplicate,
renamed, reordered, or command-weakened check cannot substitute for one of them.

A separate evidence consumer may move the canonical status pack from `tested`
to `deployed` only after all required GitHub checks succeed for the exact source
SHA, the fresh Supabase Management API version order matches both the source
artifact's expected version chain and the immutable post-deploy database receipt,
and Vercel reports exactly one production deployment for that SHA. The database
receipt stores the source artifact locator/hash and source-byte-chain digest; it
does not claim that the provider reconstructed the original SQL file bytes. The
rollback deployment must be provider-read and distinct from production.

A route comparison is not a rollback rehearsal. The immutable rehearsal
receipts must record this complete production-alias sequence in order:

1. Record the candidate deployment.
2. Transition the fixed production alias to the distinct rollback deployment.
3. Probe the required routes on rollback.
4. Restore the alias to the candidate deployment.
5. Probe the required routes after restoration.

Each phase is captured by the service-role-only
`capture_canonical_vercel_rehearsal_receipt` RPC. The RPC reads the fixed
`mcpmaster.vercel.app` alias, applies probes only to that fixed host, then
re-reads the alias and rejects the receipt if its deployment identity changed.
Both probe phases must apply the checked-in semantics exactly: `/health` must
return healthy JSON with HTTP 200; unauthenticated `GET` and `POST` requests to
`/mcp` must preserve the HTTP 401 bearer boundary; and the OAuth protected
resource metadata route must return HTTP 200 with the expected metadata shape.

After the database migrations are deployed, the service-role-only
`capture_canonical_supabase_release_receipt` RPC reads the live
`supabase_migrations.schema_migrations` order and accepts the receipt only when
its version-chain digest matches the exact pushed-main source artifact expectation.
The receipt is immutable and a fresh Management API read must continue to match
it. `sourceArtifactDatabaseReceipt` names the stored source binding honestly;
`exactAppliedBytesProven` and the stored byte digest's `providerReadback` remain
false because version history cannot reconstruct comments, whitespace, or the
original migration-file bytes.

The production-verified gate additionally requires the same physical Android
build to complete the owner-command → durable dispatch → Worker-01 → exact
provider result/proof journey once on Wi-Fi and once on mobile data. Both runs
must bind the same source SHA/tree, production deployment ID, and APK SHA-256.
The accepted APK is not a local or self-labelled build: it is the exact
`pandora-mobile-android-validation-<source-sha>` artifact emitted by the
successful push-to-`main` `Exact source / Flutter / Android` job. The status
provider freshly reads the GitHub artifact ID and `sha256:` digest, its workflow
run and attempt, the run's source tree, and the exact job/check-suite identity.
The physical receipts must repeat the artifact locator/digest and APK SHA-256,
name `https://mcpmaster.vercel.app` as the production origin, bind the immutable
rollback-restoration receipt SHA-256 and its provider-observed completion time,
and be observed after that restoration readback. A deleted, expired, renamed,
wrong-run, wrong-tree, wrong-check, or digest-mismatched artifact fails closed.

Independent review and owner authorization come last and must bind the exact
identities above. Review must follow both physical runs; owner authorization
must follow and bind that exact review receipt and must be issued from an AAL2
owner session. No evidence consumer should infer either from repository content
or from the existence of a source-only CI artifact.

## Current state

`release-evidence.source.json` contains requirements only. All real provider,
reviewer, owner, rehearsal, and physical-device receipts are absent and pending;
therefore the release decision is `not_ready`.
