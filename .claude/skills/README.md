# Pandora Skill System

Reusable Claude skills for building, operating, reviewing, securing, deploying, governing, and commercializing Pandora's Box and the projects managed through it.

**North star:** human intent → trusted working digital systems.

## Layout

```
.claude/skills/
├── README.md                  this file
├── DEPENDENCY_GRAPH.md        which proof must exist before which stage
├── pandora-router/            entry point — selects the smallest sufficient skill set
├── pandora-governance-contract/
│   ├── SKILL.md               the shared safety, proof, and mutation contract
│   └── references/            proof-gates · risk-classification · mutation-safety · escalation
├── pandora-<domain>/          31 further domain skills
└── evals/
    ├── evals.json             24 evaluation cases
    ├── check_structure.py     native skill-format validation
    ├── check_invariants.py    governance properties the system claims to have
    ├── check_routing.py       description discrimination
    └── run_all.sh             full suite
```

## Using it

Start at `pandora-router`. It classifies the request into one of four bands and loads only what that band needs:

- **Band A** — a single read answers it. Load nothing.
- **Band B** — scoped to one domain. Load that one skill.
- **Band C** — vague or state-dependent (`fix X`, `ship it`, `what next`). Load `pandora-control-tower` first, never a coding skill.
- **Band D** — multi-stage delivery. Walk the chain in `DEPENDENCY_GRAPH.md`, loading each stage as you reach it.

`pandora-governance-contract` is a shared library loaded on demand — before mutating, when classifying risk, and when judging whether work is done.

## The two rules everything rests on

**The proof ladder.** `documented → implemented → tested → deployed → production_verified`. These are not synonyms, and they are the enforced `proofStage` enum on `pandora_plan_memory_submitEvidenceCandidate` — using the wrong one writes a false claim into canonical Memory. Nothing counts as proof of the next state up: not green CI, not a merged PR, not a READY deployment, not an agent's assertion.

**Governed mutation.** Reads are direct; state changes never are. Every mutation goes plan → approve → execute through Pandora, with payload integrity, a one-time claim, and a hash-linked audit chain. Once a provider confirms a mutation, a downstream failure must never reclassify it as retryable.

## Source-of-truth hierarchy

1. Fresh authenticated provider evidence for the exact external state
2. Corrected Pandora Memory canonical state
3. Exact canonical source and manifests
4. Approved strategy sources
5. Static skill instructions (including these files)
6. Conversation recollection — never authoritative when Pandora MCP can answer

A static skill never overwrites newer verified reality. Skills hold **procedures**; Pandora Memory and provider evidence hold **state**.

## Running the evaluations

```bash
bash .claude/skills/evals/run_all.sh
```

Three checks: structural validity of the native skill format, the governance invariants the system claims (reviewer independence, governed mutation routing, the confirmed-mutation rule, escalation coverage, no secrets), and routing discrimination across the eval prompts.

The routing check is a lexical proxy for model-driven activation — it verifies descriptions are discriminative, which is necessary but not sufficient. Treat a failure as a real signal.

## Extending it

Add a skill when it materially improves execution — not to increase coverage on paper. Before adding, check whether an existing skill should be parameterized or given a reference file instead; near-duplicate skills degrade activation for both.

New skills must: state activation and non-activation conditions in the description, declare a safety classification for anything that mutates, define an output contract, name their handoff targets, and route mutations through `pandora-governed-execution`. Then add eval cases and re-run the suite.
