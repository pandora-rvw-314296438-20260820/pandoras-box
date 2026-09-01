import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_event.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_reducer.dart';

LiveBuildEvent event(
  int sequence,
  LiveBuildEventKind kind, {
  String streamId = 'stream-1',
  String? filePath,
  String? content,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return LiveBuildEvent(
    streamId: streamId,
    sequence: sequence,
    schemaVersion: 2,
    kind: kind,
    rawEventType: kind.name,
    safePayload: payload,
    createdAt: DateTime.utc(2026, 9, 1, 6, 0, sequence),
    filePath: filePath,
    contentChunk: content,
  );
}

void main() {
  const reducer = LiveBuildTheatreReducer();

  test(
    'canonical sequence fixes reversed arrival without dropping real code',
    () {
      final state = reducer.reduce(<LiveBuildEvent>[
        event(3, LiveBuildEventKind.fileCompleted, filePath: 'lib/main.dart'),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/main.dart',
          content: 'void main() {}\n',
        ),
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/main.dart'),
      ]);

      expect(state.visibleCode, 'void main() {}\n');
      expect(state.activeFile, 'lib/main.dart');
      expect(state.completedFileCount, 1);
      expect(state.latestSequence, 3);
    },
  );

  test('shuffled replay and live overlap dedupe by stream sequence', () {
    final duplicateChunk = event(
      2,
      LiveBuildEventKind.codeChunk,
      filePath: 'lib/a.dart',
      content: 'alpha\n',
    );
    final state = reducer.reduce(<LiveBuildEvent>[
      event(4, LiveBuildEventKind.generationCompleted),
      duplicateChunk,
      event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/a.dart'),
      duplicateChunk,
      event(3, LiveBuildEventKind.fileCompleted, filePath: 'lib/a.dart'),
    ]);

    expect(state.uniqueFileCount, 1);
    expect(state.sourceLineCount, 2);
    expect(state.sourceByteCount, 'alpha\n'.codeUnits.length);
    expect(state.visibleCode, 'alpha\n');
    expect(state.generationComplete, isTrue);
  });

  test('file_started alone never creates visible source', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/empty.dart'),
    ]);

    expect(state.activeFile, 'lib/empty.dart');
    expect(state.visibleCode, isEmpty);
    expect(state.hasVisibleRealSource, isFalse);
  });

  test('first actual code bytes are enough to open live source', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/main.dart'),
      event(
        2,
        LiveBuildEventKind.codeChunk,
        filePath: 'lib/main.dart',
        content: 'x',
      ),
    ]);

    expect(state.visibleCode, 'x');
    expect(state.hasVisibleRealSource, isTrue);
  });

  test(
    'rewriting the same path resets latest-file metrics without double count',
    () {
      final state = reducer.reduce(<LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/a.dart'),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/a.dart',
          content: 'old\nvalue',
        ),
        event(3, LiveBuildEventKind.fileCompleted, filePath: 'lib/a.dart'),
        event(4, LiveBuildEventKind.fileStarted, filePath: 'lib/a.dart'),
        event(
          5,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/a.dart',
          content: 'new',
        ),
        event(6, LiveBuildEventKind.fileCompleted, filePath: 'lib/a.dart'),
      ]);

      expect(state.uniqueFileCount, 1);
      expect(state.completedFileCount, 1);
      expect(state.sourceByteCount, 3);
      expect(state.sourceLineCount, 1);
      expect(state.visibleCode, 'new');
    },
  );

  test(
    'high-rate chunks keep display buffer bounded while metrics stay exact',
    () {
      const boundedReducer = LiveBuildTheatreReducer(
        maxVisibleSourceChars: 512,
      );
      final events = <LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/large.dart'),
        for (var i = 0; i < 1000; i += 1)
          event(
            i + 2,
            LiveBuildEventKind.codeChunk,
            filePath: 'lib/large.dart',
            content: 'line-$i\n',
          ),
      ];

      final state = boundedReducer.reduce(events);
      final exactBytes = List<String>.generate(
        1000,
        (i) => 'line-$i\n',
      ).join().codeUnits.length;

      expect(state.visibleCode.length, lessThanOrEqualTo(512));
      expect(state.sourceByteCount, exactBytes);
      expect(state.sourceLineCount, 1001);
      expect(state.latestSequence, 1001);
    },
  );

  test('retention gap never claims locally complete source metrics', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      event(
        10,
        LiveBuildEventKind.generationCompleted,
        payload: const <String, Object?>{'fileCount': 28},
      ),
    ], historyGapDueToRetention: true);

    expect(state.generationComplete, isTrue);
    expect(state.reportedFileCount, 28);
    expect(state.locallyCompleteSourceMetrics, isFalse);
  });

  test('local final metrics are only trusted after complete source history is proven', () {
    final events = <LiveBuildEvent>[
      event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/a.dart'),
      event(
        2,
        LiveBuildEventKind.codeChunk,
        filePath: 'lib/a.dart',
        content: 'a\nb',
      ),
      event(3, LiveBuildEventKind.fileCompleted, filePath: 'lib/a.dart'),
      event(4, LiveBuildEventKind.generationCompleted),
    ];

    final conservative = reducer.reduce(events);
    final proven = reducer.reduce(events, sourceHistoryComplete: true);

    expect(conservative.locallyCompleteSourceMetrics, isFalse);
    expect(proven.locallyCompleteSourceMetrics, isTrue);
    expect(proven.sourceLineCount, 2);
  });

  test(
    'future optional event type is ignored without breaking known source',
    () {
      final state = reducer.reduce(<LiveBuildEvent>[
        event(1, LiveBuildEventKind.fileStarted, filePath: 'lib/a.dart'),
        event(
          2,
          LiveBuildEventKind.codeChunk,
          filePath: 'lib/a.dart',
          content: 'real',
        ),
        event(3, LiveBuildEventKind.unknown),
      ]);

      expect(state.visibleCode, 'real');
      expect(state.latestSequence, 3);
    },
  );

  test('mixed stream identities fail closed', () {
    expect(
      () => reducer.reduce(<LiveBuildEvent>[
        event(1, LiveBuildEventKind.streamStarted, streamId: 'stream-a'),
        event(2, LiveBuildEventKind.streamStarted, streamId: 'stream-b'),
      ]),
      throwsFormatException,
    );
  });
}
