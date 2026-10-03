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

  test('current shell exposes Vision Intelligence without changing Batalla IA',
      () {
    expect(shell, contains("'Vision Intelligence'"));
    expect(shell, contains("10 => 'vision_intelligence'"));
    expect(shell, contains('10 => EnterpriseVisionScreen('));
    expect(shell, contains("label: 'Pandora'"));
    expect(shell, contains('indices: const <int>[9, 0, 2]'));
    expect(shell, contains("label: 'Work'"));
    expect(shell, contains('indices: const <int>[1, 12, 13, 4, 6]'));
    final advancedStart = shell.indexOf("'pandora-advanced-navigation'");
    final advancedEnd = shell.indexOf("label: 'Security'", advancedStart);
    expect(advancedStart, greaterThanOrEqualTo(0));
    expect(advancedEnd, greaterThan(advancedStart));
    final advanced = shell.substring(advancedStart, advancedEnd);
    expect(advanced, contains("title: const Text('Advanced')"));
    expect(advanced, contains("label: 'Tools'"));
    expect(advanced, contains('indices: const <int>[10, 8, 11, 5]'));
    expect(advanced, contains('onSelected: onSelected'));
    expect(advanced,
        contains('const <int>[8, 10, 11, 5, 14, 15].contains(selectedIndex)'));
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

  test('Android uses a native WebView platform view for the same live feed',
      () {
    expect(adapter,
        contains("if (dart.library.html) 'enterprise_vision_embed_web.dart'"));
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
    expect(androidHost, contains('if (!request.isForMainFrame)'));
    expect(androidHost, contains('webChromeClient = WebChromeClient()'));
    expect(
      androidHost,
      contains('setAcceptThirdPartyCookies(playerWebView, true)'),
    );
  });

  test('public demo exposes display analysis and verified-event states', () {
    expect(screen, contains('DISPLAY ONLY'));
    expect(screen, contains('ANALYSIS ACTIVE'));
    expect(screen, contains('VERIFIED EVENT'));
    expect(screen, contains('frames are not being processed by Pandora'));
    expect(screen,
        contains('no verified incident exists for this display source'));
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
