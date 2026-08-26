---
name: pandora-evidence-ledger
description: "Record verified findings and project-state changes into Pandora Memory as governed evidence candidates. Load after establishing something worth remembering — a completed proof gate, a resolved contradiction, a provider fact, a security finding, a release outcome — or whenever asked to 'update Memory' or 'record this'. Covers proof-stage selection, provenance construction, idempotency, and why candidates never auto-promote to canon."
---

# Pandora Evidence Ledger

Work that is not recorded did not durably happen. The next session, the next agent, and the next incident all start from Memory — if your finding is not there, it is lost.

## The governed path

Evidence enters Memory as a **candidate for human review**. It never becomes canonical automatically. That is the design: an agent can propose, only a human can canonize.

```
projectos_plan_memory_submitEvidenceCandidate  → durable plan (not executed)
projectos_approve_plan                          → authenticated owner/admin approval
projectos_execute_plan                          → one-time claim + submit
```

Three separate calls. Creating a plan does nothing on its own; approving it does nothing on its own. This separation is what makes the write path auditable.

The tool is classified `write`, so approval is required — `requiresApproval()` returns true for anything that is not `read`.

## Required fields

| Field | Rule |
|---|---|
| `namespace` | `real_life` or `au`. Confirm it; do not assume. |
| `title` | Specific and self-contained. It will be read years later out of context. |
| `summary` | ≤1800 chars. The finding, its evidence, its limits. |
| `proofStage` | `documented` / `implemented` / `tested` / `deployed` / `production_verified` |
| `claim` | The single assertion this record makes |
| `evidenceRefs[]` | `{type, ref}` plus `sha256`, `observed_at`, `artifact_class` where available |
| `provenance` | `{source_type, source_locator, observed_at}` plus `source_sha`, `parent_sha` |
| `idempotencyKey` | Derived from intent, so a retry cannot double-write |
| `projectKey` / `projectId` | The **canonical** key. Verify it — see below. |

## Choosing the proof stage

This is the field most often wrong, and getting it wrong writes a false claim into canon.

Claim the stage you actually reached, not the one you were aiming at. If you implemented and tested but did not deploy, the stage is `tested`. A record claiming `production_verified` asserts that you observed correct production behavior on an exact artifact *and* proved rollback — if you did not do both, do not claim it.

Requirements per stage: `pandora-governance-contract/references/proof-gates.md`.

When a finding spans stages, split it. One record per claim keeps precedence resolvable later.

## Provenance

Provenance is what makes a record auditable. Weak provenance produces a record nobody can trust in six months.

Strong: `{source_type: "github_commit", source_locator: "pandora-rvw-314296438-20260820/pandoras-box@<sha>", source_sha: "<sha>", parent_sha: "<parent>", observed_at: "<iso8601>"}`

Weak: `{source_type: "analysis", source_locator: "reviewed the code", observed_at: "today"}`

Prefer content-addressed references — commit SHAs, tree SHAs, SHA-256 hashes, deployment IDs, run IDs. Prefer things that cannot move. A branch name is not provenance; branches move. A PR number is not provenance; heads advance.

## Project key discipline

Before submitting, confirm the canonical project key. Key drift silently partitions a project's history across several keys, and the damage is only visible much later when a query returns two thirds of the truth.

Check `projectos_list_plans` for the keys actually in use and reconcile against the canonical instruction. If you find drift, that itself is a finding worth recording — and worth escalating, because merging partitioned history is a repair someone has to authorize.

Note that Pandora's intake derives a fallback key when arguments carry no repository, so an omitted `projectKey` does not mean "no key" — it means a default was chosen for you. Pass the key explicitly.

## Idempotency

Key on intent, never on the attempt: `evidence:<project>:<capability>:<proof-stage>:<source-sha>` is stable across retries. A timestamp or random value is not.

If a submission fails *after* the provider confirmed, do not re-submit — read back and reconcile. The confirmed-mutation rule in `pandora-governance-contract/references/mutation-safety.md` governs this exactly.

## When intake blocks

A plan can fail with `intakeStatus: blocked`. The mandatory-intake gate requires an executable intake state (`accepted`, `analyzing`, `planned`, or `executing`); anything else is rejected by design.

Blocked is a governance signal, not a transient error. **Do not retry it unchanged, and do not route around it.** Diagnose: is the project key wrong, is the repository historical-only under the source-authority policy, is the intake in a terminal state? Fix the cause or escalate. Retrying a blocked plan is how a governance gate gets worn down.

## Never record

Credentials, tokens, keys, OIDC material · private customer or KYC data · financial documents · message contents · anything already surfaced as `[REDACTED]`.

Record the shape and location of sensitive findings, never their content.

## Never record as fact

Inferences, intentions, plans, or agent assertions. Memory holds what was *verified*. "We will deploy this Friday" is not evidence. "Deployment dpl_X is READY and bound to SHA Y, observed at T" is.

## Output

```
CANDIDATE     <title>
PROOF STAGE   <stage> — <why this stage and not the next one up>
CLAIM         <the assertion>
EVIDENCE      <refs with hashes and timestamps>
PLAN          <planId> · approved: <bool> · executed: <bool>
STATUS        <submitted | pending approval | blocked — with reason>
```

Report honestly when a candidate is created but not approved. A pending candidate is not a recorded fact.
