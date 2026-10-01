# Pandora Enterprise Architecture Glossary V1

Status: Canonical vocabulary for Universal Enterprise Architecture V1.

| Term | Canonical meaning |
| --- | --- |
| Enterprise Model | Pandora's provider-neutral representation of the business. |
| Universal Core | Shared typed enterprise nouns used across industries. |
| Entity spine | Thin identity/lifecycle record linking typed enterprise tables. Not a generic payload store. |
| Typed entity | Business state stored in a schema dedicated to that noun, such as `enterprise_people`. |
| Industry Pack | Domain-specific entities and workflows extending the Universal Core. |
| Capability | A versioned vendor-neutral verb Pandora may request. |
| Provider | External actor/system that implements a capability. |
| Provider Adapter | Translation between a Pandora capability request and one provider's interface. |
| Compatibility Layer | Anti-corruption boundary translating legacy/current systems into Pandora contracts. |
| Integration connection | Governed connection to one external business system. |
| Source record | Immutable observation of an external object/version with provenance. |
| Entity binding | Mapping from an external source record to a canonical Pandora entity. |
| Identity signal | Keyed-HMAC evidence usable for entity resolution without duplicating raw identifiers. |
| Provenance | Evidence describing origin, observation, verification, and lineage of a fact. |
| Source authority | Policy defining which source may determine an object/field fact. |
| source_of_record | Authority mode where an external source is authoritative for the fact. |
| pandora_derived | Authority mode where Pandora computes the fact from governed inputs. |
| advisory | Source contributes evidence but is not authoritative. |
| fallback_source | Secondary authority used only under explicit policy. |
| AUTO | Provider-routing mode choosing among eligible providers. |
| PREFERRED | Provider-routing mode preferring one provider with approved fallback. |
| REQUIRED | Provider-routing mode requiring one provider unless explicit fallback exists. |
| Approval | Authorization to execute an action. Separate from provider selection. |
| Evidence | Receipt, callback, readback, hash, artifact, or other proof supporting a claim. |
| Verification | Process of proving the actual external/business outcome. |
| Reconciliation | Applying verified results to enterprise state under authority/conflict rules. |
| Observe | Read-only coexistence mode. |
| Synchronize | Controlled data exchange coexistence mode. |
| Coordinate | Pandora orchestrates while specialist systems continue underneath. |
| Replace | Optional retirement of an incumbent component after verified migration. |
| Verified Learning | Durable learning promoted only from evidence-backed outcomes. |
| ProjectOS | Retired historical terminology. It is not an active Pandora architecture or execution authority. |
