import tempfile
import unittest
from pathlib import Path

import configure_eurofish_android


class ConfigureEurofishAndroidTest(unittest.TestCase):
    def test_retargets_package_label_and_kotlin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gradle = root / "build.gradle.kts"
            manifest = root / "AndroidManifest.xml"
            kotlin = root / "kotlin"
            source = kotlin / "com" / "banataosystems" / "pandora_mobile" / "MainActivity.kt"
            source.parent.mkdir(parents=True)
            gradle.write_text(
                'android {\n'
                '    namespace = "com.banataosystems.pandora_mobile"\n'
                '    defaultConfig {\n'
                '        applicationId = "com.banataosystems.pandora_mobile"\n'
                '    }\n'
                '}\n'
            )
            manifest.write_text(
                '<manifest><application android:label="Pandora"></application></manifest>'
            )
            source.write_text(
                'package com.banataosystems.pandora_mobile\nclass MainActivity\n'
            )

            result = configure_eurofish_android.configure(gradle, manifest, kotlin)

            self.assertEqual(result, 0)
            self.assertIn(
                'com.banataosystems.pandora.eurofish',
                gradle.read_text(),
            )
            self.assertIn(
                'android:label="Euro-Fish Pandora Enterprise"',
                manifest.read_text(),
            )
            self.assertIn(
                'package com.banataosystems.pandora.eurofish',
                source.read_text(),
            )
            self.assertNotIn(
                'com.banataosystems.pandora_mobile',
                gradle.read_text() + source.read_text(),
            )


if __name__ == "__main__":
    unittest.main()
