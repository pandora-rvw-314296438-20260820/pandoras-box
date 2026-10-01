import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("configure_plp_emulator_android.py")
SPEC = importlib.util.spec_from_file_location("configure_plp_emulator_android", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ConfigurePlpEmulatorAndroidTest(unittest.TestCase):
    def test_retargets_disposable_build_and_disables_native_local_ai(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            gradle = root / "build.gradle.kts"
            kotlin = root / "kotlin"
            main = kotlin / "com" / "banataosystems" / "pandora" / "plp" / "MainActivity.kt"
            main.parent.mkdir(parents=True)

            gradle.write_text(
                """android {
    defaultConfig {
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DGGML_VULKAN=ON")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
}
""",
                encoding="utf-8",
            )
            main.write_text(
                """class MainActivity {
    private var localAiChannel: PandoraLocalAiChannel? = null
    fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        localAiChannel = PandoraLocalAiChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
""",
                encoding="utf-8",
            )

            self.assertEqual(MODULE.configure(gradle, kotlin), 0)
            gradle_text = gradle.read_text(encoding="utf-8")
            main_text = main.read_text(encoding="utf-8")
            self.assertIn('abiFilters += "x86_64"', gradle_text)
            self.assertNotIn('abiFilters += "arm64-v8a"', gradle_text)
            self.assertNotIn("externalNativeBuild {", gradle_text)
            self.assertIn("x86_64 acceptance build", main_text)
            self.assertNotIn("localAiChannel = PandoraLocalAiChannel(", main_text)


if __name__ == "__main__":
    unittest.main()
