
#!/usr/bin/env python3
"""Apply the bounded Android identity used by Pandora validation builds."""

from __future__ import annotations

import sys
from pathlib import Path


_GENERATED_LABEL = 'android:label="pandora_mobile"'
_VALIDATION_LABEL = 'android:label="Pandora"'
_GENERATED_ICON = 'android:icon="@mipmap/ic_launcher"'
_PANDORA_ICON = 'android:icon="@drawable/pandora_launcher_icon"'
_MANIFEST_OPEN = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
_INTERNET_PERMISSION_NAME = 'android.permission.INTERNET'
_INTERNET_PERMISSION = (
    '<uses-permission android:name="android.permission.INTERNET"/>'
)
_LAUNCHER_ICON_XML = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1024"
    android:viewportHeight="1024">
    <path
        android:fillType="evenOdd"
        android:pathData="M511,326 C458,288 401,267 348,268 C244,271 170,354 164,472 C157,612 225,750 337,850 C397,904 445,934 487,932 C511,931 529,917 551,917 C576,917 595,932 619,933 C666,934 713,906 770,852 C878,752 940,614 931,478 C923,361 851,282 754,269 C689,260 632,281 573,322 C551,338 531,340 511,326 Z M986,382 A107,107 0,1 1 772,382 A107,107 0,1 1 986,382 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="180"
                android:startY="100"
                android:endX="850"
                android:endY="930">
                <item android:offset="0" android:color="#FFB72DFF" />
                <item android:offset="0.36" android:color="#FFD32BE8" />
                <item android:offset="0.70" android:color="#FF7046FF" />
                <item android:offset="1" android:color="#FF2063FF" />
            </gradient>
        </aapt:attr>
    </path>
    <path
        android:pathData="M566,247 C584,175 644,121 716,106 C713,174 677,230 619,262 C596,276 577,270 566,247 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="566"
                android:startY="106"
                android:endX="690"
                android:endY="270"
                android:startColor="#FFB72DFF"
                android:endColor="#FFD32BE8" />
        </aapt:attr>
    </path>
</vector>
'''


def _write_launcher_icon(manifest: Path) -> Path:
    drawable_dir = manifest.parent / "res" / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    icon = drawable_dir / "pandora_launcher_icon.xml"
    icon.write_text(_LAUNCHER_ICON_XML, encoding="utf-8")
    return icon


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
    if text.count(_GENERATED_ICON) != 1:
        print(
            "Expected exactly one generated Flutter launcher icon reference; "
            "refusing an ambiguous icon mutation.",
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
    updated = updated.replace(_GENERATED_ICON, _PANDORA_ICON, 1)
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
    launcher_icon = _write_launcher_icon(manifest)

    verified = manifest.read_text(encoding="utf-8")
    if verified.count(_VALIDATION_LABEL) != 1 or _GENERATED_LABEL in verified:
        print("Android validation identity verification failed.", file=sys.stderr)
        return 1
    if verified.count(_PANDORA_ICON) != 1 or _GENERATED_ICON in verified:
        print("Android Pandora launcher icon verification failed.", file=sys.stderr)
        return 1
    if verified.count(_INTERNET_PERMISSION_NAME) != 1:
        print("Android INTERNET permission verification failed.", file=sys.stderr)
        return 1
    if _INTERNET_PERMISSION not in verified:
        print("Android INTERNET permission is not in the approved form.", file=sys.stderr)
        return 1
    icon_text = launcher_icon.read_text(encoding="utf-8")
    for required in (
        'android:fillType="evenOdd"',
        '#FFB72DFF',
        '#FFD32BE8',
        '#FF7046FF',
        '#FF2063FF',
    ):
        if required not in icon_text:
            print("Android Pandora launcher artwork verification failed.", file=sys.stderr)
            return 1

    print("Configured Android application label: Pandora")
    print("Configured Android launcher icon: Pandora gradient apple")
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
