# Pandora Tool Gateway V1

Status: implemented architecture for Worker C. This document describes merged behavior only; provider credentials remain outside model and customer-visible contexts.

## Purpose

Pandora models propose actions. They do not execute tools directly and they do not possess provider credentials.

Canonical flow:

`model proposal -> Tool Gateway validation -> policy/risk -> approval binding -> durability/idempotency/rate/concurrency -> scoped trusted executor -> normalized receipt + immutable lineage`

The gateway is default-deny. An action is executable only when every required contract is satisfied.

## Provider-independent tool contract

The registry is versioned and explicit. Registered operations cover project/context reads, bounded workspace file operations, schema inspection/query, governed database-change requests, builds/tests, preview, publish, domain attachment, and artifact metadata/content references. Arbitrary shell execution, raw provider calls, unregistered tool names, and raw SQL from model output are not Tool Gateway capabilities.

Each registered tool binds:
- exact tool name and version;
- input/output schema;
- required capability;
- allowed environments;
- default risk;
- approval mode;
- idempotency mode;
- side-effect class;
- retry semantics;
- timeout/payload bounds;
- provider-independent executor identity.

## Action identity

Every action receives a canonical action hash over the security-relevant immutable inputs, including tool/version, arguments, organization, project, environment, target resource, project version, and policy version. Model prose/reason text is not authorization data and cannot change action identity.

ProjectSpec requirement references are checked against trusted ProjectSpec context. A model cannot manufacture requirement authority.

## Policy and risk

Policy returns one of ALLOW, DENY, REQUIRE_APPROVAL, or DEFER. Unknown or incomplete high-risk state fails closed.

Policy enforces organization/project/resource ownership, exact environment, capability grants, production access, budgets, independent verification, ProjectSpec/version freshness, migration preflight, domain ownership, and current project/resource state.

Trusted preflight can elevate risk. In particular, a migration independently classified as destructive/critical cannot be authorized by a lower-risk approval that was bound before that trusted classification.

## Approval binding

Approval grants are bound to the exact action hash plus organization, project, actor, tool/version, environment, target resource, effective risk, policy version, project version, and project-state hash. Expired, revoked, consumed, cross-scope, stale-state, wrong-risk, or wrong-action approvals are rejected.

One-time approvals are consumed before provider mutation begins. Durable production operation requires durable approval storage.

## Durable execution state

Worker C uses Worker A Control Plane state rather than a competing system of record. Durable ports bind Tool Gateway events to canonical approvals, policy actions, tool calls/results, rate limits, idempotency/replay evidence, and immutable audit lineage.

Production mutation fails closed if the required durability ports are absent.

## Idempotency, replay, retry, and ambiguity

Idempotency is scoped by organization/project/environment/tool/key and action hash. A successful prior execution replays its receipt without executing again. A key reused with a different action hash is rejected. In-progress duplicates are blocked.

Only definitely safe failures can enter a retryable state when the tool's retry contract permits it. If a provider mutation may have committed but the result is unknown, the execution is classified ambiguous and automatic mutation replay is blocked pending reconciliation.

## Concurrency

Production mutations require durable concurrency protection. Worker C accepts either its own durable lease implementation or a trusted executor-owned durable claim/compare-and-set contract. A self-declared arbitrary object does not satisfy the production concurrency contract.

Worker F owns deployment/runtime claims and production compare-and-set. Worker A owns database-change plan claims. Worker C validates and binds these contracts; it does not duplicate their provider/runtime state machines.

## Worker boundaries

- Worker A: durable Control Plane, approvals, canonical execution/audit state, database-change plans.
- Worker B: intent/model proposals. Models do not execute and do not receive credentials.
- Worker C: provider-independent Tool Gateway authorization and credential scoping.
- Worker D: bounded build/workspace execution only after Worker C authorization; production workspace/build mutation is not exposed by the Tool Gateway.
- Worker E: independent verification. Builder/model self-verification is not publish authority.
- Worker F: preview/production runtime, deployment, domain, provider reconciliation and durable production runtime CAS.

Worker C executor bridges carry exact immutable lineage into D/E/F-owned contracts and never embed provider-specific deployment logic into policy code.

## Publish authorization

A production publish is authorized only for the exact verified project version/artifact/source identity, exact verification reference, exact current ProjectSpec/version state, required production capability, current budget state, approval when required, and durable runtime concurrency contract. Stale verification, artifact drift, version drift, wrong project/environment, or missing production authority is denied before provider execution.

Provider READY/promotion truth is not independent verification. Final Live truth remains subject to Worker E's independent production verification contract as implemented by the runtime layer.

## Database-change authorization

The model proposes an opaque migration reference, never a database UUID and never raw SQL. A trusted resolver maps it to an exact governed artifact. Worker C binds the action to Worker A's approved database-change plan. Destructive classification comes from trusted preflight, not model assertion. Ambiguous provider outcomes remain reconciliation-required rather than being falsely marked failed or retried.

## Secrets Broker and Vault boundary

Master/provider credentials are never model inputs, tool arguments, receipts, lineage payloads, or committed source.

Platform provider access uses dedicated server-side Supabase Vault brokers. The currently governed master credential names are `Github_supabase`, `vercel`, and `gemini_api_key`; the names are metadata, not secret values. Callers provide bounded method/path/model/body inputs only.

The Secrets Broker validates purpose plus organization/project/environment/operation/resource scope and short TTL before permitting credential use. Plaintext exists only inside the trusted holder callback and adapter result is redacted before it leaves that boundary.

Same-process callback leases may use ephemeral memory state. Opaque leases handed across worker/process boundaries require a durable lease-store capability; otherwise issuance/delegation fails closed. The public lease object contains no secret reference or plaintext credential.

Worker D/F platform Vercel execution uses its own Vault-backed provider broker and does not require copying the Vercel master token into a customer credential-lease record.

## Network safety

Outbound network access is deny-by-default and category/host allowlisted. URL credentials are rejected. Allowed hostnames must resolve through trusted DNS binding and all resolved addresses are checked before execution; private, loopback, link-local, metadata-service, and DNS-rebinding targets are denied.

## Tool output trust and receipts

Provider/tool output is untrusted data. It cannot grant capabilities, approvals, ProjectSpec authority, or follow-on execution. Receipts carry normalized provenance, execution identity, artifacts/output, retry classification, and owner-safe errors. Secret-shaped keys/values, bearer strings, credential URLs, private-key blocks, configured canaries, and known provider-token formats are redacted.

## Failure normalization

Provider-specific errors are normalized into stable classes such as authorization, invalid request, resource missing, conflict, rate limit, timeout/network, provider unavailable, policy denied, verification required, budget, and ambiguous mutation. Raw stacks and credential-bearing provider messages are not owner-facing output.

## Versioning

Tool definitions and policy are explicitly versioned. Unknown tool versions and unsupported envelope fields fail closed. Legacy model aliases are normalized only at the integration boundary before they enter the canonical v1 gateway contract.

## Proof obligations

Worker C is considered release-ready only when the exact current-main candidate passes repository CI, dependency/security checks, mobile exact-source verification, the adversarial authorization matrix, executor bridge tests, credential canary tests, and bounded live provider readbacks without exposing credentials.
