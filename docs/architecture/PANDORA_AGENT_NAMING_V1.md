# Pandora Agent Naming v1

**Status:** Canonical naming layer  
**Effective:** 2026-08-30  
**Scope:** Pandora Worker A-J architecture roles

Pandora's architecture roles are now presented as **Pandora Agents** with Greek mythology codenames.

This is a naming-layer migration, not a protocol or storage migration. Existing machine identifiers, database values, routing keys, event contracts, migrations, historical evidence, file names, and audit records that use `worker_a` through `worker_j` or `Worker A` through `Worker J` remain valid compatibility identifiers.

## Canonical mapping

| Stable machine ID | Legacy alias | Pandora Agent | Domain |
| --- | --- | --- | --- |
| `worker_a` | Worker A | **Atlas Agent** | Control Plane / durable state / ProjectSpec / jobs |
| `worker_b` | Worker B | **Athena Agent** | Intelligence / intent compiler / model routing / context |
| `worker_c` | Worker C | **Themis Agent** | Policy / authorization / approvals / secrets |
| `worker_d` | Worker D | **Hephaestus Agent** | Build runtime / sandbox / execution / repair |
| `worker_e` | Worker E | **Aletheia Agent** | Independent verification / QA / release proof |
| `worker_f` | Worker F | **Hermes Agent** | Project runtime / preview / deployment / domains |
| `worker_g` | Worker G | **Apollo Agent** | Product experience / Flutter / customer journey |
| `worker_h` | Worker H | **Plutus Agent** | Business intelligence / economics / outcomes |
| `worker_i` | Worker I | **Daedalus Agent** | Trusted primitives / reusable composition |
| `worker_j` | Worker J | **Argus Agent** | Integration / E2E proof / production readiness |

## Product-language rule

New human-facing UI, documentation, status summaries, and owner communications should use the Greek agent name first.

Preferred:

- `Athena Agent — Intelligence`
- `Hephaestus Agent — Build Runtime`
- `Argus Agent — Integration & Release`

During migration, technical documentation may write `Athena Agent (Worker B)` once when the legacy identifier is material to understanding a contract.

Do not replace stable machine identifiers inside persisted or provider-facing contracts merely for branding.

## System flow

```text
PANDORA
  ↓
ATHENA     understands intent
  ↓
ATLAS      records and orchestrates durable work
  ↓
THEMIS     authorizes and governs
  ↓
DAEDALUS   selects trusted primitives
  ↓
HEPHAESTUS builds in bounded execution
  ↓
ALETHEIA   independently verifies
  ↓
HERMES     deploys preview and production runtime
  ↓
APOLLO     presents the customer experience
  ↓
PLUTUS     measures economics and outcomes
  ↓
ARGUS      proves cross-system integration and release readiness
```

## Compatibility contract

1. `worker_a` through `worker_j` remain canonical stable machine keys.
2. Historical `Worker A` through `Worker J` references remain valid and must not be rewritten in immutable evidence.
3. Greek names are display identities and architecture codenames.
4. No secret, provider credential, database enum, migration history, durable event, or routing contract is renamed as part of this change.
5. New code needing a display name should use `src/projectos/pandora-agent-registry.js` rather than maintaining another mapping.

## Naming authority

The programmatic source of truth is:

`src/projectos/pandora-agent-registry.js`

Any future rename must preserve stable machine IDs unless a separately reviewed protocol migration explicitly changes them.
