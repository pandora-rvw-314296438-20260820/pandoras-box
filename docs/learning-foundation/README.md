# Learning foundation: exact-source inventory v1

This is the P0-02 evidence tool and reuse map for the existing Skills/Memory/RAG tracker. It is not another tracker, skill catalog, router, scheduler, or authority service.

## Scope and current acceptance

The implementation reads exact committed Git objects from only the two canonical repositories. It emits metadata and Git blob identities, not skill bodies, customer records, environment values, credentials, or runtime claims. The auditor never executes code from the audited snapshot.

`INVENTORY_COMPLETE` means the bounded inventory completed. It does **not** mean a task is merged, deployed, production-ready, rights-approved, or independently reviewed. `INVENTORY_UNAVAILABLE` is a nonzero failure, never an empty successful search. A missing exact path does not prove that a capability is absent everywhere.

Authoritative plan: https://docs.google.com/spreadsheets/d/19_1tfUVVTOvYGGnWR_mUfuRkiu3l44dGDW01U8ocMlA/edit

At evidence capture, this is pre-merge implementation. Independent review, required CI, exact-head landing authorization, and merged-SHA readback remain release gates. No product runtime deployment is required for this standalone diagnostic.

## Reproduce

Use Node 24 and Git with complete local objects for the requested commit. Fetch only through an already approved canonical remote before running the audit; the auditor itself does not fetch.

```sh
node scripts/audit-learning-foundation.mjs --repo . --kind box --sha fd037d0f3329ad295dc8f3b2b84ad473e538ff7d
node scripts/audit-learning-foundation.mjs --repo /path/to/canonical-memory-checkout --kind memory --sha 2d193c0667a037e815f50a1c1c81fd578eaf9d92
node --test test/pandora-learning-foundation-audit.test.js
node scripts/validate-pandora-skills.mjs
node --test test/pandora-skills-registry.test.js test/pandora-skills-runtime.test.js test/pandora-internal-skill-exact-source-contract.test.js
```

Moving refs such as `main`, `HEAD`, and `latest` are rejected by the audit CLI. The caller must resolve a full commit SHA first. Local origin configuration is checked, but it is not a remote-provider attestation; pair the report with live canonical GitHub/main readback before acting on it.

Limits: 15-second default total Git-read budget, 30-second maximum configurable budget, 4 MiB cumulative Git output, 10,000 tree entries, 32 catalog shards, and 1,024 skills. Missing objects, unsupported catalog structure, unsafe entrypoint paths, duplicate identities, and inconsistent denominators fail explicitly. Git commands have fixed argument shapes and never use a shell.

Git's replacement refs, inherited Git repository redirection, global/system config, interactive prompts, lazy object fetching, and all network transport protocols are excluded from audit execution. Reference: https://git-scm.com/docs/git (GIT_NO_REPLACE_OBJECTS, GIT_NO_LAZY_FETCH, GIT_ALLOW_PROTOCOL). On Windows the Git global-config null path is `NUL`, not Node's device-namespace `os.devNull` value; the latter failed on the actual RDP Git build and the failed run is retained in the execution receipt.

## Actual baseline and reuse decisions

Audited Box: `fd037d0f3329ad295dc8f3b2b84ad473e538ff7d`.
Audited Memory: `2d193c0667a037e815f50a1c1c81fd578eaf9d92`.

The existing canonical skill validator passed: 51 skills, 57 capabilities, 16 specified evaluation cases, and 71 manifest files. The three existing focused test files passed 18 tests, including the test that exercises all 16 deterministic routing cases. These are not the tracker experiment protocols and do not populate their model-benchmark counters.

The new auditor passed 23 synthetic, offline Git-fixture tests after the Windows null-path correction. Both actual canonical source inventories exited successfully. Exact source/tree/blob identities, content receipts, tool-file hashes, timestamps, and test-log digests are in `evidence/`. The initial setup failure is recorded separately, not silently replaced by the successful rerun.

| Tracker area | Existing source to reuse | Remaining boundary |
| --- | --- | --- |
| P1 Skills | `.agents/skills`, the 51-entry source catalog, deterministic read-only runtime, manifest validator, and existing tests | Extend the existing contract; do not build a second catalog. Passing source tests is not provider activation. |
| P1 exact-source trust | `packages/pandora-intelligence/src/skills/agent-catalog-adapter.js` and `registry.js`; existing exact-source contract tests | Projection begins EXPERIMENTAL. Current source identity and independent digest-bound acceptance must remain distinct from historical catalog provenance. |
| P2 governed context | Existing trusted-context and trusted-material modules | Source presence does not prove current tenant/freshness behavior in the live service. |
| P2 Memory retrieval | M5 task-aware migration, verifier, behavior tests, approved-canon evidence, and machine-gateway source | Preserve Memory PR93 incumbent ownership. Its typed/legacy transition remains an open PR at the captured exact head. No grant activation or bridge edits here. |
| P3 Router | Existing model router, policy, bounded fallback, plus the separately claimed Router implementation | The new Router package was absent from audited main, while another acknowledged session owned uncommitted implementation. This is not evidence that no work exists. |
| Evaluation/training | Existing deterministic skill test cases and this offline audit fixture suite | No model quality/cost/latency benchmark, training-set admission, fine-tuning, or paid compute authorization is established. |

