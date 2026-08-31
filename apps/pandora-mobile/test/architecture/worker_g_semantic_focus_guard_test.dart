import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'semantic focus is derived from exact preview source and stays bounded',
    () {
    final source = File('lib/features/simple/project_experience_v2.dart')
        .readAsStringSync();

    expect(source, contains("import 'dart:convert';"));
    expect(source, contains("final targets = <String>['Whole page'];"));
    expect(source, contains("path.endsWith('.html')"));
    expect(source, contains('base64Decode(encoded)'));
    expect(source, contains("targets.add('Header & navigation')"));
    expect(source, contains("targets.add('Main content')"));
    expect(source, contains("targets.add('Section')"));
    expect(source, contains("targets.add('Footer')"));
    expect(source, contains("label: Text(_focusTarget ?? 'Focus')"));
    },
  );

  test('focus is bound to both reasoning and durable change intent', () {
    final source = File('lib/features/simple/project_experience_v2.dart')
        .readAsStringSync();

    expect(source, contains('message: _focusBoundRequest(request),'));
    expect(source, contains('intentText: _focusBoundRequest(actionRequest),'));
    expect(source, contains('Focus target: $focus'));
    expect(source, contains('Requested change: $request'));
  });

  test(
    'semantic focus never introduces an arbitrary script bridge',
    () {
    final source = File('lib/features/simple/project_experience_v2.dart')
        .readAsStringSync();
    final embedded = File('lib/core/platform/pandora_embedded_preview.dart')
        .readAsStringSync();
    final combined = '$source\n$embedded';

    expect(combined, isNot(contains('evaluateJavascript')));
    expect(combined, isNot(contains('JavascriptChannel')));
    expect(combined, isNot(contains('runJavaScript')));
    expect(combined, isNot(contains('addJavaScriptChannel')));
    },
  );
}
