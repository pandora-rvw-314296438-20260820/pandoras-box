#!/usr/bin/env python3
"""Contract tests for the reusable Android OEM adapter registry."""

from __future__ import annotations

import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_ANDROID = (
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
)
_REGISTRY = _ANDROID / "PandoraOemAdapterRegistry.kt"
_RUNTIME = _ANDROID / "PandoraAndroidOemAdapter.kt"


class OemAdapterRegistryContractTest(unittest.TestCase):
    def test_registry_exposes_one_reusable_family_contract(self) -> None:
        source = _REGISTRY.read_text(encoding="utf-8")
        self.assertIn("internal interface PandoraOemFamilyAdapter", source)
        self.assertIn("internal data class PandoraOemAdapterPolicy", source)
        self.assertIn("internal object PandoraOemAdapterRegistry", source)
        self.assertIn("fun resolve(manufacturer: String, brand: String)", source)

    def test_supported_oem_families_are_explicit_and_additive(self) -> None:
        source = _REGISTRY.read_text(encoding="utf-8")
        expected = {
            "XiaomiOemFamilyAdapter": "xiaomi_public_v1",
            "SamsungOemFamilyAdapter": "samsung_public_v1",
            "PixelOemFamilyAdapter": "pixel_public_v1",
            "OnePlusOemFamilyAdapter": "oneplus_public_v1",
        }
        for adapter, adapter_id in expected.items():
            self.assertIn(adapter, source)
            self.assertIn(f'adapterId = "{adapter_id}"', source)
        self.assertIn('adapterId = "android_generic_public_v1"', source)

    def test_xiaomi_aliases_remain_manual_and_other_families_do_not_fake_autostart(self) -> None:
        source = _REGISTRY.read_text(encoding="utf-8")
        self.assertIn('setOf("xiaomi", "redmi", "poco")', source)
        self.assertEqual(source.count('autostartManagement = "manual_oem_control"'), 1)
        self.assertGreaterEqual(
            source.count('autostartManagement = "public_api_unavailable"'),
            4,
        )

    def test_android_runtime_delegates_classification_to_registry(self) -> None:
        source = _RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PandoraOemAdapterRegistry.resolve(", source)
        self.assertIn('val xiaomiFamily = oemPolicy.family == "xiaomi"', source)
        self.assertIn('"adapterId" to oemPolicy.adapterId', source)
        self.assertIn('"autostartManagement" to oemPolicy.autostartManagement', source)
        self.assertNotIn("fun isXiaomiFamily()", source)

    def test_registry_never_uses_private_oem_or_privileged_execution_paths(self) -> None:
        source = _REGISTRY.read_text(encoding="utf-8") + _RUNTIME.read_text(encoding="utf-8")
        for forbidden in (
            "com.miui.securitycenter",
            "miui.intent.action.OP_AUTO_START",
            "ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            "Runtime.getRuntime().exec",
            "ProcessBuilder(",
            "Shizuku",
            "executeShellCommand",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
