import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String shell;
  late String section;
  late String screen;
  late String webEmbed;

  setUpAll(() {
    shell = File('lib/app/pandora_chat_shell.dart').readAsStringSync();
    section =
        File('lib/features/simple/enterprise_section_screen.dart').readAsStringSync();
    screen =
        File('lib/features/enterprise/enterprise_vision_screen.dart').readAsStringSync();
    webEmbed =
        File('lib/features/enterprise/enterprise_vision_embed_web.dart')
            .readAsStringSync();
  });

  test('Vision Intelligence is first-class Enterprise navigation', () {
    expect(shell, contains("'Vision Intelligence'"));
    expect(shell, contains("28 => 'enterprise_vision'"));
    expect(shell, contains("28 => '/enterprise/vision'"));
    expect(
      shell,
      contains(
        'const ownerIndexes = <int>[8, 23, 28, 24, 9, 25, 26, 27, 21];',
      ),
    );
    expect(section, contains("surface == 'enterprise_vision'"));
    expect(section, contains('EnterpriseVisionScreen'));
  });

  test('public demo uses the permitted World Port Cams embed', () {
    expect(
      webEmbed,
      contains(
        'https://worldportcams.com/embed/usa/florida/courtyard-key-largo',
      ),
    );
    expect(webEmbed, contains('allowfullscreen'));
    expect(screen, contains('World Port Cams'));
    expect(screen, contains('Powered-by attribution remains visible'));
  });

  test('public feed never claims automated analysis', () {
    expect(screen, contains('AI analysis'));
    expect(screen, contains('Off for public demo'));
    expect(screen, contains('Biometrics'));
    expect(screen, contains('Pandora retention'));
    expect(screen, contains('None'));
    expect(
      screen,
      contains('Automated analysis is deliberately disabled for this public demo feed.'),
    );
  });

  test('authorized camera capability is described without synthetic detections', () {
    expect(screen, contains('Search footage'));
    expect(screen, contains('Detect & review'));
    expect(screen, contains('Build timelines'));
    expect(screen, contains('Extract clips'));
    expect(screen, contains('Operational alerts'));
    expect(screen, contains('Pandora Chat'));
    expect(screen, isNot(contains('People detected:')));
    expect(screen, isNot(contains('Boats detected:')));
  });
}
