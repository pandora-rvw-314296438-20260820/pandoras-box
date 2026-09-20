from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("patch_inference_engine_android.py")


class PatchInferenceEngineAndroidTest(unittest.TestCase):
    def test_rewrites_native_diagnostics_and_fail_loud_generation(self) -> None:
        implementation = """
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

    @FastNative
    private external fun generateNextToken(): String?

    @FastNative
    private external fun unload()

            processUserPrompt(message, predictLength).let { result ->
                if (result != 0) {
                    Log.e(TAG, "Failed to process user prompt: $result")
                    return@flow
                }
            }

    override suspend fun bench(pp: Int, tg: Int, pl: Int, nr: Int): String =
        withContext(llamaDispatcher) {
            check(_state.value is InferenceEngine.State.ModelReady) {
                "Benchmark request discarded due to: $state"
            }
            Log.i(TAG, "Start benchmark (pp: $pp, tg: $tg, pl: $pl, nr: $nr)")
            _readyForSystemPrompt = false   // Just to be safe
            _state.value = InferenceEngine.State.Benchmarking
            benchModel(pp, tg, pl, nr).also {
                _state.value = InferenceEngine.State.ModelReady
            }
        }

                is InferenceEngine.State.Error -> {
                    Log.i(TAG, "Resetting error states...")
                    _state.value = InferenceEngine.State.Initialized
                    Log.i(TAG, "States reset!")
                    Unit
                }
"""
        interface = """interface InferenceEngine {
    suspend fun bench(pp: Int, tg: Int, pl: Int, nr: Int = 1): String

    /**
     * Unloads the currently loaded model.
     */
    fun cleanUp()
}
"""
        with tempfile.TemporaryDirectory() as directory:
            impl_path = Path(directory) / "InferenceEngineImpl.kt"
            interface_path = Path(directory) / "InferenceEngine.kt"
            impl_path.write_text(implementation, encoding="utf-8")
            interface_path.write_text(interface, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(impl_path), str(interface_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            patched = impl_path.read_text(encoding="utf-8")
            patched_interface = interface_path.read_text(encoding="utf-8")

        self.assertIn("Native library initialization failed:", patched)
        self.assertIn("Native llama.cpp model load failed with code ", patched)
        self.assertIn("Native llama.cpp context preparation failed with code ", patched)
        self.assertIn("Native llama.cpp user prompt failed with code ", patched)
        self.assertIn("nativeRuntimeDiagnostics()", patched)
        self.assertIn("override fun runtimeDiagnostics(): String", patched)
        self.assertIn("Unloading native resources after error...", patched)
        self.assertNotIn("Failed to process user prompt: $result", patched)
        self.assertNotIn("return@flow", patched)
        self.assertEqual(
            patched_interface.count("fun runtimeDiagnostics(): String"),
            1,
        )


if __name__ == "__main__":
    unittest.main()
