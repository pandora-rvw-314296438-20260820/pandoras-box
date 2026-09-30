# Pandora Universal Enterprise Architecture V1

Status: Accepted / Locked architectural baseline  
Canonical source repository: `pandora-rvw-314296438-20260820/pandoras-box`  
Canonical Memory repository: `pandora-rvw-314296438-20260820/pandoras-box-memory`

## 1. Fixed boundary

Pandora is the vendor-neutral enterprise operating layer.

Business
→ Pandora Experience
→ Business Intent
→ Enterprise Model
→ Intelligence / Orchestration
→ Policy / Authorization
→ Capability Layer + Compatibility Layer
→ Provider Adapters / Existing Systems
→ Verified Results
→ Reconciliation
→ Enterprise State + Provenance
→ Verified Learning

The durable conceptual law is:

- Enterprise Model = nouns.
- Capabilities = verbs.
- Providers = actors that perform verbs.

Provider schemas never define Pandora business semantics.

## 2. Universal Enterprise Core

Pandora uses a Universal Core plus Industry Packs and typed custom extensions.

The Universal Core is not one generic object payload table. It uses:

1. a thin enterprise entity identity spine for stable Pandora identity, organization scope, entity kind, schema version, and lifecycle;
2. explicitly typed tables for business state;
3. typed relationships;
4. source bindings and field-level provenance outside the business payload.

No generic EAV or arbitrary business-data JSONB payload belongs in the entity spine.

Phase 1A establishes the identity/provenance framework and the first typed entity, Person. Other Core nouns are added as typed additive slices under the same contract.

Current Core vocabulary includes Person, Organization, Location, Money Account, Transaction, Product / Service, Inventory Item, Asset, Contract, Document, Task / Work Item, Event, Device, Identity Reference, Policy, and Relationship.

`public.organizations` remains Pandora's tenant/business organization root. It must not be duplicated.

## 3. Industry Packs

Industry concepts extend, never redefine, the Core.

Examples:

- Hospitality: Guest, Reservation, Stay, Room, Rate, Folio, Housekeeping Job.
- Restaurant: Table, Menu Item, Recipe, Order, Check, Kitchen Ticket, Shift.
- Law: Matter, Client Intake, Hearing, Filing, Evidence Item, Deadline.
- Import / Export: Shipment, Container, Purchase Order, Incoterm, Customs Entry, Bill of Lading.
- Retail: SKU, Store, Sale, Return, Promotion, Stock Position.
- Custom: namespaced typed extensions that cannot mutate Core semantics.

A provider-specific type such as `LalamoveShipment`, `AWSCustomer`, or `PLDTUser` is never a Universal Core entity.

## 4. Compatibility / Anti-Corruption Layer

Businesses keep existing systems unless replacement has a business reason.

Coexistence modes:

1. OBSERVE — Pandora reads; the incumbent system runs.
2. SYNCHRONIZE — controlled data exchange with explicit authority.
3. COORDINATE — Pandora is the operating interface while specialist systems remain underneath.
4. REPLACE — an incumbent component is retired only when justified.

Integration preference:

native connector
→ industry/open standard
→ REST / GraphQL / supported SDK
→ legacy API such as SOAP/XML
→ webhook / events / CDC
→ supported database access
→ CSV / Excel / XML / JSON / EDI / SFTP
→ Pandora Local Bridge
→ controlled UI automation
→ human-assisted workflow

Unsupported direct writes to third-party application databases are prohibited by default.

The Compatibility Layer translates protocols, schemas, identities, fields, events, and conflicts. It does not own business strategy, approval, provider routing, or enterprise reasoning.

## 5. Source binding, provenance, and authority

External systems participate through explicit bindings:

enterprise integration connection
→ external source record
→ entity binding
→ typed Pandora entity

A source record retains external identity, source schema version, observation time, content hash where applicable, and safe redacted metadata.

Field provenance answers: Where did Pandora's belief about this field come from?

Source authority answers: Which source is permitted to determine this fact?

These are separate contracts.

