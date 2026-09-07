# Pandora Web Control Plane v1

Status: canonical product/design contract  
Canonical implementation: `apps/control-tower`  
Product loop: **See → Focus → Tell → Transform → Review → Publish**

## Product contract

Pandora has one responsive web control plane with three presentation modes over the same governed backend state:

1. **Simple** — owner/customer outcome surface.
2. **Professional** — operating workspace for builders and operators.
3. **Admin** — protected provider, security, plan, approval, execution and audit controls.

Do not create a second web framework or duplicate control plane. The existing Express/static materialization path remains canonical. The result is the hero. Pandora stays quiet. Governance becomes prominent only when it changes what the owner must decide.

No surface may invent status, progress, live URLs, revenue, deployment state, verification, or provider health.

## Information architecture

### Simple Mode

Primary navigation is exactly:

- **Home**
- **Projects**
- **Ask Pandora**
- **Needs You**
- **Business**

Settings, account and mode switching live in the header/profile surface.

### Professional Mode

- **Home**
- **Build**
- **Run**
- **Connect**
- **Memory**
- **Verify**
- **Business**
- **Library**
- **Settings**

### Admin Mode

Evolve the existing Advanced Control Tower:

- ProjectOS / authoritative status
- Action Builder
- Durable Plans
- Approval Center
- Connections
- Audit
- Security Center
- Operations
- Settings

## Responsive shell

### Desktop
- 248px left rail
- flexible primary workspace
- optional 360–420px contextual inspector
- max primary width around 1440px
- sticky status/command header
- result-first center canvas

### Tablet
- collapsible rail
- main workspace
- inspector becomes a drawer

### Mobile
Simple Mode bottom nav is `Home / Projects / Ask Pandora / Needs You / Business`.

Professional/Admin use compact headers and contextual drawers.

### Global header
- Pandora identity and organization/workspace
- owner state: `Working / Ready / Live / Needs You / Problem`
- command/search entry when appropriate
- notifications only for actionable owner decisions
- account and mode menu

## Simple Mode

### Home — what matters now

1. **Needs You** hero only when a consequential decision exists.
2. Otherwise the **current result** is the hero.
3. Compact **Ask Pandora** entry.
4. Active/recent Projects.
5. Recent verified outcomes.
6. Business snapshot only when an authoritative source exists.

Never lead with queues, jobs, tokens, model names, provider internals or audit metrics.

### Projects

Cards show only proven information: project name, owner-facing state, what Pandora is doing, next meaningful milestone, verified live destination, Needs You reason, and latest verified outcome.

Do not manufacture completion percentages. Evidence-derived progress is explicitly labeled.

### Project workspace

Header: project name, owner state, exact verified live host when available, and the state-appropriate primary action.

Hero: Build Theatre while building/rebuilding/publishing; otherwise latest verified result or preview.

Build Theatre stages:
1. Understanding
2. Designing
3. Building
4. Checking
5. Ready
6. Publishing
7. Live

Stages come from authoritative runtime projection, never timers or optimistic browser state.

Below the hero:
- Preview/result
- Tell Pandora change field
- Undo
- Current / Live / History
- Files on demand
- verification summary
- publish controls

### Ask Pandora

Use the existing `pandora-intelligence-chat` boundary with the authenticated owner session.

Capabilities:
- start an intent
- continue a thread
- optional project context
- supported attachments
- server-controlled fast/auto/deep routing
- reply, clarification and governed handoff states

Model output never performs a mutation directly.

Actionable flow:
`Ask Pandora → governed intake → plan → review/approval when required → one-time execution → verification → visible result`

### Needs You

One owner-decision inbox for approvals, production release authorization, permission/credential reconnection, spending, destructive actions, legal/public commitments, failed verification requiring the owner, and blocked builds requiring owner input.

Routine repairable failures do not become owner notifications.

### Business

Show commercial truth only from connected authoritative sources: active customer systems, pilots, usage, revenue/payment metrics when connected, cost/runtime credits, validation, and retention/outcome evidence.

When sources are absent, show an explicit unavailable state. Never fabricate ROI or revenue.

## Professional Mode

### Home
Cross-project operations, deployment health, blockers, cost and verification signals.

### Build
Intent/spec, Build Theatre, source/artifact lineage, preview, rebuild, publish candidate and rollback candidate.

### Run
Deployments, workers, jobs, runtime events, retries, failures and recovery state.

### Connect
GitHub, Supabase, Vercel, PostHog, model providers and installed connectors. Show identities/scopes/allowlists, never credentials.

### Memory
Project context, decisions, learned patterns, evidence candidates, promotion state, health and lineage.

