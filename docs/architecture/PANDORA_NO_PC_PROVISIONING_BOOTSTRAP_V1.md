# Pandora No-PC Provisioning Bootstrap v1

Status: M8-002 implementation candidate. Source/CI acceptance is separate from physical-device acceptance.

## Goal

Pandora must reach normal operating readiness from the Android device plus Pandora/cloud infrastructure. A Windows/macOS/Linux machine, Android Studio, permanent ADB/Wireless Debugging connection, root, bootloader unlock, custom ROM, or inferred Device Owner authority is not part of normal operation.

The bootstrap contract is intentionally a bounded readiness surface. It does not install packages, execute shell commands, grant Android roles, grant runtime permissions, alter protected applications, or perform destructive provisioning.

## Normal enrollment path

1. `app_installation` — the Pandora APK is installed through an authorized installer or release channel.
2. `in_app_authentication` — the user establishes a session-scoped Pandora identity inside the app.
3. `android_roles_and_permissions` — capabilities request Android roles/permissions only when that capability is actually invoked.
4. `oem_background_reliability` — OEM battery/autostart controls remain optional user-managed reliability work, never a hidden authority shortcut.

The Device Agent reports actual readiness and actual Device Owner/HOME state. It never converts desired future authority into current authority.
## Recovery-only paths

The bootstrap may advertise bounded recovery surfaces:

- Android Settings
- Pandora app details
- battery-optimization settings
- `adb_development_bridge` for development/recovery only

Every recovery path declares `normalOperationDependency=false`. ADB must remain `development_only`; losing ADB must not make an otherwise healthy Pandora installation unusable.

## Security invariants

- `normalOperationRequiresDesktop=false`
- `adbRequiredForNormalOperation=false`
- `rootRequired=false`
- `bootloaderUnlockRequired=false`
- `deviceOwnerRequiredForNormalOperation=false`
- protected-app reauthentication remains required
- protected-app private data and credentials remain denied
- bootstrap evidence carries no password, token, OTP, secret, private key, or service-role key
- no arbitrary shell, executable, package-operation, or opaque command payload is exposed

Factory reset, Device Owner reprovisioning, bootloader changes, authenticator migration, password export, financial-app recovery, and other consequential recovery remain outside this bounded bootstrap and retain their existing authorization/recovery gates.
## Source and CI test plan

M8-002 source acceptance requires all of the following:

1. Parser accepts the canonical on-device/self-service bootstrap.
2. Parser rejects desktop, ADB, root, bootloader-unlock, or Device Owner normal-operation dependencies.
3. Parser rejects protected-app boundary weakening and credential/secret transport.
4. Parser requires every enrollment step and rejects duplicate step identity.
5. ADB exists only as a non-dependent `development_only` recovery path.
6. Android Device Agent exposes only `getProvisioningBootstrap`; no provisioning shell/command executor is introduced.
7. Canonical Dart format, `flutter analyze`, focused Flutter tests, complete Flutter suite, and complete mobile Python tool suite pass.
8. Disposable Android materialization compiles the Kotlin/Flutter candidate successfully.
9. Exact-head CI passes Android/iOS mobile gates plus security/release/Windows checks before merge.
10. Provider main is read back after merge.

## Physical-device test plan

Physical acceptance is separate. On the exact intended APK, verify normal Pandora startup/authentication without a PC attached; reboot and repeat; disconnect/disable development debugging and confirm normal operation remains available; exercise required Android role/permission user flows; verify OEM battery/autostart recovery surfaces; and recheck protected apps, telephony, Wi-Fi/mobile data, emergency/system fallbacks, source/version/package/signing identity, and rollback evidence where applicable.

CI or emulator success must never be recorded as physical Redmi acceptance. M8-005 owns the signed update/rollback channel; M8-002 does not claim that downstream milestone.