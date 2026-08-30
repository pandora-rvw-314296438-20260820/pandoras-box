#!/usr/bin/env python3
"""Apply the bounded Android identity used by Pandora validation builds."""

from __future__ import annotations

import hashlib
import shutil
import sys
from pathlib import Path


_GENERATED_LABEL = 'android:label="pandora_mobile"'
_VALIDATION_LABEL = 'android:label="Pandora"'
_GENERATED_ICON = 'android:icon="@mipmap/ic_launcher"'
_PANDORA_ICON = 'android:icon="@drawable/pandora_launcher_icon"'
_MANIFEST_OPEN = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
_INTERNET_PERMISSION_NAME = 'android.permission.INTERNET'
_INTERNET_PERMISSION = '<uses-permission android:name="android.permission.INTERNET"/>'
_CANONICAL_MARK_SHA256 = (
    '8a35b74baec47b960a42bb74587f9c531d6cbf8d45f16061836a9e63f00efcc5'
)
_SOURCE_MARK = (
    Path(__file__).resolve().parents[1]
    / 'assets'
    / 'brand'
    / 'pandora-product-mark-ui-1024.png'
)
_LAUNCHER_ICON_XML = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item
        android:left="12dp"
        android:top="12dp"
        android:right="12dp"
        android:bottom="12dp">
        <bitmap
            android:src="@drawable/pandora_product_mark"
            android:gravity="center"
            android:tint="#FF171717" />
    </item>
</layer-list>
'''


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _write_launcher_icon(manifest: Path) -> tuple[Path, Path]:
    if not _SOURCE_MARK.is_file() or _sha256(_SOURCE_MARK) != _CANONICAL_MARK_SHA256:
        raise RuntimeError('Canonical Pandora spiral mark is missing or changed.')

    resource_root = manifest.parent / 'res'
    drawable_dir = resource_root / 'drawable'
    nodpi_dir = resource_root / 'drawable-nodpi'
    drawable_dir.mkdir(parents=True, exist_ok=True)
    nodpi_dir.mkdir(parents=True, exist_ok=True)

    mark = nodpi_dir / 'pandora_product_mark.png'
    shutil.copyfile(_SOURCE_MARK, mark)
    icon = drawable_dir / 'pandora_launcher_icon.xml'
    icon.write_text(_LAUNCHER_ICON_XML, encoding='utf-8')
    return icon, mark


def configure_manifest(manifest: Path) -> int:
    if not manifest.is_file():
        print(f'Android manifest not found: {manifest}', file=sys.stderr)
        return 2

    text = manifest.read_text(encoding='utf-8')
    if text.count(_GENERATED_LABEL) != 1:
        print(
            'Expected exactly one generated pandora_mobile application label; '
            'refusing an ambiguous manifest mutation.',
            file=sys.stderr,
        )
        return 1
    if text.count(_GENERATED_ICON) != 1:
        print(
            'Expected exactly one generated Flutter launcher icon reference; '
            'refusing an ambiguous icon mutation.',
            file=sys.stderr,
        )
        return 1
    if 'android:usesCleartextTraffic="true"' in text:
        print(
            'Pandora validation builds must not explicitly enable cleartext traffic.',
            file=sys.stderr,
        )
        return 1

    internet_mentions = text.count(_INTERNET_PERMISSION_NAME)
    if internet_mentions > 1:
        print(
            'Expected at most one Android INTERNET permission; refusing an '
            'ambiguous manifest mutation.',
            file=sys.stderr,
        )
        return 1
    if internet_mentions == 1 and _INTERNET_PERMISSION not in text:
        print(
            'Android INTERNET permission exists in an unexpected form; refusing '
            'to rewrite it implicitly.',
            file=sys.stderr,
        )
        return 1

    updated = text.replace(_GENERATED_LABEL, _VALIDATION_LABEL, 1)
    updated = updated.replace(_GENERATED_ICON, _PANDORA_ICON, 1)
    if internet_mentions == 0:
        if updated.count(_MANIFEST_OPEN) != 1:
            print(
                'Expected exactly one generated Android manifest root; refusing '
                'an ambiguous permission mutation.',
                file=sys.stderr,
            )
            return 1
        updated = updated.replace(
            _MANIFEST_OPEN,
            f'{_MANIFEST_OPEN}\n    {_INTERNET_PERMISSION}',
            1,
        )

    manifest.write_text(updated, encoding='utf-8')
    try:
        launcher_icon, copied_mark = _write_launcher_icon(manifest)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1

    verified = manifest.read_text(encoding='utf-8')
    if verified.count(_VALIDATION_LABEL) != 1 or _GENERATED_LABEL in verified:
        print('Android validation identity verification failed.', file=sys.stderr)
        return 1
    if verified.count(_PANDORA_ICON) != 1 or _GENERATED_ICON in verified:
        print('Android Pandora launcher icon verification failed.', file=sys.stderr)
        return 1
    if verified.count(_INTERNET_PERMISSION_NAME) != 1:
        print('Android INTERNET permission verification failed.', file=sys.stderr)
        return 1
    if _INTERNET_PERMISSION not in verified:
        print('Android INTERNET permission is not in the approved form.', file=sys.stderr)
        return 1

    icon_text = launcher_icon.read_text(encoding='utf-8')
    for required in ('@drawable/pandora_product_mark', '#FF171717'):
        if required not in icon_text:
            print('Android Pandora launcher artwork verification failed.', file=sys.stderr)
            return 1
    if _sha256(copied_mark) != _CANONICAL_MARK_SHA256:
        print('Android Pandora spiral mark digest verification failed.', file=sys.stderr)
        return 1

    print('Configured Android application label: Pandora')
    print('Configured Android launcher icon: canonical Pandora spiral apple')
    print('Configured Android permission: android.permission.INTERNET')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(
            'usage: configure_validation_android.py <AndroidManifest.xml>',
            file=sys.stderr,
        )
        return 2
    return configure_manifest(Path(sys.argv[1]))


if __name__ == '__main__':
    raise SystemExit(main())
