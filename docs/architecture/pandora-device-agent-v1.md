# Pandora Device Agent v1 — M4-001 foundation

Status: implementation candidate for **M4-001**.

## Purpose

Pandora Device Agent is the reusable Android capability boundary between Pandora AI and the phone. It describes what the current installation can do, which authority each capability requires, and whether that authority is actually available. It is deliberately **OEM-neutral**; Xiaomi/HyperOS behavior belongs behind the later M4-008 OEM adapter.

Normal Pandora operation must work from the phone plus Pandora/cloud infrastructure. A Windows/macOS/Linux machine, Android Studio, permanent ADB connection, root, bootloader unlock, or custom ROM is not part of the normal trust or availability model.

## Channel

Flutter talks to Android over `pandora/device_agent`.

M4-001 exposes only:

- `getCapabilityManifest`
- `getPermissionStates`
- `runSafeDiagnostic`

`runSafeDiagnostic` accepts only the explicit kinds `capability_manifest` and `permission_state`. It does not accept a shell command, executable, path, script, package operation, or opaque provider payload.

## Capability model

Every capability declares:

- stable capability `id`
- `authority`: `public_app`, `runtime_permission`, `android_role`, `device_owner`, `development_only`, or `policy_denied`
- `availability`: `available`, `unsupported`, `permission_required`, `implementation_pending`, or `forbidden`
- human-readable `reason`
- whether normal Pandora operation depends on it

The manifest also records the actual Android SDK level and actual `DevicePolicyManager.isDeviceOwnerApp(...)` result. Device Owner is never inferred from Developer Options, ADB, ownership of the hardware, or a desired future architecture.

## Security invariants

M4-001 does not:

- root the phone or unlock the bootloader;
- require a desktop or permanent ADB/Wireless Debugging connection;
- expose arbitrary shell/command execution;
- add camera, microphone, contacts, SMS, call, location, Bluetooth, broad-storage, overlay, package-install, or package-query permissions;
- claim Device Owner if Android does not report it;
- read app-private data from GCash, banks, e-wallets, authenticators, password managers, or other protected apps;
- move OTPs, credentials, provider secrets, or protected-app data into Pandora Memory, logs, model prompts, diagnostics, or Activity Theatre.

The current validation APK continues to use the existing least-privilege manifest gate. Later tasks may add capabilities only through their own Android role/permission/security acceptance work.

## Deferred implementation ownership

M4-001 establishes the abstraction and truthful capability surface. It intentionally leaves these implementations to their assigned tasks:

- M4-002: HOME/launcher
- M4-003: calls and SMS
- M4-005: camera, microphone, screenshots, permitted sensors
- M4-006: scoped files/media
- M4-007: connectivity
- M4-008: Xiaomi/HyperOS adapter
- M4-009: live CPU/RAM/storage/battery/thermal/process/network introspection and safe benchmarks
- M7-006: least-privilege runtime permission broker and revocation controls

A later implementation may change a capability from `implementation_pending` or `unsupported` only when the corresponding authority and physical/device acceptance evidence exist.

## Acceptance for M4-001

Source acceptance requires:

1. OEM-neutral manifest parser and Android adapter.
2. No desktop/root/bootloader requirement.
3. Actual Device Owner state readback.
4. Protected-app and arbitrary-shell capabilities fail closed.
5. No new sensitive Android permission in the validation APK.
6. Unit/source-contract tests plus exact-source Android/iOS CI.
7. Provider readback after merge.

Physical Redmi behavior is not proven by this contract alone and remains a downstream acceptance requirement.
