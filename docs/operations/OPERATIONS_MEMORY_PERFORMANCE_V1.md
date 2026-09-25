# Operations Room approved numeric Memory performance client V1

Task OPS-MEMORY-PERFORMANCE-V1-001; Operations Room714 comments5838373571 and5838708095; tracker38. ChatGPT authored this isolated source increment on the authorized RDP. This branch is stacked on Box736: initially fd920a66c31ee7569af1fba642a23facb6fa44f9, then reconciled to current parent841e1d3fb5740617f3e8e43686dbf6592adbf87d. The parent Memory contracts/client are byte-identical across that update. Only four new files are added; parent, primary Router/ARES/UI and activation source are unchanged.

## Interface

`NativeOperationsPerformanceClient` receives the unchanged Box736 trusted Memory mapping plus a server-owned Supabase client fixed to the canonical Memory project. `getPerformance(scope, request, {signal})` calls only `memory_operations_performance_v1`. It has no mutation, credential-discovery, provider-selection or approval operation.

Requests specify one of the ten frozen Router capability classes and optional exact provider/model/revision/configuration filters. A fresh request identity and complete mapping are checked on reply. Client target changes, stale replies, cross-project/namespace/principal/environment results, invalid metrics, overlapping cohorts and claimed provider/action authorization are rejected.

Only actual approved, current and fresh performance snapshots are accepted. Unreported latency, quality, billing, revision and configuration remain null/unknown. `meanLatencyMs` is an aggregate, and `estimatedWindowCostMicros`/`billedWindowCostMicros` are totals for the evidence window, not per-call prices. A single latest snapshot per exact cohort is returned; samples from overlapping windows must not be summed.

The trusted caller must recheck current security/permission policy, owner overrides, capability, provider health and budgets. Memory evidence cannot approve a provider or action. Never treat the largest raw sample count as proof of the best model, compare incomparable revisions/configurations, or claim global optimality from a truncated result. A zero-row reply means `insufficient_history` and requires an explicitly approved non-history policy, not fabricated performance.

## Verification and release

83 focused client cases plus one actual SQL/client boundary test passed on Node24.21.0,84 total. The boundary test executes96 assertions from the exact Memory SQL in disposable PGlite, then proves numeric response compatibility and actual grant denial. Those96 repeat the Memory suite rather than adding another96 unique cases. Cancellation, timeouts, stale/scope-mismatched data, malformed metrics, unknown values, deterministic filters and credential-shaped output are covered.

The new workflow pins Memory PR116 source commit2a35b71a0da910d9da99bde9b19eb2c5e88e9ba1 and verifies SHA-256 for fixture, migration and behavior before execution. The normal root suite skips this one cross-repository boundary case when SQL is not supplied; dedicated CI must execute it. No dependency, lockfile, master token or SSH ACL changed.

Actual provider-network read acceptance, governed Memory migration deployment and primary Router call-site adoption remain separate release gates. No production DDL, grant expansion, canonical promotion, automatic best-model decision, production optimization or physical-device acceptance is claimed. The live baseline contained zero approved provider-performance records.

Rollback removes/pauses this new read consumer; it never deletes Memory or rewrites prior outcome evidence. Existing parent retrieval/outcome-delivery interfaces remain unchanged.
