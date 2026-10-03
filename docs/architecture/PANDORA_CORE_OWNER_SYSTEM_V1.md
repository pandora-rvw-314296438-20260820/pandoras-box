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

Operator customer entry requires actual target membership, an explicit operator grant,
a live AAL2 session and an expiring audited entry receipt. The shell rebuilds
scope-bound services and its ephemeral cache, fences stale asynchronous replies,
clears conversation state and displays persistent administrator context. The
existing PLP adapter validates its organization/property before loading data.
A common Enterprise workspace supplies actual task capture, documents, people and
activity for other clients. It extends canonical `enterprise_tasks`, with scoped,
idempotent operations and optimistic concurrency. Go-live requires recent
same-tenant runtime task evidence in addition to onboarding verification.
Specialized industry workflows remain separate from this common adapter and
cannot be claimed verified from its availability.

Normal customer launch resolves only active, server-authorized memberships and
starts a runtime bound to the selected organization. Scoped Pandora staff use the
same chooser with mandatory audited entry; they do not receive the global Core
control plane. Ordinary member chat reaches a bounded, authenticated workspace
read path before legacy owner, provider or team execution. PLP context hydration
verifies the authenticated organization before retaining business data.

The membership bypass is closed by removing raw authenticated DML. The existing
user-admin Edge broker requires explicit Core authority for internal actors even
when they also hold a customer owner role. Customer owners retain their own team
administration boundary. Membership changes serialize by organization and retain
last-owner protection. Invitation failures preserve the global Auth account,
record partial outcomes and resume the existing account. Shared tenant helpers
enforce organization suspension and banned/deleted account state without adding
cross-tenant operator shortcuts.

Chat authority is classified from the requested organization and current server
records before context hydration, regardless of omitted or editable UI metadata.
Known internal identities need a current audited entry for registered customer
business reads, including direct table reads and the older business RPCs. Exact
inspected function-body hashes fence those bounded legacy changes. The existing
activity engine receives the same scope checks at its original begin operation;
the client wrapper does not replace the engine. Revocation and expiry invalidate
both customer navigation and its execution authority.

The Memory tab retrieves bounded approved policy/advisory records through the
existing production workload bridge. The owner HTTP entrypoint checks a live
global Core owner/operator grant before and after the provider read. Flutter
rejects mismatched scope, draft records, authority expansion and a changed session.
Learning outbox rows remain labeled delivery state, not approved Memory. The
generic evidence-candidate handler is absent from the currently deployed native
Memory bridge; general release evidence must use a canonical Memory repository
review candidate rather than a fabricated execution.

Commercial values entered through Core are manual. They cannot self-promote to
provider-verified billing. Payments enforce invoice organization, currency and
remaining balance; posted receipts are append-only through this surface.
Subscription changes retain sanitized before/after commercial values in audit.
Plan limits are authoritative configured terms, but full execution admission and
billing reconciliation are separate capabilities and are not claimed complete.

The first complete candidate in PR #944 was
`f29118135393b69abee89476c5b74a11f940217a`. GitHub executed its frozen Deno checks
and full migration replay successfully. It also caught stale source assertions
and four shell test failures, corrected in the follow-up candidate. Working-tree
results are superseded by final exact-commit CI evidence; no initial-candidate
result is silently credited to a later head. The replay harness uses the hosted
UTC timezone and inspected auth-user columns, but its provider substitutions are
not equivalent to hosted Supabase verification.

Main advanced during implementation to
`7884d2fe2851a8f06ac2329e30c772ffd25134d5`, through separately merged PR #943.
Its provider-diverse routing change must be retained alongside the new caller
authority checks. It also adds a source audit exception for the unchanged braces
advisory (`GHSA-vfj7-8cjw-p6xm`), expiring October 17. The original candidate's raw
audit failure remains valid historical evidence. This lane did not create that
exception and does not infer a named security acceptance from the merge account.
The vulnerability remains open, with no compatible published patch found on
October 3. The root production dependency audit reports no findings; this does
not prove every provider-generated bundle excludes the dependency. Audit policy
passing under an exception is not vulnerability remediation.

No production acceptance follows from these local results. Required remaining
proof is tracked with the PR: hosted migration/readback/advisors, exact deployed
source, authenticated owner/client flows and device evidence when an APK is made.
No production demo financial data, provider probe, external invitation or customer
business mutation is needed to verify the capture paths.
