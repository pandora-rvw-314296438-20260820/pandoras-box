
# Pandora Skill Catalog / Trust Convergence v1

## Decision

Pandora has one canonical source skill catalog: `.agents/skills` plus its deterministic read-only runtime under `.agents/runtime/pandora-skill-runtime.mjs`.

`packages/pandora-intelligence/src/skills` is **not** a second catalog. It is Worker B's trust/version/risk projection over exact catalog artifacts and future external candidates. Worker A remains durable lineage authority and Worker E remains certification authority.

## Existing source catalog

The existing source catalog owns:

- skill identity and entrypoint;
- capability declarations;
- dependency graph;
- source-catalog risk/autonomy vocabulary;
- deterministic intent routing;
- kill switch and fail-closed behavior;
- content manifest validation.

The source runtime is deliberately read-only. Skill selection grants no provider mutation authority.

## Trusted projection

`projectAgentCatalogSkill()` maps a validated source-catalog entry into `PandoraSkillDefinition` using:

- `skillId` = existing catalog `id`;
- `version` = exact catalog version;
- `capabilities` = existing catalog capabilities;
- `dependsOn` = existing catalog dependency ids;
- source path/repository/base SHA = catalog provenance;
- source digest = exact SHA-256 from the validated skill manifest;
- risk mapping = source risk into Worker-B risk vocabulary;
- trust state = always `EXPERIMENTAL` on projection;
- execution mode = always `proposal_only`.

No source-catalog entry becomes `TRUSTED` merely because it exists in the repository or passes static catalog validation. Worker E must provide PASS evidence bound to the exact skill source digest.

## Risk mapping

| Source catalog risk | Worker B risk |
| --- | --- |
| `read` | `READ_ONLY_DIAGNOSTIC` |
| `reversible-write` | `SAFE_MUTATION` |
| `sensitive-write` | `PRIVILEGED` |
| `high-risk` | `DESTRUCTIVE` |

The mapping does not grant authority. Worker C still decides whether any tool proposal may execute and whether approval is required.

## Why two representations exist

They solve different problems:

1. `.agents/skills` is the versioned repository/source catalog used for authoring, deterministic discovery, dependencies and provider-neutral skill packaging.
2. Worker B's trusted projection records whether one exact content digest is independently accepted for use in an intelligence composition.
3. Worker A will persist durable trust/evidence lineage; in-memory Worker-B registries must never become another durable control plane.

## External skills

External sources such as `ComposioHQ/awesome-claude-skills` enter as candidate source artifacts. They are not appended directly to the canonical catalog and are not silently treated as trusted.

Pipeline:

`external exact commit -> parse candidate -> license/provenance -> normalize -> risk classify -> local source-catalog candidate -> static validation -> EXPERIMENTAL trust projection -> Worker E evaluation -> TRUSTED`

A future importer must either create a governed source-catalog candidate or reject the source. Provider-specific skill formats remain adapters, never alternate catalog authorities.

## Invariants

- One source skill catalog.
- One durable control plane: Worker A / Supabase.
- Worker B may select and compose but cannot grant mutation authority.
- Worker E alone may promote exact source digests to trusted.
- Worker C alone authorizes privileged operations.
- Exact content digest is mandatory for trusted projection.
- Catalog version aliases such as `latest` are forbidden by the trusted projection.
- External source popularity is never a trust signal.
