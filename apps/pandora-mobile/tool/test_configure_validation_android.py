#!/usr/bin/env python3
"""Regression tests for the bounded Android validation manifest patch."""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


_SCRIPT = Path(__file__).with_name('configure_validation_android.py')
_CANONICAL_MARK_SHA256 = (
    '8a35b74baec47b960a42bb74587f9c531d6cbf8d45f16061836a9e63f00efcc5'
)
_BASE_MANIFEST = """<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n    <application android:label=\"pandora_mobile\" android:name=\"${applicationName}\" android:icon=\"@mipmap/ic_launcher\">\n        <activity android:name=\".MainActivity\" android:exported=\"true\">\n            <intent-filter>\n                <action android:name=\"android.intent.action.MAIN\"/>\n                <category android:name=\"android.intent.category.LAUNCHER\"/>\n            </intent-filter>\n        </activity>\n    </application>\n</manifest>\n"""


class ConfigureValidationAndroidTest(unittest.TestCase):
    def _run(
        self,
        manifest_text: str,
    ) -> tuple[subprocess.CompletedProcess[str], str, str | None, bytes | None]:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / 'AndroidManifest.xml'
            manifest.write_text(manifest_text, encoding='utf-8')
            result = subprocess.run(
                [sys.executable, str(_SCRIPT), str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )
            icon = manifest.parent / 'res' / 'drawable' / 'pandora_launcher_icon.xml'
            mark = (
                manifest.parent
                / 'res'
                / 'drawable-nodpi'
                / 'pandora_product_mark.png'
            )
            icon_text = icon.read_text(encoding='utf-8') if icon.is_file() else None
            mark_bytes = mark.read_bytes() if mark.is_file() else None
            return result, manifest.read_text(encoding='utf-8'), icon_text, mark_bytes

    def test_adds_internet_permission_product_label_and_spiral_icon(self) -> None:
        result, updated, icon_text, mark_bytes = self._run(_BASE_MANIFEST)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count('android.permission.INTERNET'), 1)
        self.assertIn(
            '<uses-permission android:name="android.permission.INTERNET"/>',
            updated,
        )
        self.assertEqual(updated.count('android.permission.ACCESS_NETWORK_STATE'), 1)
        self.assertIn(
            '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
            updated,
        )
        for permission in (
            'android.permission.READ_CALENDAR',
            'android.permission.WRITE_CALENDAR',
            'android.permission.POST_NOTIFICATIONS',
            'android.permission.SCHEDULE_EXACT_ALARM',
        ):
            self.assertEqual(updated.count(permission), 1)
        self.assertIn(
            '<receiver android:name=".PandoraLocalReminderReceiver" android:exported="false"/>',
            updated,
        )
        self.assertIn('android:label="Pandora"', updated)
        self.assertEqual(updated.count('android:allowBackup="false"'), 1)
        self.assertNotIn('android:label="pandora_mobile"', updated)
        self.assertIn('android:icon="@drawable/pandora_launcher_icon"', updated)
        self.assertNotIn('android:icon="@mipmap/ic_launcher"', updated)
        self.assertIsNotNone(icon_text)
        self.assertIsNotNone(mark_bytes)
        assert icon_text is not None
        assert mark_bytes is not None
        self.assertIn('@drawable/pandora_product_mark', icon_text)
        self.assertIn('#FF171717', icon_text)
        self.assertEqual(hashlib.sha256(mark_bytes).hexdigest(), _CANONICAL_MARK_SHA256)
        self.assertIn('canonical Pandora spiral apple', result.stdout)

    def test_preserves_one_approved_existing_internet_permission(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            '\n    <application',
            '\n    <uses-permission android:name="android.permission.INTERNET"/>\n'
            '    <application',
        )
        result, updated, _, _ = self._run(manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count('android.permission.INTERNET'), 1)

    def test_refuses_duplicate_internet_permission(self) -> None:
        permission = '<uses-permission android:name="android.permission.INTERNET"/>'
        manifest = _BASE_MANIFEST.replace(
            '\n    <application',
            f'\n    {permission}\n    {permission}\n    <application',
        )
        result, _, _, _ = self._run(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertIn('at most one Android INTERNET permission', result.stderr)

    def test_refuses_duplicate_network_state_permission(self) -> None:
        permission = (
            '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>'
        )
        manifest = _BASE_MANIFEST.replace(
            '\n    <application',
            f'\n    {permission}\n    {permission}\n    <application',
        )
        result, _, _, _ = self._run(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertIn('at most one Android ACCESS_NETWORK_STATE permission', result.stderr)

    def test_refuses_preexisting_backup_policy(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher" android:allowBackup="true"',
        )
        result, _, _, _ = self._run(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertIn('already declares backup policy', result.stderr)

    def test_refuses_cleartext_traffic(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher" android:usesCleartextTraffic="true"',
        )
        result, _, _, _ = self._run(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertIn('must not explicitly enable cleartext traffic', result.stderr)

    def test_refuses_ambiguous_launcher_icon_reference(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@drawable/unknown"',
        )
        result, _, icon_text, mark_bytes = self._run(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertIn('launcher icon reference', result.stderr)
        self.assertIsNone(icon_text)
        self.assertIsNone(mark_bytes)

    def test_adds_home_candidate_and_preserves_launcher_recovery(self) -> None:
        result, updated, _, _ = self._run(_BASE_MANIFEST)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count('android.intent.category.HOME'), 1)
        self.assertEqual(updated.count('android.intent.category.DEFAULT'), 1)
        self.assertEqual(updated.count('android.intent.category.LAUNCHER'), 1)
        self.assertEqual(updated.count('android.intent.action.MAIN'), 2)
        self.assertNotIn('android.permission.CALL_PHONE', updated)
        self.assertNotIn('android.permission.READ_SMS', updated)
        self.assertNotIn('android.permission.SEND_SMS', updated)
        self.assertNotIn('android:lockTaskMode', updated)
        self.assertIn('without forcing default HOME', result.stdout)

    def test_refuses_preexisting_home_or_default_routing(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n'
            '                <category android:name="android.intent.category.HOME"/>',
        )
        result, _, _, _ = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn('already declares HOME/DEFAULT routing', result.stderr)


if __name__ == '__main__':
    unittest.main()
