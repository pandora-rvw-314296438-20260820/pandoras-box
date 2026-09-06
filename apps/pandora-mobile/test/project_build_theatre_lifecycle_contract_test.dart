import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Build Theatre polling is foreground-bound and generation-fenced', () {
    final source = File('lib/features/simple/project_journey_flow.dart')
        .readAsStringSync();

    expect(source, contains('bool _lifecycleResumed = true;'));
    expect(source, contains('int _lifecycleGeneration = 0;'));
    expect(
      source,
      contains('_lifecycleResumed = state == AppLifecycleState.resumed;'),
    );
    expect(
      source,
      contains('if (!_lifecycleResumed) {\n      _refreshTimer?.cancel();'),
    );
    expect(
      source,
      contains('unawaited(_resumeBuild(requestPreviewIfNeeded: true));'),
    );
    expect(
      source,
      contains('if (!_lifecycleResumed || _hasRenderablePreview) return;'),
    );
    expect(source, contains('final generation = _lifecycleGeneration;'));
    expect(source, contains('Completer<void>? _refreshCompletion;'));
    expect(source, contains('await pendingRefresh.future;'));
    expect(
      source,
      contains('generation != _lifecycleGeneration'),
    );
    expect(
      source,
      contains('generation == _lifecycleGeneration'),
    );
  });
}
