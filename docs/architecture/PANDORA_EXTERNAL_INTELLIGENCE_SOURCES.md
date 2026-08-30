# Pandora External Intelligence Sources

Pandora may study or curate external repositories, but external source presence never grants runtime authority, trust, or permission to execute.

## Pinned fork roles

| Fork | Exact fork commit | Role | Import policy |
|---|---|---|---|
| `pandora-rvw-314296438-20260820/awesome-claude-skills` | `be2a406907dbc61b73e6827ded415c96139d13a2` | Skill seed | The repository declares Apache-2.0, but individual skills may use different licenses. Metadata discovery is allowed; source/instruction materialization remains blocked until the specific skill path's license is reviewed and approved. |
| `pandora-rvw-314296438-20260820/router` | `16b1480edf5d012f544516df514b1b28ee4ea83e` | Router benchmark/reference | Elastic License 2.0. Reference/benchmark only: no code import, no runtime dependency, no execution authority. Pandora keeps its own provider-independent router. |
| `pandora-rvw-314296438-20260820/the-book-of-secret-knowledge` | `7d37069a361d3fd9f214480755f7969744e866fa` | Operational knowledge seed | MIT. Curated bounded knowledge candidates may be imported as `EXPERIMENTAL`; raw snippets are never executed by import. |

## Reviewed per-entry sources

A per-entry review is narrower than repository approval. It binds one exact fork commit, path, SHA-256 content identity, and license evidence. It never changes the parent repository's default policy.

| Source | Exact content identity | License evidence | Approved use |
|---|---|---|---|
| `awesome-claude-skills/mcp-builder/SKILL.md` | `sha256:b1010e90adcb8fd6bf57640df34ab6454fbf7e4216e150a4620f7caccadc4e63` (Git blob `c9ef8a261f80e0c37dc73300ce90679e946c4407`) | `mcp-builder/LICENSE.txt`, Apache-2.0, Git blob `7a4a3ea2424c09fbe48d455aed1eaa94d9124835` | `METADATA_ONLY`: may enter the candidate registry as `EXPERIMENTAL`. Raw upstream instructions are not approved prompt material and remain non-materializable. |

Changing the path or SHA-256 invalidates the entry review. A reviewed metadata candidate is still non-selectable at runtime until Worker E independently verifies the exact candidate and, separately, any Pandora-owned prompt material that would be supplied to a model.

## Trust boundary

External source -> exact repository + commit + path + SHA-256 -> governed candidate -> `EXPERIMENTAL`/`BLOCKED` -> Worker E independent verification -> `TRUSTED`.

`BLOCKED` and `DEPRECATED` registry entries cannot be certified. Imported skills remain `proposal_only`. Model output and external material cannot grant Worker C authority, provider credentials, or direct mutation capability.

## Runtime rule

The three forks are development-time evidence/reference inputs only. Pandora runtime must not depend on their mutable branches, network availability, or credentials. Any adopted artifact must be content-addressed and independently verified inside Pandora.
