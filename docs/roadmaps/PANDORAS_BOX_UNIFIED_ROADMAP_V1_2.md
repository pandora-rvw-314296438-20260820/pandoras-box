# PANDORA / PROJECTOS
# Pandora's Box Unified Roadmap

**v1.2 structural update - 13 phases / 116-task denominator preserved**

---

### NORTH STAR
**Human intent -> Pandora -> trusted working digital system**

Pandora absorbs technical complexity so a business owner can describe the outcome they want, see value quickly, and rely on a governed system to build, verify, release, operate, remember, and improve it.

---

- **EFFECTIVE DATE:** 26 August 2026
- **STRATEGIC STAGE:** Stage A - Focused Entry
- **DOCUMENTED EXECUTION PHASE:** Phase 0 - Recovery and Truth Baseline
- **PRIMARY CONTROL PLANE:** Pandora / ProjectOS
- **VERIFIED CURRENT SOURCE REPOSITORY:** `pandora-rvw-314296438-20260820/pandoras-box`
- **VERIFIED MAIN AT GENERATION:** `9c61910d211fe65e7d0fcbbe184edb22ae35cb96`

> **Status discipline:** this roadmap defines direction and gates. It does not mark implementation complete. Documented, implemented, tested, deployed, and production-verified remain separate proof states.

---

## Purpose

Empower non-technical business owners — beginning with a focused Philippine entry — to use AI as a disciplined, contained, outcome-producing business lever rather than only as a chat assistant.

---

## 1. What changed in the new roadmap

The roadmap no longer treats mobile UI, workers, providers, learning, and business validation as separate competing roadmaps. They are one system with one phase denominator.

| Structural change | Meaning |
| :--- | :--- |
| **One phase system** | The canonical denominator remains 13 phases (0–12) and 116 tasks. No second numbering system is created for UI screens, workers, Builder, Verifier, or providers. |
| **Pandora-first control plane** | Owner intent enters Pandora / ProjectOS first. GitHub, GitLab, Supabase, Vercel, PostHog, FlutterFlow, Jules, model vendors, and future systems are governed, replaceable providers or agents. |
| **Builder + Verifier are equal halves** | Pandora Builder creates the candidate. Pandora Verifier independently proves that the candidate is the right thing, bound to the right source/deployment, safe, functional, recoverable, and actually producing the intended result. |
| **14 workers are an execution fabric** | The 14-worker layout is parallel implementation capacity under ProjectOS — not 14 phases and not a permanent worker limit. |
| **Three product modes share one platform** | Simple Mode, Professional Mode, and Pandora Admin Mode use the same governed backend, permissions, evidence model, memory, and audit trail. |
| **Rapid prototype is the hook, not the finish line** | Pandora should show a stunning frontend quickly to create immediate customer confidence, while clearly labeling it as a prototype until backend, data, auth, integrations, tests, deployment, and verification are complete. |
| **Business proof moves earlier** | Interviews, prototypes, pilots, willingness-to-pay tests, synthetic cost accounting, and safe non-regulated pilots begin during Technical Alpha. Formal paid economics and scale authorization remain Phase 9. |
| **Scale is earned** | Launch focused -> architect for horizontal growth -> earn ecosystem status. Marketplace, proprietary model, and expensive enterprise surface area stay conditional. |

---

## 2. Operating model

The revised system is a governed outcome loop:

1. **Owner intent:** A business owner states the result they want in ordinary language.
2. **Pandora / ProjectOS:** Resolves project, policy, identity, tenancy, context, risk, and the governed plan.
3. **Workers + providers + models + agents:** Parallel implementation capacity executes bounded tasks through governed adapters.
4. **Pandora Builder:** Creates plans, prototypes, source changes, data/auth, integrations, tests, and deployment candidates.
5. **Pandora Verifier:** Independently checks intent match, exact binding, functional behavior, security, privacy, tenancy, accessibility, performance, persistence, recovery, review, and rollback.
6. **Verified working result:** The owner sees what works, what is proven, what is still provisional, and what decision is needed.
7. **Business outcome:** Pandora measures whether the system creates a real customer or business result, not merely whether code ran.
8. **Governed learning:** Verified outcomes feed Memory, routing, skills, evaluation, and improvement without silently expanding authority.

