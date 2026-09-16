#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KOTLIN = ROOT / 'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraCalendarChannel.kt'
DART = ROOT / 'lib/core/device/pandora_calendar_runtime.dart'
MAIN = ROOT / 'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/MainActivity.kt'
MANIFEST_TOOL = ROOT / 'tool/configure_validation_android.py'


class CalendarRuntimeContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.kotlin = KOTLIN.read_text(encoding='utf-8')
        cls.dart = DART.read_text(encoding='utf-8')
        cls.main = MAIN.read_text(encoding='utf-8')
        cls.manifest_tool = MANIFEST_TOOL.read_text(encoding='utf-8')

    def test_channel_is_installed_without_chat_surface_edits(self) -> None:
        self.assertIn('PandoraCalendarChannel.install(', self.main)
        self.assertIn('pandora/calendar_runtime', self.kotlin)
        self.assertIn('pandora/calendar_runtime', self.dart)

    def test_calendar_permissions_and_provider_readback_are_explicit(self) -> None:
        for token in (
            'Manifest.permission.READ_CALENDAR',
            'Manifest.permission.WRITE_CALENDAR',
            'CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL',
            'CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR',
            'readback_pending',
            'readback_failed',
        ):
            self.assertIn(token, self.kotlin)

    def test_operation_ids_prevent_blind_duplicate_mutation(self) -> None:
        self.assertIn('operation_id_reused_with_different_input', self.kotlin)
        self.assertIn('duplicatePrevented', self.kotlin)
        self.assertIn('getOperationStatus', self.kotlin)
        self.assertIn('getOperationStatus', self.dart)

    def test_exact_reminders_fail_closed_to_special_access(self) -> None:
        self.assertIn('canScheduleExactAlarms()', self.kotlin)
        self.assertIn('special_access_required', self.kotlin)
        self.assertIn('setExactAndAllowWhileIdle', self.kotlin)
        self.assertIn('setAndAllowWhileIdle', self.kotlin)
        self.assertNotIn('setAlarmClock(', self.kotlin)

    def test_receiver_is_non_exported_and_notification_revocation_is_checked(self) -> None:
        self.assertIn('PandoraLocalReminderReceiver', self.kotlin)
        self.assertIn('notification_permission_revoked_before_fire', self.kotlin)
        self.assertIn('android:exported="false"', self.manifest_tool)
        self.assertIn('android.permission.POST_NOTIFICATIONS', self.manifest_tool)

    def test_calendar_runtime_does_not_add_privileged_or_hidden_paths(self) -> None:
        forbidden = (
            'Runtime.getRuntime().exec',
            'ProcessBuilder(',
            'Shizuku',
            'android.permission.READ_SMS',
            'android.permission.RECEIVE_SMS',
            'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE',
        )
        for token in forbidden:
            self.assertNotIn(token, self.kotlin)

    def test_manifest_declares_only_bounded_calendar_reminder_authority(self) -> None:
        for permission in (
            'android.permission.READ_CALENDAR',
            'android.permission.WRITE_CALENDAR',
            'android.permission.POST_NOTIFICATIONS',
            'android.permission.SCHEDULE_EXACT_ALARM',
        ):
            self.assertIn(permission, self.manifest_tool)


if __name__ == '__main__':
    unittest.main()
