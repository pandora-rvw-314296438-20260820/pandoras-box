import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build conversation uses the authoritative live theatre projection', () {
    final source = File('lib/features/simple/project_build_conversation.dart')
        .readAsStringSync();

    expect(source, contains('watchResilientBuildStream('));
    expect(
        source, contains('ProjectBuildStreamTheatreProjection.fromSnapshot('));
    expect(source, contains('LiveBuildTheatre(state: theatre)'));
    expect(source,
        contains('Source will appear only after real source bytes arrive.'));
    expect(source, isNot(contains('class _BuildConversationView')));
    expect(source, isNot(contains('class _LiveBuildMessage')));
  });

  test('conversation does not infer preview readiness from candidate identity',
      () {
    final source = File('lib/features/simple/project_build_conversation.dart')
        .readAsStringSync();

    expect(source, contains('if (theatre.previewReady)'));
    expect(source, isNot(contains('projectVersionId != null')));
    expect(source, isNot(contains('buildStart.projectVersionId')));
  });
}
