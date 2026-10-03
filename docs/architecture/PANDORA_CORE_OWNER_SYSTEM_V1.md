# Pandora Core owner operating system

## Delivery envelope

Owner instruction: 2026-10-03, complete Pandora Core Admin / Owner Operating System.
Canonical repository: `pandora-rvw-314296438-20260820/pandoras-box`.
Exact initial main: `9d6a5ebadd67a14b949871dca911a11453aedf26`.
Task branch: `chatgpt/pandora-core-owner-system-v1`.
Production database: `jcyqixttuebxqqfkjonq`.
Memory database: `ivmvufhcsezyhczzondn`.
Vercel: team `mbanatao`, project `mcpmaster`.

This is an integrated change to the existing Flutter shell and Supabase
contracts. No independent admin application, replacement execution engine,
provider registry, user store, or Memory system is introduced.

## Evidence before implementation

- **Provider evidence:** current source has the Lane H shell changes from #940.
- **Provider evidence:** production Vercel deployment
  `dpl_JT1DTq6hdFpx74HgQ91hEMFdZKKW` is READY at
  `de16cac98f2a1b4b400b73e333898e9882061fd2`. The served Flutter manifest
  independently reports that SHA. READY is not user-flow acceptance.
- **Provider evidence:** production contains two organizations: the existing
  Pandora organization and PLP. Euro-Fish, Batalla and BOK have no organization
  records at inspection time. The legacy PLP demonstration property belongs to
  the Pandora organization and is not the customer tenant.
- **Verified source:** Home is a fixed directory; selecting a workspace does
  not change the immutable organization binding of the global conversation.
  Returning Home retains customer navigation context. These are scope defects.
- **Provider evidence:** authenticated clients have direct membership mutation
  privileges that can bypass user-admin role checks. New administration must
  close this path while preserving the existing audited membership service.
- **Memory lesson:** retrieval succeeded with context digest
  `827858942f5adb36531bc198535a39110d18e90bd77531204f751a2141bfc6af`.
  Relevant approved lessons distinguish provider artifact failures from source
  failures and prefer bounded deterministic readback over unnecessary model
  inference or reauthentication. The current explicit owner instructions
  supersede historical repository names and retired governance references.

## Active lane boundaries

#922 owns model-picker/chat-routing work. #812 overlaps the shell navigation.
#793 and #668 overlap the old enterprise directory and PLP GraphQL reads.
#869/#868 own PLP lifecycle/session work. These PRs are read as candidate
evidence, not silently merged or overwritten. New owner pages live in one Core
module; shared shell changes are limited to navigation and scope integration.

## Architecture

The owner shell reads authenticated projections over canonical organizations,
memberships, capabilities, connection verification, costs, deployments,
execution tasks, approvals, audit and enterprise entities. A customer account
is the commercial/operator relationship to an existing organization; it does
not replace that organization. Catalog availability, commercial entitlement,
live connection usability and execution authorization remain separate.

The normal navigation has Core, Enterprise, Platform, Business and
Administration groups. Detailed subjects are tabs inside a bounded workspace,
not dozens of top-level destinations. The persistent conversation remains the
existing app-level layer. It retains its state within a scope, and changes
scope explicitly through an authorized server boundary.

Owner Home contains decisions, customer service health, actual work in progress,
platform exceptions, Pandora commercial state and meaningful outcomes. It
excludes customer operating KPIs. Manage Client and Enter Client Workspace are
separate actions. Customer workspace access never follows from merely being
signed in or from user-editable metadata.

## Data and operation rules

- Reuse `organizations` and `memberships` for identity and users.
- Reuse `enterprise_contracts`, `enterprise_documents`, `enterprise_tasks`,
  `enterprise_devices`, industry packs, connections, provider/model evidence,
  `pandora_cost_entries`, budgets, deployments, operations and audit.
- Add only missing account/commercial/case/provisioning specializations.
- Empty authoritative data stays empty. Missing billing does not mean zero
  revenue. No currency aggregation without separate currency groups.
- Discovery/activation metadata is not proof of runtime provider health.
- Provisioning uses an atomic, payload-bound idempotency receipt and exposes
  unfinished prerequisites. It never silently sends invitations, buys domains,
  invokes model probes or marks a customer live.
