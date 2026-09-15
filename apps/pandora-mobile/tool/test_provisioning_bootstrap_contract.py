#!/usr/bin/env python3
"""M8-002 source-boundary tests for no-PC provisioning bootstrap."""

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
    / "PandoraProvisioningBootstrap.kt"
)
_CHANNEL = _KOTLIN.with_name("PandoraDeviceAgentChannel.kt")
_DART = _ROOT / "lib" / "core" / "device" / "pandora_provisioning_bootstrap.dart"


class ProvisioningBootstrapContractTest(unittest.TestCase):
    def test_bootstrap_is_on_device_and_self_service(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        for required in (
            '"runtimeLocation" to "on_device"',
            '"enrollmentMode" to "self_service_app_v1"',
            '"normalOperationRequiresDesktop" to false',
            '"adbRequiredForNormalOperation" to false',
            '"developmentBridgePolicy" to "optional_recovery_only"',
            '"deviceOwnerRequiredForNormalOperation" to false',
        ):
            self.assertIn(required, source)

    def test_bootstrap_preserves_security_boundaries(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        for required in (
            '"rootRequired" to false',
            '"bootloaderUnlockRequired" to false',
            '"protectedAppReauthenticationRequired" to true',
            '"deny_private_app_data_and_credentials"',
        ):
            self.assertIn(required, source)
        for forbidden in (
            "Runtime.getRuntime().exec",
            "ProcessBuilder",
            "Settings.Secure.ANDROID_ID",
            "serviceRoleKey",
        ):
            self.assertNotIn(forbidden, source)

    def test_required_setup_and_recovery_paths_are_explicit(self) -> None:
        source = _KOTLIN.read_text(encoding="utf-8")
        for required in (
            '"app_installation"',
            '"in_app_authentication"',
            '"android_roles_and_permissions"',
            '"oem_background_reliability"',
            '"android_settings"',
            '"app_details"',
            '"battery_optimization_settings"',
            '"adb_development_bridge"',
            '"development_only"',
        ):
            self.assertIn(required, source)

    def test_channel_exposes_only_bounded_bootstrap_read(self) -> None:
        source = _CHANNEL.read_text(encoding="utf-8")
        self.assertIn('"getProvisioningBootstrap"', source)
        self.assertIn("PandoraProvisioningBootstrap(context, oemAdapter)", source)
        self.assertIn("provisioningBootstrap.snapshot(", source)
        self.assertNotIn('"runProvisioningShell"', source)

    def test_dart_contract_rejects_dependency_and_secret_escalation(self) -> None:
        source = _DART.read_text(encoding="utf-8")
        for required in (
            "optional_recovery_only",
            "Provisioning bootstrap must not carry credentials or secrets",
            "Protected-app bootstrap boundaries must remain fail-closed",
            "ADB must exist only as a development/recovery path",
            "deviceOwnerRequiredForNormalOperation",
        ):
            self.assertIn(required, source)


if __name__ == "__main__":
    unittest.main()
