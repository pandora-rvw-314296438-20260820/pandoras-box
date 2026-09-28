---
name: pandora-control-tower
description: "Master state recovery and next-action selection for any Pandora project. Load when a request is vague or open-ended ('fix X', 'ship it', 'get it live', 'what should I work on', 'build X and deploy it'), when a request spans multiple delivery stages, when starting substantial work on a project whose current state you have not established this session, when asked for status or progress, or when choosing among competing tasks. Recovers identity, phase, source, providers, deployments, proof gates, blockers, and open loops from authoritative evidence, then selects the highest-value safe action."
---

# Pandora Control Tower

You are the control plane. Before any substantial work, establish what is actually true — then pick one action.

The failure this skill prevents: an agent reads a request, assumes a plausible project state, and does confident work against a world that does not exist. Every downstream artifact inherits the error.

## Discipline

**Recover before you plan. Plan before you act.** No exceptions for requests that sound simple.

**Never infer a capability because Pandora is intended to have it.** The roadmap describes intent. The tool catalog describes reality. Check the catalog.

**Chat recollection is not authority** when Pandora MCP can answer the question. Ask the MCP.

## Recovery sequence

Run these in parallel where they do not depend on each other — recovery is read-only and should be fast.

### 1. Connectivity
`memory_health` — if Memory is unreachable, you are operating degraded. Say so, and fall back per the hierarchy in `pandora-governance-contract`.

### 2. Canonical context
`memory_canonicalContext` with the project's namespace (`real_life` or `au`) and a query naming the project and the work at hand.

Read the envelope before the content:
- `degraded: true` → context is stale or unavailable. **Do not treat the payload as current.** Report degradation; fall back to provider evidence.
- `conflicts: [...]` non-empty → unresolved contradictions exist. Resolve them (see `pandora-memory-context`) before planning work that depends on the contested facts.
- `freshestRecordAt` → how old is your picture? Days-old canon plus an active provider means re-read the provider.

Results can be large. When the payload exceeds what you need, extract with `jq` rather than reading it whole; keep the recovery cheap.

### 3. Capability inventory
`pandora_tool_catalog` — what can actually be done, at what risk, under what allowlist. Never assume a tool exists. An unauthenticated connector is a real constraint to report, not a detail to route around.

### 4. Execution state
- `pandora_list_plans` — in-flight, completed, and **failed** plans. Failed plans are open loops; read `intakeStatus` and the failure reason.
- `pandora_verify_audit` — chain validity and event count. An invalid chain is an incident, not a warning.

### 5. Provider truth
Only for providers this work actually touches:
- **GitHub** — default branch, exact head SHA and tree SHA, protection rules, open PRs and their exact heads, workflow runs bound to those SHAs.
- **Supabase** — project status, migration ledger, RLS and policy counts, advisors, source/provider parity.
- **Vercel** — project, git binding, deployments, environment separation, alias/domain.
- **FlutterFlow** — readiness assessment, if mobile is in scope.

## The state model

Fill this in. An unknown is a finding, not a blank to guess at.

```
IDENTITY      project key · canonical repository · Memory namespace · Pandora project ID
PURPOSE       what this project is for, in one sentence
PHASE         current roadmap phase and what closes it
SOURCE        default branch head SHA + tree SHA · active branches · open PRs with exact heads
PROVIDERS     per provider: reachable? authenticated? allowlisted? what is it holding?
DEPLOYMENTS   environment · deployment ID · source SHA bound to it · verified behavior?
PROOF         per capability: documented | implemented | tested | deployed | production_verified
TESTS         last run, exact SHA, pass/total
REVIEWS       outstanding, and whether any qualifying independent review exists
SECURITY      open advisories, lints, known authorization gaps
ROLLBACK      identified target · proven or unproven
BLOCKERS      what is stopping progress, and who can unblock it
OPEN LOOPS    started and unfinished, including failed plans
```

Two entries carry disproportionate weight:

- **PROOF is per capability, not per project.** "The project is deployed" is meaningless. "Auth is production-verified; booking is implemented but untested" is actionable.
- **ROLLBACK proven vs unproven** decides whether a release gate can open at all.

## Selecting the next action

Score candidates on: does it unblock the most downstream work · is it safe and reversible · does it produce durable evidence · is it the cheapest way to close the largest uncertainty.

Prefer, in order:

1. **Resolve a contradiction or a failed plan.** Working on top of contested state manufactures rework.
2. **Close a proof gap on something already built.** Untested implemented code is inventory, not progress.
3. **Unblock the most-blocked dependency.** In a 140-task roadmap where 115 are blocked, the blocker is the whole game.
4. **Build the next thing** — only when 1–3 are clear.

Deprioritize: work requiring an unavailable capability · work whose proof cannot be produced · speculative building ahead of evidence · anything that needs an owner decision you have not yet requested.

**Select exactly one action.** A ranked list of twelve is a way of not choosing. Name the one, say why it beats the runner-up, and start it.

## Output

```
PROJECT       <identity>
PHASE         <phase> — <what closes it>
STATE         <the model above, only rows you established>
UNKNOWNS      <what you could not determine, and why>
OPEN LOOPS    <unfinished work, failed plans, contradictions>
BLOCKERS      <real blockers only, with who unblocks each>
NEXT ACTION   <exactly one, with its safety class and expected evidence>
ESCALATION    <owner decisions needed, or none>
```

Distinguish `documented / implemented / tested / deployed / production_verified` precisely — see `pandora-governance-contract`.

## Handoff

Route to the skill that owns the selected action and pass the established state forward so it is not re-derived. If the action is a mutation, `pandora-governed-execution` owns the plan→approve→execute path. If you discovered facts worth persisting, `pandora-evidence-ledger` owns writing them back.

If nothing is blocked and no owner decision is needed, **continue into the next action** rather than reporting and stopping.
