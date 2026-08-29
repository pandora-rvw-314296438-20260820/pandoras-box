> **SUPERSEDED FOR CURRENT STATUS — 2026-08-28**
>
> The canonical current Pandora roadmap/status source is `docs/roadmaps/PANDORAS_BOX_CANONICAL_ROADMAP_V2.md`.
> This v1 file remains historical product/design evidence. Its old canonical-repository, baseline, mobile-version, issue-number and “next slice” statements must not be used as current provider truth or completion evidence.

# Pandora Mobile — Apple-Level Product Roadmap & Execution Plan v1.0

**Status:** Owner-approved roadmap source candidate  
**Created:** 2026-08-14 Asia/Manila  
**Canonical repo:** `banataosystems/Pandoras-box`  
**Baseline:** `main@1cfccdc37f77a314f2afb5f56a2f23f953e19f8b`  
**Mobile source:** `apps/pandora-mobile`  
**Current mobile:** `0.1.1+2`  

## North star

Transform Pandora Mobile from a secure operator prototype into the owner's calm, premium operating system for the entire project portfolio.

**Raw system data → owner understanding → safe decision → governed action → verifiable evidence.**

Apple-level is a quality bar, not an iOS copy: extreme clarity, restraint, consistent hierarchy, excellent feedback, accessibility, native Android behavior, and meticulous finish.

## Non-negotiable product principles

1. Owner meaning before machine structure.
2. “Needs you” is the highest-value state.
3. Proof before confidence.
4. Progressive disclosure.
5. Server authorization remains authoritative.
6. No manual project/action/approval IDs in primary flows.
7. Calm over spectacle.
8. Android-native behavior with Pandora-native identity.
9. Every loading/empty/stale/error/degraded/success state is designed.
10. Every releasable artifact is bound to exact source, tests, signing identity, and rollback.

## Target navigation

**Phone:** Home · Projects · Command · Approvals · Activity

**Secondary:** Connections · Safety · Settings · Account · Notifications · Developer Diagnostics

**Large screen:** navigation rail plus list-detail layouts instead of stretched phone cards.

## Source preservation

- Open PR #8 contains useful premium terminology/design/test concepts but is stale and dirty. Salvage concepts and tests; do not merge it wholesale.
- Open PR #12 records the approved spiral-apple product mark. Reconcile the exact asset against current main, generate deterministic derivatives, then visually verify on device.
- Uploaded `mcpmaster-main (3).zip` is design archaeology only. Never flat-merge or restore `mbanatao/*` source authority.

## Proof ladder

Every project, feature, action, and release must distinguish:

`Documented → Implemented → Tested → Deployed → Production verified`

Never collapse these into a generic green “done” state.

## Execution phases

- **Phase 0:** baseline, salvage map, identity reconciliation, acceptance matrix
- **Phase 1:** architecture, typed models, system themes, design tokens, shared components, Diagnostics boundary
- **Phase 2:** premium Home + Projects
- **Phase 3:** natural-language Command + plan review
- **Phase 4:** evidence-rich Approval queue/detail
- **Phase 5:** Activity + Connections + Safety + Settings
- **Phase 6:** brand + motion + accessibility + adaptive layouts
- **Phase 7:** performance + optimized Android packaging/signing
- **Phase 8:** exact-candidate release proof
- **Phase 9:** daily briefing, notifications, evidence packets, read-only offline, continuous learning

## PR strategy

Do not build the redesign in one giant PR:

A. Foundation  
B. Home  
C. Projects  
D. Command  
E. Approvals  
F. Activity / Connections / Safety  
G. Brand / accessibility / adaptive  
H. Release engineering

Each PR must branch from current canonical main, preserve exact parent/head, stay bounded, pass exact-head CI, preserve rollback, and avoid production mutation.

## Immediate implementation slice

Next branch after roadmap landing:

`feature/pandora-mobile-premium-foundation`

Scope:
- reconcile PR #8 concepts and PR #12 identity;
- modularize app;
- introduce design tokens and system light/dark themes;
- add typed core models;
- add proof/status/freshness/loading/empty/error components;
- move raw JSON behind Developer Diagnostics;
- redesign Home and Projects;
- add golden/accessibility tests;
- produce exact-head Android test artifact;
- verify on the owner’s real Android device;
- stop before production/store release.

## Release boundary

Final production/store release requires all applicable gates: exact source, CI, visual, accessibility, authenticated device journey, security regression, runtime identity, rollback proof, independent review, and separate owner authorization for one exact release candidate.

## Detailed roadmap records

- `docs/roadmaps/pandora-mobile-v1/01_PRODUCT_UX.md` — product and interaction specification
- `docs/roadmaps/pandora-mobile-v1/02_DESIGN_BRAND.md` — design system, brand, motion, accessibility
- GitHub issue `#35` — complete execution tracker containing architecture/data rules, PMOB task IDs across phases 0–9, test/release gates, success criteria, immediate implementation slice, and Pandora Memory capture contract.

Issue #35 is the authoritative detailed execution tracker when a child document is absent. This avoids incomplete links and preserves the entire roadmap despite connector write-classification limits.
