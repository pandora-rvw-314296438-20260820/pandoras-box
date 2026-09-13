#!/usr/bin/env python3
"""Source-contract tests for the bounded Android Device Agent foundation."""

from __future__ import annotations

import unittest
from pathlib import Path


_ROOT = Path(__file__).resolve().parents[1]
_AGENT = (
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
    / "PandoraDeviceAgentChannel.kt"
)
_MAIN = (
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
    / "MainActivity.kt"
)
_MANIFEST_TOOL = _ROOT / "tool" / "configure_validation_android.py"


class DeviceAgentContractTest(unittest.TestCase):
    def test_channel_is_installed_once(self) -> None:
        source = _MAIN.read_text(encoding="utf-8")
        self.assertEqual(source.count("PandoraDeviceAgentChannel.install("), 1)

    def test_channel_exposes_only_bounded_methods(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for method in (
            '"getCapabilityManifest"',
            '"getPermissionStates"',
            '"openSystemSurface"',
            '"runSafeDiagnostic"',
        ):
            self.assertIn(method, source)
        for unsafe in (
            "Runtime.getRuntime().exec",
            "ProcessBuilder(",
            "executeShellCommand",
            "Shizuku",
            "android.os.Debug",
        ):
            self.assertNotIn(unsafe, source)

    def test_normal_operation_is_phone_only_and_non_root(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        self.assertIn('"normalOperationRequiresDesktop" to false', source)
        self.assertIn('"rootRequired" to false', source)
        self.assertIn('"bootloaderUnlockRequired" to false', source)
        self.assertIn('"developmentBridgePolicy" to "optional_not_trust_dependency"', source)

    def test_protected_apps_fail_closed(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        self.assertIn('"protected_apps.private_data"', source)
        self.assertIn('"policy_denied"', source)
        self.assertIn('"forbidden"', source)

    def test_m4_001_does_not_broaden_validation_permissions(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        self.assertIn("_INTERNET_PERMISSION_NAME = 'android.permission.INTERNET'", source)
        for permission in (
            "android.permission.CAMERA",
            "android.permission.RECORD_AUDIO",
            "android.permission.READ_CONTACTS",
            "android.permission.READ_SMS",
            "android.permission.CALL_PHONE",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.BLUETOOTH_SCAN",
        ):
            self.assertNotIn(permission, source)

    def test_m4_002_recovery_surfaces_are_allowlisted(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for bounded_surface in (
            '"android_settings"',
            '"home_app_settings"',
            '"system_dialer"',
            "Settings.ACTION_SETTINGS",
            "Settings.ACTION_HOME_SETTINGS",
            "Intent.ACTION_DIAL",
        ):
            self.assertIn(bounded_surface, source)
        self.assertNotIn("Intent.ACTION_CALL", source)
        self.assertNotIn("Intent.ACTION_CALL_PRIVILEGED", source)
        self.assertIn("UNSUPPORTED_SYSTEM_SURFACE", source)

    def test_m4_002_home_manifest_is_candidate_not_kiosk(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        self.assertIn("_HOME_CATEGORY = 'android.intent.category.HOME'", source)
        self.assertIn("_DEFAULT_CATEGORY = 'android.intent.category.DEFAULT'", source)
        self.assertIn("_LAUNCHER_CATEGORY = 'android.intent.category.LAUNCHER'", source)
        self.assertIn("without forcing default HOME", source)
        for forbidden in (
            "android:lockTaskMode",
            "addPersistentPreferredActivity",
            "setLockTaskPackages",
            "DevicePolicyManager",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
