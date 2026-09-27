# Pandora Skill System v1

This catalog contains **51 governed foundation skills** plus **144 deterministic capability-fabric skills** generated from 48 capability packs, for **195 runtime skills** total.

- Canonical repository: `pandora-rvw-314296438-20260820/pandoras-box`
- Capability-fabric source base: `ea0cf99ad622247d59577f971b21eb56821530d5`
- Strategy source SHA-256: `6118eb2872c9d2d3f4b9bcd1d1f36450e445a12a029b97ebcd251bd2540d0eed`
- Registry: `registry.json`
- Registry schema: `registry.schema.json`
- Shared operating contract: `../AGENTS.md`
- Static validator: `scripts/validate-pandora-skills.mjs`
- Runtime activation: **proven by the governed runtime and capability-fabric test suites**
- Production activation: **owner-authorized; deployment and live verification remain separately evidenced**

Compatible agent runtimes may discover the `.agents/skills/<name>/SKILL.md` layout. Other runtimes can package the same entrypoints, but repository presence alone is not activation evidence.

Every skill is intentionally concise. Shared authority, proof, autonomy, security, and reporting rules live in `.agents/AGENTS.md`; skill files contain the workflow-specific instructions.
