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


def patch(path: Path) -> int:
    if not path.is_file():
        print(f"InferenceEngineImpl.kt not found: {path}", file=sys.stderr)
        return 2

    text = path.read_text(encoding="utf-8")

    init_old = '''            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library", e)
                throw e
            }
'''
    init_new = '''            } catch (throwable: Throwable) {
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
'''

    load_old = '''                load(pathToModel).let {
                    // TODO-han.yin: find a better way to pass other error codes
                    if (it != 0) throw UnsupportedArchitectureException()
                }
                prepare().let {
                    if (it != 0) throw IOException("Failed to prepare resources")
                }
'''
    load_new = '''                load(pathToModel).let { code ->
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
'''

    try:
        text = replace_exact(
            text,
            init_old,
            init_new,
            "native initialization catch block",
        )
        text = replace_exact(
            text,
            load_old,
            load_new,
            "native model load/prepare block",
        )
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    path.write_text(text, encoding="utf-8")

    verified = path.read_text(encoding="utf-8")
    required = (
        "Native library initialization failed:",
        "Native llama.cpp model load failed with code ",
        "Native llama.cpp context preparation failed with code ",
        "_state.value = InferenceEngine.State.Error(error)",
    )
    if any(item not in verified for item in required):
        print("Patched InferenceEngineImpl.kt verification failed.", file=sys.stderr)
        return 1

    print("Patched pinned llama.cpp Android wrapper with explicit native diagnostics.")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: patch_inference_engine_android.py <InferenceEngineImpl.kt>",
            file=sys.stderr,
        )
        return 2
    return patch(Path(sys.argv[1]))


if __name__ == "__main__":
    raise SystemExit(main())
