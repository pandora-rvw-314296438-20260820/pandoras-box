# Operations final production canary v1

This change closes source/runtime convergence for the Operations Room activation.

## Production Memory proof

Every production Vercel build runs `scripts/verify-operations-memory-production.mjs` after the normal TypeScript build and before the Pandora web artifact build. The script obtains Vercel's platform-issued workload OIDC token and uses the existing fixed Operations Memory transport. It must complete:

1. task-aware context retrieval;
2. approved provider-performance retrieval (including valid insufficient-history state);
3. review-only model outcome delivery;
4. independent delivery readback with the same receipt/candidate/review identities.

The canary explicitly requires `canonicalMemoryWritten=false`. It keeps model revision, token usage, and estimated/billed costs unknown instead of inventing them. Only a bounded sanitized JSON proof is written to `/operations-memory-canary.json`; no token or Memory payload is published.

## Native scheduler source convergence

The repository now carries the exact live migration `20260926061518_operations_native_pg_cron_worker_v1.sql` and its exact-head binding correction `20260926062157_operations_native_exact_head_binding_fix_v1.sql`. The live scheduler runs once per minute, registers distinct builder/release principals, claims only the fixed connector canary task, uses exact tested PR-head evidence, and performs independent Operations-native release verification.

## Session sheet bridge

The current ChatGPT session is a session-bound worker, not a persistent Workspace Agent. The existing Operations Task Intake tab was read through the authorized Google connector, machine-owned O:U fields were synchronized, and an independent readback confirmed owner-entered A:N definitions remained value-equivalent. This is the supported one-chat-session Sheets bridge until a separately authorized persistent Google runtime connection exists.

## Acceptance discipline

A queued provider request, source merge, deployment, or model response is not task completion. Canonical completion requires the native Operations verification event and receipt. The workspace remains `noProduction=true` during activation canaries.