Authority vocabulary is independent from provider-routing vocabulary. Source authority may be `source_of_record`, `pandora_derived`, `advisory`, or `fallback_source`. Provider selection remains AUTO, PREFERRED, or REQUIRED.

A newer value does not automatically override an authoritative value.

## 6. Identity resolution

Identity resolution is evidence-backed.

Names alone, AI similarity alone, or embeddings alone are insufficient to merge identities.

The flow is:

source records
→ keyed-HMAC/verified identity signals
→ resolution decision
→ canonical Pandora entity
→ confirmed source bindings

Raw identity evidence is not duplicated into resolution ledgers. Bounded evidence references and keyed-HMAC fingerprints are used for low-entropy identifiers.

False merges must remain reversible without deleting source history.

## 7. Capability families

Pandora maintains a bounded vendor-neutral capability vocabulary.

1. Compute & Data
2. Connectivity & Communications
3. Money & Commerce
4. Customers & Growth
5. Physical Operations
6. Trust, Identity & Government

Examples include `ai.infer`, `storage.put`, `message.send`, `payment.collect`, `campaign.launch`, `delivery.dispatch`, `identity.verify`, and `permit.submit`.

A new provider should implement an existing capability when semantics match; a new provider does not justify a new top-level interface family.

## 8. Provider selection and approval

Provider eligibility is evaluated before selection.

Eligibility may include contract, jurisdiction, consent, data residency, permissions, provider health, availability, account state, coverage, SLA, and capability version.

Selection modes:

- AUTO — choose among eligible providers.
- PREFERRED — attempt an approved preference with policy-bounded fallback.
- REQUIRED — exact provider; fail closed unless explicit fallback policy exists.

Provider selection is not authorization. Pandora may automatically select a provider while still requiring human approval for the action.

## 9. Standard execution lifecycle

Intent
→ Context
→ Plan
→ Policy / Eligibility
→ Capability Resolution
→ Provider Eligibility
→ Provider Selection
→ Approval when required
→ Execution
→ Provider Acknowledgement
→ Verification
→ Reconciliation
→ Enterprise State Update
→ Verified Learning

Execution is a claim; verification is evidence.

HTTP 200, HTTP 202, queued, accepted, or job-created states never equal completed business outcome without the appropriate evidence.

Material external writes require safe duplicate behavior and idempotency or equivalent fencing.

## 10. Reuse before rebuild

The Universal architecture converges the strongest existing Pandora mechanisms. It does not create competing runtimes.

Reuse/generalize where compatible:

- Pandora capability registry;
- provider-neutral AI contracts and model router;
- Tool Gateway policy / approval / execution boundary;
- native execution ledgers and idempotency patterns;
- `packages/pandora-verification`;
- external-success reconciliation;
- tax source/provenance/evidence patterns;
- enterprise hospitality projections;
- verified-learning outboxes.

A new ledger, router, policy engine, or registry requires evidence that the incumbent cannot satisfy the contract.

## 11. Existing enterprise_source_connections collision

`public.enterprise_source_connections` already exists as a hospitality/property-oriented projection. It is retained as historical/current domain infrastructure.

The universal Phase 1A source-connection contract therefore uses `public.enterprise_integration_connections`. No destructive rename or silent semantic reuse occurs in the foundation migration.

A later verified migration may bridge or converge the hospitality projection after compatibility analysis.

## 12. ProjectOS retirement

ProjectOS is permanently retired as an active planning, governance, authorization, execution, verification, or architectural model.

Historical ProjectOS-named migrations, tables, functions, tests, and records may remain as provenance or compatibility evidence. They do not confer current architectural authority and must not be used to reintroduce ProjectOS into new design.

New work uses Pandora Enterprise, Capability, Policy, Execution, Evidence, and Verification terminology.

## 13. Completion standard

Implementation is complete only when source, tests, provider/database readback, exact SHA, and acceptance evidence agree.

Spreadsheet status, documentation, an unmerged PR, or an API acceptance response alone is never completion proof.
