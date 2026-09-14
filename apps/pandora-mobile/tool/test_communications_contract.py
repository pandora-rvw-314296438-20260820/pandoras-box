#!/usr/bin/env python3
"""Source-contract tests for bounded call/SMS Android handoffs."""

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
_ACTIVITY = (
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
_DART = _ROOT / "lib" / "core" / "device" / "pandora_communications.dart"


class CommunicationsContractTest(unittest.TestCase):
    def test_handoffs_use_system_composers_only(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for required in (
            '"openCommunicationComposer"',
            "Intent.ACTION_DIAL",
            "Intent.ACTION_SENDTO",
            'Uri.fromParts("tel", recipient, null)',
            'Uri.fromParts("smsto", recipient, null)',
            'putExtra("sms_body", message)',
            '"userConfirmationRequired" to true',
        ):
            self.assertIn(required, source)
        for forbidden in (
            "Intent.ACTION_CALL",
            "Intent.ACTION_CALL_PRIVILEGED",
            "TelecomManager.placeCall",
            "SmsManager",
            "sendTextMessage",
        ):
            self.assertNotIn(forbidden, source)

    def test_android_roles_are_observed_not_assumed(self) -> None:
        source = _AGENT.read_text(encoding="utf-8")
        for required in (
            "RoleManager.ROLE_DIALER",
            "RoleManager.ROLE_SMS",
            "manager.isRoleAvailable(roleName)",
            "manager.isRoleHeld(roleName)",
            '"permission_required"',
            "explicit user consent",
        ):
            self.assertIn(required, source)
        for forbidden in (
            "createRequestRoleIntent",
            "addRoleHolderAsUser",
            "setDefaultDialer",
        ):
            self.assertNotIn(forbidden, source)

    def test_validation_manifest_does_not_gain_telephony_permissions(self) -> None:
        source = _MANIFEST_TOOL.read_text(encoding="utf-8")
        for forbidden in (
            "android.permission.CALL_PHONE",
            "android.permission.READ_PHONE_STATE",
            "android.permission.READ_CALL_LOG",
            "android.permission.WRITE_CALL_LOG",
            "android.permission.READ_SMS",
            "android.permission.RECEIVE_SMS",
            "android.permission.SEND_SMS",
        ):
            self.assertNotIn(forbidden, source)

    def test_named_contact_resolution_uses_system_picker_without_broad_permission(self) -> None:
        activity = _ACTIVITY.read_text(encoding="utf-8")
        manifest_tool = _MANIFEST_TOOL.read_text(encoding="utf-8")
        for required in (
            '"pickPhoneContact"',
            "Intent.ACTION_PICK",
            "ContactsContract.CommonDataKinds.Phone.CONTENT_URI",
            "ContactsContract.CommonDataKinds.Phone.NUMBER",
        ):
            self.assertIn(required, activity)
        self.assertNotIn("android.permission.READ_CONTACTS", manifest_tool)

    def test_dart_contract_has_no_direct_execution_bypass(self) -> None:
        source = _DART.read_text(encoding="utf-8")
        self.assertIn("openCommunicationComposer", source)
        self.assertIn("userConfirmationRequired", source)
        self.assertIn("_recipientPattern", source)
        for forbidden in (
            "sendDirect",
            "sendSmsDirect",
            "placeCallDirect",
            "CALL_PHONE",
            "SEND_SMS",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