### Verify
Exact source SHA, artifact SHA-256, CI, independent review, deployment binding, runtime checks, production verification and audit-chain validity.

### Business
Expanded commercial analytics and validation operations.

### Library
Artifacts, generated files, specs, reports, evidence, releases and searchable project knowledge.

### Settings
Organization, appearance, mode, notifications, billing/credits, security/session controls and integration entry points.

## Owner-facing state model

Every project resolves to one of:
- `working`
- `ready`
- `live`
- `needs_you`
- `problem`

**READY is never LIVE.** Live requires verified production deployment truth.

History:
- **Current** — latest working version
- **Live** — production-verified version
- **History** — immutable prior versions/outcomes

Undo binds to a real reversible prior state.

## Source-of-truth matrix

| Surface | Authoritative source |
| --- | --- |
| Portfolio/project status | `/api/operator/status` / owner projection |
| Owner session | `/api/operator/session` |
| Connections | protected operator connections |
| Plans/approvals | durable ProjectOS plan API |
| Audit | durable ProjectOS audit chain |
| Ask Pandora | `pandora-intelligence-chat` |
| Build Theatre | owner/project runtime projection |
| Preview/current/live/history | project runtime/version/deployment truth |
| Memory | dedicated Memory plane boundaries |
| Verification | exact source/artifact/review/deployment attestations |
| Business | connected first-party business/analytics sources only |

## Admin safety invariants

Preserve:
- authoritative `/api/operator/status`
- authenticated owner/admin session
- memory-only browser session
- durable plan ledger
- approval separate from execution
- one-time execution claim
- exact payload hash
- allowlisted provider targets
- distributed rate limiting
- audit-chain verification
- no automatic mutation retry
- fail closed if identity, ledger, limiter or audit verification is unavailable
- caller-controlled privileged internal headers stripped at browser boundary
- no provider credential in browser storage, model inputs, receipts or source

## Visual system

Premium, neutral clarity:
- near-black/dark and warm-white/light surfaces
- one restrained accent
- 8px spacing base
- 12–16px radii
- minimum 44px controls; target 48px
- high-contrast typography
- no gratuitous gradients/glows
- continuity-driven motion and reduced-motion support
- skeletons only for genuine loading
- repair-intent errors in Simple Mode
- WCAG 2.2 AA target

## Delivery slices

### A — Shell and IA
Simple navigation becomes Home / Projects / Ask Pandora / Needs You / Business. More/Settings moves to header. `?advanced=1` remains Admin entry during convergence.

### B — Ask Pandora web
Bounded Edge Function invocation through existing auth; access token stays memory-only; carry `x-organization-id`; render reply/clarification/handoff; never auto-execute tool proposals.

### C — Needs You
Combine approvals, owner blockers, release decisions and reconnect requirements; deduplicate; one clear decision per item.

### D — Project workspace and Build Theatre
Runtime-bound theatre, preview/result hero, Tell Pandora loop, Current/Live/History, exact public host after verified publish, publish progress in the theatre.

### E — Professional Mode
Nine-area workspace over the same data/action boundaries.

### F — Business, Memory, Verify and Library
Connect only to authoritative sources and show explicit unavailable states until backing data exists.

### G — Verification
Syntax/build, accessibility, browser smoke, auth regression, canonical-status regression, approval/execution separation, no-secret boundary, responsive visual acceptance, and exact-source production verification after release.

## Acceptance gates

- [ ] Simple primary nav is exactly Home / Projects / Ask Pandora / Needs You / Business.
- [ ] Ask Pandora works with owner auth and no provider secret reaches browser code.
- [ ] Needs You is the single owner-decision inbox.
- [ ] Project workspace has Build Theatre driven by runtime truth.
- [ ] Ready is never displayed as Live.
- [ ] Verified live host is visible after publish.
- [ ] Undo / Current / Live / History bind to real versions.
- [ ] Professional Mode exposes Build / Run / Connect / Memory / Verify / Business / Library / Settings.
- [ ] Admin mode preserves durable plan, approval, execution and audit controls.
- [ ] No page fabricates status, metrics, URL, business outcome or verification.
- [ ] Responsive acceptance passes mobile/tablet/desktop.
- [ ] WCAG 2.2 AA target and >=44px interactive controls.
- [ ] Existing Control Tower auth/canonical-status tests remain green.

## Convergence decision

The current owner-first shell centers Home / Projects / Approvals / Activity / More. Advanced Control Tower already contains the secure foundations for canonical status, action planning, approvals, connections, audit, security and operations.

Implementation evolves `apps/control-tower` in place. It does not introduce another web app.
