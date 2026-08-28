# Pandora Trusted Primitives v1

## Purpose

Pandora Trusted Primitives are versioned reusable customer-application building blocks. Pandora should prefer an exact compatible primitive plus bounded configuration/customization over regenerating solved infrastructure from scratch. Customers remain project/outcome oriented; primitive package choices are internal composition details.

## Worker boundaries

Worker I owns primitive contracts, registry metadata, compatibility, composition artifacts, source/module boundaries, customization/upgrade lineage, fixtures and security baselines. Worker B selects from ProjectSpec; C authorizes privileged operations; D materializes exact versions; E independently verifies; F provisions declared runtime requirements; G hides implementation detail; H consumes usage/economic facts; A remains durable project/version lineage authority.

## Definition and trust

A `PrimitiveDefinition` declares exact semantic version, business capabilities, supported project types, runtime requirements, abstract secret requirements, dependencies, bounded configuration, permissions/events, extension points, source form, verification profile, lifecycle state and optional immutable source digest.

Lifecycle states: `EXPERIMENTAL`, `TRUSTED`, `DEPRECATED`, `BLOCKED`. Worker I cannot set `TRUSTED` through lifecycle APIs. PASS evidence must identify Worker E and match the exact source digest. Experimental entries without a source digest are intentionally impossible to promote to trusted. Final composed applications are independently verified even when all parts are trusted.

## Exact versioning and compatibility

Lineage uses exact versions such as `pandora-booking@3.0.2`; mutable `latest` is rejected. Dependencies use semantic ranges and composition fails closed on missing/incompatible required primitives or runtime capabilities.

## Registry / Worker B interface

`TrustedPrimitiveRegistry.findByCapability()` returns capability matches, exact versions, trust state, runtime requirements, configuration schema, complexity and verification-history signals. Worker B does not need source inspection. The initial catalog covers Auth, RBAC, Admin, Audit, Notifications, Analytics, Booking, Commerce, Billing/Payments, CRM, Forms, Files/Media, Search, Content, Scheduling, Customer Profile, Settings and Feature Flags. In the registry milestone they are contracts in `EXPERIMENTAL`, not implementation-complete claims.

## Composition and Worker A lineage

`composePrimitives()` accepts project ID, immutable project-version ID, project type, available runtime capabilities and exact primitive selections. It validates trust/block state, project compatibility, runtime requirements, dependencies and bounded config. Output records exact versions, definition/source digests, configuration/customization digests and a deterministic manifest digest designed for Worker A persistence without a second control plane.

`deriveGeneratedSourceLineage()` maps generated files to `primitive@version`, primitive definition/source digest, customization digest and ownership. Upgrade code must use this lineage and never blindly overwrite customization.

## Runtime, secrets and isolation

Manifests declare abstract capabilities such as `database`, `transactions`, `identity-provider` or `payment-provider` and abstract secret names only. They never carry Pandora master GitHub/Vercel/model credentials or Control Plane service-role values. Worker C/F resolves scoped runtime configuration. Generated-app DB/storage belongs to customer runtime; primitive migrations must not target Pandora Control Plane schemas.

## Events, verification and supply chain

Domain events have explicit schema versions such as `reservation.created@1.0`, `order.completed@1.0` and `payment.completed@1.0`. Verification profiles declare Worker E checks. Already-used primitive versions are immutable; behavior changes require a new version. Source/dependency changes cannot inherit trusted status without matching independent evidence.

## Implemented in the registry milestone

- canonical definition/trust/source contracts
- semantic version parser/range compatibility
- bounded configuration validation
- capability registry and Worker B selection signals
- Worker E-only trust transition gate
- lifecycle block/deprecation surface
- exact composition manifest and deterministic digests
- generated-source lineage mapping
- initial 18-family experimental catalog
- deterministic contract/security regression tests

Runtime implementations and proof fixtures are subsequent bounded milestones and must not be documented as implemented before their source/tests exist.
