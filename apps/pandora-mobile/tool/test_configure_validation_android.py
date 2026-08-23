#!/usr/bin/env python3
"""Regression tests for the bounded Android validation manifest patch."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


_SCRIPT = Path(__file__).with_name("configure_validation_android.py")
_BASE_MANIFEST = """<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n    <application android:label=\"pandora_mobile\" android:name=\"${applicationName}\" android:icon=\"@mipmap/ic_launcher\">\n    </application>\n</manifest>\n"""


class ConfigureValidationAndroidTest(unittest.TestCase):
    def _run(self, manifest_text: str) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "AndroidManifest.xml"
            manifest.write_text(manifest_text, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(_SCRIPT), str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )
            return result, manifest.read_text(encoding="utf-8")

    def test_adds_internet_permission_and_product_label(self) -> None:
        result, updated = self._run(_BASE_MANIFEST)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count("android.permission.INTERNET"), 1)
        self.assertIn(
            '<uses-permission android:name="android.permission.INTERNET"/>',
            updated,
        )
        self.assertIn('android:label="Pandora"', updated)
        self.assertNotIn('android:label="pandora_mobile"', updated)

    def test_preserves_one_approved_existing_internet_permission(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            "\n    <application",
            '\n    <uses-permission android:name="android.permission.INTERNET"/>\n'
            "    <application",
        )
        result, updated = self._run(manifest)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count("android.permission.INTERNET"), 1)

    def test_refuses_duplicate_internet_permission(self) -> None:
        permission = '<uses-permission android:name="android.permission.INTERNET"/>'
        manifest = _BASE_MANIFEST.replace(
            "\n    <application",
            f"\n    {permission}\n    {permission}\n    <application",
        )
        result, _ = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn("at most one Android INTERNET permission", result.stderr)

    def test_refuses_cleartext_traffic(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher" android:usesCleartextTraffic="true"',
        )
        result, _ = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn("must not explicitly enable cleartext traffic", result.stderr)


if __name__ == "__main__":
    unittest.main()
