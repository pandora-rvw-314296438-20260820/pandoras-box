# Pandora’s Box — Canonical Roadmap & Status Matrix v2.0

**Status:** CANONICAL CURRENT ROADMAP SOURCE  
**Observed:** 2026-08-28 Asia/Manila  
**Canonical repository:** `pandora-rvw-314296438-20260820/pandoras-box`  
**Baseline at creation:** `main@77bed9c83daafd742cd299073adf98f9a44ea705`  

This document is the single roadmap/status authority for Pandora’s Box. Older dated roadmap files remain historical design and execution evidence only. They must not be used to claim current completion.

## Completion language

Pandora uses the proof ladder:

`Documented → Implemented → Tested → Deployed → Production verified`

Never collapse those states into a generic “done”.

Roadmap status labels in this document mean:

- **DONE** — source-level implementation for the phase is materially present and tested in canonical source; this does **not** mean production verified.
- **PARTIAL** — meaningful implementation exists but one or more phase requirements or release gates remain open.
- **NOT STARTED** — no sufficient canonical implementation evidence has been verified.
- **PRODUCTION VERIFIED** — exact source, runtime, device journeys, deployment, rollback, provider parity, independent review, and owner authorization are all proven for the release candidate.

## Executive status

**Pandora is not fully roadmap-complete and is not production verified.**

The current canonical Android/Simple Mode implementation has substantial working coverage, including Home, Systems, Ask Pandora, Needs You, Build/Preview, Business Intelligence, Activity, Verify & Safety, Projects/System detail, Connections, governed commands, diagnostics, team/user administration, Settings, and authentication. The owner-facing core is implemented and tested in source, but product acceptance remains open because the Simple Mode information architecture is still too complex and production release proof is incomplete.

## Phase 0–9 matrix

| Phase | Scope | Status | Current evidence | Remaining before closure |
|---|---|---|---|---|
| 0 | Baseline, recovery, source authority, acceptance matrix | **PARTIAL** | Canonical recovery repo established; source authority and migration ledger substantially converged | Close remaining provider/release evidence, production parity, rollback and current-status proof |
| 1 | Architecture, typed models, themes, design tokens, shared components, diagnostics boundary | **DONE** | Native architecture and owner/diagnostic separation are present and covered by source tests | Production verification is handled by later phases |
| 2 | Premium Home + Systems/Projects | **DONE** | Home and Systems owner surfaces implemented with filters, status semantics, goldens and responsive behavior | Simple Mode IA/product-acceptance simplification remains a cross-cutting blocker |
| 3 | Natural-language Ask Pandora / Command + plan review | **DONE** | Ask Pandora, governed preparation, Build Theatre and preview flows are implemented | End-to-end production journey proof remains open |
| 4 | Evidence-rich Needs You / approvals | **DONE** | Queue/detail, risk, reversibility, rollback, expiry and proof-state semantics are implemented | Production authorization/device evidence remains open |
| 5 | Activity, Connections, Safety, Settings | **DONE** | Activity, connection management preparation, four-layer Verify & Safety board and settings surfaces are implemented | Final owner simplification and production proof remain open |
| 6 | Brand, motion, accessibility, adaptive layouts | **PARTIAL** | Porcelain/Graphite system, goldens, accessibility work and responsive NavigationRail exist | Full motion/reduced-motion acceptance, physical TalkBack/device pass, deterministic delivery-asset packaging and remaining brand convergence |
| 7 | Performance, optimized Android packaging/signing | **PARTIAL** | Android builds and CI gates exist | Final optimized release artifact, signing/reproducibility evidence and device performance acceptance |
| 8 | Exact-candidate release proof | **PARTIAL** | Exact-head CI and source-bound checks exist | Physical Android Wi-Fi/mobile-data journeys, production deployment/rollback binding, Supabase parity, independent review and exact owner authorization |
| 9 | Daily briefing, notifications, evidence packets, offline, continuous learning | **PARTIAL** | Daily briefing and bounded read-only saved/offline evidence are present | Notifications, complete evidence-packet UX and continuous-learning loop are not yet proven complete |

## Product-mode status

| Product layer | Status | Decision |
|---|---|---|
| Simple Mode surface coverage | **DONE** | Core owner surfaces exist in canonical Android source |
| Simple Mode usability / information architecture | **PARTIAL** | Current navigation still exposes too many internal concepts; simplify before declaring product UX complete |
| Professional Mode | **PARTIAL** | Technical/diagnostic surfaces exist, but the complete professional workflow is not proven against the full master plan |
| Pandora Admin | **PARTIAL** | Control-plane/admin capabilities exist in the system, but a complete owner-approved Admin product experience is not proven |
| Supabase integration/parity | **PARTIAL** | Production migration history is converged and user-admin work has landed; additional convergence/performance work remains and production parity must still be proven |
| Vercel/runtime release | **PARTIAL** | Runtime/deployment infrastructure exists; exact production deployment and rollback proof remain release gates |
| FlutterFlow parity | **PARTIAL** | Readiness integration exists; editor/page parity has not been verified and must not be inferred from native source |
| Production release | **PARTIAL** | Build/test evidence exists; full production verification is not complete |

## Current highest-priority blockers

1. **Simple Mode IA reset** — preserve functionality but reduce the owner mental model to Home, Systems, Ask Pandora, Needs You, and Business; technical surfaces belong behind Professional Mode/contextual disclosure.
2. **Finish active convergence work** — resolve current open source/provider PRs and keep canonical `main` green.
3. **Release candidate proof** — bind one exact source SHA to Android artifact, backend/runtime identity, Supabase parity and rollback.
4. **Physical-device journeys** — authenticated Android flows over Wi-Fi and mobile data, including approvals, Ask Pandora, system state and failure/degraded behavior.
5. **Independent review + owner authorization** — only after all evidence is complete.

## Canonical Simple Mode mental model

Simple Mode should require the customer to understand only:

1. **Home** — what is happening and what needs attention.
2. **Systems** — what Pandora has built and whether it works.
3. **Ask Pandora** — request an outcome in natural language.
4. **Needs You** — decisions, approvals or blockers requiring the owner.
5. **Business** — business results, intelligence and economics.

Activity, verification, evidence, connections, memory, provider details, ProjectOS concepts and diagnostics remain available through contextual drill-down or Professional Mode, not as competing primary destinations.

## Release closure rule

The roadmap may be described as **fully implemented** only when all Phase 0–9 requirements are at least DONE and all cross-cutting product acceptance requirements are complete.

Pandora may be described as **finished / production verified** only when the exact release candidate reaches **PRODUCTION VERIFIED** with:

- canonical exact source SHA;
- required CI and security checks green;
- reproducible signed Android artifact;
- authenticated physical-device journey evidence;
- production Vercel/runtime source binding;
- Supabase schema/function/policy/migration parity;
- rollback proof;
- current Pandora Memory/status-pack health;
- separate independent review;
- explicit owner authorization for that exact candidate.

## Authority and supersession

This v2 document supersedes old roadmap files **for current status and completion claims**. Older files remain valid as historical requirements/design references unless a requirement is explicitly replaced here.

The following must be treated as historical when they conflict with current provider truth:

- old `banataosystems/Pandoras-box` canonical-repo references;
- old mobile version/baseline statements;
- old GitHub issue-number mappings that no longer refer to the same tracker in the recovery repository;
- dated “next implementation slice” statements already overtaken by merged work.

Current provider truth and the authenticated canonical status pack always outrank stale checked-in status text.
