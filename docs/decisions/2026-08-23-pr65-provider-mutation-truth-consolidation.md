# PR 65 provider-mutation truth consolidation

Date: 2026-08-23

Decision: consolidate selected invariants; do not land the branch wholesale

Audited head: `c53ed2f333672069b915f4b9c8e6fcfe3746fc96`

Protected-main starting point: `5a630893f2102064dcb2c7c72a3374042e6b4542`

This is an implementation decision record, not a current project-status surface. Current project status remains `/api/operator/status`.

## Durable outcome

The clean protected-main-derived branch now has one provider-mutation truth contract across MCP, HTTP, and the Memory evidence-candidate adapter:

- authorization, exact payload binding, one-time claim, and provider dispatch remain separate phases;
- a provider invocation is never inferred safe to repeat from an HTTP status alone;
- unclassified failures after invocation are `ambiguous`;
- only a reviewed adapter may privately mark `failed_before_side_effects`;
- confirmed provider success is finalized as `completed` only after bounded local processing and exact durable readback;
- provider success or ambiguity followed by local/finalization failure is durably `failed` with `terminalOutcome.terminalClassification = reconciliation_required`;
- every terminal outcome disables automatic retry, and reconciliation outcomes require the original provider effect to be checked before any new plan is created;
- provider results, errors, and summaries are structurally bounded and redacted before they can cross a response or ledger boundary.

The terminal ledger `status` is intentionally `failed`, not `completed`, for reconciliation-required outcomes. Status-only readers therefore cannot mistake the execution for success. Readers that list plans receive a separate bounded `terminalOutcome`, derived inside the database from the stored terminal evidence. It exposes only allowlisted truth fields such as provider outcome, mutation state, retry contract, reconciliation requirement, and identity hashes. It never exposes the provider payload or raw error text. Unknown legacy failures conservatively become `failed_unknown` plus `reconcile_before_retry`.

## Consolidated from PR 65

The following application concepts were retained and hardened for the current branch:

- canonical execution-payload hashing in `src/runtime/execution-payload.js`;
- bounded provider-result normalization in `src/runtime/provider-result-contract.js`;
- provider outcome and mutation-state envelopes in `src/runtime/provider-outcome-contract.js`;
- the guarded post-provider state machine in `src/runtime/provider-execution-state-machine.js`;
- the separated Memory evidence-candidate adapter in `src/tools/memory-evidence-intake-core.js` and its governed wrapper;
- MCP and HTTP use of the same guarded execution contract;
- one immutable, allowlisted Memory idempotency identity;
- exact durable finalization readback in `src/runtime/execution-ledger-client.js`;
- focused provider truth, idempotency, Memory scope, and finalization tests.

Additional convergence work, required to make those invariants safe on the current branch, was added rather than copied from PR 65:

- `supabase/migrations/20260823150000_add_safe_execution_terminal_outcomes.sql` adds the private terminal-outcome projection and extends `list_execution_plans` with its bounded safe result;
- `docs/supabase/recovery/jcyqixttuebxqqfkjonq/rollback/20260823150000_remove_safe_execution_terminal_outcomes.sql` restores the exact prior list shape and removes only the derived helper;
- Control Tower's canonical and public mirrors label reconciliation-required terminal plans explicitly and warn that provider execution must not be repeated;
- database replay and list/readback tests prove the non-retry contract and absence of raw provider payloads.

## Already present or superseded on current main

These protections were kept from the protected-main-derived implementation rather than replaced with PR 65 variants:

- durable create, approve, claim, exact payload-hash, expiry, and one-time lifecycle gates;
- current request-path handling that avoids enumerating or invoking Vercel accessor-backed request state;
- current MCP structured-content response behavior;
- the active Memory privacy scanner, governed namespace checks, proof-stage validation, and production configuration path;
- current owner/worker, mobile, release-evidence, and canonical-status convergence work.

## Rejected from PR 65

The following branch behavior or artifacts were not imported:

- treating generic HTTP 408 or 429 responses as proof that dispatch did not occur;
- treating a malformed or negative 2xx provider body as proof of no side effect;
- trusting an arbitrary thrown `.providerOutcome` property;
- recording reconciliation-required provider success or ambiguity as `completed`;
- retrying finalization three times before checking durable state;
- the `http-app-core.js` and `projectos-mcp-handler-core.js` branch split, which would regress current request-accessor protections;
- old-head fixtures, regression harness snapshots, one-shot workflows, branch-specific audit prose, and branch deletions.

## Verification

- Full Node/application suite: 294 passed, 0 failed.
- Windows-worker suite: 13 passed, 0 failed.
- Complete static check: passed, including TypeScript, 17 browser syntax checks, 29 mirror checks, 4 Supabase Edge syntax checks, and Deno type checking.
- PGlite migration replay: 60 migrations; chain SHA-256 `ca602fb8d360b24e8af33e1fa468300131944d40b9eaab1829e360eb9a44be66`.
- Replay assertions: reconciliation terminal status `failed`; classification `reconciliation_required`; automatic retry disabled; raw provider payload absent; unknown failures require reconciliation.
- Focused provider-mutation set: 49 passed, 0 failed. The maximal optional-metadata envelope is 981 bytes against a 1000-byte cap.

PGlite replay is deterministic source validation, not proof of provider equivalence. The migration must be deployed before the application version that requires `terminalOutcome` readback. No live provider mutation, production deployment, rollback, or physical Android journey was performed as part of this consolidation.
