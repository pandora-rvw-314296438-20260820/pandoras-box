
# Pandora Control Plane V1

Status: source-complete only when the migrations and verification listed in this document are present on `main` and live in the canonical Pandora Supabase control-plane project.

## 1. Purpose

Pandora Control Plane V1 is the durable system of record for customer intent, ProjectSpec state, orchestration state, execution lineage, artifacts, verification, policy/approval decisions, project versions, economics, runtime-resource metadata, database-change safety, customer-safe build progress, and immutable audit history.

The Control Plane persists truth. It does not directly implement model-provider SDK calls, build sandboxes, provider deployment execution, verifier execution, or customer presentation.

Canonical project identity remains `projectos_projects`. Worker A does not introduce a competing project root.

## 2. Source migrations

Control Plane V1 is implemented by these replayable source migrations:

1. `20260828153500_pandora_project_spec_control_plane_v1.sql`
2. `20260828170000_pandora_durable_execution_lineage_v1.sql`
3. `20260828181500_pandora_economics_runtime_safety_v1.sql`
4. `20260828193000_pandora_realtime_audit_security_v1.sql`

Repository migration parity and full replay are release gates. Recovery-era history-only receipts remain historical evidence and are not the implementation source for Worker A.

## 3. Canonical ProjectSpec

Customer chat is input, not canonical specification truth.

`pandora_project_intents` records customer intent receipts append-only.

`pandora_project_specs` is the immutable/versioned canonical ProjectSpec. A ProjectSpec version binds to its source intent and, after version 1, its immediately previous ProjectSpec version. Content is immutable after insertion; only controlled status transitions are allowed.

Queryable ProjectSpec children are:

- `pandora_project_business_objectives`
- `pandora_project_requirements`
- `pandora_project_constraints`
- `pandora_project_acceptance_criteria`

`projectos_decisions` may bind back to ProjectSpec and source intent for provenance without replacing the canonical ProjectOS decision history.

## 4. Durable build orchestration

`pandora_build_jobs` is the project/spec-bound lifecycle record. It binds the customer project, exact ProjectSpec, optional source intent, target project version, generic `workflow_runs` execution lineage, parent job, requester, idempotency key, retry limits, budgets, cancellation, public-safe failures, and bounded leases.

The Control Plane does not replace the existing generic workflow/execution substrate. Build jobs point to it.

Durable child state is stored in:

- `pandora_build_job_steps`
- `pandora_build_job_attempts`
- `pandora_build_job_events`

Lease acquisition, heartbeat, and expired-lease requeue are service-owned private functions. Customer roles cannot claim or forge build work.

Customer-facing build stages are derived from durable job truth rather than animation timers.

## 5. Model, tool, and artifact lineage

Provider-independent model execution metadata is stored in `pandora_model_runs`.

Governed tool execution metadata is stored in:

- `pandora_tool_calls`
- `pandora_tool_results`

Artifact lineage is stored in:

- `pandora_artifacts`
- `pandora_artifact_versions`
- `pandora_artifact_links`

These contracts store identifiers, digests, bounded/redacted metadata, and lineage. They do not authorize models to perform provider mutations directly.

The intended trace is:

`Intent → ProjectSpec → Build Job → Model Run / Tool Call → Artifact Version → Project Version → Verification → Runtime`

## 6. Project versions and release eligibility

`pandora_project_versions` remains the canonical customer project-version table and is enriched with parent version, ProjectSpec, build job, root artifact version, source commit, artifact digest, migration-set digest, runtime-target digest, lifecycle status, rollback target, rollback eligibility, and verification run.

A version cannot become `verified`, `production_candidate`, or `live` without a bound verification run whose status is `PASS` and whose immutable identity digests match the version.

Direct authenticated mutation of project versions is forbidden. Version truth is service-owned.

## 7. Independent verification contract

Verification state is durable in:

- `pandora_verification_runs`
- `pandora_verification_checks`
- `pandora_verification_evidence`

Verification identity binds the exact ProjectSpec/project version/source/artifact/migration/runtime target. A builder cannot make a project version release-eligible merely by changing a status field.

Worker E executes independent verification; Worker A stores its durable contract and evidence references.

## 8. Policy and approvals

`pandora_policy_actions` binds an exact action hash, argument digest, tool identity/version, environment, risk, side-effect class, policy version, and optional approval.

The existing `approvals` table remains the approval authority. An approval is valid only when its organization and exact `action_hash` match the proposed action and it remains approved and unexpired.

High-risk provider execution remains owned by the Tool Gateway / specialist workers. Worker A stores the authoritative decision and lineage.

## 9. Economics and budgets

`pandora_budget_limits` provides service-owned hard spending limits by project/build/model/verification/deployment/runtime/provider scope. Budget reservation, release, and commit are atomic private operations.

`pandora_cost_entries` is append-only and idempotent. It records model, build compute, verification, deployment, runtime, storage, network, and provider-API cost in integer micros, including estimated, billed, charged, and credit values.

Cost metadata is redacted and rejected when it contains secret-like keys.

## 10. Project knowledge graph

Queryable semantic project structure is stored in `pandora_project_nodes` and `pandora_project_relationships`.

Nodes are bound to one immutable ProjectSpec and may represent features, workflows, pages, entities, integrations, runtime components, acceptance criteria, and business objectives. Relationships may bind requirements, artifact versions, and project versions so Pandora can answer project-structure and impact questions without treating chat history as the database.

## 11. Generated-application runtime isolation

`pandora_runtime_resources` records generated-application runtime metadata for database, storage, auth, edge functions, web runtime, queues, caches, search, analytics, domains, and related resources.