### Source identity finding: preserve origin, bind current source separately

The existing registry and its validation schema still declare the historical, now-blacklisted repository identity. The validator explicitly expects that identity, so a green validator alone does not establish current canonical source authority. The trust projection copies catalog repository/commit metadata into an EXPERIMENTAL definition.

This audit reports the mismatch without querying the blacklisted repository, overwriting historical provenance, promoting a definition, or altering the incumbent runtime. A future scoped contract change must distinguish historical origin from the exact current canonical source snapshot and obtain independent acceptance before trusted use. No production incident or exploit is claimed from this source observation.

### Ownership and dependency reconciliation

The current acknowledged Router owner is `OPS-INTEGRATION-ROUTER-20260925`, recorded in the allowed Facebook tracker's Operations Room rows33-34 and Resource Leases row30. Its new Router package/service/migration and Operations Room integrations are excluded from this change. Box709/668, Memory93, root dependency manifests/locks, production configuration, and emulator state are untouched.

Memory PR93 is open at `4ee4573a06083eb201a9b2e3fd0676dcab94a5f6`; its implementation is not duplicated. The previous merge-first prerequisite, Box728, is already merged. Box main at this capture also includes the Hono repair merged as731. Historical blockers are not presented as current blockers.

The Skills tracker was updated before source work. It records this actual session, `P0-FOUNDATION-20260925`; no parallel worker or distributed mutex is invented. A coordination comment through the GitHub connector failed with403, and the attempted existing-broker comment was tool-blocked without a publication result. The tracker ACK is real; a published GitHub coordination ACK is not claimed.

## P0-01 owner boundary reconciliation

The current owner instruction permits the RDP as an engineering forge and for controlled, disposable local-model research. It does not substitute the RDP for approved phone-local/cloud production architecture. This narrowly supersedes the blanket no-research-host wording in the historical, unmerged Memory PR104 proposal; its history is preserved.

No new model, GPU purchase, compute capacity, training run, production activation, or provider mutation is approved by this record. RDP-off production independence remains a separate unexecuted acceptance test.

## P0-03 observation and rights limitations

The execution receipt records the actual Desktop Commander online-device observation and guest CPU/RAM/disk read. It is not cloud billing/instance-capacity certification, an exclusive host lease, GPU verification, model usability, emulator acceptance, or physical-phone acceptance. Dirty root checkouts were not used for new implementation; a fresh isolated worktree was used.

No conventional LICENSE/COPYING/NOTICE filename was found in the complete 2,211-path audited Box tree. This is only a filename inventory, not a conclusion about ownership, licenses in headers, third-party dependency rights, or training permissions. Source rights remain NOT_EVALUATED. Newly authored code and synthetic test fixtures are AI-assisted implementation artifacts, not approved training data merely because they enter the owner's repository.

## Durable learning candidate and release handoff

Useful verified lesson: isolate source inspection from working-tree edits, Git replacement refs, network fetching, and local config; then test on the actual operating system rather than assuming Node's portable null-device string is accepted by every subprocess.

The successful Windows fix is narrow and reproducible, and the negative run is preserved. This is a proposed learning record awaiting the authorized canonical Memory review path, not automatic Memory promotion. Raw polling and full routine logs are not proposed for canonical Memory.

Release handoff must include the exact PR head, required CI/review state, current-main reconciliation, and source-only acceptance. A green local test or this receipt does not authorize landing. A new head invalidates any previous exact-head authorization.

## Pre-publication main reconciliation

Main advanced from `fd037d0f3329ad295dc8f3b2b84ad473e538ff7d` to `b63e3a710534aa530ba26f8a654f60aabc6e7a93` during local verification. The unpublished feature branch fast-forwarded normally, without rewriting published history. The ten added main paths did not overlap this scope; a fresh exact-source inventory succeeded and is preserved alongside the initial snapshot.

Live ruleset21532267 currently reports **zero native required approvals**, review-thread resolution, strict required-status-check freshness, seven required check contexts, and CodeQL thresholds. No one-approval rule is invented or changed here. Independent tracker acceptance, any applicable coordinator checks, and exact-head owner landing authorization remain distinct from the native approval count.
