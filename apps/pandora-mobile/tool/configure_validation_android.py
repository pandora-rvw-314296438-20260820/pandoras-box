#!/usr/bin/env python3
"""Apply the bounded Android identity used by Pandora validation builds."""

from __future__ import annotations

import sys
from pathlib import Path


_GENERATED_LABEL = 'android:label="pandora_mobile"'
_VALIDATION_LABEL = 'android:label="Pandora"'
_MANIFEST_OPEN = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
_INTERNET_PERMISSION_NAME = 'android.permission.INTERNET'
_INTERNET_PERMISSION = (
    '<uses-permission android:name="android.permission.INTERNET"/>'
)


def configure_manifest(manifest: Path) -> int:
    if not manifest.is_file():
        print(f"Android manifest not found: {manifest}", file=sys.stderr)
        return 2

    text = manifest.read_text(encoding="utf-8")

    if text.count(_GENERATED_LABEL) != 1:
        print(
            "Expected exactly one generated pandora_mobile application label; "
            "refusing an ambiguous manifest mutation.",
            file=sys.stderr,
        )
        return 1

    if 'android:usesCleartextTraffic="true"' in text:
        print(
            "Pandora validation builds must not explicitly enable cleartext "
            "traffic.",
            file=sys.stderr,
        )
        return 1

    internet_mentions = text.count(_INTERNET_PERMISSION_NAME)
    if internet_mentions > 1:
        print(
            "Expected at most one Android INTERNET permission; refusing an "
            "ambiguous manifest mutation.",
            file=sys.stderr,
        )
        return 1
    if internet_mentions == 1 and _INTERNET_PERMISSION not in text:
        print(
            "Android INTERNET permission exists in an unexpected form; refusing "
            "to rewrite it implicitly.",
            file=sys.stderr,
        )
        return 1

    updated = text.replace(_GENERATED_LABEL, _VALIDATION_LABEL, 1)
    if internet_mentions == 0:
        if updated.count(_MANIFEST_OPEN) != 1:
            print(
                "Expected exactly one generated Android manifest root; refusing "
                "an ambiguous permission mutation.",
                file=sys.stderr,
            )
            return 1
        updated = updated.replace(
            _MANIFEST_OPEN,
            f"{_MANIFEST_OPEN}\n    {_INTERNET_PERMISSION}",
            1,
        )

    manifest.write_text(updated, encoding="utf-8")

    verified = manifest.read_text(encoding="utf-8")
    if verified.count(_VALIDATION_LABEL) != 1 or _GENERATED_LABEL in verified:
        print("Android validation identity verification failed.", file=sys.stderr)
        return 1
    if verified.count(_INTERNET_PERMISSION_NAME) != 1:
        print("Android INTERNET permission verification failed.", file=sys.stderr)
        return 1
    if _INTERNET_PERMISSION not in verified:
        print("Android INTERNET permission is not in the approved form.", file=sys.stderr)
        return 1

    print("Configured Android application label: Pandora")
    print("Configured Android permission: android.permission.INTERNET")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: configure_validation_android.py <AndroidManifest.xml>",
            file=sys.stderr,
        )
        return 2

    return configure_manifest(Path(sys.argv[1]))


if __name__ == "__main__":
    raise SystemExit(main())