Isolation is explicit: `dedicated`, `shared_isolated`, or `logical`.

Where a runtime resource also exists in `projectos_project_resources`, provider and external identity must match.

This table records runtime truth. It does not provision infrastructure itself. Worker F owns provider execution.

## 12. Secret references

`pandora_secret_references` stores secret-reference metadata only: provider, environment, logical secret name, purpose/scopes, reference kind, reference locator, version/rotation state, and lifecycle timestamps.

It never stores the credential value.

The table is service-only and is not customer-readable. Credential values stay in Supabase Vault or the provider's secret store.

## 13. Database-change safety

Database mutations are planned in `pandora_database_change_plans` and `pandora_database_change_items`.

A plan binds exact schema-before/schema-after/diff/migration/action hashes, target database runtime resource, compatibility/destructive-change assessment, lock risk, approval, migration artifact, backup artifact, rollback-plan digest, execution tool call, and verification run.

Production or destructive execution requires an action-bound live approval, a backup artifact, and rollback plan. Applied state requires tool-call lineage. Verified state requires independent `PASS` verification.

Worker A stores this state. The Tool Gateway/runtime worker executes the mutation.

## 14. Build Theatre Realtime projection

`pandora_build_theatre_projection` is the only Worker A table intentionally added to `supabase_realtime`.

It exposes only customer-safe fields: project/build/spec/version references, owner state/stage, bounded progress, fixed public message, safe preview/live URL, Needs You state, retry availability, and timestamps.

It never contains model prompts, model responses, tool arguments/results, worker identity, lease tokens, internal error codes, raw logs, secret references, or credential values.

The projection is derived by database triggers from durable build/version/deployment/domain truth and is member-readable under RLS. Customers cannot write it.

## 15. Immutable audit history

Pandora continues using the existing organization hash-chained `audit_events` table.

Control Plane V1 extends it with project/resource addressing, request/idempotency identity, action hash, and redacted provenance. Project identifiers intentionally are historical values rather than cascading foreign keys so audit history survives project deletion.

A private security-definer append function takes the organization advisory lock, reads the prior organization event hash, builds a bounded/redacted payload, rejects secret-like keys, computes the new SHA-256 event hash, and inserts the event.

Direct table insert/update/delete is unavailable to `anon`, `authenticated`, and `service_role`.

Lifecycle triggers append audit events for ProjectSpec, build jobs, verification, policy/approvals, versions, deployments/domains, budgets, runtime resources, secret-reference lifecycle, and database-change plans.

## 16. RLS and authority model

Customer access is organization-scoped. Authenticated members may read the customer-visible Control Plane records allowed by RLS.

Customer intent intake is the deliberate customer-write exception: an authenticated member may insert their own customer intent, but cannot spoof requester identity.

Service-owned truth includes compiled ProjectSpecs, build jobs, model/tool/artifact lineage, verification, policy actions, budgets/costs, runtime-resource truth, secret references, database plans, project versions, deployments/domains, and Build Theatre projection.

Direct authenticated mutation of `pandora_project_versions`, `pandora_project_deployments`, and `pandora_project_domains` is removed in Control Plane V1.

Private trigger/validator functions are not customer RPCs. Their default PUBLIC/anon/authenticated EXECUTE privileges are revoked. The customer-intent scope helper remains callable where required by its RLS/check-constraint path.

## 17. Query-driven indexes

Control Plane indexes are tied to live access patterns: active jobs and expiring leases, per-project active stage/build history, latest ProjectSpec/version and live version, verification status/project identity, pending policy actions, budget/cost scopes, runtime-resource environment/type/status, database-change pending state, project/resource/idempotency audit history, and the Realtime owner-state projection.

## 18. Worker boundaries

- Worker A: durable Control Plane and system of record.
- Worker B: intent compilation, context, model routing, Gemini/model execution proposals.
- Worker C: Tool Gateway, policy evaluation, approval enforcement, scoped secret brokering, authorized execution boundary.
- Worker D: isolated build workspace/runtime execution.
- Worker E: independent verification execution.
- Worker F: preview/production/runtime provider execution and reconciliation.
- Worker G: customer product experience and Build Theatre presentation.
- Worker H: business intelligence/economics analysis and optimization recommendations.
- Worker I: trusted primitive implementations/composition.
- Worker J: cross-worker integration, E2E proof, release convergence.

Provider workers may update Worker A contracts only through their governed service boundaries. Worker A does not take over their execution lanes.

## 19. Release and rollback rules

A release path is eligible only when exact immutable identities line up:

`ProjectSpec + Build Job + Artifact + Project Version + Verification PASS + Policy/Approval (when required) + Runtime target`

Production promotion must not be inferred from a provider URL alone. Rollback is represented as explicit project-version/build/database-change lineage rather than destructive history rewriting.

## 20. Completion proof

Worker A is complete only when all of the following are true on the same current `main`:

- all four Worker A migrations replay successfully from source;
- repository source/parity gates pass;
- Node, security, Flutter, Android, and exact-source gates pass;
- the four source migrations exist in the production Supabase migration ledger;
- required tables/functions/indexes/RLS policies are live;
- `pandora_build_theatre_projection` is present in `supabase_realtime`;
- raw Worker A build/model/tool/artifact/secret tables are not published for Build Theatre;
- authenticated users cannot directly mutate project versions/deployments/domains;
- secret-reference metadata contains no plaintext credential column;
- audit history remains append-only and hash chained;
- no credential value or PAT is committed as Worker A source;
- PR #26 remains untouched by Worker A.
