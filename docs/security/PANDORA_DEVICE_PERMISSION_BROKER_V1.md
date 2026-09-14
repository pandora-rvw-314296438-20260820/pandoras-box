# Pandora Device Permission Broker v1

Status: policy contract implemented; Android runtime binding and physical acceptance pending.

Task: M7-006 — least-privilege runtime permissions and clear revocation controls.

## Core rule

Pandora never treats a cached grant, model output, client payload, Memory pattern, prior success, or standing policy as proof that Android permission is currently available.

The permission broker must re-read trusted Android runtime state before a permission-backed capability is used. Missing, stale, unknown, revoked, or untrusted authority fails closed.

## Authority modes

- public_app — no additional Android runtime permission is required.
- runtime_permission — the permission must already be declared in the manifest and the current Android grant must be freshly verified.
- android_role — Android must report the role as available and currently held. Role changes remain user-controlled.
- device_owner — Android must report actual Device Owner provisioning. Policy cannot pretend that provisioning occurred.
- development_only — unavailable to normal Pandora operation.
- policy_denied — permanently denied by Pandora policy.

Implementation availability and Pandora policy authorization are separate gates. Passing one never implies the other.

## Runtime permission behavior

Pandora does not broaden the manifest merely to make a capability easier to build. A runtime permission that is not declared is denied rather than silently added or requested.

When a declared permission is not currently granted, the capability becomes a real Needs You boundary. Pandora may open an Android permission prompt only from a visible current user request and only when Android reports that prompting is available. Background permission prompts are forbidden.

If Android cannot present a normal permission prompt, Pandora may direct the user to the app-details surface. Pandora must not silently re-grant a revoked permission, loop permission prompts, or auto-retry the protected capability after denial.

Revocation takes effect on the next capability evaluation because the current Android state is re-read before use. The app-details surface is the canonical revocation/recovery control for runtime permissions.

## Roles and Device Owner

Android roles are user-controlled boundaries. Pandora may explain why a role is needed and route to the supported role/settings surface, but it cannot silently acquire or retain a role after Android reports it absent.

Device Owner is stronger authority and is never inferred. If the installation is not actually provisioned as Device Owner, the broker denies Device Owner capabilities.

## Needs You semantics

Needs You appears only when a real user action can satisfy the Android authority boundary. Permanent policy denial, unsupported authority, stale state, undeclared permissions, or unavailable implementation are denials, not fake approval prompts.

Every Needs You projection explains why the capability needs user action, identifies the Android surface to use, and forbids automatic retry. After the user acts, Pandora must re-read current Android state before retrying.

## Parallel implementation boundary

This increment deliberately avoids MainActivity.kt, connectivity runtime files, Device Agent resource-runtime files, capability-registry files, and intelligence Edge/API files owned by active parallel workers.

The Android bootstrap and local permission-request plumbing must be reconciled after the active MainActity.kt owner releases that file. This policy contract does not claim Android runtime wiring or physical Redmi acceptance.

## Physical acceptance

M7-006 is not Done until an exact-source Redmi run proves at least: grant, deny, deny-without-repeat-loop, reny, deny-without-repeat-loop, revocation from app settings, re-read after revocation, capability fail-closed behavior, clear Needs You copy, and recovery after an explicit user grant.

CI cannot substitute for that physical evidence.
