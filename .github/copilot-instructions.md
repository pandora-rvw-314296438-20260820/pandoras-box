# Pandora Copilot repository instructions

These instructions apply to GitHub Copilot coding-agent and code-review work in this repository.

## Repository and authority

- Canonical repository: `pandora-rvw-314296438-20260820/pandoras-box`.
- Never mutate `main` directly. Work on a bounded task branch and pull request.
- Do not use, revive, or integrate retired ProjectOS paths or `banataosystems/Pandoras-box`.
- Before editing any file, inspect current `main`, open pull requests, and changed-file sets. Do not create overlapping implementation against an active owner of the same coupled files or subsystem.

## Secrets, providers, and production

- Never expose, print, commit, echo, or place secrets, PATs, API keys, signing material, provider credentials, service-role material, or database passwords in source, logs, comments, artifacts, screenshots, or PR text.
- Use existing Supabase Vault/OIDC/provider-native secret paths. Never replace them with plaintext credentials.
- Do not change paid model activation, billing, provider entitlements, production credentials, tenant membership, routing policy, production domains, or production promotion unless explicitly in scope and authorized.
- Do not infer provider/runtime truth from source code alone. Use provider readback and existing verification gates where applicable.

## Pandora product invariants

- Pandora is one coherent Core system, not a collection of stitched-together modules.
- Preserve the global active-chat shell and persistent composer across navigation, Settings, Back, history, and client/workspace scope changes unless an explicit owner decision supersedes it.
- Customer-facing surfaces must not expose raw debug language, implementation caveats, internal IDs, provider plumbing, engineering-only state, or placeholder evidence unless the surface is explicitly advanced diagnostics.
- Preserve one coherent design system: dark-theme invariance, legible typography, safe areas, contained overlays, consistent spacing, readable contrast, and comfortable mobile touch targets.
- Fix root causes and shared primitives before screen-by-screen patches when a defect is systemic.

## State and truth semantics

Keep these stages distinct:

`Documented -> Implemented -> Tested -> Built -> Deployed -> Runtime Verified -> Production Verified`

- A successful build is not runtime verification.
- A provider deployment marked READY is not production verification.
- Never show a reassuring READY, VERIFIED, or equivalent operator state when runtime or user-flow verification is absent.
- Unknown is not PASS.
- Stale evidence must not be presented as current-head proof.

## Loading, errors, empty states, and perceived performance

- Prefer canonical shared state primitives over page-specific spinners, error cards, or ad hoc skeletons.
- Preserve already-loaded usable state while refreshing when safe.
- Avoid indefinite loading. Every asynchronous surface needs bounded loading, meaningful degraded/error behavior, and retry/recovery semantics.
- Do not blank an entire page unnecessarily during refetch.
- Preserve navigation state and avoid redundant refetches when cached data is still valid.
- Prefer partial usable results over all-or-nothing failure when independent reads can succeed separately.

## Mobile interaction requirements

- Overlays and pickers require a contained surface, backdrop/z-order, clipping, safe-area behavior, keyboard behavior, and deterministic dismissal.
- Never allow overlay content to render uncontained over conversation text.
- Preserve composer stability across keyboard, drawer, model picker, Back, navigation, and lifecycle changes.
- Do not introduce desktop-density controls into phone surfaces.
- Do not hide failures by swallowing exceptions without a user-safe state and regression coverage.

## Change discipline

- Keep tasks bounded. Do not opportunistically redesign unrelated areas.
- Prefer the smallest coherent file set that fixes the root cause.
- Preserve working routing, tenant boundaries, authorization, RLS/RPC contracts, and provider-diverse inference unless explicitly in scope.
- Do not rewrite already-applied migrations. Use additive forward corrective migrations and preserve provider history.
- Do not recreate deleted or superseded architecture from stale comments or historical branches.

## Testing and evidence

For every implementation task:

1. State the exact defect or contract being fixed.
2. Add or update targeted regression coverage that would fail before the change.
3. Run the smallest relevant tests first, then required repository gates.
4. Record the exact head SHA used for evidence.
5. Treat compile/analyze/test success as only the stage it actually proves.
6. If runtime/device/provider verification is required but unavailable, leave the task at the correct verification stage.

For UI/mobile changes, verify continuous user journeys, not only static screenshots. Include relevant transitions such as navigation, Back, keyboard, drawers, overlays, loading, errors, stale-state cleanup, and composer persistence.

## Pull-request quality

PR descriptions should include:

- why the change is needed;
- exact bounded scope;
- files/subsystems changed;
- tests and exact results;
- source/head SHA;
- migration/security/provider impact;
- what is explicitly not verified;
- rollback/recovery notes when relevant.

Do not call a task production-ready unless production evidence supports the claim.

## Review behavior

When reviewing an existing PR:

- Review the exact current head, not an earlier green SHA.
- Look for regressions in state ownership, async lifecycle, navigation persistence, safe areas, overlay containment, theme consistency, status semantics, accessibility, tenant boundaries, authorization, and provider/runtime claims.
- Explicitly inspect loading/error/empty/degraded states and cached-state behavior.
- Flag contradictory status semantics such as provider READY beside unverified runtime/user flows.
- Distinguish correctness/release blockers from polish.
- Prefer specific actionable findings tied to code or an observable user flow.
- Do not approve solely because CI is green.
