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
_NETWORK_PERMISSION_NAME = 'android.permission.ACCESS_NETWORK_STATE'
_NETWORK_PERMISSION = '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>'
_CALL_PERMISSION_NAME = 'android.permission.CALL_PHONE'
_CALL_PERMISSION = '<uses-permission android:name="android.permission.CALL_PHONE"/>'
_SMS_PERMISSION_NAME = 'android.permission.SEND_SMS'
_SMS_PERMISSION = '<uses-permission android:name="android.permission.SEND_SMS"/>'
_CONTACTS_PERMISSION_NAME = 'android.permission.READ_CONTACTS'
_CONTACTS_PERMISSION = '<uses-permission android:name="android.permission.READ_CONTACTS"/>'
_GENERATED_LAUNCH_MODE = 'android:launchMode="singleTop"'
_HOME_LAUNCH_MODE = 'android:launchMode="singleTask"'
_GENERATED_EMPTY_TASK_AFFINITY = 'android:taskAffinity=""'
_M4_018_PERMISSIONS = (
    ("android.permission.READ_CALENDAR", '<uses-permission android:name="android.permission.READ_CALENDAR"/>'),
    ("android.permission.WRITE_CALENDAR", '<uses-permission android:name="android.permission.WRITE_CALENDAR"/>'),
    ("android.permission.POST_NOTIFICATIONS", '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>'),
    ("android.permission.SCHEDULE_EXACT_ALARM", '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>'),
)
_REMINDER_RECEIVER_NAME = '.PandoraLocalReminderReceiver'
_REMINDER_RECEIVER = '        <receiver android:name=".PandoraLocalReminderReceiver" android:exported="false"/>'
_SMS_STATUS_RECEIVER_NAME = '.PandoraSmsStatusReceiver'
_SMS_STATUS_RECEIVER = '        <receiver android:name=".PandoraSmsStatusReceiver" android:exported="false"/>'
_APPLICATION_CLOSE = '    </application>'
_HOME_CATEGORY = 'android.intent.category.HOME'
_DEFAULT_CATEGORY = 'android.intent.category.DEFAULT'
_LAUNCHER_CATEGORY = 'android.intent.category.LAUNCHER'
_LAUNCHER_FILTER = '''            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>'''
_HOME_FILTER = '''            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.HOME"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>'''
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

    network_mentions = text.count(_NETWORK_PERMISSION_NAME)
    if network_mentions > 1:
        print(
            'Expected at most one Android ACCESS_NETWORK_STATE permission; refusing an '
            'ambiguous manifest mutation.',
            file=sys.stderr,
        )
        return 1
    if network_mentions == 1 and _NETWORK_PERMISSION not in text:
        print(
            'Android ACCESS_NETWORK_STATE permission exists in an unexpected form; '
            'refusing to rewrite it implicitly.',
            file=sys.stderr,
        )
        return 1

    for permission_name, permission_xml in _M4_018_PERMISSIONS:
        mentions = text.count(permission_name)
        if mentions > 1:
            print(
                f'Expected at most one Android {permission_name} permission; refusing an ambiguous manifest mutation.',
                file=sys.stderr,
            )
            return 1
        if mentions == 1 and permission_xml not in text:
            print(
                f'Android {permission_name} permission exists in an unexpected form; refusing to rewrite it implicitly.',
                file=sys.stderr,
            )
            return 1
    if text.count(_REMINDER_RECEIVER_NAME) != 0:
        print(
            'Generated Android manifest already declares the Pandora reminder receiver; refusing an ambiguous receiver mutation.',
            file=sys.stderr,
        )
        return 1

    for permission_name, permission_xml, label in (( _CALL_PERMISSION_NAME, _CALL_PERMISSION, 'CALL_PHONE'), (_SMS_PERMISSION_NAME, _SMS_PERMISSION, 'SEND_SMS'), (_CONTACTS_PERMISSION_NAME, _CONTACTS_PERMISSION, 'READ_CONTACTS')):
        mentions = text.count(permission_name)
        if mentions > 1:
            print(f'Expected at most one Android {label} permission; refusing an ambiguous manifest mutation.', file=sys.stderr)
            return 1
        if mentions == 1 and permission_xml not in text:
            print(f'Android {label} permission exists in an unexpected form; refusing to rewrite it implicitly.', file=sys.stderr)
            return 1
    if text.count(_SMS_STATUS_RECEIVER_NAME) != 0:
        print('Generated Android manifest already declares the Pandora SMS status receiver; refusing an ambiguous receiver mutation.', file=sys.stderr)
        return 1

    if text.count(_HOME_CATEGORY) != 0 or text.count(_DEFAULT_CATEGORY) != 0:
        print(
            'Generated Android manifest already declares HOME/DEFAULT routing; '
            'refusing an ambiguous launcher mutation.',
            file=sys.stderr,
        )
        return 1
    if text.count(_LAUNCHER_FILTER) != 1:
        print(
            'Expected exactly one generated Flutter launcher intent filter; '
            'refusing an ambiguous HOME mutation.',
            file=sys.stderr,
        )
        return 1

    if text.count(_GENERATED_LAUNCH_MODE) != 1:
        print('Expected exactly one generated singleTop launch mode; refusing an ambiguous HOME task mutation.', file=sys.stderr)
        return 1
    if text.count(_GENERATED_EMPTY_TASK_AFFINITY) != 1:
        print('Expected exactly one generated empty task affinity; refusing an ambiguous HOME task mutation.', file=sys.stderr)
        return 1

    updated = text.replace(_GENERATED_LABEL, _VALIDATION_LABEL, 1)
    updated = updated.replace(_GENERATED_LAUNCH_MODE, _HOME_LAUNCH_MODE, 1)
    updated = updated.replace(f' {_GENERATED_EMPTY_TASK_AFFINITY}', '', 1)
    updated = updated.replace(_GENERATED_ICON, _PANDORA_ICON, 1)
    updated = updated.replace(
        _LAUNCHER_FILTER,
        f'{_LAUNCHER_FILTER}\n{_HOME_FILTER}',
        1,
    )
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

    if network_mentions == 0:
        if updated.count(_MANIFEST_OPEN) != 1:
            print(
                'Expected exactly one generated Android manifest root; refusing '
                'an ambiguous network permission mutation.',
                file=sys.stderr,
            )
            return 1
        updated = updated.replace(
            _MANIFEST_OPEN,
            f'{_MANIFEST_OPEN}\n    {_NETWORK_PERMISSION}',
            1,
        )

    for permission_name, permission_xml in _M4_018_PERMISSIONS:
        if text.count(permission_name) == 0:
            if updated.count(_MANIFEST_OPEN) != 1:
                print(
                    'Expected exactly one generated Android manifest root; refusing an ambiguous M4-018 permission mutation.',
                    file=sys.stderr,
                )
                return 1
            updated = updated.replace(
                _MANIFEST_OPEN,
                f'{_MANIFEST_OPEN}\n    {permission_xml}',
                1,
            )

    for permission_name, permission_xml in ((_CALL_PERMISSION_NAME, _CALL_PERMISSION), (_SMS_PERMISSION_NAME, _SMS_PERMISSION), (_CONTACTS_PERMISSION_NAME, _CONTACTS_PERMISSION)):
        if text.count(permission_name) == 0:
            if updated.count(_MANIFEST_OPEN) != 1:
                print('Expected exactly one generated Android manifest root; refusing an ambiguous communication permission mutation.', file=sys.stderr)
                return 1
            updated = updated.replace(_MANIFEST_OPEN, f'{_MANIFEST_OPEN}\n    {permission_xml}', 1)

    if updated.count(_APPLICATION_CLOSE) != 1:
        print(
            'Expected exactly one generated Android application close tag; refusing an ambiguous reminder receiver mutation.',
            file=sys.stderr,
        )
        return 1
    updated = updated.replace(
        _APPLICATION_CLOSE,
        f'{_REMINDER_RECEIVER}\n{_SMS_STATUS_RECEIVER}\n{_APPLICATION_CLOSE}',
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
    if verified.count(_NETWORK_PERMISSION_NAME) != 1:
        print('Android ACCESS_NETWORK_STATE permission verification failed.', file=sys.stderr)
        return 1
    if _NETWORK_PERMISSION not in verified:
        print('Android ACCESS_NETWORK_STATE permission is not in the approved form.', file=sys.stderr)
        return 1
    for permission_name, permission_xml in _M4_018_PERMISSIONS:
        if verified.count(permission_name) != 1 or permission_xml not in verified:
            print(
                f'Android {permission_name} permission verification failed.',
                file=sys.stderr,
            )
            return 1
    for permission_name, permission_xml, label in ((_CALL_PERMISSION_NAME, _CALL_PERMISSION, 'CALL_PHONE'), (_SMS_PERMISSION_NAME, _SMS_PERMISSION, 'SEND_SMS'), (_CONTACTS_PERMISSION_NAME, _CONTACTS_PERMISSION, 'READ_CONTACTS')):
        if verified.count(permission_name) != 1 or permission_xml not in verified:
            print(f'Android {label} permission verification failed.', file=sys.stderr)
            return 1
    if verified.count(_SMS_STATUS_RECEIVER_NAME) != 1 or _SMS_STATUS_RECEIVER not in verified:
        print('Android Pandora SMS status receiver verification failed.', file=sys.stderr)
        return 1
    if verified.count(_REMINDER_RECEIVER_NAME) != 1 or _REMINDER_RECEIVER not in verified:
        print('Android local reminder receiver verification failed.', file=sys.stderr)
        return 1
    if verified.count(_HOME_CATEGORY) != 1:
        print('Android HOME eligibility verification failed.', file=sys.stderr)
        return 1
    if verified.count(_DEFAULT_CATEGORY) != 1:
        print('Android HOME DEFAULT category verification failed.', file=sys.stderr)
        return 1
    if verified.count(_LAUNCHER_CATEGORY) != 1:
        print('Android launcher recovery entry verification failed.', file=sys.stderr)
        return 1
    if verified.count(_HOME_LAUNCH_MODE) != 1 or _GENERATED_LAUNCH_MODE in verified:
        print('Android HOME task launch-mode verification failed.', file=sys.stderr)
        return 1
    if _GENERATED_EMPTY_TASK_AFFINITY in verified:
        print('Android HOME task affinity verification failed.', file=sys.stderr)
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
    print('Configured Android permission: android.permission.ACCESS_NETWORK_STATE')
    print('Configured Android permission: android.permission.CALL_PHONE')
    print('Configured Android permission: android.permission.SEND_SMS')
    print('Configured Android permission: android.permission.READ_CONTACTS')
    print('Configured Android HOME root task: singleTask with normal app affinity')
    print('Configured Android SMS callback receiver: non-exported')
    print('Configured Android permission: android.permission.READ_CALENDAR')
    print('Configured Android permission: android.permission.WRITE_CALENDAR')
    print('Configured Android permission: android.permission.POST_NOTIFICATIONS')
    print('Configured Android special access declaration: android.permission.SCHEDULE_EXACT_ALARM')
    print('Configured Android local reminder receiver: non-exported')
    print('Configured Android HOME eligibility without forcing default HOME')
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