- Privileged RPCs derive the actor from authenticated identity, validate the
  exact target, use bounded payloads, write durable audit and fail closed.
- High-risk financial, security and access changes require a live verified
  session and stronger authorization. Every exposed new table has RLS and
  explicit grants; raw direct mutation is withheld where the RPC is the
  authoritative operation boundary.

## Acceptance and release gates

1. Dynamic customer identity, exact organization scope and operator boundaries.
2. Home/Clients/Manage Client/Onboarding and grouped operational workspaces.
3. Payload-bound replay, failed/partial onboarding, safe retries and cancellation.
4. Anonymous, member, customer administrator, operator, revoked and cross-tenant
   negative tests; no metadata-based privilege escalation.
5. Membership last-owner and self-change protections remain effective.
6. Persistent composer, explicit context, back/refresh/restart, offline, empty
   state, small viewport and actual owner/client journeys.
7. Source checks, database migration replay, RLS tests and hosted advisors.
8. Exact source/PR/CI/migration/deployment/artifact readback before acceptance.
9. Runtime error scan and rollback evidence; no production-ready claim from a
   green build or deployment state alone.

## Rollback and stop conditions

Keep the initial source and current production deployment as recovery anchors.
Use additive schema changes; preserve records on application rollback. Revoke
new entry points or forward-fix authorization defects rather than deleting
customer data. Reverting Vercel does not revert database changes.

Stop promotion for cross-tenant access, unresolved high-risk authorization
defects, source/migration/deployment mismatch, required failing CI/review,
missing authenticated acceptance or signing/device proof. Continue independent
implementation and verification while a provider gate remains unresolved.

This document is an implementation contract, not evidence of completion. The
release report must distinguish Implemented, Tested, Built, Deployed, Runtime
Verified and Production Verified.


## Implemented scope and evidence boundaries

The Core module now supplies Home, Clients, Manage Client, unified Needs You,
Business, Platform and Administration inside the existing persistent shell.
RPC projections read canonical records. Governed operations cover atomic client
registration, onboarding checkpoints/attestations, plans, subscriptions, invoices,
payment/credit/refund capture, prospects, linked enterprise contracts, support
cases, incidents, partner records, device trust revocation and operator grants.

Customer entry requires actual target membership, an explicit operator grant,
a live AAL2 session and an expiring audited entry receipt. The shell rebuilds
scope-bound services and its ephemeral cache, fences stale asynchronous replies,
clears conversation state and displays persistent administrator context. The
existing PLP adapter validates its organization/property before loading data.
Other adapters remain visibly unverified; they cannot be activated by checklist
attestation alone. This is an explicit remaining product/runtime boundary.

The membership bypass is closed by removing raw authenticated DML. The existing
user-admin Edge broker accepts explicit Core authority without changing the user
store, serializes membership changes by organization and preserves last-owner
protections. Shared tenant helpers now enforce organization suspension and
banned/deleted account state, without adding cross-tenant operator shortcuts.

Commercial values entered through Core are manual. They cannot self-promote to
provider-verified billing. Payments enforce invoice organization, currency and
remaining balance; posted receipts are append-only through this surface.
Subscription changes retain sanitized before/after commercial values in audit.
Plan limits are authoritative configured terms, but full execution admission and
billing reconciliation are separate capabilities and are not claimed complete.

Current focused local results: 35 database/authorization tests; 49 Flutter tests
across Core, scope/receipt/handoff/money and Team; 36 Core-chat and existing
team/Growth regressions. The broader Node run passed 4,159 tests with one optional
native-SQL test skipped, plus 52 worker tests, before the final approvals-projection
fixture was added. Exact final-commit CI must supersede these working-tree counts.
The full migration chain has replayed locally with provider substitutions; it is
not equivalent to hosted Supabase verification. The replay harness now uses the
hosted UTC timezone and inspected auth-user columns.

No production acceptance follows from these local results. Required remaining
proof is tracked with the PR: hosted migration/readback/advisors, exact deployed
source, authenticated owner/client flows and device evidence when an APK is made.
No production demo financial data, provider probe, external invitation or customer
business mutation is needed to verify the capture paths.
