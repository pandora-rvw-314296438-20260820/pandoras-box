# Banatao Systems 25,000-Business Personalization Operating Contract

**Canonical version:** 1.0.0  
**Effective date:** 2026-08-08  
**Owner:** Banatao Systems  
**Primary control plane:** MCPMaster / Pandora's-Box / Pandora  
**Authoritative operating memory:** Pandora's-Box Memory  
**Durable source mirror:** GitHub under `banataosystems`  
**Initial geographic objective:** Bacolod and the surrounding market, expanded only through evidence-backed cohorts  
**Ultimate portfolio objective:** 25,000 distinct, useful, owner-governed business systems

---

## 1. Directive

Build a portfolio of 25,000 highly personalized business systems without creating 25,000 unrelated codebases, without publishing unverified business claims, and without forcing owners to reorganize their work around generic software.

The system must adapt to the real business. The business must not be forced to adapt to the system.

“Personalized” means that each business receives a system assembled from a governed shared platform, sector modules, configuration, verified business facts, approved workflows, brand assets, permissions, integrations, and owner preferences. It does **not** mean generating an unmaintainable fork of the application for every customer.

The work must proceed in dependency order. No later scale phase may be treated as active merely because it is attractive or technically possible. Every phase exits only when its proof gate passes.

This contract cannot guarantee a commercial outcome. It is designed to prevent false progress and maximize the probability of reaching the objective through measurable, reversible, evidence-bound execution.

---

## 2. Exact definition of the 25,000-business outcome

A database row, scraped listing, generated preview, unpublished website, or unclaimed profile does not count toward the 25,000 objective.

A business counts as an **Active Useful Business System** only when all required conditions are true:

1. **Unique identity:** It has a deduplicated canonical business identity and stable internal identifier.
2. **Lawful source:** The origin, permitted use, retrieval date, and source evidence for public discovery data are recorded.
3. **Authorized control:** The owner, an authorized representative, or an approved sponsoring partner has claimed or explicitly authorized the system.
4. **Approved truth:** Material public facts are owner-approved or independently verified, versioned, and traceable to evidence.
5. **Published capability:** At least one production-verified digital surface or business workflow is live.
6. **Working action:** At least one owner-approved customer action—call, message, inquiry, booking request, order intent, quote request, registration, or equivalent—has been tested end to end.
7. **Tenant isolation:** The business cannot access another business’s private records, and another business cannot access its private records.
8. **Operational ownership:** The owner can perform the essential update or operating workflow from a common Android phone without needing a developer.
9. **Freshness:** Facts and contact routes have a review date, staleness policy, and re-verification path.
10. **Safety and compliance:** Applicable privacy, security, consumer, contractual, sector, and regulated-capability gates are satisfied.
11. **Recovery:** The active publication or workflow has a known source version, deployment evidence, and rollback path.
12. **Useful outcome:** The business has either received a legitimate customer action or has completed a controlled real-world test proving the action path works.

The portfolio is complete only when **25,000 unique businesses simultaneously satisfy this definition**, with the evidence query and deduplication method preserved. Counts must be database-derived and reproducible. No manual estimate is permitted.

---

## 3. Portfolio architecture: one platform, many adaptive systems

### 3.1 Shared horizontal platform

The shared platform supplies:

- identity, organizations, memberships, roles, and tenant isolation;
- Business Fact Registry and provenance;
- media handling;
- module entitlement;
- structured site and workflow specifications;
- deterministic rendering;
- preview, publishing, immutable releases, and rollback;
- leads and contact actions;
- consent, notifications, support, audit, analytics, and incident operations;
- owner-facing phone-first control surfaces;
- provider adapters;
- sector module contracts.

### 3.2 Business-specific adaptive layer

Each business receives a versioned **Business Blueprint** containing:

- canonical business identity and aliases;
- owner and operator roles;
- category and operating model;
- customer journeys;
- approved public facts;
- offerings, prices, schedules, service areas, and policies;
- brand identity and approved media;
- internal operating workflows;
- enabled modules and integrations;
- notification preferences;
- data classification and retention rules;
- sector-specific compliance gates;
- success metrics;
- current active publication and rollback target.

