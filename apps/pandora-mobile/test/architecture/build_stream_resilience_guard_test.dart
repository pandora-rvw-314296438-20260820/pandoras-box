import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resilient stream consumes Protocol V2 replay and sequence authority',
      () {
    final api =
        File('lib/core/data/project_experience_api.dart').readAsStringSync();
    final repository = File('lib/core/data/project_experience_repository.dart')
        .readAsStringSync();

    expect(api, contains("'pandora_build_stream_replay_v2'"));
    expect(api, contains("'p_after_sequence': afterSequence"));
    expect(api, contains(".order('sequence')"));
    expect(api, contains('left.sequence.compareTo(right.sequence)'));
    expect(api, contains('watchResilientBuildStream'));
    expect(api, contains('snapshot.requiresReplay'));
    expect(repository, contains('watchResilientBuildStream'));
    expect(api, isNot(contains(".order('id')")));
  });

  test('local resume state stores only a monotonic sequence cursor', () {
    final cursor = File('lib/core/data/project_build_stream_cursor_store.dart')
        .readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();

    expect(pubspec, contains('shared_preferences: 2.5.5'));
    expect(lock, contains('shared_preferences:'));
    expect(lock, contains('dependency: "direct main"'));
    expect(cursor, contains('pandora.build-stream.cursor.v2'));
    expect(cursor, contains('prefs.getInt'));
    expect(cursor, contains('prefs.setInt'));
    expect(cursor, contains('if (sequence > current)'));
    expect(cursor, isNot(contains('contentChunk')));
    expect(cursor, isNot(contains('safePayload')));
    expect(cursor, isNot(contains('source')));
  });

  test('expired theatre is described truthfully instead of recreated', () {
    final api =
        File('lib/core/data/project_experience_api.dart').readAsStringSync();
    final conversation =
        File('lib/features/simple/project_build_conversation.dart')
            .readAsStringSync();

    expect(api, contains('historyGapDueToRetention'));
    expect(api, contains('oldestRetainedSequence'));
    expect(conversation, contains('Build continued while you were away'));
    expect(conversation, contains('Reconnecting to the live build'));
    expect(conversation, contains('snapshot.buildStage'));
    expect(conversation, isNot(contains('fake code')));
  });
}
