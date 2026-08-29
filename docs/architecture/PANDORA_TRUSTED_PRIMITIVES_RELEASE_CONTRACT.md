# Pandora Trusted Primitives — Worker I Release Contract

Status: release candidate, exact-source governed.

## Implemented primitive catalog

The catalog contains 18 reusable generated-application primitive families: Auth, RBAC, Admin, Audit, Notifications, Analytics, Booking, Commerce, Billing/Payments, CRM, Forms, Files, Search, Content, Scheduling, Customer Profile, Settings, and Feature Flags.

Every implemented catalog entry is exact-versioned and bound to an immutable SHA-256 source bundle. Mutable `latest` references are forbidden. Customer-runtime migrations remain source artifacts and are not applied to the Pandora Control Plane.

## Composition and materialization

Composition binds the exact project/version identity, primitive versions, source/definition/configuration/customization digests, required runtime capabilities, and dependencies. Materialization distinguishes primitive-core, customer-owned, and extension-point files. Customer-owned files are preserved; modified primitive-core and changed extension bases become review collisions instead of being overwritten.

Worker D receives exact digests and opaque runtime resource references only. Raw secret-shaped runtime fields are rejected.

## Upgrade lifecycle

Upgrade plans are exact from-version/to-version transitions with immutable migration digests. Downgrades, migration gaps, ambiguous chains, BLOCKED targets, incompatible event majors, unsafe automatic major changes, and irreversible automatic migrations fail closed or require manual review. Rollback and forward-fix identities are first-class lineage.

## Trust boundary

Worker I does not promote a primitive to `TRUSTED`.

A default registry cannot accept a PASS promotion. TRUSTED promotion requires a registry configured with a Worker E verification authority. That authority re-reads the exact sealed verification run by evidence ID and checks exact primitive source identity and authoritative required-check evidence before a PASS decision is accepted. Caller-supplied `authority: worker-e` text is insufficient.

Deliberately vulnerable fixtures cover disabled/allow-all RLS, privileged authenticated writes, secret-boundary leakage, payment spoofing, cross-tenant predicates, webhook replay, destructive migrations, and unsafe upgrades.

## Cross-worker lineae

- Worker A persists exact primitive composition and upgrade lineage against canonical project versions.
- Worker B may discover/select capabilities but cannot mutate trust.
- Worker C remains the privileged authorization/secrets boundary.
- Worker D materializes exact composition plans in bounded workspaces.
- Worker E independently verifies exact source/evidence and is the trust authority.
- Worker F consumes exact project/source/artifact/verification identity for preview and publish.
- Worker G owns Pandora's customer-facing Flutter experience; generated-app UI foundations are reusable inputs only.
- Worker H receives exact reuse, repair, verification, upgrade-burden, and comparable-baseline savings facts.
- Worker J verifies the integrated journey and live provider identity.

## Release proof

`test/trusted-primitives-worker-j-e2e.test.js` composes all 18 families in one web-application manifest and proves immutable supply-chain identity, upgrade planning, customer customization preservation, compensation boundaries, Worker D handoff, Worker E evidence/adversarial behavior, Worker A lineage, Worker F preview/production lineage, and Worker H economics.

Repository CI and exact-head Vercel provider readback are release gates. A Vercel provider `READY` state is deployment evidence only and does not replace Worker E application verification.
