---
name: pandora-router
description: "Entry point for any Pandora's Box or Banatao Systems portfolio work. Load first when a request concerns a Pandora-managed project, MCPMaster, Pandora, Pandora Memory, or any connected provider (GitHub, Supabase, Vercel, FlutterFlow) — and whenever a request is vague about scope, such as 'fix booking', 'is it deployed?', 'ship this', or 'what should I work on?'. Selects the smallest sufficient set of Pandora skills and refuses to over-invoke."
---

# Pandora Skill Router

Your job is to select the **smallest sufficient** set of skills, then get out of the way. Loading nine skills for a question that needed one is a real cost: it burns context, slows the turn, and dilutes the instructions that actually mattered.

## First move: classify the request

Read the request and place it in one of four bands.

**Band A — Answerable from a single read.** "Is the audit chain valid?" "What's on main?" "Is Memory healthy?"
→ Call the tool. Load nothing. Report.

**Band B — Scoped work in one domain.** "Review this PR for security." "Design the bookings schema." "Write the release runbook."
→ Load the one matching domain skill. Load `pandora-governance-contract` only if the work mutates something or makes a completion claim.

**Band C — Vague, or references project state you do not have.** "Fix booking." "Ship it." "What should I work on?" "Why is it broken?"
→ **Do not jump to a coding skill.** Load `pandora-control-tower` first. It recovers state and tells you what the request actually means. This is the single most important routing rule here.

**Band D — Multi-stage delivery.** "Build feature X and get it live."
→ Load `pandora-control-tower`, then walk the delivery chain, loading each skill as you reach its stage. Do not preload the chain.

## Routing table

| Request shape | Load |
|---|---|
| Vague / "fix X" / "what next" | `pandora-control-tower` |
| Lost context, new session, handoff | `pandora-project-recovery` |
| "What do we know about…", contradiction | `pandora-memory-context` |
| Record a finding or state change | `pandora-evidence-ledger` |
| Any provider mutation | `pandora-governed-execution` |
| "Can you even do X?" / tool missing | `pandora-mcp-discovery` |
| Repo, branch, PR, commit, exact head | `pandora-source-control` |
| Review a candidate independently | `pandora-exact-head-review` |
| Security review, vuln, authz hole | `pandora-security-review` |
| Schema, migration, RLS, advisors | `pandora-supabase` |
| Release, deploy, rollback | `pandora-deployment-release` |
| Down, slow, erroring, incident | `pandora-runtime-observability` |
| Test strategy or coverage | `pandora-testing` |
| Workflows, Actions, pipeline | `pandora-cicd` |
| "I want an app that…" | `pandora-requirements` |
| System design, ADR | `pandora-architecture` |
| Write/change application code | `pandora-implementation` |
| Flutter, mobile, PWA, APK | `pandora-mobile-flutter` |
| Screens, layout, accessibility | `pandora-ui-ux` |
| Slow, expensive, heavy | `pandora-performance` |
| Login, roles, permissions | `pandora-auth` |
| New connector or integration | `pandora-provider-adapter` |
| Model choice, routing, eval | `pandora-ai-routing` |
| PII, retention, logging safety | `pandora-privacy-data-governance` |
| Payments, health, legal, identity | `pandora-regulated-activation` |
| "Will anyone pay for this?" | `pandora-commercial-validation` |
| Pricing, margin, CAC, credits, cost | `pandora-unit-economics` |
| Sales, onboarding, churn, enterprise | `pandora-gtm-customer` |
| Docs, runbook, README, ADR | `pandora-documentation` |
| Backup, snapshot, provider loss | `pandora-disaster-recovery` |
| Templates, marketplace, SDK | `pandora-ecosystem` |

## Worked example — "Fix booking."

The wrong reflex is `pandora-implementation`. You do not yet know that anything is broken in code, which project "booking" belongs to, or whether a fix already shipped.

Correct sequence:

1. `pandora-control-tower` → identify the project, its phase, its live state, open loops.
2. Now the request resolves into one of:
   - *broken in production* → `pandora-runtime-observability` for diagnosis first
   - *a known open task* → follow the delivery chain from wherever it stalled
   - *a new requirement* → `pandora-requirements`
   - *already fixed, not deployed* → `pandora-deployment-release`
3. Load only the branch that survived step 2.

Four of those five paths never touch `pandora-implementation`. Diagnosing before coding is the whole point.

## Anti-patterns

**Do not load the full delivery chain up front.** Load implementation when implementing, testing when testing.

**Do not load `pandora-control-tower` for a narrow, well-specified question.** "Does this SQL have an injection risk?" needs `pandora-security-review`, not full state recovery.

**Do not load `pandora-governance-contract` for read-only work.** It earns its place when you are about to mutate, classify risk, or claim completion.

**Do not skip `pandora-control-tower` on Band C because the request sounds simple.** "Just ship it" is the highest-risk sentence in this system — it implies a production release, which is exactly what must not happen unexamined.

## Handing off

When you hand work to the next skill, pass forward: the resolved project identity, the exact state you established (SHAs, deployment IDs, provider facts), the current proof state, and what remains unverified. The next skill should not have to re-derive what you already established — that is the main source of wasted context in a multi-skill turn.
