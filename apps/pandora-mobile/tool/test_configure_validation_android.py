
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
    def _run(
        self,
        manifest_text: str,
    ) -> tuple[subprocess.CompletedProcess[str], str, str | None]:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "AndroidManifest.xml"
            manifest.write_text(manifest_text, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(_SCRIPT), str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )
            icon = manifest.parent / "res" / "drawable" / "pandora_launcher_icon.xml"
            icon_text = icon.read_text(encoding="utf-8") if icon.is_file() else None
            return result, manifest.read_text(encoding="utf-8"), icon_text

    def test_adds_internet_permission_product_label_and_apple_icon(self) -> None:
        result, updated, icon_text = self._run(_BASE_MANIFEST)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count("android.permission.INTERNET"), 1)
        self.assertIn(
            '<uses-permission android:name="android.permission.INTERNET"/>',
            updated,
        )
        self.assertIn('android:label="Pandora"', updated)
        self.assertNotIn('android:label="pandora_mobile"', updated)
        self.assertIn('android:icon="@drawable/pandora_launcher_icon"', updated)
        self.assertNotIn('android:icon="@mipmap/ic_launcher"', updated)
        self.assertIsNotNone(icon_text)
        assert icon_text is not None
        self.assertIn('android:fillType="evenOdd"', icon_text)
        self.assertIn("#FFB72DFF", icon_text)
        self.assertIn("#FF2063FF", icon_text)
        self.assertIn("Pandora gradient apple", result.stdout)

    def test_preserves_one_approved_existing_internet_permission(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            "\n    <application",
            '\n    <uses-permission android:name="android.permission.INTERNET"/>\n'
            "    <application",
        )
        result, updated, _ = self._run(manifest)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated.count("android.permission.INTERNET"), 1)

    def test_refuses_duplicate_internet_permission(self) -> None:
        permission = '<uses-permission android:name="android.permission.INTERNET"/>'
        manifest = _BASE_MANIFEST.replace(
            "\n    <application",
            f"\n    {permission}\n    {permission}\n    <application",
        )
        result, _, _ = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn("at most one Android INTERNET permission", result.stderr)

    def test_refuses_cleartext_traffic(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher" android:usesCleartextTraffic="true"',
        )
        result, _, _ = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn("must not explicitly enable cleartext traffic", result.stderr)

    def test_refuses_ambiguous_launcher_icon_reference(self) -> None:
        manifest = _BASE_MANIFEST.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@drawable/unknown"',
        )
        result, _, icon_text = self._run(manifest)

        self.assertEqual(result.returncode, 1)
        self.assertIn("launcher icon reference", result.stderr)
        self.assertIsNone(icon_text)


if __name__ == "__main__":
    unittest.main()
