#!/usr/bin/env python3
"""Retarget the disposable PLP Android project for x86_64 emulator acceptance.

The production PLP APK remains arm64-only with the native local-AI runtime.
This helper is only for the disposable emulator candidate used to verify UI,
navigation, lifecycle, permissions, and cloud/provider fallback behavior.
"""

from __future__ import annotations

import sys
from pathlib import Path

_ARM64_FILTER = 'abiFilters += "arm64-v8a"'
_X86_FILTER = 'abiFilters += "x86_64"'
_LOCAL_AI_INIT = """        localAiChannel = PandoraLocalAiChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
"""
_LOCAL_AI_DISABLED = """        // x86_64 acceptance build: local llama.cpp is arm64-only.
        // Cloud/provider fallback remains available; production arm64 is unchanged.
        localAiChannel = null
"""


def _remove_balanced_block(text: str, marker: str) -> tuple[str, int]:
    removed = 0
    while True:
        marker_index = text.find(marker)
        if marker_index < 0:
            return text, removed

        line_start = text.rfind("\n", 0, marker_index) + 1
        brace_start = text.find("{", marker_index)
        if brace_start < 0:
            raise ValueError(f"Unbalanced block for {marker!r}.")

        depth = 0
        end = None
        for index in range(brace_start, len(text)):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            raise ValueError(f"Unbalanced block for {marker!r}.")

        while end < len(text) and text[end] in " \t":
            end += 1
        if end < len(text) and text[end] == "\n":
            end += 1

        text = text[:line_start] + text[end:]
        removed += 1


def configure(gradle: Path, kotlin_root: Path) -> int:
    if not gradle.is_file():
        print(f"Gradle file not found: {gradle}", file=sys.stderr)
        return 2
    if not kotlin_root.is_dir():
        print(f"Kotlin root not found: {kotlin_root}", file=sys.stderr)
        return 2

    text = gradle.read_text(encoding="utf-8")
    if text.count(_ARM64_FILTER) != 1:
        print("Expected exactly one arm64 ABI filter.", file=sys.stderr)
        return 1

    text = text.replace(_ARM64_FILTER, _X86_FILTER, 1)
    try:
        text, removed = _remove_balanced_block(text, "externalNativeBuild {")
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    if removed != 2:
        print(
            f"Expected two local-AI externalNativeBuild blocks; removed {removed}.",
            file=sys.stderr,
        )
        return 1
    gradle.write_text(text, encoding="utf-8")

    main_candidates = [
        path
        for path in kotlin_root.rglob("MainActivity.kt")
        if "PandoraLocalAiChannel" in path.read_text(encoding="utf-8")
    ]
    if len(main_candidates) != 1:
        print(
            "Expected exactly one Pandora MainActivity for emulator retargeting.",
            file=sys.stderr,
        )
        return 1

    main_activity = main_candidates[0]
    main_text = main_activity.read_text(encoding="utf-8")
    if main_text.count(_LOCAL_AI_INIT) != 1:
        print("Expected exactly one local-AI initialization block.", file=sys.stderr)
        return 1
    main_text = main_text.replace(_LOCAL_AI_INIT, _LOCAL_AI_DISABLED, 1)
    main_activity.write_text(main_text, encoding="utf-8")

    verified_gradle = gradle.read_text(encoding="utf-8")
    verified_main = main_activity.read_text(encoding="utf-8")
    failures = (
        _X86_FILTER not in verified_gradle,
        _ARM64_FILTER in verified_gradle,
        "externalNativeBuild {" in verified_gradle,
        _LOCAL_AI_INIT in verified_main,
        "x86_64 acceptance build: local llama.cpp is arm64-only." not in verified_main,
    )
    if any(failures):
        print("PLP x86_64 emulator configuration verification failed.", file=sys.stderr)
        return 1

    print("Configured disposable PLP x86_64 emulator candidate without arm64 local AI.")
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: configure_plp_emulator_android.py "
            "<android/app/build.gradle.kts> <android/app/src/main/kotlin>",
            file=sys.stderr,
        )
        return 2
    return configure(Path(sys.argv[1]), Path(sys.argv[2]))


if __name__ == "__main__":
    raise SystemExit(main())
