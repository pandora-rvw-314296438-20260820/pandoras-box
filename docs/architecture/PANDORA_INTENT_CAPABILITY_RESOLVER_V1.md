# Pandora Universal Intent & Capability Resolver v1

Status: **Frozen M1-002 contract candidate**  
Owner: **M1 Universal Chat Runtime**  
Machine schema: `docs/architecture/pandora-intent-capability-resolution-v1.schema.json`  
Runtime module: `packages/pandora-intelligence/src/resolution/intent-capability-resolver.js`

## Purpose

This contract keeps Pandora Chat universal. It converts an owner request into provider-neutral execution constraints before model/provider selection or tool execution. Software building is one capability family, never Pandora's default interpretation.

The resolver answers **what outcome/capabilities/effect boundary are required**. It does **not** choose a model/provider, grant authority, execute a tool, fabricate progress, or create a Project.

## M1 -> M3 handoff

M1 owns:

- `intent`
- `requestedOutcome`
- `requiredCapabilities`
- `actionMode` (`no_action`, `read_only`, `state_change`)
- risk/consequence signals and the authority requirement
- privacy/execution-boundary constraints
- local/cloud/device execution characteristics
- project/context binding only when relevant
- confidence and ambiguity behavior
- tool/effect constraints
- bounded routing evidence
- model capability requirements and allowed execution boundaries

M3 owns:

- provider/model eligibility
- quality/reliability/cost/latency policy
- health/circuit state
- session compatibility
- provider/model preference
- fallback ordering
- actual provider/model selection

Accordingly, M1 always emits `providerPreference: null`, `modelPreference: null`, and `modelSelectionOwner: "M3"`.

## Universal intent domains

The v1 domain set is deliberately horizontal:

- `communication`
- `research`
- `coding_building`
- `files`
- `device_operations`
- `business`
- `travel`
- `scheduling`
- `future_capability`
- `general_assistance`

Future domains are additive through a versioned contract. They must not silently repurpose an existing domain.

## Builder-default invariant

Generic verbs such as **build**, **create**, **make**, **fix**, **change**, or **update** are not software evidence by themselves.

Examples:

- `Create a workout plan` -> not software
- `Build a better morning routine` -> not software
- `Create a marketing strategy` -> business/general assistance, not software
- `Build a booking system for my restaurant` -> software
- `Fix checkout in this app` -> software

A selected Project is context, not intent. An unrelated communication, travel, research, business, file, or device request must remain unrelated even while a Project is selected.

## Project binding

The resolver may bind a selected Project only when the resolved domain is `coding_building` and the request itself makes software/project context relevant, such as a state-changing software instruction or explicit project/repository reference.

The resolver must never create a Project as a prerequisite. Existing repositories/providers/systems may be addressed by later capability routing without inventing project state.

## Planning versus execution

Planning artifacts do not authorize execution merely because they contain action words.

Examples:

- `Create an implementation roadmap to deploy this website` -> planning/read-only/no-action boundary
- `Explain how to fix the checkout bug` -> planning/read-only/no-action boundary
- `Build it according to the approved plan` -> state-changing software instruction when project context is actually relevant

This is aligned with the existing selected-project speech-act protection in Universal Chat v9.

## Authority boundary

M1 identifies effect class and consequence signals; it never grants permission.

`riskAuthority.authorityDecisionOwner` is always `pandora-standing-authority-policy-v1`, and `resolverGrantsAuthority` is always false.

State-changing requests require downstream evaluation against explicit-current or matching standing authority. Consequential signals include production/public release, external communication/commitment, money movement/purchase, destructive/irreversible action, and account/security changes.

Prediction, Memory patterns, model proposals, provider capability, and prior success never create authority.

## Privacy and execution placement

The M1 resolver can narrow allowed model execution boundaries to the M3 vocabulary:

- `device`
- `pandora_trusted_cloud`
- `external_provider`

Device operations prefer device execution and require device presence for side effects. File work prefers device-first execution. Explicit private/confidential/local-only signals conservatively exclude external-provider model execution.

These fields describe Pandora routing constraints only. They are not claims about provider retention, residency, training, or compliance.

## Tool constraints

Every resolution carries invariants:

- never auto-create a Project
- never expose credentials
- provider-neutral capability requirements
- state changes require the governed mutation boundary
- state changes require post-action readback
- retries of state changes reuse idempotency identity
- fallback may not expand the resolved effect/privacy/authority scope

## Routing evidence

Routing evidence is bounded and provider-neutral. It may contain matched signal labels and scored candidate domains. It must not contain credentials, raw provider internals, provider/model selection, or invented runtime status.

## Acceptance corpus

Executable tests cover communication, research, coding/building, files, device operations, business, travel, scheduling, future capabilities, general assistance, selected-project irrelevance, selected-project build/change binding, planning-versus-action speech acts, privacy narrowing, authority non-granting, and M1/M3 ownership separation.

Physical Android behavior remains a separate acceptance gate. This contract does not claim an APK/device PASS.
