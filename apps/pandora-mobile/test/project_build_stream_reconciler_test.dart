import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/project_experience_api.dart';

ProjectBuildStreamEvent _event(
  int sequence, {
  String type = 'job_state',
  String? filePath,
  String? contentChunk,
}) {
  return ProjectBuildStreamEvent(
    id: sequence,
    sequence: sequence,
    eventType: type,
    safePayload: const <String, Object?>{},
    createdAt: DateTime.utc(2026, 9, 1, 9, 0),
    filePath: filePath,
    contentChunk: contentChunk,
  );
}

ProjectBuildStreamReplay _replay({
  required List<ProjectBuildStreamEvent> events,
  required int watermark,
  int? oldestRetained,
  bool retentionGap = false,
  bool hasMore = false,
}) {
  return ProjectBuildStreamReplay(
    events: events,
    watermarkSequence: watermark,
    oldestRetainedSequence: oldestRetained,
    historyGapDueToRetention: retentionGap,
    hasMore: hasMore,
    streamStatus: 'building',
    buildStatus: 'running',
    buildStage: 'building',
    buildJobId: 'job-1',
    projectVersionId: null,
    publicErrorCode: null,
    durableSummary: const <String, Object?>{'completedSteps': 2},
  );
}

void main() {
  test('live overlap is deduplicated by stream sequence', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(2);

    final snapshot = reconciler.mergeLive(<ProjectBuildStreamEvent>[
      _event(2),
      _event(3),
      _event(3),
    ]);

    expect(snapshot.latestSequence, 3);
    expect(snapshot.requiresReplay, isFalse);
    expect(snapshot.events.map((event) => event.sequence), <int>[3]);
  });

  test('live sequence gap refuses out-of-order rendering and requires replay',
      () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(3);

    final snapshot = reconciler.mergeLive(<ProjectBuildStreamEvent>[
      _event(5),
    ]);

    expect(snapshot.latestSequence, 3);
    expect(snapshot.requiresReplay, isTrue);
    expect(snapshot.events, isEmpty);
  });

  test(
      'retention gap accepts surviving authoritative replay without fake source',
      () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(3);

    final snapshot = reconciler.mergeReplay(
      _replay(
        events: <ProjectBuildStreamEvent>[_event(5, type: 'verification')],
        watermark: 5,
        oldestRetained: 5,
        retentionGap: true,
      ),
    );

    expect(snapshot.latestSequence, 5);
    expect(snapshot.historyGapDueToRetention, isTrue);
    expect(snapshot.events.single.eventType, 'verification');
  });

  test('fully expired theatre can fast-forward to durable watermark', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(0);

    final snapshot = reconciler.mergeReplay(
      _replay(events: const <ProjectBuildStreamEvent>[], watermark: 9),
    );

    expect(snapshot.latestSequence, 9);
    expect(snapshot.historyGapDueToRetention, isTrue);
    expect(snapshot.events, isEmpty);
    expect(snapshot.buildStage, 'building');
  });

  test('non-retention replay gap fails closed', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(2);

    expect(
      () => reconciler.mergeReplay(
        _replay(events: <ProjectBuildStreamEvent>[_event(4)], watermark: 4),
      ),
      throwsFormatException,
    );
  });

  test('transport-reordered code_chunk is canonicalized before file_started',
      () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(0);

    final snapshot = reconciler.mergeLive(<ProjectBuildStreamEvent>[
      _event(
        2,
        type: 'code_chunk',
        filePath: 'lib/main.dart',
        contentChunk: 'void main() {}\n',
      ),
      _event(1, type: 'file_started', filePath: 'lib/main.dart'),
    ]);

    expect(snapshot.latestSequence, 2);
    expect(snapshot.requiresReplay, isFalse);
    expect(snapshot.events.map((event) => event.sequence), <int>[1, 2]);
    expect(snapshot.events[0].eventType, 'file_started');
    expect(snapshot.events[1].contentChunk, 'void main() {}\n');
  });

  test('shuffled replay source events converge to authoritative sequence', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(0);

    final snapshot = reconciler.mergeReplay(
      _replay(
        events: <ProjectBuildStreamEvent>[
          _event(3, type: 'file_completed', filePath: 'lib/main.dart'),
          _event(
            2,
            type: 'code_chunk',
            filePath: 'lib/main.dart',
            contentChunk: 'alpha\n',
          ),
          _event(1, type: 'file_started', filePath: 'lib/main.dart'),
        ],
        watermark: 3,
      ),
    );

    expect(snapshot.latestSequence, 3);
    expect(snapshot.events.map((event) => event.sequence), <int>[1, 2, 3]);
    expect(snapshot.events[1].contentChunk, 'alpha\n');
  });

  test('live overlap cannot replace replayed authoritative source bytes', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(0);

    reconciler.mergeReplay(
      _replay(
        events: <ProjectBuildStreamEvent>[
          _event(1, type: 'file_started', filePath: 'lib/a.dart'),
          _event(
            2,
            type: 'code_chunk',
            filePath: 'lib/a.dart',
            contentChunk: 'authoritative\n',
          ),
          _event(3, type: 'file_completed', filePath: 'lib/a.dart'),
        ],
        watermark: 3,
      ),
    );

    final snapshot = reconciler.mergeLive(<ProjectBuildStreamEvent>[
      _event(
        2,
        type: 'code_chunk',
        filePath: 'lib/a.dart',
        contentChunk: 'stale-overlap\n',
      ),
      _event(4, type: 'file_started', filePath: 'lib/b.dart'),
      _event(
        5,
        type: 'code_chunk',
        filePath: 'lib/b.dart',
        contentChunk: 'new\n',
      ),
      _event(3, type: 'file_completed', filePath: 'lib/a.dart'),
    ]);

    expect(snapshot.latestSequence, 5);
    expect(snapshot.requiresReplay, isFalse);
    expect(
        snapshot.events.map((event) => event.sequence), <int>[1, 2, 3, 4, 5]);
    expect(snapshot.events[1].contentChunk, 'authoritative\n');
    expect(snapshot.events[4].contentChunk, 'new\n');
  });

  test('reconnect replay overlap converges to one monotonic sequence', () {
    final reconciler = ProjectBuildStreamReconciler();
    reconciler.seedCursor(0);

    reconciler.mergeReplay(
      _replay(
        events: <ProjectBuildStreamEvent>[
          _event(1),
          _event(2),
          _event(3),
        ],
        watermark: 3,
      ),
    );

    final snapshot = reconciler.mergeReplay(
      _replay(
        events: <ProjectBuildStreamEvent>[
          _event(5),
          _event(2),
          _event(4),
          _event(3),
        ],
        watermark: 5,
      ),
      reconnecting: true,
    );

    expect(snapshot.latestSequence, 5);
    expect(
        snapshot.events.map((event) => event.sequence), <int>[1, 2, 3, 4, 5]);
    expect(snapshot.reconnecting, isTrue);
  });
}
