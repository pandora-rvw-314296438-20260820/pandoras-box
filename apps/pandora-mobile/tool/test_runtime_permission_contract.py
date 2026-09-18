#!/usr/bin/env python3
"""Source-contract tests for M7-006 Android runtime permission binding."""

from __future__ import annotations

import unittest
from pathlib import Path


_ROOT = Path(__file__).resolve().parents[1]
_AGENT = (
    _ROOT / "platform" / "android" / "app" / "src" / "main" / "kotlin"
    / "com" / "banataosystems" / "pandora_mobile" / "PandoraDeviceAgentChannel.kt"
)
_MAIN = (
    _ROOT / "platform" / "android" / "app" / "src" / "main" / "kotlin"
    / "com" / "banataosystems" / "pandora_mobile" / "MainActivity.kt"
)
_MANIFEST_TOOL = _ROOT / "tool" / "configure_validation_android.py"


class RuntimePermissionContractTest(unittest.TestCase):
    def test_prompt_is_foreground_and_user_initiated_only(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for required in (
            '"requestRuntimePermission"',
            'call.argument<Boolean>("userInitiated") == true',
            "ActivityResultContracts.RequestPermission()",
            "Lifecycle.State.RESUMED",
            '"PERMISSION_PROMPT_NOT_USER_INITIATED"',
        ):
            self.assertIn(required, source)

    def test_permission_state_is_fresh_and_revocation_stays_user_controlled(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for required in (
            "shouldShowRequestPermissionRationale(permission)",
            "permissionStateStore",
            "permissionBlockedKey(permission)",
            '"stateFresh" to true',
            '"revocationControlSurface" to "app_details"',
            '"permanently_denied"',
        ):
            self.assertIn(required, source)
        self.assertIn('"automaticRetryAllowed" to false', source)
        self.assertNotIn("FLAG_PERMISSION_USER_FIXED", source)
        self.assertNotIn("getPermissionFlags(", source)
        self.assertNotIn("runtimePromptAttempts", source)
        self.assertIn('"recheckRequired" to true', source)

    def test_prompt_result_is_re_read_after_android_callback(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        callback = source.split("private fun completeRuntimePermissionRequest()", 1)[1]
        self.assertIn("permissionState(permission)", callback)
        self.assertIn('granted -> "granted"', callback)
        self.assertIn('userFixed -> "permanently_denied"', callback)
        self.assertIn('else -> "denied"', callback)
        self.assertIn("recordPermissionPromptOutcome(permission)", callback)

    def test_device_agent_receives_the_foreground_activity(self) -> None:
        source = _MAIN.read_text(encoding="utf-8")
        self.assertIn("PandoraDeviceAgentChannel.install(\n            this,", source)
        self.assertNotIn(
            "PandoraDeviceAgentChannel.install(\n            applicationContext,", source
        )

    def test_m7_does_not_silently_broaden_android_manifest(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        self.assertIn("android.permission.SEND_SMS", source)
        self.assertIn("android.permission.CALL_PHONE", source)
        for forbidden in (
            "android.permission.CAMERA",
            "android.permission.RECORD_AUDIO",
            "android.permission.READ_SMS",
            "android.permission.ACCESS_FINE_LOCATION",
        ):
            self.assertNotIn(forbidden, source)

    def test_no_privileged_or_shell_permission_shortcut_exists(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for forbidden in (
            "grantRuntimePermission",
            "pm grant",
            "Runtime.getRuntime().exec",
            "ProcessBuilder(",
            "executeShellCommand",
            "addRoleHolderAsUser",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
