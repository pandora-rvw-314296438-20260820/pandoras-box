#!/usr/bin/env python3
"""M8-001 source-boundary tests for the portable device compatibility profile."""

from __future__ import annotations

import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_KOTLIN = (
    _ROOT
    / "platform"
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "banataosystems"
    / "pandora_mobile"
    / "PandoraDeviceCompatibilityProfile.kt"
)
_CHANNEL = _KOTLIN.with_name("PandoraDeviceAgentChannel.kt")
_DART = _ROOT / "lib" / "core" / "device" / "pandora_device_compatibility_profile.dart"


class DeviceCompatibilityProfileContractTest(unittest.TestCase):
    def test_profile_declares_required_portable_dimensions(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        for required in (
            '"cpu" to mapOf(',
            '"memory" to mapOf(',
            '"storage" to mapOf(',
            '"accelerators" to mapOf(',
            '"roles" to mapOf(',
            '"sensors" to mapOf(',
            '"oem" to mapOf(',
            '"constraints" to mapOf(',
            '"supportedAbis"',
            '"logicalProcessors"',
            '"totalBytes"',
            '"npu"',
        ):
            self.assertIn(required, source)

    def test_profile_fails_closed_on_npu_and_device_trust(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        self.assertIn('"availability" to "unknown"', source)
        self.assertIn('"evidence" to "not_probed_by_stable_public_api"', source)
        self.assertIn('"normalOperationRequiresDesktop" to false', source)
        self.assertIn('"rootRequired" to false', source)
        self.assertIn('"bootloaderUnlockRequired" to false', source)
        self.assertIn('"hiddenOemApiRequired" to false', source)
    def test_channel_exposes_bounded_profile_method(self) -> None:
        source = _CHANNEL.read_text(encoding="utf-8")
        self.assertIn('"getCompatibilityProfile"', source)
        self.assertIn("PandoraDeviceCompatibilityProfile(context, oemAdapter)", source)
        self.assertIn("deviceCompatibilityProfile.snapshot(", source)

    def test_profile_uses_public_non_identifying_sources(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        for required in (
            "Build.SUPPORTED_ABIS",
            "ActivityManager.MemoryInfo",
            "StatFs",
            "PackageManager.FEATURE_CAMERA_ANY",
            "PackageManager.FEATURE_MICROPHONE",
        ):
            self.assertIn(required, source)
        for forbidden in (
            "Settings.Secure.ANDROID_ID",
            "Build.SERIAL",
            "getConnectionInfo",
            "HardwarePropertiesManager",
            "Runtime.getRuntime().exec",
            "ProcessBuilder",
        ):
            self.assertNotIn(forbidden, source)

    def test_dart_contract_rejects_identity_and_unverified_npu_claims(self) -> None:
        source = _DART.read_text(encoding="utf-8")
        self.assertIn("not_probed_by_stable_public_api", source)
        self.assertIn("Compatibility profile must not contain device or network identifiers", source)
        self.assertIn("hardwarePresenceOnly", source)
        self.assertIn("optional_not_trust_dependency", source)


if __name__ == "__main__":
    unittest.main()
