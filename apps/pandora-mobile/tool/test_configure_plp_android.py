#!/usr/bin/env python3
"""Regression tests for the dedicated PLP Android identity configurator."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).with_name("configure_plp_android.py")


class ConfigurePlpAndroidTest(unittest.TestCase):
    def test_retargets_gradle_manifest_and_kotlin_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gradle = root / "build.gradle.kts"
            manifest = root / "AndroidManifest.xml"
            kotlin = root / "kotlin" / "com" / "banataosystems" / "pandora_mobile"
            kotlin.mkdir(parents=True)
            source = kotlin / "MainActivity.kt"

            gradle.write_text(
                'android {\n'
                '    namespace = "com.banataosystems.pandora_mobile"\n'
                '    defaultConfig {\n'
                '        applicationId = "com.banataosystems.pandora_mobile"\n'
                '    }\n'
                '}\n',
                encoding="utf-8",
            )
            manifest.write_text(
                '<manifest><application android:label="Pandora"/></manifest>\n',
                encoding="utf-8",
            )
            source.write_text(
                "package com.banataosystems.pandora_mobile\n\n"
                "class MainActivity\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(_SCRIPT),
                    str(gradle),
                    str(manifest),
                    str(root / "kotlin"),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("com.banataosystems.pandora.plp", gradle.read_text())
            self.assertNotIn("com.banataosystems.pandora_mobile", gradle.read_text())
            self.assertIn('android:label="PLP Pandora Enterprise"', manifest.read_text())
            self.assertIn(
                "package com.banataosystems.pandora.plp",
                source.read_text(),
            )

    def test_fails_closed_when_generated_identity_is_ambiguous(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gradle = root / "build.gradle.kts"
            manifest = root / "AndroidManifest.xml"
            kotlin = root / "kotlin"
            kotlin.mkdir()
            (kotlin / "MainActivity.kt").write_text(
                "package com.banataosystems.pandora_mobile\n",
                encoding="utf-8",
            )
            gradle.write_text(
                'namespace = "other.namespace"\n'
                'applicationId = "com.banataosystems.pandora_mobile"\n',
                encoding="utf-8",
            )
            manifest.write_text(
                '<application android:label="Pandora"/>\n',
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(_SCRIPT),
                    str(gradle),
                    str(manifest),
                    str(kotlin),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("generated Android namespace", result.stderr)


if __name__ == "__main__":
    unittest.main()
