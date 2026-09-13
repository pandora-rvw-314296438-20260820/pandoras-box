#!/usr/bin/env python3
"""Source-contract tests for the public Android/Xiaomi OEM reliability adapter."""

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
_OEM = _ANDROID / "PandoraAndroidOemAdapter.kt"
_AGENT = _ANDROID / "PandoraDeviceAgentChannel.kt"
_SETTINGS = _ROOT / "lib" / "features" / "settings" / "settings_screen.dart"
_MANIFEST_TOOL = _ROOT / "tool" / "configure_validation_android.py"


class OemReliabilityContractTest(unittest.TestCase):
    def test_uses_public_android_background_and_battery_state(self) -> None:
        source = _OEM.read_text(encoding="utf-8")
        for required in (
            "ActivityManager",
            "isBackgroundRestricted",
            "PowerManager",
            "isIgnoringBatteryOptimizations",
            "Settings.ACTION_APPLICATION_DETAILS_SETTINGS",
            "Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS",
        ):
            self.assertIn(required, source)

    def test_xiaomi_autostart_is_manual_not_fake_automation(self) -> None:
        source = _OEM.read_text(encoding="utf-8")
        self.assertIn('"manual_oem_control"', source)
        self.assertIn('"public_api_unavailable"', source)
        self.assertIn('"hiddenOemApiRequired" to false', source)
        self.assertIn('"normalOperationRequiresDesktop" to false', source)
        self.assertIn('"rootRequired" to false', source)
        self.assertIn('"bootloaderUnlockRequired" to false', source)

    def test_hidden_oem_and_direct_exemption_paths_are_forbidden(self) -> None:
        sources = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (_OEM, _AGENT, _MANIFEST_TOOL)
        )
        for forbidden in (
            "ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            "com.miui.securitycenter",
            "miui.intent.action.OP_AUTO_START",
            "Runtime.getRuntime().exec",
            "ProcessBuilder(",
            "Shizuku",
            "executeShellCommand",
        ):
            self.assertNotIn(forbidden, sources)

    def test_device_agent_exposes_only_safe_oem_surface_and_diagnostic(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for required in (
            '"app_details"',
            '"battery_optimization_settings"',
            '"oem_reliability"',
            "oemAdapter.openAppDetails()",
            "oemAdapter.openBatteryOptimizationSettings()",
            "oemAdapter.reliabilityState()",
            '"background.oem_reliability"',
        ):
            self.assertIn(required, source)
        self.assertIn('"available"', source)

    def test_owner_settings_keep_oem_controls_visible_and_manual(self) -> None:
        source = _SETTINGS.read_text(encoding="utf-8")
        for required in (
            "Pandora app details",
            "Battery optimization",
            "PandoraSystemSurface.appDetails",
            "PandoraSystemSurface.batteryOptimizationSettings",
            "Xiaomi/HyperOS autostart remains user-controlled",
        ):
            self.assertIn(required, source)

    def test_validation_manifest_does_not_gain_oem_privilege(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        self.assertNotIn("REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", source)
        self.assertNotIn("RECEIVE_BOOT_COMPLETED", source)
        self.assertNotIn("FOREGROUND_SERVICE", source)


if __name__ == "__main__":
    unittest.main()