The blueprint is data and configuration, not arbitrary executable code.

### 3.3 Sector modules

Sector repositories add bounded capabilities to the shared platform. A sector module may define new workflows, records, screens, validations, and reports, but it must not create a second identity system, bypass tenant isolation, silently copy customer data, or establish an independent ungoverned publishing path.

### 3.4 Control-plane separation

- **Pandora's-Box / Pandora** governs work, approvals, provider actions, releases, evidence, and recovery.
- **Pandora Memory** stores durable project operating state, decisions, requirements, source evidence, hashes, and proof. It is not the customer application database.
- **LaunchOS and sector applications** store customer and operational data in their own protected application databases.
- **GitHub** is the durable source and collaboration mirror, not the sole source of project truth.
- **Vercel** is a deployment plane, not proof by itself.
- **Supabase** is an application data plane and must enforce RLS, authorization, backup, and environment separation.

No public customer runtime may depend on Pandora Memory being online.

---

## 4. Dependency-ordered execution roadmap

### Phase 0 — Control plane, recovery, and canonical registry

**Objective:** Establish trustworthy project identity, source, deployment, memory, and authority before scaling.

Deliver:

- restore the MCPMaster-to-Pandora Memory connector;
- remove or correctly bypass the Vercel protection boundary for the machine endpoint without exposing privileged user surfaces;
- verify positive health/search with the correct workload identity and negative failure with the wrong identity;
- reconcile every project to one canonical GitHub repository, Vercel project, Supabase project, production URL, source snapshot, and rollback target;
- register all projects, aliases, dependencies, proof gates, and owners in Pandora Memory;
- establish the GitHub/Pandora dual-write protocol;
- preserve source recovery evidence from the suspended historical GitHub account;
- create the portfolio project mapping queue for products without a verified repository.

**Exit proof:** Canonical registry is retrievable; GitHub repositories are writable; the Memory data plane is healthy; machine retrieval is verified; no project is represented as recovered without a source manifest and hash.

### Phase 1 — Bacolod 25K Business Census and Readiness Blueprint

**Objective:** Define how the target population will be discovered lawfully and converted into a verified master registry.

Deliver:

- source inventory: official, partner, business-controlled, licensed, and permitted public sources;
- source terms, licensing, retrieval method, allowed fields, update cadence, and deletion obligations;
- canonical registry schema;
- deduplication and alias strategy;
- geocoding and address-normalization rules;
- sector taxonomy;
- claim eligibility and contact-permission rules;
- anti-spam and do-not-contact controls;
- data-quality rubric;
- sample acquisition and manual validation;
- coverage estimate with confidence intervals, not an invented exact population claim.

**Exit proof:** A legal/terms-reviewed acquisition plan, schema, source register, and dedupe test exist. No bulk collection begins before the relevant source is approved.

### Phase 2 — Verified discovery registry and claim workflow

**Objective:** Build a clean unclaimed-business registry without pretending the entries are customers.

Lifecycle:

`discovered → source-verified → deduplicated → classified → claim-eligible → invited → claimed → owner-verified → facts-approved`

Deliver:

- source snapshots and retrieval timestamps;
- duplicate candidate scoring and human resolution;
- business aliases and historical names;
- public contact-route validation;
- clear “unclaimed” labeling;
- business claim flow;
- authorization challenge appropriate to risk;
- ownership dispute and appeal process;
- removal and correction requests;
- partner cohort imports with source contracts.

**Exit proof:** A representative sample can be imported, deduplicated, corrected, claimed, and removed without cross-tenant exposure or unsupported claims.

### Phase 3 — Human discovery and Android proof

**Objective:** Validate the operating experience before broad engineering.

Deliver:

