import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/pandora_config.dart';

void main() {
  test('visible owner-test version matches packaged version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    final packageVersion = versionMatch!.group(1)!;

    expect(PandoraConfig.appVersion, packageVersion);
    expect(
      PandoraConfig.releaseLabel,
      '${packageVersion.split('+').first} Owner Test',
    );
  });
}
