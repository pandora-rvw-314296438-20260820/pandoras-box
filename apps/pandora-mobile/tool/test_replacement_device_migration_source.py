from pathlib import Path

MOBILE = Path(__file__).resolve().parents[1]
REPO = Path(__file__).resolve().parents[3]
DART = MOBILE / "lib" / "core" / "device" / "pandora_replacement_device_migration.dart"
DOC = REPO / "docs" / "architecture" / "PANDORA_REPLACEMENT_DEVICE_MIGRATION_V1.md"
PUBSPEC = MOBILE / "pubspec.yaml"

source = DART.read_text(encoding="utf-8")
doc = DOC.read_text(encoding="utf-8")
pubspec = PUBSPEC.read_text(encoding="utf-8")

required_source = [
    "pandora-replacement-device-migration-v1",
    "computePayloadSha256",
    "requiresUserReauthentication",
    "protectedAppReauthenticationRequired",
    "discardDeviceLocalRecoveryHints",
    "requiresRevalidation",
    "refreshCompatibilityProfile",
    "refreshOemAdapter",
    "restoreMeasuredHardwareFacts",
    "restoreAndroidRoles",
    "restoreRuntimePermissions",
]
for needle in required_source:
    assert needle in source, f"missing M8-004 source invariant: {needle}"

for forbidden in [
    "signInWithPassword(",
    "SharedPreferences.getInstance",
    "MethodChannel(",
    "deviceOwnerProvisioned = true",
    "bootloaderUnlock",
    "rootRequired = true",
]:
    assert forbidden not in source, f"migration contract gained forbidden authority: {forbidden}"

required_doc = [
    "never transfers protected-app private data",
    "current owner-test Supabase session is memory-only and is intentionally not migrated",
    "pending project-creation idempotency state and build-stream cursors are not authoritative portable state",
    "Import never activates a policy",
    "Measured hardware facts, OEM facts, Android roles, runtime permissions, Device Owner state",
    "Physical acceptance remains separate",
]
for needle in required_doc:
    assert needle in doc, f"missing M8-004 documentation boundary: {needle}"

assert "  crypto: 3.0.7" in pubspec, "crypto must be an explicit mobile dependency"
print("M8-004 replacement-device migration source contract: PASS")
