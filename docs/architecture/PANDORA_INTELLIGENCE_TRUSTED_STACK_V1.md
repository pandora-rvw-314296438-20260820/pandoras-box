
# Pandora Intelligence Trusted Stack v1

## Purpose

Pandora owns the durable intelligence system. Models are replaceable reasoning engines; external skill/knowledge repositories are upstream inputs; primitives are reusable implementation components; Worker C remains the only execution authority; Worker E remains independent verification authority; Worker A remains durable lineage authority.

This layer turns:

`CUSTOMER INTENT -> PROJECTSPEC -> TRUSTED SKILLS + TRUSTED KNOWLEDGE + TRUSTED PRIMITIVES -> MODEL ROUTING -> STRUCTURED PROPOSAL -> WORKER C -> WORKER D -> WORKER E -> WORKER F`

The customer-facing product continues to expose projects, build progress, preview, changes and publish. Provider names, skill IDs, knowledge packs, primitive versions and routing details stay internal unless an explicit professional/admin diagnostic surface requests them.

## Canonical separation

- **Skill**: a versioned proposal-only workflow describing how Pandora should approach a class of task.
- **Knowledge**: versioned, provenance-bearing operational/reference material used to ground a task.
- **Primitive**: a versioned reusable application implementation component owned by Worker I.
- **Model**: a replaceable reasoning/generation provider selected by Worker B under policy.
- **Tool**: a real-world operation whose authorization belongs to Worker C.
- **Receipt**: durable lineage recording exact skill/knowledge/primitive/model inputs and content digests without storing master credentials.

Knowledge is not authority. Skills are not authority. Model output is not authority.

## Worker ownership

### Worker A — Control Plane

Persists exact ProjectSpec/project-version lineage and, in later storage milestones, AI execution receipts, skill/knowledge versions and verification evidence. Worker B registries must not become a second durable control plane.

### Worker B — Intelligence

Owns:

- model contracts and capability registry;
- trusted skill selection;
- trusted knowledge retrieval;
- bounded context composition;
- model policy/routing;
- provider adapters;
- structured proposals;
- secret exclusion before provider calls.

### Worker C — Tool Gateway

Owns every privileged operation. Skills declare required tool capabilities by abstract name only. They never contain master credentials and cannot execute commands directly.

### Worker D — Build Runtime

Materializes exact project/source/skill-driven plans in bounded sandboxes after Worker C authorization.

### Worker E — Independent Verification

The only worker allowed to promote exact skill/knowledge source digests to `TRUSTED`. Builder model output is never sufficient evidence. Final composed applications remain independently verified even when all ingredients are trusted.

### Worker F — Project Runtime

Provisioning/deployment remains exact-version, authorized and provider-readback bound.

### Worker G — Product Experience

Hides provider and implementation details from Simple Mode.

### Worker H — Business Intelligence

Consumes execution receipts and verified outcomes to calculate cost, latency, first-pass success, repair cost and model/skill performance.

### Worker I — Trusted Primitives

Continues to own reusable application implementation components. Skills may require primitive capabilities but do not own primitive source.

### Worker J — Integration

Proves the complete intent -> skill/knowledge/primitive -> model -> authorization -> build -> verification -> runtime journey.

## Skill contract

Every `PandoraSkillDefinition` uses an exact semantic version. Mutable aliases such as `latest` are rejected.

Lifecycle:

`DISCOVERED -> IMPORTED -> EXPERIMENTAL -> VERIFIED -> TRUSTED -> DEPRECATED/BLOCKED`

A skill declares:

- exact `skillId@version`;
- business/technical capabilities;
- supported project types;
- required knowledge topics;
- required tool capability names;
- required primitive capability names;
- bounded instructions;
- model requirements;
- risk class;
- source provenance and immutable source digest;
- verification profile.

All skills are `proposal_only`. Worker E PASS evidence must match the exact `sourceDigest` before promotion to `TRUSTED`.

## Operational knowledge contract

Knowledge entries are exact-versioned and provenance-bearing. The registry records source repository/commit/path/URL/license and optional upstream authority. Entries carry risk class, platform scope, verification timestamp and optional expiry.

Trusted retrieval excludes:

- expired entries;
- `BLOCKED`/`DEPRECATED` entries;
- entries above the task's maximum permitted risk;
- unverified candidates when trusted-only retrieval is requested.

External collections such as `trimstray/the-book-of-secret-knowledge` are upstream discovery sources only. The repository's license does not relicense every linked external resource. Pandora therefore stores provenance and verifies/references upstream material selectively instead of blindly copying or executing it.

## Risk classes

1. `INFORMATIONAL`
2. `READ_ONLY_DIAGNOSTIC`
3. `SAFE_MUTATION`
4. `PRIVILEGED`
5. `SECURITY_ACTIVE`
6. `DESTRUCTIVE`
7. `PROHIBITED`