### Provider access rule
- Pandora-native governed adapters are the normal architecture.
- Direct/native provider access is for independent verification, diagnostics, or controlled fallback when the Pandora-native path is unavailable or incomplete.
- A direct provider read may establish truth; it does not authorize a write.
- Writes remain subject to planning, authorization, bounded execution, exact pre/post-state verification, audit evidence, one-time semantics, and rollback protection.
- If a provider result is ambiguous, assume the side effect may have happened once and verify actual state before retrying.

### Evidence authority
`Verified provider/runtime -> corrected approved Memory -> exact source/artifact/test evidence -> approved strategy/requirements -> chat`

> **Note:** Pandora Memory remains the canonical operating context, but stale Memory cannot override freshly verified provider/runtime truth. When they disagree, correct Memory from evidence.

---

## 3. Roadmap map: stages, waves, and phases

The roadmap has three business stages and four execution waves. Evidence — not dates — authorizes movement.

| Stage | Strategy | State | Roadmap mapping | Gate |
| :--- | :--- | :--- | :--- | :--- |
| **Stage A** | Focused Entry | Current strategic stage | Phases 0–9 | Prove one narrow, valuable customer wedge; Technical Alpha; paid validation; retention and unit economics. |
| **Stage B** | Horizontal Growth | Conditional | After Phase 9 scale authorization; primarily Phases 10–11 | Expand application building, runtime, teams, routing and infrastructure only after the focused wedge proves economics. |
| **Stage C** | Platform / Ecosystem | Conditional | Phase 12 | SDKs, marketplaces, third-party agents/components, private runtimes and ecosystem economics only after organic evidence. |

### Execution waves
- **Wave A (Phases 0–3):** Truth, contracts, durable transport, and evaluation. Pandora must become trustworthy and measurable before it becomes adaptive.
- **Wave B (Phases 4–7):** Make Pandora learn safely: Memory quality, adaptive routing, reusable skills, champion-challenger promotion, bounded self-repair.
- **Wave C (Phases 8–9):** Prove the owner experience and the business: Technical Alpha, premium product experience, paid pilots, retention, pricing, and contribution economics.
- **Wave D (Phases 10–12):** Scale only what earned the right to scale: long-term data plane, optional proprietary task model, enterprise/ecosystem.

### Dependency chain
`0 -> 1; 1 -> 2 and 3; 2 -> 4; 3 -> 4/5; 4 + 5 -> 6; 3 + 5 + 6 -> 7; 0 + 4 + 7 -> 8; 1 + 3 + 8 -> 9; 2 + 4 + 9 -> 10; 3 + 5 + 9 + 10 -> 11; 7 + 9 + 10 -> 12`

> Only Phases 0–3 are immediately authorized in the latest documented planning baseline. Phases 4–12 are evidence-gated and must not be treated as calendar commitments.

---

## 4. The 13 phases

