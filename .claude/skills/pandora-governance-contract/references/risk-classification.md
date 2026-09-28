# Risk classification — decision procedure

## The four tiers

**READ-ONLY.** Inspection, retrieval, listing, reading provider state. No state changes anywhere. Proceed freely and without approval. Pandora's `requiresApproval()` returns false only for `read`.

**SAFE REVERSIBLE MUTATION.** Changes state, fully reversible by you, no new spending, inside authorization the owner already granted. Examples: creating a branch, opening a draft PR, committing to a non-protected feature branch, creating a Supabase preview branch within existing quota, submitting an evidence candidate for review.
Proceed autonomously. Record what you did.

**SENSITIVE MUTATION.** Reversible only with effort, or touches security, authorization, customer-visible surface, or shared state. Examples: schema migration on a shared database, modifying RLS policies, changing CI workflow permissions, altering environment variables, merging to a protected branch.
Requires: existing durable authorization + proof the change is correct + a rollback artifact identified *before* acting. Prefer a preview/branch rehearsal first.

**DESTRUCTIVE / HIGH-RISK.** Fail closed. Do not act without explicit owner authorization for this specific action.

## Always-escalate list

No amount of confidence downgrades these:

- irreversible deletion of anything (repository, project, branch with unmerged work, data)
- production database destruction, truncation, or destructive migration
- **new spending** — any action that creates a charge that did not already exist
- public commitments: published content, external communications, anything a third party will read as a promise
- production financial activity: real money movement, live payment capture, payouts, refunds against real funds
- regulated activation: turning on a payments/health/legal/identity/employment capability for real users
- secret exposure, including into logs, code, screenshots, PR bodies, or Memory
- weakening any security control — RLS off, auth check removed, CI check disabled, protection bypassed
- a production release not covered by an existing durable authorization

## Procedure

1. Name the exact action and its exact target. "Update the database" is unclassifiable; "apply migration X to Supabase project kywmbyekwgtghkhhurof" is classifiable.
2. Ask: if this is wrong, what does it take to undo? If the answer involves data loss, money, or a third party's knowledge, it is at least SENSITIVE.
3. Check the always-escalate list.
4. Check the tool's declared risk in `pandora_tool_catalog`. **The declared risk is a floor, not a ceiling** — `github.write-repository-api` is declared `write`, but using it to force-push over unmerged work is destructive in effect.
5. Classify by effect, not by tool name.

## The unknown-tool rule

Pandora's runtime classifies any tool it does not recognize as `destructive`. Adopt the same posture: an unfamiliar capability, an undocumented endpoint, or a tool whose blast radius you cannot describe is treated as high-risk until you have established otherwise. Prefix conventions and reassuring names ("sync", "refresh", "update") are not evidence of safety.

## Worked cases

*Opening a draft PR from a feature branch* → SAFE REVERSIBLE. Autonomous.

*Merging that PR to a protected main* → SENSITIVE at minimum. Requires review proof and passing exact-head CI. If merging triggers a production deploy, it is a production release and escalates.

*Enabling Supabase leaked-password protection* → SENSITIVE, but strictly security-strengthening and reversible. The Pandora tool for this deliberately rejects disabling. Proceed with existing authorization; record evidence.

*Creating a Supabase project* → new spending. ESCALATE, always, even if the plan called for it.

*Reading provider state to resolve a Memory contradiction* → READ-ONLY. Do this eagerly; it is how contradictions get resolved.

*Submitting an evidence candidate to Memory* → SAFE REVERSIBLE. It is a proposal for human review and never becomes canonical automatically. This is the intended way to record findings.
