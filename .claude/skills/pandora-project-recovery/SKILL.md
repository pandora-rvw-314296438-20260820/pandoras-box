---
name: pandora-project-recovery
description: "Rebuild working context for a Pandora project from durable evidence after a lost chat, a new session, an agent handoff, or a long gap. Load when you have little or no context about a project you are asked to work on, when the user says they lost a conversation, when taking over work another agent started, or when preparing a handoff. Reconstructs state from Memory and providers rather than from recollection."
---

# Pandora Project Recovery

Pandora projects must not depend on one chat, one device, one agent, or human memory. This skill is the proof of that property: everything needed to resume work is recoverable from durable evidence.

If recovery fails, that is a finding about the project's durability — record it.

## When you are recovering

Signals: a new session with no established state · "we were working on X" with no detail · taking over from another agent · a long gap since the last touch · the user has lost the conversation.

Do not paper over this by asking the user to re-explain the project. They should not have to be the backup. Recover from evidence first, then ask only about genuine gaps.

## Sequence

**1. Establish identity.**
Which project, which namespace, which canonical repository, which Pandora project key. If the request is ambiguous, resolve it from Memory before going further — recovering the wrong project wastes the whole effort.

Watch for **project-key drift**: the same project appearing under several keys partitions its history, so a query returns a confident but partial picture. If you see drift, treat it as a finding, not a nuisance.

**2. Recover canonical state.**
`memory_canonicalContext`, checking `degraded`, `conflicts`, and `freshestRecordAt` before the payload. See `pandora-memory-context`.

**3. Recover work in flight.**
`pandora_list_plans` — completed, in-flight, and failed. Failed plans are exactly the open loops a lost chat leaves behind, and they are invisible to anyone who only reads the roadmap.
`pandora_list_audit` and `pandora_verify_audit` — what actually executed, and whether the record is intact.

**4. Recover provider truth.**
For each provider in scope, read current state: repository heads and open PRs · database migrations and advisors · deployments and their source bindings. Then compare against Memory. Divergence tells you what changed while nobody was recording.

**5. Reconcile.**
Fresh provider evidence wins for external state. Preserve the correction and its provenance rather than discarding the Memory record — `pandora-memory-context` covers the procedure.

**6. Rebuild the state model.**
Fill in the model from `pandora-control-tower`. Every unknown is a finding.

## What "recovered" means

You have recovered when you can state, from evidence:

- what the project is for
- its current phase and what closes it
- the exact source state (SHAs, not branch names)
- per-capability proof state
- what is in flight and what failed
- what is blocked and who unblocks it
- the highest-value safe next action

If you cannot state these, you have partially recovered. Say which parts are missing rather than filling them with plausible inference. A confident reconstruction that is wrong is worse than an honest partial one, because nobody will re-check it.

## Handoff packages

When handing work to another agent or session, write down what the receiver would otherwise have to re-derive:

```
PROJECT       identity · namespace · canonical repository · project key
PURPOSE       one sentence
PHASE         current phase · what closes it
EXACT STATE   head SHA · tree SHA · open PRs with head SHAs · deployment IDs + bound source SHAs
PROOF         per capability, with what proved it
IN FLIGHT     plans created/approved/executing, with IDs
BLOCKED       what and who
OPEN LOOPS    unfinished work, failed plans, unresolved contradictions
NEXT ACTION   the one thing to do next
AUTHORITY     what the receiver may do without asking, and what needs the owner
DO NOT        traps discovered — stale sources, blocked paths, things that look safe and are not
```

`DO NOT` earns its place. Knowledge of what *not* to do is the first thing lost in a handoff and the most expensive to relearn.

Persist the package via `pandora-evidence-ledger` rather than leaving it in chat. A handoff that lives only in a conversation reproduces the failure this skill exists to prevent.

## Recovery failure

If durable evidence is insufficient to resume work, that is a single-point-of-failure finding. Record what was unrecoverable and what would have made it recoverable, then route to `pandora-disaster-recovery` to close the gap. Do not simply ask the owner to remember — that re-establishes the dependency the architecture forbids.

## Output

```
RECOVERED     <what you established, with evidence>
UNRECOVERED   <what is missing, and why it could not be recovered>
CONTRADICTIONS <Memory vs provider divergence found>
OPEN LOOPS    <in-flight and failed work>
NEXT ACTION   <one>
DURABILITY    <gaps in the project's own recoverability>
```