| # | Phase | Objective | Primary output | Exit proof |
| :- | :--- | :--- | :--- | :--- |
| **0** | **Recovery and Truth Baseline** | Restore a truthful, reproducible foundation. | Canonical source/runtime/provider/Memory truth; governed execution/review/audit/rollback; recovery baseline. | A safe end-to-end governed command is reproducible without routine manual rescue; no false recovery or completion claims. |
| **1** | **Outcome and Privacy Contract** | Define success, identity, tenancy, authority, and privacy before adaptation. | Owner-readable outcome contract; roles/permissions; tenant isolation; privacy boundaries; product-mode access model. | Identity, tenancy and privacy controls are enforced and tested; successful outcome can be measured without unsafe data exposure. |
| **2** | **Durable Learning Transport and Observability** | Prevent silent loss, duplication, reordering, or untrusted outcome ingestion. | Transactional outbox/queues; idempotency; retry/DLQ/replay; integrity checks; SLOs and failure observability. | Zero lost outcomes or duplicate side effects in test; exact replay works; failures cannot block owner commands indefinitely. |
| **3** | **Evaluation Foundation** | Know whether Pandora is becoming better rather than merely different. | Benchmark corpus; deterministic/security/human/model/production evaluation layers; exact evidence binding; cost/quality baselines. | Content-addressed baselines exist; hard security/privacy gates cannot be averaged away; model judges are not sole authority for sensitive work. |
| **4** | **Memory Quality, Reflection and Wise Forgetting** | Turn verified experience into scoped, explainable, reversible knowledge. | Deduplication; contradiction handling; confidence/decay; provenance; review; retrieval-quality evaluation; governed forgetting. | Memory promotion is explainable and reversible; retrieval quality is measured before canonical promotion. |
| **5** | **Adaptive Model and Tool Router** | Choose the least-cost capable provider/model/method subject to policy and proof. | Shadow routing; task/policy/context constraints; fallbacks; circuit breakers; cost/latency/quality telemetry; low-risk canary. | Shadow recommendations meet/beat baseline; constraints hold under chaos tests; one canary survives observation. |
| **6** | **Skill Compiler and Reusable Strategy Library** | Convert repeated verified success into reusable, versioned capability. | Versioned skills/strategies; prerequisites; scope/risk contract; exact-head tests; review and rollback; anti-pattern capture. | A reusable skill activates only after exact-head evidence and risk-appropriate review, and can be disabled without corrupting project state. |
| **7** | **Champion-Challenger Promotion and Self-Repair** | Improve safely through measured competition and bounded repair. | Champion/challenger evaluation; repair loops; verifier independence; canary promotion; regression detection; automatic rollback. | No candidate becomes champion without evidence of improvement and independent verification; failures return to bounded repair or rollback. |
| **8** | **Owner Experience and Mobile Learning Control** | Make Pandora understandable and useful to a non-technical owner from a phone. | Simple/Professional/Admin modes; 9-concept IA; premium UI; rapid frontend hook; Technical Alpha; Builder/Verifier surfaces; mobile control. | From a smartphone, an owner can state one software task and receive a verified working result without routine developer rescue. |
| **9** | **Business Outcome and Unit-Economics Loop** | Prove real customers value the result and the economics can support growth. | Paid pilots; Build vs Runtime credits; outcome telemetry; retention; pricing; contribution margin; gross-margin path; LTV/CAC and scale gate. | Real payment, repeat use/retention, attributable outcomes and credible contribution economics justify or reject horizontal scale. |
| **10** | **Scale Data Plane and Long-Term Experience Archive** | Scale durable outcome/history infrastructure without losing privacy, isolation, recovery, or cost control. | Multi-tenant archive; retention; partitioning; replay/recovery; storage/compute governance; long-horizon experience history. | Load, recovery, privacy/tenancy and cost tests prove the data plane can support the next scale envelope. |
| **11** | **Proprietary Pandora Task-Model Gate** | Build a Pandora-specific task model only if evidence proves it earns its cost. | Benchmark external/open/specialized alternatives; data governance; distillation/fine-tuning experiments; fallback and portability. | A controlled evaluation shows material quality/cost/latency/reliability/privacy advantage; otherwise remain model-agnostic. |
| **12** | **Enterprise / Ecosystem Conditional Phase** | Earn enterprise and ecosystem expansion only when demand exists. | SSO/SCIM/audit/private execution; policy controls; SDKs; connectors; third-party agents/skills/components; BYO models; marketplace economics. | Multiple credible enterprise demands and/or organic ecosystem transactions justify the complexity and economics. |

> **Task denominator note:** The 116-task denominator is preserved. This unified roadmap intentionally does not renumber or invent missing task IDs; the phase-level overlay governs how the existing task ledger is interpreted.

---

## 5. Technical Alpha — Cross-Phase Proof Track

Technical Alpha is not Phase 14 and it does not alter the 13-phase denominator. It is the shortest vertical path through the roadmap that proves Pandora can turn owner intent into a verified working system.

> **Technical Alpha success condition:** from a smartphone, the owner gives one bounded software task and Pandora returns a verified working result without routine manual developer rescue.

### Reference Alpha Journey
Owner input: *"I want customers to book my aircon technicians online."*
1. Understand the request and infer the correct project/workspace.
2. Generate a polished, convincing frontend immediately so the owner sees tangible value early.
3. Show what Pandora understood and ask only questions that truly block implementation.
4. Continue backend, database, authentication and integration work through governed workers/providers.
5. Run functional, security, privacy, tenancy, persistence, accessibility, performance and recovery checks.
6. Bind the result to exact source, environment, deployment candidate and rollback evidence.
7. Present the Verifier evidence in owner language.
8. Request approval only where the owner or policy is actually required.
9. Release safely, observe the real booking outcome, and write governed learning back to Memory.

### Rapid prototype contract
- The first visual should be excellent enough to sell the possibility of the final product.
- The UI must never imply that backend, auth, payments, data persistence, integrations, deployment, or security are already verified when they are not.
- A clear proof ladder must remain visible: `Documented -> Implemented -> Tested -> Deployed -> Production verified`.
- The early frontend is a customer-acquisition and comprehension hook; Pandora Verifier is what converts it into trust.