- 15–25 genuine adult Philippine Android-first participants across at least five creation or business types;
- observation of existing Facebook, Messenger, spreadsheet, paper, phone, and informal workflows;
- test of the wording “AI-assisted, owner-approved”;
- test of minimum facts required for a credible presence;
- adaptive owner interview;
- Tagalog, Taglish, and English comprehension tests;
- owner workflow map and rejected-feature list.

**Exit proof:** At least 80% complete the critical prototype without developer help; repeated confusion is repaired; minimum fact sets and first template/module families are evidence-approved.

### Phase 4 — Multi-tenant security and data foundation

**Objective:** Create the safe substrate before customer data or mass onboarding.

Deliver:

- pinned application stack and lockfiles;
- identity, organizations, memberships, roles, and last-owner protection;
- RLS on every exposed tenant-owned table;
- positive and negative authorization tests;
- server-side authorization for privileged mutations;
- preview/production secret separation;
- migrations, backup, restore, audit, incident, and retention controls;
- upload safety;
- privacy impact and threat assessments;
- accessibility and mobile performance budgets.

**Exit proof:** Cross-tenant tests pass; restore drill succeeds; no unresolved critical/high security finding; production secrets are isolated; every privileged mutation is auditable.

### Phase 5 — Business Fact Registry and owner approval

**Objective:** Convert research and owner input into controlled business truth.

Every fact must include:

- fact key and value;
- status: proposed, owner-approved, independently verified, disputed, stale, retired;
- source reference and captured date;
- confidence;
- who proposed, edited, approved, and verified it;
- public/private classification;
- effective and review dates;
- supersession history.

Material claims include identity, contact routes, address, service area, prices, credentials, regulated status, guarantees, testimonials, hours, and payment instructions.

**Exit proof:** No material fact becomes publishable without the required approval. Interrupted onboarding resumes without loss. Every public fact can be traced to its active revision and provenance.

### Phase 6 — Structured personalization and deterministic rendering

**Objective:** Produce high-quality variation without arbitrary code generation.

Deliver:

- versioned component and workflow registry;
- sector-aware template families;
- design tokens;
- structured site/workflow specification schema;
- validator;
- deterministic renderer;
- three owner-selectable design directions;
- simple phone editor;
- accessibility, SEO, performance, and visual checks;
- canonical Banatao Systems/Red Apple attribution where approved.

**Exit proof:** Unsupported blocks fail closed; generated specifications pass validation; owner edits preserve provenance and version history; representative outputs pass mobile visual review.

### Phase 7 — Preview, publishing, rollback, and contact routes

**Objective:** Complete the first useful value loop.

Deliver:

- private preview;
- explicit owner publication confirmation;
- immutable publication records;
- atomic active-publication pointer;
- failed-release protection;
- subdomain and later domain management;
- call/message/inquiry/booking/order/quote actions;
- source attribution;
- notification delivery;
- spam and abuse controls;
- one-tap rollback.

**Exit proof:** Ten consecutive publish-and-rollback exercises pass; a failed candidate cannot replace the live version; every enabled contact route is tested end to end.

### Phase 8 — Closed pilot: 25–50 businesses

**Objective:** Prove usefulness and operational support in a controlled cohort.

Deliver:

- 25–50 accepted businesses across three or more sectors;
- assisted onboarding playbook;
- factual-error reporting;
- daily funnel, failure, performance, and support review;
- device and poor-network testing;
- moderation and impersonation response;
- incident and rollback runbooks;
- real cost model.

Initial pilot gates:

- at least 70% of accepted pilot businesses publish;
- at least 50% of published businesses receive or successfully complete a real contact-action test;
- no unresolved critical security, privacy, data-loss, or tenant-isolation defect;
- owners can update and republish without developer intervention;
- support load and unit cost fit an owner-approved scale model.

### Phase 9 — Controlled public MVP and first 100 Active Useful Business Systems

**Objective:** Prove repeatability outside a hand-held pilot.

Deliver:

- invite-only or segment-limited onboarding;
- support and incident ownership;
- pricing experiments only after cost evidence;
- provider-hosted billing if authorized;
- accurate funnel instrumentation checked against database truth;
- first 100 businesses meeting the full outcome definition.

