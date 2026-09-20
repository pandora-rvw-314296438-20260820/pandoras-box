#!/usr/bin/env python3
"""Configure the disposable Flutter Android project for pinned local AI."""

from __future__ import annotations

import sys
from pathlib import Path

_GENERATED_NDK = '    ndkVersion = flutter.ndkVersion'
_PINNED_NDK = '    ndkVersion = "29.0.13113456"'
_VERSION_ANCHOR = '''        versionCode = flutter.versionCode
        versionName = flutter.versionName
'''
_NATIVE_DEFAULT = '''        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DBUILD_SHARED_LIBS=ON",
                    "-DLLAMA_BUILD_APP=OFF",
                    "-DLLAMA_BUILD_COMMON=ON",
                    "-DLLAMA_OPENSSL=OFF",
                    "-DGGML_NATIVE=OFF",
                    "-DGGML_BACKEND_DL=OFF",
                    "-DGGML_CPU_ALL_VARIANTS=OFF",
                    "-DGGML_VULKAN=ON",
                    "-DGGML_LLAMAFILE=OFF",
                )
            }
        }
'''
_BUILD_TYPES_CLOSE = '''    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'''
_NATIVE_BUILD_CLOSE = '''    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }
}
'''
_FLUTTER_ANCHOR = '''flutter {
    source = "../.."
}
'''
_DEPENDENCIES = '''dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

flutter {
    source = "../.."
}
'''
_DISABLE_FLUTTER_ABI_FILTERING = "disable-abi-filtering=true"


def configure(path: Path) -> int:
    if not path.is_file():
        print(f"Android app Gradle file not found: {path}", file=sys.stderr)
        return 2

    text = path.read_text(encoding="utf-8")
    requirements = (
        (_GENERATED_NDK, 1, "generated Flutter NDK declaration"),
        (_VERSION_ANCHOR, 1, "Flutter version anchor"),
        (_BUILD_TYPES_CLOSE, 1, "generated build-types block"),
        (_FLUTTER_ANCHOR, 1, "Flutter source block"),
    )
    for needle, expected, label in requirements:
        if text.count(needle) != expected:
            print(f"Expected exactly one {label}.", file=sys.stderr)
            return 1

    updated = text.replace(_GENERATED_NDK, _PINNED_NDK, 1)
    updated = updated.replace(_VERSION_ANCHOR, _NATIVE_DEFAULT, 1)
    updated = updated.replace(_BUILD_TYPES_CLOSE, _NATIVE_BUILD_CLOSE, 1)
    updated = updated.replace(_FLUTTER_ANCHOR, _DEPENDENCIES, 1)
    path.write_text(updated, encoding="utf-8")

    verified = path.read_text(encoding="utf-8")
    required = (
        'ndkVersion = "29.0.13113456"',
        'abiFilters.clear()',
        'abiFilters += "arm64-v8a"',
        'path = file("src/main/cpp/CMakeLists.txt")',
        'version = "3.31.6"',
        'kotlinx-coroutines-android:1.10.2',
        '-DGGML_BACKEND_DL=OFF',
        '-DGGML_CPU_ALL_VARIANTS=OFF',
        '-DGGML_VULKAN=ON',
    )
    if any(item not in verified for item in required):
        print("Pandora local-AI Gradle verification failed.", file=sys.stderr)
        return 1

    print("Configured pinned Pandora local-AI Android native build with Vulkan + CPU fallback.")
    return 0


def configure_properties(path: Path) -> int:
    if not path.is_file():
        print(f"Android Gradle properties file not found: {path}", file=sys.stderr)
        return 2

    lines = path.read_text(encoding="utf-8").splitlines()
    existing = [
        line.strip()
        for line in lines
        if line.strip().startswith("disable-abi-filtering=")
    ]
    if existing and existing != [_DISABLE_FLUTTER_ABI_FILTERING]:
        print(
            "Flutter ABI-filtering property exists in an unexpected form.",
            file=sys.stderr,
        )
        return 1
    if not existing:
        with path.open("a", encoding="utf-8") as stream:
            if lines:
                stream.write("\n")
            stream.write(f"{_DISABLE_FLUTTER_ABI_FILTERING}\n")

    verified = path.read_text(encoding="utf-8").splitlines()
    if verified.count(_DISABLE_FLUTTER_ABI_FILTERING) != 1:
        print("Flutter ABI-filtering override verification failed.", file=sys.stderr)
        return 1

    print("Preserved Pandora arm64-only ABI filter from Flutter defaults.")
    return 0


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            "usage: configure_local_ai_android.py "
            "<android/app/build.gradle.kts> [android/gradle.properties]",
            file=sys.stderr,
        )
        return 2

    status = configure(Path(sys.argv[1]))
    if status != 0 or len(sys.argv) == 2:
        return status
    return configure_properties(Path(sys.argv[2]))


if __name__ == "__main__":
    raise SystemExit(main())