---

## 6. Product experience architecture

Pandora is not fundamentally a chat app, code editor, DevOps dashboard, or no-code builder. The customer experience is **Human Intent -> Pandora -> Trusted Working Result**.

### Three modes
- **Simple Mode:** Founders, SMB owners, operators, non-technical users. Outcome language; minimal technical vocabulary; guided Build/Run/Verify; owner decisions only when needed.
- **Professional Mode:** Developers, agencies, technical teams. Source, branches, environments, APIs, migrations, logs, observability, model controls, custom infrastructure, rollback and diagnostics.
- **Pandora Admin Mode:** Pandora platform operators/owner. Provider governance, worker fabric, memory/evaluation, policy, risk, audits, costs, system health, release governance and portfolio control.

### Nine-concept information architecture
1. **Home:** What needs me? What is Pandora doing? What is blocked? What happens next?
2. **Build:** Describe outcomes, review interpretation, see prototype, create governed implementation plans.
3. **Run:** Operating systems, workflows, jobs, deployments, health and active business operations.
4. **Connect:** Providers, accounts, scopes, allowlisted targets and connection health — never secrets.
5. **Memory:** What Pandora knows, why it believes it, freshness/confidence, conflicts, review and forgetting.
6. **Verify:** Independent evidence, proof ladder, exact binding, tests, security, review, rollback and production proof.
7. **Business:** Customer outcomes, pilots, revenue, retention, credits, COGS, margin and scale gates.
8. **Library:** Reusable templates, skills, strategies, components and later ecosystem artifacts.
9. **Settings:** Account, team, roles, privacy, policies, notifications, appearance and developer diagnostics.

> **Screen denominator:** The UI/UX Master Plan targets approximately 112 canonical screens across the three modes, with an 18-screen Simple Mode as the minimal owner experience.

---

## 7. The 14-worker execution fabric

The 14-window/worker layout is how Pandora executes work in parallel. It is not the roadmap and it is not a hard architectural limit.

- Workers receive bounded tasks from ProjectOS; they do not become independent authorities.
- Each worker task carries project identity, exact source/head where relevant, risk class, allowed providers, evidence requirements, retry semantics, and rollback/stop conditions.
- Workers may specialize in source, data/auth, frontend, mobile, providers, release, observability, research, business validation, review or other functions, but roles can be reassigned as workload changes.
- Jules and future coding/review agents are workers/agents in the same governed fabric. Their output is evidence input, not automatic truth.
- Where reviewer independence is required, the system verifies independence and qualification rather than assuming a different model/vendor is sufficient.
- Pandora Builder coordinates creation; Pandora Verifier coordinates proof. A worker that builds a candidate must not be the sole authority that declares it production-safe.

---

## 8. Business validation and commercialization

Pandora validates the business while the technical system is still being proven.

- **During Technical Alpha:** Interview narrow target segments; observe workflows; test the rapid prototype; collect willingness-to-pay; run safe non-regulated pilots; estimate build/runtime cost even before billing is live.
- **Before Phase 9 exit:** Convert at least a subset to real paid pilots. Measure activation, time-to-first-useful-result, repeated use, deployment usage, support burden and actual outcome.
- **Phase 9:** Formalize Build Credits vs Runtime Credits, contribution margin, retention, pricing/packaging, gross-margin path, LTV/CAC and scale authorization.
- **After Phase 9:** Expand horizontally only if economics and adjacent demand support it. Otherwise remain focused and deepen the winning vertical.
- **Phase 12:** Add marketplace/ecosystem only when third parties already want to build, reuse, publish, monetize or operate on Pandora.

---

## 9. Immediate Phase 0 Priority Stack

1. **Restore reliable Pandora-native Memory and provider reads** so the control plane itself can establish fresh truth.
2. **Reconcile and record the new source authority** in Memory and canonical documentation; remove stale old-owner assumptions from operating docs.
3. **Restore protected-main / exact-head governance** and verify review trust on the current canonical repository.
4. **Reconcile Supabase source/migration/auth state** and prove the platform can create and manage real users under correct tenancy/roles.
5. **Land the unified roadmap and structural amendment** into the canonical docs without changing the 13-phase / 116-task denominator.
6. **Complete the Technical Alpha vertical slice** with a rapid premium frontend, real backend/provider behavior, independent Verifier evidence, and real-device proof.
7. **Run customer discovery/pilot work in parallel**; do not wait for the whole platform to be feature-complete before testing willingness to pay.
