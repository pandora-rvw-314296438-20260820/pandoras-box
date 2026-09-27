# Pandora Skill System v1

## Purpose

Pandora's north star is **human intent → trusted working digital systems**. This skill system turns that goal into a governed capability catalog spanning focused customer validation, product and architecture work, implementation, testing, deployment, runtime operation, memory, repair, economics, enterprise controls, and earned ecosystem expansion.

## Strategic sequence

The catalog preserves the project strategy:

1. **Focused entry:** validate a repeated painful problem, deliver a technical alpha, charge real customers, and prove retention and outcome economics.
2. **Horizontal growth:** generalize architecture, agents, integrations, runtime, model routing, team controls, and reusable skills only after evidence supports adjacent demand.
3. **Platform and ecosystem:** earn enterprise and marketplace investment through organic reuse, publisher behavior, safe distribution, and viable economics.

Calendar dates may start experiments; evidence authorizes expansion.

## Architecture

- `.agents/AGENTS.md` contains universal authority, proof, autonomy, security, and reporting rules.
- `.agents/skills/<skill>/SKILL.md` contains one concise workflow with trigger conditions, proof, stop conditions, and outputs.
- `.agents/skills/registry.json` provides machine-readable risk, autonomy, dependencies, capabilities, and entrypoints.
- `PANDORA_SKILL_COVERAGE.json` defines the current completeness denominator.
- `PANDORA_SKILL_EVALS.json` defines normal and adversarial evaluation cases; they are specified but not yet model-run.
- `scripts/validate-pandora-skills.mjs` checks structure, dependencies, coverage, evaluations, secret patterns, and content hashes.

## Composition

For substantial work, start with `orchestrating-intent-to-working-system`. It composes the minimum specialist skills needed. Existing project work always starts with `recovering-canonical-project-state`. Writes use `planning-governed-actions`, risk gates, exact verification, and durable Memory updates.

## Proof state

- Strategy and capability model: **documented**.
- 51 static core skill entrypoints plus 144 deterministic capability-fabric skills (195 runtime skills total), registry, coverage, eval specification, validator, and tests: **implemented in source**.
- Local static validation: recorded separately by exact command output.
- Exact-head repository CI: **not proven until the branch workflow completes**.
- Agent runtime discovery, capability-skill generation, routing, loading, kill switch, and mutation-boundary behavior: **proven by source tests**.
- Deployment: **not performed**.
- Production activation: **owner-authorized; deployment and live provider verification remain separate proof stages**.

Repository presence must never be reported as installed runtime capability. Provider-specific upload or discovery evidence is required for each target runtime.

## Change policy

Skills are versioned source. Any change requires a preserved parent, registry and coverage reconciliation, static validation, updated evals when behavior changes, exact-head CI, and independent review appropriate to risk. Meaningful runtime activation additionally requires provider discovery, representative execution, security/privacy review, and rollback or disable evidence.

## Current completeness denominator

The v1 denominator is the required capability list in `PANDORA_SKILL_COVERAGE.json`. Every required capability must map to at least one registered skill. This is a complete foundation against the approved strategy scope, not a claim that future customer evidence can never reveal new skills.
