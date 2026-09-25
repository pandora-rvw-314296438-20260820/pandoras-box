# Operations Room native Memory integration V1

Status: source candidate. No live runtime enrollment, production deployment or all-upgrades completion is asserted.

## Ownership and boundaries

ChatGPT remains the coding and reasoning engine. Operations Room coordinates tasks/resources; the separate Intelligence Router coordinates models; Memory records evidence and approved learning. This additive integration reuses the canonical `memory_task_context_v1` and `memory_ingest_model_outcome_candidate_v1` functions through a new bounded Memory wrapper. It does not change the active Router, ARES, UI, Memory gateway or review/promotion implementations.

The server-only `NativeOperationsMemoryClient` accepts an existing trusted Supabase client for the exact canonical Memory project, plus a trusted mapping from the Operations Room project to its Memory project/user/principal. These are different identity namespaces: never guess one UUID from the other. Credentials stay with the server credential holder; no secret value, arbitrary URL or SQL is an adapter input.

## Calls and adoption

- `getTaskContext(scope, request)` performs native hard-canon task-aware retrieval. Policies remain separate from advisory records. Neither category grants execution authority. Degraded context remains degraded; missing typed grants remain empty. Numeric routing performance cannot be inferred from text summaries.
- `proposeOutcome(scope, outcome)` writes one validated metadata-only model-outcome candidate, then independently reads back the persisted candidate, review row and immutable delivery receipt. A candidate is never approved canonical Memory.
- `reconcileOutcome(scope, outcome)` only reads. An unknown response never triggers an automatic second write. Safe explicit replay must retain exactly the same outcome identity and payload; conflicting replay is rejected server-side.

Before calling the adapter, the trusted Operations Room/M3 runtime must authenticate the workload, validate its current task/lease/generation and project mapping, and read the actual canonical verification evidence. The adapter is not an authorization issuer or an exposed browser endpoint. Do not construct its privileged client from model input. No existing credential is copied into the source.

The complete required outcome envelope is exported as `OUTCOME_FIELDS`. It preserves provider/model, actual revision when available, task class, routing-policy version, execution/verification/downstream status, latency, nullable quality/cost/token usage, retries, source commit, deployment evidence, configuration digest and evidence references. Missing revision stays explicitly unreported; unknown cost is not zero. Prompts, model outputs and customer records are not accepted.

## Cross-repository dependency

Memory must first deploy the reviewed CLI-generated `pandora_operations_memory_bridge_v1` migration from its canonical repository. That wrapper locks current principal/project grants, rejects payload-conflicting replay, invokes the native M5 functions, and verifies full candidate plus review lineage. Its immutable receipt is delivery evidence, not a competing Memory database.

Then the primary Router owner can adopt this client at the existing retrieval/outcome boundaries, supply actual run/source/verification metadata and bind the receipt to its durable learning outbox. The current Router outcome envelope must be enriched from authoritative records where revision, policy, source or occurrence time is missing; never invent these fields. Approved performance aggregation for routing is a distinct acceptance gate; this component does not convert summaries into statistics or promote its own outcomes.

## Verification and limitations

Run `node --test test/pandora-operations-memory*.test.js`. The client suite uses mocked RPC transport to test behavior, not to claim live connectivity. Memory's companion tests execute the exact existing native SQL plus the new wrapper against disposable fixtures, with an independent-connection PostgreSQL workflow for replay and grant races.

As authored, 57 client cases passed on Node 24.21.0. Runtime adoption, production migration, protected credential/principal configuration, independent review and real end-to-end inference-to-Memory acceptance remain required. Keep these distinct from passing source tests.

## Rollback

Before activation, keep the new consumer disabled. After governed activation, pause its outbound deliveries and leave ambiguous outcomes reserved for reconciliation. Preserve native candidates, review history and immutable delivery receipts. Never delete history to clear a retry, bypass a grant, or self-promote a candidate.
