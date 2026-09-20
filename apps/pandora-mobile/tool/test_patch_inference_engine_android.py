from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("patch_inference_engine_android.py")


class PatchInferenceEngineAndroidTest(unittest.TestCase):
    def test_rewrites_native_init_and_load_diagnostics(self) -> None:
        source = """
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library", e)
                throw e
            }

                load(pathToModel).let {
                    // TODO-han.yin: find a better way to pass other error codes
                    if (it != 0) throw UnsupportedArchitectureException()
                }
                prepare().let {
                    if (it != 0) throw IOException("Failed to prepare resources")
                }
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "InferenceEngineImpl.kt"
            path.write_text(source, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            patched = path.read_text(encoding="utf-8")
            self.assertIn("Native library initialization failed:", patched)
            self.assertIn("Native llama.cpp model load failed with code ", patched)
            self.assertIn(
                "Native llama.cpp context preparation failed with code ",
                patched,
            )
            self.assertNotIn("UnsupportedArchitectureException()", patched)


if __name__ == "__main__":
    unittest.main()