**Exit proof:** Reproducible count of 100; release/rollback and support metrics stable; no material factual-approval or tenant-isolation regression.

### Phase 10 — 500-business operating cohort

**Objective:** Prove cohort automation and sector modularity.

Deliver:

- automated onboarding triage;
- business freshness jobs;
- module entitlement;
- partner cohort access with isolation;
- support queue prioritization;
- quality sampling;
- first sector modules promoted through evidence.

**Exit proof:** 500 Active Useful Business Systems; measured support load, costs, availability, factual-error rate, and contact outcomes remain within approved thresholds.

### Phase 11 — 2,500-business city-scale cohort

**Objective:** Prove infrastructure, partner, and data-quality scalability.

Deliver:

- queue-backed generation and publishing;
- rate and spend controls;
- bulk partner imports with contracts;
- source refresh and stale-record handling;
- portfolio health dashboards;
- load, soak, restore, and incident exercises;
- cohort profitability and high-performing segment analysis.

**Exit proof:** 2,500 qualifying businesses; capacity headroom proven; privacy/security sampling passes; no manual process exists that cannot meet the next scale target.

### Phase 12 — 10,000-business regional-scale cohort

**Objective:** Prove multi-cohort operations without degrading trust.

Deliver:

- regional source and partner governance;
- resilient queues and storage;
- fraud, impersonation, and abuse operations;
- delegated agency/partner permissions;
- automated site/contact health;
- business export, transfer, suspension, and deletion at scale;
- quarterly security, privacy, reliability, and economics review.

**Exit proof:** 10,000 qualifying businesses; exact count reproducible; service objectives, support, and recovery targets proven under measured load.

### Phase 13 — 25,000 Active Useful Business Systems

**Objective:** Reach the defined portfolio outcome without lowering the definition.

Deliver:

- 25,000 unique qualifying businesses;
- reproducible deduplication and eligibility query;
- owner/partner authorization evidence;
- approved fact and publication lineage;
- tested contact/action paths;
- portfolio-wide freshness state;
- sector and cohort distribution;
- capacity, support, privacy, security, incident, backup, and rollback evidence;
- unit-economics and sustainability review;
- independent verification of the count and proof method.

**Exit proof:** Independent verification confirms the count and criteria. No unclaimed profile, dead contact route, generated preview, duplicate identity, or unsupported claim is included.

### Phase 14 — Advanced and regulated capabilities

Only after the core portfolio is stable:

- custom domains and domain lifecycle;
- tiered verification;
- booking, catalog, ordering, inventory, workforce, and sector operations;
- partner APIs and webhooks;
- branded calling and carrier bundles;
- licensed payment links and reconciliation;
- funding, property, or regulated workflows;
- large institutional and government-sponsored cohorts.

Each capability remains independently gated. Scale does not waive regulation, security, privacy, contracts, or owner authorization.

---

## 5. Canonical business registry model

Minimum entities:

- `businesses`
- `business_aliases`
- `business_locations`
- `business_categories`
- `business_sources`
- `source_snapshots`
- `source_permissions`
- `dedupe_candidates`
- `business_claims`
- `claim_challenges`
- `claim_disputes`
- `business_fact_items`
- `business_fact_revisions`
- `business_blueprints`
- `business_modules`
- `business_memberships`
- `sites`
- `site_spec_versions`
- `previews`
- `publications`
- `publication_checks`
- `contact_routes`
- `contact_events`
- `leads`
- `consent_records`
- `support_cases`
- `moderation_cases`
- `verification_cases`
- `audit_events`
- `retention_actions`
- `partner_cohorts`

Public rendering must read only a deliberately published projection. It must never expose broad internal tables.

---

## 6. Research, acquisition, and outreach rules

Permitted work must be source-specific, documented, and proportionate.

Never:

