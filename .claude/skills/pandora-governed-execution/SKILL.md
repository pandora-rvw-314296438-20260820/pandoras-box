---
name: pandora-governed-execution
description: "Execute provider mutations through the Pandora plan → approve → execute path with audit, idempotency, and fail-closed gates. Load before any action that changes state in GitHub, Supabase, Memory, or another connected provider; when a mutation failed or its outcome is ambiguous; or when deciding whether an action needs owner approval. Covers one-time claims, payload integrity, confirmed-mutation safety, and audit verification."
---

# Pandora Governed Execution

Reads are direct. **Mutations are never direct.** Every state change goes through a durable plan that is separately created, approved, and executed.

## Why the three steps are separate

```
pandora_create_plan / pandora_plan_<tool>   → durable plan; nothing happens yet
pandora_approve_plan                           → authenticated owner/admin; still nothing happens
pandora_execute_plan                           → one-time claim, then the mutation
```

Separation is the control. The planner cannot self-execute; the approver sees an exact, hashed payload rather than a description of one; execution claims the plan once, so a duplicate invocation cannot produce a duplicate effect. A plan carries `payloadHash`, `memoryContextHash`, `intakeId`, and `claimedAt` — payload integrity, context binding, intake linkage, and single-claim, all enforced at execution time.

Never look for a shortcut around this. If a mutation seems to need a direct call, the correct conclusion is that the capability is missing, not that the gate should be bypassed.

## Before planning

1. **Classify the risk** by effect, not by tool name. See `pandora-governance-contract/references/risk-classification.md`. Note that the runtime classifies any unknown tool as `destructive` — adopt the same default.
2. **Confirm the tool exists** in `pandora_tool_catalog`, with its risk, scope, allowlist, and required provider scopes. Do not plan against a tool you have not seen in the catalog.
3. **Check the source-authority policy.** Mutations targeting a historical-only repository (every `mbanatao/*`) are rejected fail-closed, and correctly so.
4. **Identify the rollback artifact** — before acting, not after failing.
5. **Decide whether this needs the owner.** `read` never does. Everything else does, and the always-escalate list overrides any local judgment.

## Constructing the plan

Use the specific `pandora_plan_<tool>` variant when one exists; it carries the correct schema. Fall back to `pandora_create_plan` with an exact `tool` and `args`.

Make arguments exact and minimal. A plan is a commitment to a specific effect on a specific target — vague arguments produce a plan nobody can meaningfully approve. Include the project key explicitly rather than letting intake derive a fallback.

Then **read your own plan back** as an approver would. If the payload does not make the blast radius obvious, rewrite it.

## Executing

Execute only after approval. On execution, the platform re-enforces payload integrity, the one-time claim, allowlists, mutation policy, and destructive gates — approval does not disable any of them.

After execution, **read the provider back** to confirm the effect. A success response is a claim about the effect; the provider's state is the effect. For anything sensitive, verify independently.

## When execution fails

Classify the failure before reacting:

| Symptom | Meaning | Action |
|---|---|---|
| `intakeStatus: blocked` | Governance gate, by design | Diagnose the cause. Do not retry unchanged. |
| Payload hash mismatch | Plan mutated after approval | Fail closed. Investigate — this is a tamper signal. |
| Already claimed | Plan already executed once | Read provider state. **Do not re-execute.** |
| Allowlist rejection | Target outside authorized scope | Escalate. Never widen the allowlist to pass. |
| Provider 5xx / timeout | Ambiguous | Read back before any retry. |

The gate that says no is doing its job. Weakening it to make a workflow pass is explicitly prohibited.

## Confirmed mutations

The rule that prevents duplicate real-world effects:

> Once a provider confirms a mutation, a downstream serialization, validation, or reporting failure must not reclassify it as failed-and-retryable.

If the provider confirmed and your parsing then threw, the external state changed. Record the confirmed effect immediately, mark the *reporting* step failed, reconcile by reading back — and never re-issue. The full procedure, including genuinely ambiguous outcomes, is in `pandora-governance-contract/references/mutation-safety.md`.

For ambiguity you cannot resolve by reading back, escalate. Guessing on money, communications, or third-party-visible state is not acceptable.

## Audit

`pandora_verify_audit` verifies the hash-linked chain and returns `valid`, `eventCount`, and `lastHash`.

Verify after meaningful mutations and during any incident. **A chain that does not verify is an incident in itself** — escalate immediately, do not continue mutating, and do not attempt to repair the chain. Its value is that it is tamper-evident; an agent "fixing" it destroys exactly that property.

Record `eventCount` and `lastHash` in your evidence so a later reader can bind their view of history to yours.

## Bulk operations

Never issue unbounded bulk mutations. Batch with explicit bounds, isolate failures so one bad item does not poison the run, verify a small batch end-to-end before scaling, and keep per-item idempotency keys.

## Output

```
ACTION        <exact operation and target>
RISK CLASS    <read-only | safe reversible | sensitive | destructive>
PLAN          <planId> · payloadHash · approved by <who> at <when>
EXECUTION     <claimed at> · <result>
READBACK      <what the provider shows now>
ROLLBACK      <artifact> · proven: <bool>
AUDIT         eventCount <n> · lastHash <hash> · valid: <bool>
PROOF STATE   <stage reached>
```

## Handoff

Record the outcome → `pandora-evidence-ledger`.
Mutation was a release → `pandora-deployment-release`.
Tool missing or unauthenticated → `pandora-mcp-discovery`.
