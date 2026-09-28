#!/usr/bin/env python3
"""Configure the disposable Flutter Android project as dedicated Euro-Fish Enterprise."""

from __future__ import annotations

import sys
from pathlib import Path

_GENERIC_PACKAGE = "com.banataosystems.pandora_mobile"
_EUROFISH_PACKAGE = "com.banataosystems.pandora.eurofish"
_GENERIC_LABEL = 'android:label="Pandora"'
_EUROFISH_LABEL = 'android:label="Euro-Fish Pandora Enterprise"'


def _replace_exact(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"Expected exactly one {label}; found {text.count(old)}.")
    return text.replace(old, new, 1)


def configure(gradle: Path, manifest: Path, kotlin_root: Path) -> int:
    if not gradle.is_file():
        print(f"Android Gradle file not found: {gradle}", file=sys.stderr)
        return 2
    if not manifest.is_file():
        print(f"Android manifest not found: {manifest}", file=sys.stderr)
        return 2
    if not kotlin_root.is_dir():
        print(f"Android Kotlin root not found: {kotlin_root}", file=sys.stderr)
        return 2

    try:
        gradle_text = gradle.read_text(encoding="utf-8")
        gradle_text = _replace_exact(
            gradle_text,
            f'namespace = "{_GENERIC_PACKAGE}"',
            f'namespace = "{_EUROFISH_PACKAGE}"',
            "generated Android namespace",
        )
        gradle_text = _replace_exact(
            gradle_text,
            f'applicationId = "{_GENERIC_PACKAGE}"',
            f'applicationId = "{_EUROFISH_PACKAGE}"',
            "generated Android applicationId",
        )
        gradle.write_text(gradle_text, encoding="utf-8")

        manifest_text = manifest.read_text(encoding="utf-8")
        manifest_text = _replace_exact(
            manifest_text,
            _GENERIC_LABEL,
            _EUROFISH_LABEL,
            "Pandora validation application label",
        )
        manifest.write_text(manifest_text, encoding="utf-8")
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    kotlin_files = sorted(kotlin_root.rglob("*.kt"))
    pandora_files = []
    for path in kotlin_files:
        text = path.read_text(encoding="utf-8")
        if _GENERIC_PACKAGE not in text:
            continue
        path.write_text(
            text.replace(_GENERIC_PACKAGE, _EUROFISH_PACKAGE),
            encoding="utf-8",
        )
        pandora_files.append(path)

    if not pandora_files:
        print("No Pandora Kotlin package declarations were found to retarget.", file=sys.stderr)
        return 1

    gradle_verified = gradle.read_text(encoding="utf-8")
    manifest_verified = manifest.read_text(encoding="utf-8")
    if _GENERIC_PACKAGE in gradle_verified:
        print("Generic Pandora Android package remains in Gradle.", file=sys.stderr)
        return 1
    if f'namespace = "{_EUROFISH_PACKAGE}"' not in gradle_verified:
        print("Euro-Fish Android namespace verification failed.", file=sys.stderr)
        return 1
    if f'applicationId = "{_EUROFISH_PACKAGE}"' not in gradle_verified:
        print("Euro-Fish Android applicationId verification failed.", file=sys.stderr)
        return 1
    if _EUROFISH_LABEL not in manifest_verified or _GENERIC_LABEL in manifest_verified:
        print("Euro-Fish Android application label verification failed.", file=sys.stderr)
        return 1

    for path in pandora_files:
        if _GENERIC_PACKAGE in path.read_text(encoding="utf-8"):
            print(f"Generic Pandora package remains in {path}.", file=sys.stderr)
            return 1

    print(f"Configured dedicated Euro-Fish Android package: {_EUROFISH_PACKAGE}")
    print("Configured dedicated Euro-Fish Android label: Euro-Fish Pandora Enterprise")
    print(f"Retargeted {len(pandora_files)} Pandora Kotlin source files.")
    return 0


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: configure_eurofish_android.py "
            "<android/app/build.gradle.kts> "
            "<android/app/src/main/AndroidManifest.xml> "
            "<android/app/src/main/kotlin>",
            file=sys.stderr,
        )
        return 2
    return configure(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))


if __name__ == "__main__":
    raise SystemExit(main())
