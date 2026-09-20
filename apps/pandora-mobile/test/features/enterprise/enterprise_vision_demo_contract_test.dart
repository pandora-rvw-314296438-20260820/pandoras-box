
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String shell;
  late String screen;
  late String adapter;
  late String stub;
  late String webEmbed;
  late String androidHost;

  setUpAll(() {
    shell = File('lib/app/pandora_chat_shell.dart').readAsStringSync();
    screen = File(
      'lib/features/enterprise/enterprise_vision_screen.dart',
    ).readAsStringSync();
    adapter = File(
      'lib/features/enterprise/enterprise_vision_embed.dart',
    ).readAsStringSync();
    stub = File(
      'lib/features/enterprise/enterprise_vision_embed_stub.dart',
    ).readAsStringSync();
    webEmbed = File(
      'lib/features/enterprise/enterprise_vision_embed_web.dart',
    ).readAsStringSync();
    androidHost = File(
      'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/MainActivity.kt',
    ).readAsStringSync();
  });

  test('current shell exposes Vision Intelligence without changing Batalla IA', () {
    expect(shell, contains("'Vision Intelligence'"));
    expect(shell, contains("10 => 'vision_intelligence'"));
    expect(shell, contains('10 => EnterpriseVisionScreen('));
    expect(shell, contains('for (final index in const <int>[9, 10, 0, 8, 1, 2, 4, 5, 6, 7, 3])'));
  });

  test('web uses provider-controlled CamStreamer Kabukicho embed', () {
    expect(
      webEmbed,
      contains(
        'https://camstreamer.com/embed/VSnOa4OubclxMcFKpTws6Yv7U2rt0VbMfcrHomkq?rel=0',
      ),
    );
    expect(webEmbed, contains('allowfullscreen'));
    expect(webEmbed, contains('strict-origin-when-cross-origin'));
    expect(webEmbed, isNot(contains('youtube.com/embed/')));
    expect(screen, contains('CamStreamer'));
    expect(screen, contains('LIVE KABUKICHO'));
    expect(screen, contains('Kabukicho · Shinjuku, Tokyo'));
  });

  test('Android uses a native WebView platform view for the same live feed', () {
    expect(adapter, contains("if (dart.library.html) 'enterprise_vision_embed_web.dart'"));
    expect(stub, contains("Platform.isAndroid"));
    expect(stub, contains("AndroidView"));
    expect(stub, contains("pandora/camstreamer_kabukicho"));
    expect(androidHost, contains('PandoraCamStreamerViewFactory'));
    expect(androidHost, contains('pandora/camstreamer_kabukicho'));
    expect(
      androidHost,
      contains(
        'https://camstreamer.com/embed/VSnOa4OubclxMcFKpTws6Yv7U2rt0VbMfcrHomkq?rel=0',
      ),
    );
  });

  test('public demo exposes display analysis and verified-event states', () {
    expect(screen, contains('DISPLAY ONLY'));
    expect(screen, contains('ANALYSIS ACTIVE'));
    expect(screen, contains('VERIFIED EVENT'));
    expect(screen, contains('frames are not being processed by Pandora'));
    expect(screen, contains('no verified incident exists for this display source'));
    for (final oldSource in <String>[
      'Times Square',
      'Perdido',
      'Shibuya',
      'youtube.com',
      'youtube-nocookie.com',
      'webcamlivestream.com',
    ]) {
      expect(screen + webEmbed + stub, isNot(contains(oldSource)));
    }
  });
}