Worker B may reason about higher-risk knowledge when policy permits, but execution remains Worker C-gated. A command appearing in external knowledge never becomes executable authority.

## Model routing

Routing order is:

1. task requirements;
2. model capability compatibility;
3. Pandora policy filters;
4. provider availability;
5. reliability/cost/latency baseline score;
6. verified Pandora performance evidence;
7. fallback only after retryable provider failures.

Routing policy supports provider/model allow/deny lists, maximum cost class, minimum reliability, builder/verifier independence and performance-weighted scoring.

Gemini remains the primary initial provider, but the contract is provider-independent. Additional providers are adapters, not architectural dependencies.

## Independent verification

A verification route may exclude the builder provider/model. This is an additional independence signal only; deterministic tests, exact source/artifact checks, live provider readbacks and Worker E acceptance remain authoritative.

## Intelligence composition

`IntelligenceComposer` receives the exact project/task capability request and selects only `TRUSTED` skills and `TRUSTED`, non-expired knowledge within the risk budget. It records exact skill/knowledge/primitive references, required tool capabilities, aggregated model requirements and deterministic ProjectSpec/context digests.

Composition output explicitly records `executionAuthority: worker_c_only`.

## AI execution lineage

`createAiExecutionReceipt()` persists a secret-free receipt shape containing:

- execution/project/project-version/task identifiers;
- exact skill refs;
- exact knowledge refs;
- exact primitive refs;
- routed provider/model and fallback metadata;
- context/input/output digests;
- token/cost/latency usage;
- verification requirement/evidence reference;
- deterministic receipt digest.

Raw prompt/output bodies are intentionally not part of the receipt. Master credentials are rejected by the existing Worker B secret boundary.

## External skill ingestion policy

Collections such as `ComposioHQ/awesome-claude-skills` are seed catalogs, not trusted dependencies.

Target ingestion pipeline:

`DISCOVER -> SNAPSHOT EXACT COMMIT -> PARSE -> NORMALIZE -> LICENSE/PROVENANCE -> RISK CLASSIFY -> REMOVE DIRECT EXECUTION AUTHORITY -> EXPERIMENTAL -> WORKER E TESTS -> TRUSTED`

Only a curated subset should be promoted. Quantity is not a trust signal.

## WorkWeave router policy

`workweave/router` is reference/benchmark material for action-level model routing, provider abstraction, fallback and observability. Pandora retains its own router abstraction and routing-performance dataset. The external router is not the control plane and is not required for Pandora availability.

## Implemented in this milestone

- exact-version Pandora Skill contract and registry;
- proposal-only skill invariant;
- risk-bounded skill selection;
- Worker E-only exact-digest skill certification;
- exact-version Operational Knowledge contract and registry;
- provenance/freshness/risk-aware knowledge retrieval;
- Worker E-only exact-digest knowledge certification;
- bounded Intelligence Composer joining skills, knowledge and primitive refs;
- model requirement aggregation;
- routing policy filters and performance scoring hooks;
- builder/verifier route independence filter;
- deterministic secret-free AI execution receipts;
- regression tests for trust, freshness, risk, authority, secret exclusion and routing policy.

## Subsequent bounded milestones

1. Persist Skill/Knowledge/AI execution metadata through Worker A migrations without creating a second control plane.
2. Add first-party Pandora skill candidates for ProjectSpec, web/Flutter build, Supabase design, test/repair, preview/publish and verification.
3. Add official-doc-first operational knowledge candidates for HTTP, DNS, TLS, Git, GitHub, PostgreSQL, Supabase, Flutter, Node and Vercel.
4. Implement external `SKILL.md` importer with immutable provenance and license metadata.
5. Implement curated knowledge importer with freshness revalidation.
6. Wire selected skill/knowledge context into the server-side Gemini intelligence path after PR #152 convergence.
7. Add Worker E certification fixtures and exact-digest promotion evidence.
8. Add Worker A durable AI execution receipt storage.
9. Add additional model adapters only after the provider-independent policy/receipt contract is stable.
10. Add Worker H rollups for cost, latency, verified success and repair-rate feedback into routing policy.
11. Add governed candidate-skill/candidate-knowledge learning from repeated verified project outcomes.
12. Worker J proves the complete customer journey end to end.

## Security invariants

- Gemini/model providers never receive GitHub/Vercel/Supabase master credentials.
- External skill/knowledge content never grants tool authority.
- Exact source digests are mandatory for trust promotion.
- Worker B cannot certify its own skills or knowledge.
- Trusted inputs do not eliminate final application verification.
- Provider/model identity remains replaceable and hidden from the Simple Mode customer contract.
- All GitHub/Vercel/Gemini provider credentials stay in the existing server-side Vault-backed broker paths.
