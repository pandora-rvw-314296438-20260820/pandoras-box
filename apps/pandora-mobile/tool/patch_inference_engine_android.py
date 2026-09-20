#!/usr/bin/env python3
"""Patch the pinned llama.cpp Android wrapper with fail-closed diagnostics."""

from __future__ import annotations

import sys
from pathlib import Path


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"Expected exactly one {label}; found {count}.")
    return text.replace(old, new, 1)


def patch_impl(path: Path) -> int:
    if not path.is_file():
        print(f"InferenceEngineImpl.kt not found: {path}", file=sys.stderr)
        return 2

    text = path.read_text(encoding="utf-8")

    init_old = """            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library", e)
                throw e
            }
"""
    init_new = """            } catch (throwable: Throwable) {
                val error =
                    if (throwable is Exception) {
                        throwable
                    } else {
                        RuntimeException(
                            "Native library initialization failed: " +
                                throwable.javaClass.simpleName +
                                ": " +
                                (throwable.message ?: "no message"),
                            throwable,
                        )
                    }
                _state.value = InferenceEngine.State.Error(error)
                Log.e(TAG, "Failed to load native library", throwable)
            }
"""

    load_old = """                load(pathToModel).let {
                    // TODO-han.yin: find a better way to pass other error codes
                    if (it != 0) throw UnsupportedArchitectureException()
                }
                prepare().let {
                    if (it != 0) throw IOException("Failed to prepare resources")
                }
"""
    load_new = """                load(pathToModel).let { code ->
                    if (code != 0) {
                        throw IOException(
                            "Native llama.cpp model load failed with code " + code,
                        )
                    }
                }
                prepare().let { code ->
                    if (code != 0) {
                        throw IOException(
                            "Native llama.cpp context preparation failed with code " + code,
                        )
                    }
                }
"""

    native_anchor = """    @FastNative
    private external fun generateNextToken(): String?

    @FastNative
    private external fun unload()
"""
    native_replacement = """    @FastNative
    private external fun generateNextToken(): String?

    @FastNative
    private external fun nativeRuntimeDiagnostics(): String

    @FastNative
    private external fun unload()
"""

    user_prompt_old = """            processUserPrompt(message, predictLength).let { result ->
                if (result != 0) {
                    Log.e(TAG, "Failed to process user prompt: $result")
                    return@flow
                }
            }
"""
    user_prompt_new = """            processUserPrompt(message, predictLength).let { result ->
                if (result != 0) {
                    throw RuntimeException(
                        "Native llama.cpp user prompt failed with code $result",
                    )
                }
            }
"""

    bench_anchor = """    override suspend fun bench(pp: Int, tg: Int, pl: Int, nr: Int): String =
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
"""
    bench_replacement = bench_anchor + """
    override fun runtimeDiagnostics(): String = nativeRuntimeDiagnostics()
"""

    try:
        text = replace_exact(text, init_old, init_new, "native initialization catch block")
        text = replace_exact(text, load_old, load_new, "native model load/prepare block")
        text = replace_exact(text, native_anchor, native_replacement, "native diagnostics declaration anchor")
        text = replace_exact(text, user_prompt_old, user_prompt_new, "user prompt fail-closed block")
        text = replace_exact(text, bench_anchor, bench_replacement, "benchmark implementation")
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    path.write_text(text, encoding="utf-8")

    verified = path.read_text(encoding="utf-8")
    required = (
        "Native library initialization failed:",
        "Native llama.cpp model load failed with code ",
        "Native llama.cpp context preparation failed with code ",
        "Native llama.cpp user prompt failed with code ",
        "nativeRuntimeDiagnostics()",
        "override fun runtimeDiagnostics(): String",
        "_state.value = InferenceEngine.State.Error(error)",
    )
    if any(item not in verified for item in required):
        print("Patched InferenceEngineImpl.kt verification failed.", file=sys.stderr)
        return 1
    if "return@flow" in verified and "Failed to process user prompt" in verified:
        print("Silent user-prompt completion path remains.", file=sys.stderr)
        return 1

    print("Patched pinned llama.cpp Android wrapper with fail-loud generation diagnostics.")
    return 0


def patch_interface(path: Path) -> int:
    if not path.is_file():
        print(f"InferenceEngine.kt not found: {path}", file=sys.stderr)
        return 2

    text = path.read_text(encoding="utf-8")
    anchor = """    suspend fun bench(pp: Int, tg: Int, pl: Int, nr: Int = 1): String

    /**
     * Unloads the currently loaded model.
     */
"""
    replacement = """    suspend fun bench(pp: Int, tg: Int, pl: Int, nr: Int = 1): String

    /**
     * Returns bounded native runtime diagnostics for the currently loaded model.
     */
    fun runtimeDiagnostics(): String

    /**
     * Unloads the currently loaded model.
     */
"""
    try:
        text = replace_exact(text, anchor, replacement, "InferenceEngine diagnostics API anchor")
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    path.write_text(text, encoding="utf-8")
    if text.count("fun runtimeDiagnostics(): String") != 1:
        print("Patched InferenceEngine.kt verification failed.", file=sys.stderr)
        return 1

    print("Patched pinned llama.cpp Android interface with runtime diagnostics.")
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: patch_inference_engine_android.py "
            "<InferenceEngineImpl.kt> <InferenceEngine.kt>",
            file=sys.stderr,
        )
        return 2
    impl_status = patch_impl(Path(sys.argv[1]))
    if impl_status != 0:
        return impl_status
    return patch_interface(Path(sys.argv[2]))


if __name__ == "__main__":
    raise SystemExit(main())