- bypass access controls, CAPTCHAs, rate limits, robots restrictions, or contractual restrictions;
- scrape private accounts or restricted databases;
- buy or ingest unknown-origin personal data;
- infer sensitive personal attributes;
- treat a social profile as proof of ownership;
- publish a business as a customer without authorization;
- spam every discovered contact;
- store raw private messages in analytics or semantic memory;
- use an IP address or device fingerprint to identify a person beyond legitimate security, abuse prevention, or consented analytics.

For every source, record:

- source owner and URL or provider identifier;
- permitted-use basis;
- fields collected;
- retrieval method;
- retrieval date;
- update frequency;
- attribution requirement;
- retention/deletion obligation;
- whether outreach is permitted;
- review owner.

Outreach must use consent, legitimate relationship, or a documented lawful/contractual basis. Respect opt-out and do-not-contact state across the portfolio.

---

## 7. AI operating rules

AI may:

- propose structured facts from owner input or approved public sources;
- classify business type;
- suggest workflows and modules;
- draft copy from approved facts;
- generate design directions within governed components;
- detect contradictions and stale information;
- summarize analytics and operational evidence;
- recommend the one highest-value safe next action.

AI may not:

- silently publish material claims;
- invent credentials, prices, approvals, locations, testimonials, or availability;
- execute arbitrary customer-generated code;
- make a regulated eligibility or adverse decision without the required human/partner process;
- copy private customer data into Pandora Memory, GitHub, prompts, logs, or analytics;
- train or fine-tune on customer data without a separately approved dataset, privacy review, and evaluation;
- mark its own work independently reviewed;
- claim production verification from a build result alone.

Every material AI result records model/provider/version where practical, source inputs, time, disposition, and reviewer.

---

## 8. Security, privacy, and identity

Mandatory controls:

- organization- and business-scoped authorization;
- RLS for every exposed tenant-owned table;
- server-side authorization for privileged actions;
- AAL2 for role elevation, release authorization, sensitive export, destructive retention action, regulated activation, and production administration;
- last-owner protection;
- short-lived signed media access;
- secrets server-side only;
- environment separation;
- dependency and secret scanning;
- upload validation and malware controls where applicable;
- rate limiting and abuse protection;
- append-only or tamper-evident audit evidence;
- backup and restore tests;
- data retention and deletion;
- privacy-safe analytics;
- incident response.

No customer secret, credential, financial document, private KYC record, protected health information, student record, legal privileged material, investigation evidence, or raw private message may be stored in public GitHub, product analytics, screenshots, semantic project memory, or ordinary logs.

---

## 9. Sector module promotion rules

A new sector module may be promoted only when:

1. the target workflow is observed in real businesses;
2. the module does not duplicate the shared core;
3. data classes and permissions are defined;
4. its failure does not break the public website or unrelated modules;
5. it has tenant-isolation and negative authorization tests;
6. mobile owner workflows pass;
7. integration timeouts, retries, idempotency, revocation, and degraded behavior exist;
8. applicable legal and partner gates are documented;
9. support and offboarding exist;
10. the exact release has source, tests, review, deployment, and rollback evidence.

---

## 10. GitHub and Pandora Memory dual-write protocol

Every durable instruction, roadmap, architecture decision, release manifest, or meaningful verified state change must have two linked copies:

### GitHub copy

Store the human-readable source in the canonical repository with:

- path;
- branch;
- commit SHA;
- file SHA-256;
- parent history;
- review or initialization context;
- no secrets.

### Pandora Memory copy

Store the complete content or a governed content-addressed snapshot with:

- project ID and project key;
- record type;
- title and full body;
- content SHA-256;
- GitHub owner/repository/path/branch/commit;
- created-by and approved-by identities;
- canon state;
- source/evidence references;
- effective time;
- idempotency key;
- supersession history.

### Conflict rule

- Newer verified evidence wins only after Pandora Memory is corrected.
- If GitHub and Pandora disagree and neither has newer verified proof, Pandora Memory governs project state.
- Never overwrite old evidence merely to make the current state look clean.
- A new version supersedes; it does not erase lineage.
- Customer operational data remains in the application database, not copied into Pandora Memory.

