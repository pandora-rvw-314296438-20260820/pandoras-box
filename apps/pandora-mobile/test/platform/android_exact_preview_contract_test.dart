import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/MainActivity.kt',
  );

  test('Android exact preview preserves web asset MIME contracts', () {
    expect(source.existsSync(), isTrue);
    final kotlin = source.readAsStringSync();

    const mappings = <String, String>{
      '"html", "htm"': '"text/html"',
      '"css"': '"text/css"',
      '"js", "mjs"': '"application/javascript"',
      '"json", "map"': '"application/json"',
      '"svg"': '"image/svg+xml"',
      '"png"': '"image/png"',
      '"jpg", "jpeg"': '"image/jpeg"',
      '"gif"': '"image/gif"',
      '"webp"': '"image/webp"',
      '"ico"': '"image/x-icon"',
      '"woff"': '"font/woff"',
      '"woff2"': '"font/woff2"',
      '"ttf"': '"font/ttf"',
      '"otf"': '"font/otf"',
    };

    for (final entry in mappings.entries) {
      expect(
        kotlin,
        contains('${entry.key} -> ${entry.value}'),
        reason: 'Missing exact-preview MIME mapping ${entry.key}',
      );
    }
    expect(
      kotlin,
      contains('else -> declared.ifBlank { "application/octet-stream" }'),
    );
    expect(
      kotlin,
      contains('webView.loadUrl("https://pandora.local/index.html")'),
    );
    const navigationGuard =
        'return uri.scheme != "https" || uri.host != "pandora.local"';
    expect(
      kotlin.split(navigationGuard).length - 1,
      greaterThanOrEqualTo(2),
      reason: 'Both exact-preview WebViews must block foreign HTTPS navigation',
    );
  });

  test('Android exact preview keeps the WebView trust boundary closed', () {
    expect(source.existsSync(), isTrue);
    final kotlin = source.readAsStringSync();

    expect(kotlin, contains('allowFileAccess = false'));
    expect(kotlin, contains('allowContentAccess = false'));
    expect(
      kotlin,
      contains('mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW'),
    );
    expect(kotlin, isNot(contains('addJavascriptInterface')));
    expect(kotlin, contains('if (!isSafePreviewPath(path)'));
    expect(kotlin, contains('if (!files.containsKey("index.html"))'));
  });
}
