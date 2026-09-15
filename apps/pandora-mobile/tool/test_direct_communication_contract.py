#!/usr/bin/env python3
"""Source-contract tests for direct SMS/call execution truth and idempotency."""

from __future__ import annotations

import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_DIRECT = (
    _ROOT / "platform" / "android" / "app" / "src" / "main" / "kotlin"
    / "com" / "banataosystems" / "pandora_mobile" / "PandoraDirectCommunications.kt"
)
_MANIFEST_TOOL = _ROOT / "tool" / "configure_validation_android.py"


class DirectCommunicationContractTest(unittest.TestCase):
    def test_sms_rechecks_permission_and_reports_platform_acceptance_only_after_dispatch(self) -> None:
        source = _DIRECT.read_text(encoding="utf-8")
        self.assertIn("Manifest.permission.SEND_SMS", source)
        self.assertIn("checkPermission(permission, context.packageName)", source)
        self.assertIn("manager.sendTextMessage", source)
        self.assertIn("manager.sendMultipartTextMessage", source)
        self.assertIn('record(context, operationId, "sms", "submitted")', source)
        self.assertIn('markPlatformAccepted(context, operationId)', source)
        self.assertIn('prefs.getBoolean("$operationId.platformAccepted", false)', source)
        self.assertNotIn('state in setOf("dispatching", "sent", "delivered", "initiated")', source)

    def test_multipart_callbacks_are_deduplicated_per_part(self) -> None:
        source = _DIRECT.read_text(encoding="utf-8")
        for required in (
            '"$operationId.sentAck.$partIndex"',
            '"$operationId.deliveredAck.$partIndex"',
            "prefs.getBoolean(ackKey, false)",
            ".putBoolean(ackKey, true)",
            'prefs.getInt("$operationId.parts", 0)',
            "storedPartCount != partCount",
            "partIndex !in 0 until partCount",
        ):
            self.assertIn(required, source)

    def test_call_path_rechecks_permission_and_guards_emergency_numbers(self) -> None:
        source = _DIRECT.read_text(encoding="utf-8")
        for required in (
            "Manifest.permission.CALL_PHONE",
            "telephony.isEmergencyNumber(recipient)",
            "Intent.ACTION_CALL",
            'record(context, operationId, "call", "initiated")',
            '"permission_revoked_at_dispatch"',
        ):
            self.assertIn(required, source)
        self.assertNotIn("Intent.ACTION_CALL_PRIVILEGED", source)

    def test_sms_callback_receiver_is_non_exported_and_privacy_stays_narrow(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        self.assertIn("PandoraSmsStatusReceiver", source)
        self.assertIn("android:exported", source)
        for forbidden in (
            "android.permission.READ_SMS",
            "android.permission.RECEIVE_SMS",
            "android.permission.READ_CALL_LOG",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