### Verification

A dual-write is complete only when:

- GitHub returns the expected file at the expected commit;
- SHA-256 matches the local source;
- Pandora returns the matching active record;
- metadata points to the exact GitHub source;
- the previous version remains recoverable;
- the audit event is present.

---

## 11. Project execution behavior

Before substantial work on an existing project, recover:

- identity and purpose;
- current phase;
- active tasks and dependencies;
- decisions and constraints;
- blockers and open loops;
- latest source snapshot;
- latest verified deployment;
- required proof gates;
- rollback state;
- highest-value safe next action.

Proceed autonomously with safe, reversible, no-cost connected work.

Interrupt the owner only for:

- missing credentials or permissions that tools cannot resolve;
- new spending;
- destructive production or data actions;
- public, legal, contractual, or partner commitments;
- regulated production activation;
- non-preauthorized production release;
- unavoidable external confirmation.

Do not require a desktop, terminal, CLI, local repository, manual file download, or copy-and-paste when a connected tool can perform the work.

---

## 12. Proof ladder and completion language

Always report separately:

1. **Documented**
2. **Implemented**
3. **Tested**
4. **Deployed**
5. **Production-verified**

Do not collapse these states.

Examples:

- Code in a repository is implemented, not necessarily tested.
- A passing build is tested in a limited sense, not deployed.
- A READY deployment is deployed, not necessarily reachable or correct.
- A successful HTTP response is not full workflow verification.
- A production feature is complete only after its task-specific acceptance proof, security/privacy checks, exact deployment verification, and rollback evidence pass.

Project percentages must be calculated from the current weighted roadmap/task/proof state. Never invent percentages.

---

## 13. Portfolio metrics

Database records, not analytics events, are authoritative for:

- claimed businesses;
- approved facts;
- active publications;
- contact routes;
- leads;
- billing;
- entitlements;
- verification;
- qualifying business count.

Track at minimum:

- discovered, deduplicated, claim-eligible, claimed, fact-approved, previewed, published, contact-verified, active/useful, stale, suspended, and removed counts;
- time to first credible preview;
- time to publication;
- owner completion without assistance;
- factual corrections;
- contact-route success;
- legitimate customer action rate;
- owner 7/30/90-day retention;
- support interventions;
- publication and rollback success;
- availability and mobile performance;
- cross-tenant/security incidents;
- privacy requests;
- abuse and impersonation;
- AI cost per qualifying business;
- infrastructure and support cost per qualifying business;
- gross margin by cohort after monetization.

No growth spending is justified until useful contact outcomes, retention, factual quality, support load, and unit economics are evidence-stable.

---

## 14. Required end-of-work report

At the end of substantial work, update Pandora Memory first and report:

- **What changed**
- **Evidence**
- **Current phase**
- **Done**
- **In progress**
- **Blocked**
- **Risks**
- **Next autonomous action**

Every claim must distinguish documentation, implementation, testing, deployment, and production verification.

---

## 15. Immediate portfolio order

The highest-value safe order is:

1. Repair MCPMaster/Pandora machine access and verify identity isolation.
2. Complete source-recovery manifests for Pandora's-Box and Memory under `banataosystems`.
3. Reconcile every new repository and its project identity in Pandora Memory.
4. Establish SmartCity as the governed 25K registry/cohort layer without implying government affiliation.
5. Complete LaunchOS LOS-002 real Android participant research.
6. Lock the shared security/data foundation.
7. Build the Business Fact Registry and claim workflow.
8. Build deterministic personalization, preview, publishing, rollback, and contact actions.
9. Run the 25–50 business closed pilot.
10. Scale through 100 → 500 → 2,500 → 10,000 → 25,000 only when each prior proof gate passes.
11. Add sector modules according to observed demand.
12. Activate carrier, payment, funding, property, investigation, education, or other regulated/high-risk capabilities only after their separate gates.

This order must not be reversed merely to produce a visually impressive demonstration.
