from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("configure_local_ai_android.py")
SPEC = importlib.util.spec_from_file_location("configure_local_ai_android", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ConfigureLocalAiAndroidTest(unittest.TestCase):
    def test_configures_generated_flutter_gradle_file(self) -> None:
        source = """plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.banataosystems.pandora_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.banataosystems.pandora_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build.gradle.kts"
            path.write_text(source, encoding="utf-8")
            self.assertEqual(MODULE.configure(path), 0)
            configured = path.read_text(encoding="utf-8")

        self.assertIn('ndkVersion = "29.0.13113456"', configured)
        self.assertIn("abiFilters.clear()", configured)
        self.assertIn('abiFilters += "arm64-v8a"', configured)
        self.assertIn('src/main/cpp/CMakeLists.txt', configured)
        self.assertIn('kotlinx-coroutines-android:1.10.2', configured)
        self.assertIn('-DGGML_BACKEND_DL=OFF', configured)
        self.assertIn('-DGGML_CPU_ALL_VARIANTS=OFF', configured)

    def test_preserves_arm64_filter_from_flutter_plugin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gradle.properties"
            path.write_text("android.useAndroidX=true\n", encoding="utf-8")
            self.assertEqual(MODULE.configure_properties(path), 0)
            self.assertEqual(MODULE.configure_properties(path), 0)
            configured = path.read_text(encoding="utf-8").splitlines()

        self.assertEqual(configured.count("disable-abi-filtering=true"), 1)

    def test_refuses_conflicting_abi_filter_property(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gradle.properties"
            path.write_text("disable-abi-filtering=false\n", encoding="utf-8")
            self.assertEqual(MODULE.configure_properties(path), 1)

    def test_refuses_ambiguous_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build.gradle.kts"
            path.write_text("android {}\n", encoding="utf-8")
            self.assertEqual(MODULE.configure(path), 1)


if __name__ == "__main__":
    unittest.main()
