# Pandora Operational Workspace V1

Status: implemented on the owner API and Pandora mobile project detail surface.

## Purpose

This capability generalizes the useful operational patterns recovered from the PLP source snapshot without importing PLP-specific resort logic into the Pandora control plane.

The workspace gives one project a single operational view across:

- canonical provider/resource mappings
- runtime project identities
- domains and verification state
- staged external imports
- conflicts between provider truth and Pandora's canonical record
- owner resolutions with preserved history

## Trust boundaries

Pandora Verification remains the release authority. The Operational Workspace never creates verification PASS state.

Existing ProjectOS governance remains the mutation authority. Import preview and conflict resolution do not directly mutate GitHub, Vercel, Supabase, or another external provider.

The staged import pipeline is:

DISCOVER -> NORMALIZE -> VALIDATE -> DIFF -> CONFLICT CHECK -> DRY RUN -> REVIEW -> GOVERNED EXECUTION -> VERIFY

Only the first seven stages are represented by Operational Workspace evidence. Provider mutation must continue through the governed execution path.

## Persistence

No competing operational schema is introduced.

- Canonical mappings remain in `projectos_project_resources`.
- Import previews and conflicts are stored as redacted `projectos_evidence`.
- Owner conflict resolutions are stored as `projectos_decisions`.
- Resolved conflict evidence is invalidated, not deleted.

This preserves the existing audit/provenance model.

## Import safety

External import attributes are never persisted in plaintext by this layer. The preview stores only an attribute count and deterministic SHA-256 digest.

Imports are deterministic and idempotent by a canonical fingerprint bound to:

- project
- source provider
- normalized object identity
- redacted attribute digests

An exact existing mapping becomes a no-op. A replacement without an exact target fails closed as a conflict.

## Object 360

The owner API embeds `operations` in project detail and exposes a dedicated project operations route.

Pandora mobile renders a System Map inside Project Detail with:

- mapping totals and verification state
- conflict severity and recommended next action
- connected-resource identities
- staged-import summaries

High-severity unresolved operational conflicts contribute to the owner-facing Needs You count.

## Resolution

Stored staged-import conflicts can be resolved only by an owner/admin session at AAL2. Resolution choices are:

- keep canonical
- use provider truth
- remap
- ignore

The decision is recorded first. Any choice requiring an external or protected control-plane mutation remains plan-first and must be executed through ProjectOS.

## PLP relationship

The PLP application remains a customer system. Resort-specific OTA, room, reservation, housekeeping, guest, and payment logic does not become control-plane logic.

Pandora adopts only the reusable operational patterns: mapping, conflict detection, staged import, dry-run review, and Object 360.
