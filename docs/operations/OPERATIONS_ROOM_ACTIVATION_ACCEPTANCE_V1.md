# Operations Room staged activation and acceptance

Task: OPS-ACTIVATION-ACCEPTANCE-V1-001. Coordination: canonical Box issue #714,
comment 5838010968; Facebook tracker Operations Room row 37, source lease row 33.
This is a disjoint release-integration lane, not a replacement scheduler, Router,
ARES host, Memory client, coordinator or permission system.

## Executable behavior

`scripts/operations-room-rollout/rollout.mjs` supplies the release adapter:

- `collectFoundation` performs fixed read-only catalogue inspection and only asks
  for actual runtime counts after all eight tables exist. It does not interpret
  missing tables as an empty running queue.
- `inspectFoundation` checks target/freshness, exact migration identity, all eight
  private tables, all fifteen public RPCs and four private helpers, RLS, effective
  table/column/function privileges, safe defaults and actual paused-state counts.
  A grant inherited from PUBLIC is included. RLS disabled is not by itself proof
  of public access; the privilege and policy findings remain separate facts.
- `verifyFoundationSource` checks all three exact merged-source files by SHA-256,
  repository, commit and path. This release profile deliberately pins #728's
  unchanged bytes present at 23441474c590d35902a1790b3c2cfa9130dc9109. Advancing the
  profile requires a reviewed source change, not an automatic moving-main lookup.
- `stageFoundation` uses the existing `GovernedProviderActions` implementation.
  It proposes only the missing database foundation and Edge function, in that
  order. M3 must authorize AND execute each action under its existing current
  policy and lease. Separate provider readback is mandatory. Unknown outcomes,
  a quota failure, revocation, changed scope, partial schema or active work stop
  the sequence without retries or follow-on mutations.

There is no standalone `approved: true` bypass. The caller must supply the real
existing M3 adapter, exact artifact resolver and authenticated project-bound read
transports. This module does not acquire credentials or make a provider port
executable merely by naming it. It must be connected by the incumbent trusted
release service. A returned `foundation_staged` means paused foundation only;
`autonomyAccepted` remains false because whole-sheet acceptance belongs to the
independent end-to-end release gate.

## Trusted adapter contract

Database readers receive only the fixed queries checked into this directory and
an explicit Supabase project reference. Their returned `{projectRef,data}` must
be bound to the authenticated provider target, not copied from an owner payload.
The Edge reader must read current metadata AND the deployed source; its `files`
map contains the SHA-256 of exactly index.ts and handler.mjs. An HTTP health 200,
an ACTIVE label, a submitted deployment or a filename match is insufficient.
Use provider time for each observation and a synchronized service clock. Evidence
older than 30 seconds or later than the current clock fails closed.

The existing migration action must preserve the canonical version and source
identity. The adapter sets `repairHistory: false`: it must NOT replay an already
applied alias or silently rename unrelated history. The Edge action requires JWT
verification and forbids replacing a preexisting deployment. Current policy,
resource fencing, source approval, rollback evidence and independent review are
still enforced by the incumbent release system. This module never widens them.

No task, project binding, worker or provider approval is seeded. No unpause,
production enablement, Vercel promotion, function deletion, billing upgrade,
spend-cap change or physical-device operation exists in this adapter.

## Actual activation observations from this session

At 2026-09-25T19:00:34Z, Supabase project jcyqixttuebxqqfkjonq had no ledger entry
for migration 20260925101319 and no private pandora_ops tables. #728 was already
merged, with successful exact-head CI including PostgreSQL race job108114029719.
Those source checks do not establish live worker or runtime acceptance.

Native deployment of the unchanged two-file pandora-operations-runtime bundle,
with JWT verification enabled, returned PaymentRequiredException: the project
had reached its function limit. No deployment success was observed. A bounded
attempt to reclaim one already-retired, deny-only tombstone was blocked by the
tool safety check; it was not retried through a different route. No deletion or
plan change is claimed. Memory issue115 preserves the exact failure, tombstone
source and subsequent correction. Quota recovery requires a permitted action or
an owner-managed change; it must not be disguised as a completed deployment.

No Workspace Agent-named credential was found in the inspected primary Vault
metadata. That limited observation is not an account-wide entitlement finding.
An externally triggered ChatGPT Workspace Agent requires an eligible published
agent channel and its own approved access credential. Pro access or a named
Greek-god role is not proof of external worker capacity. A provider202 or queued
run ID is not the worker-start ACK and not verified task completion.

## Rollout gates after foundation staging

The active source owners retain their work: OPS-INTEGRATION-ROUTER-20260925 owns
live scheduling/Sheets/provider transport/Router wiring; OPS-ARES-HOST-20260926
owns ARES; OPS-MEMORY-INTEGRATION-20260926 owns native Memory integration.
Adopt their published exact-source handoffs, not unpublished working copies.

Before increasing concurrency, independently prove two genuine workers and
independent jobs, a dependent job, a shared-resource conflict, lost ACK/reconnect,
cancellation with ambiguous outcome retention, an intentional test failure and
bounded repair, one governed merge and applicable deployment, safe literal Sheets
writeback, truthful Theatre events and review-gated Memory delivery. Include an
unavailable-worker case and a genuine external blocker. Source tests, staged
schema and provider-queued work are not substitutes for these runtime receipts.

Keep the existing coordinator as exact-SHA merge authority. Resolve the stale
Build Theatre integration and #723 through its current source owner/release
handoff. Never fabricate a coordinator PASS, reviewer identity or completion
receipt. A browser-side DONE cell cannot authorize or verify a task.

## Verification

`node --test test/pandora-operations-rollout*.test.js`

The new isolated PGlite tests execute the actual unchanged #728 migration and
catalogue/count queries. They prove SQL behavior in a disposable database, not
production installation, concurrent client races, real credentials or workers.
Existing PostgreSQL race coverage remains in operations-room-runtime.yml.
Dedicated rollout CI uses exact PR head, read-only repository permissions and
locked dependencies without lifecycle scripts. Runtime acceptance is separate.

## Durable lesson

Source merged, CI passed, database installed, endpoint deployed, worker connected,
provider action verified and whole-sheet acceptance are distinct evidence states.
Provider capacity and exact source/history parity must be checked before rollout.
Unknown inventory is not zero; a deny-only legacy endpoint is not a working
scheduler; a denied cleanup action is not permission to find another route.
