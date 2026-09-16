# Pandora Signed Device Update Channel v1

Status: M8-005 source contract implemented; production-signing and physical rollout/rollback acceptance remain separate evidence gates.

## Purpose

Pandora verifies Android update and recovery artifacts before they can enter a trusted distribution route. The v1 contract is source-bound, package-bound, signer-bound, version-bound, app-private while staged, and fail-closed.

This contract does **not** add an arbitrary installer, unknown-source privilege, root requirement, bootloader dependency, or ADB dependency. Normal Pandora operation remains independent of a desktop computer.

## Trust roots

The installed Pandora APK is the local identity anchor. Its Android signing certificate supplies the public key used to verify the release manifest and the certificate fingerprint that candidate and recovery APKs must match exactly.

The signed release manifest binds:

- Pandora package ID;
- release channel (`stable` or `enterprise`);
- issuance and bounded expiry;
- explicit production-release intent;
- candidate APK SHA-256, source SHA, source tree, version code/name, and signer SHA-256;
- recovery APK SHA-256, source SHA, source tree, version code/name, signer SHA-256, and rollback-target source SHA.

Signer rotation is deliberately unsupported in v1. A different signing certificate fails closed rather than being inferred as valid.## Source identity

The mobile build embeds `PANDORA_SOURCE_REVISION` in the Flutter artifact. The verifier proves the candidate and recovery APKs contain the source SHA declared by the signed manifest.

The source tree is currently emitted by the exact-source CI artifact manifest rather than embedded inside the APK. Therefore v1 treats `sourceTree` as a signed-manifest assertion whose authority comes from the verified release signature and CI evidence. It must never be described as APK-internal proof.

## Staging boundary

Candidate and recovery APK paths are accepted only beneath Pandora's private `filesDir/pandora-updates` or `cacheDir/pandora-updates` directories. Canonical paths are checked before any artifact inspection. Regular `.apk` files only are accepted, with a bounded maximum size.

The channel verifies each staged artifact's SHA-256, package ID, version code/name, signing certificate fingerprint, and embedded source revision. Any mismatch rejects the bundle without exposing private verifier details to the Flutter caller.

## Install authority

`REQUEST_INSTALL_PACKAGES` remains forbidden by the existing mobile exact-source gate. M8-005 does not create an unknown-sources installation path or expose `PackageInstaller`, `ACTION_INSTALL_PACKAGE`, shell execution, or arbitrary intents.

When Android reports actual Device Owner authority, the policy identifies the distribution route as `managed_device_owner_distribution`. Otherwise the route is `trusted_store_or_user_installer`, with user confirmation required. The source contract does not infer Device Owner authority.

Debuggable Pandora builds cannot claim production update readiness and cannot verify a production update bundle.## Recovery and rollback

Android normally rejects an application downgrade by version code. Pandora therefore does not define rollback as installing an older APK.

Every release bundle must include a separately signed recovery APK. The recovery artifact must have a version code greater than the candidate while containing the last-known-good code selected for recovery. Its `rollbackTargetSourceSha` must match the source revision actually installed before the update attempt.

This produces the sequence `installed < candidate < recovery` by version code while allowing the recovery binary to restore the previous known-good implementation. Candidate and recovery must both match the currently installed Pandora signing certificate.

A recovery manifest or verified recovery APK is evidence of recoverability; it is not permission to install. Distribution/install authority remains with Android, the trusted store/managed-device channel, and the applicable user or Device Owner boundary.

## Release pipeline gates

Before a production rollout can be called ready, the applicable release pipeline must record the exact repository SHA/tree, Android package, monotonically increasing version codes, candidate/recovery APK hashes, signer certificate fingerprint, signed manifest bytes/signature, exact-source CI result, and independent readback of the published release artifacts.

The existing exact-source Android gate must continue to reject unexpected sensitive permissions, including `REQUEST_INSTALL_PACKAGES`. Private signing keys must never enter source, app storage, CI logs, Activity Theatre, or Pandora Memory evidence.## Physical acceptance plan

Source, emulator, and CI success do not prove a real Android update or rollback. Physical acceptance must use production-signed artifacts on an intended Pandora device and must capture pre-update installed package/version/source/signer identity immediately before installation.

Acceptance then verifies candidate installation through the authorized distribution route, first launch and owner authentication, retained required app state, protected-app boundaries, telephony/system recovery, Wi-Fi/mobile-data operation, reboot persistence, and post-install package/version/source/signer readback.

Rollback acceptance deliberately injects or observes an update failure or owner-approved recovery condition, installs the higher-version signed recovery artifact through the same authorized route, and re-verifies the last-known-good behavior and exact recovery identity. Evidence must preserve the failed attempt, recovery action, and final readback.

If the installed baseline changes between preflight and installation, Pandora must stop and re-baseline. If update or recovery result is ambiguous, Pandora assumes it may have happened once and reads provider/device state before any retry.

## Current non-claims

The source contract and debug compile can prove verifier behavior and Android API compatibility. They do not prove possession of a production signing key, production release signing, trusted-store or Device Owner distribution, physical Redmi installation, physical rollback, data migration, network journeys, or no-brick recovery on hardware.

Those gates remain false until evidenced independently. A debug APK is a validation candidate only and must never be promoted as the production signed-update proof.