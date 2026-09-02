import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/project_experience_api.dart';

class _FakeDurableBuildServer {
  static const streamId = 'stream-1';
  static const buildJobId = 'job-1';

  int admissionCount = 0;
  final List<ProjectBuildStreamEvent> _events = <ProjectBuildStreamEvent>[];

  ProjectBuildStart admit() {
    admissionCount += 1;
    return const ProjectBuildStart(
      streamId: streamId,
      state: 'working',
      buildJobId: buildJobId,
    );
  }

  void advanceThrough(int sequence) {
    final start = _events.isEmpty ? 1 : _events.last.sequence + 1;
    for (var value = start; value <= sequence; value += 1) {
      _events.add(
        ProjectBuildStreamEvent(
          id: value,
          sequence: value,
          eventType: value == sequence ? 'job_state' : 'build_step',
          safePayload: <String, Object?>{'serverSequence': value},
          createdAt: DateTime.utc(2026, 9, 2, 10, 0, value),
          buildJobId: buildJobId,
        ),
      );
    }
  }

  ProjectBuildStreamReplay replayAfter(int cursor) {
    final selected = _events
        .where((event) => event.sequence > cursor)
        .toList(growable: false);
    return ProjectBuildStreamReplay(
      events: selected,
      watermarkSequence: _events.isEmpty ? 0 : _events.last.sequence,
      oldestRetainedSequence: _events.isEmpty ? null : _events.first.sequence,
      historyGapDueToRetention: false,
      hasMore: false,
      streamStatus: 'building',
      buildStatus: 'running',
      buildStage: 'building',
      buildJobId: buildJobId,
      projectVersionId: null,
      publicErrorCode: null,
      durableSummary: <String, Object?>{
        'serverWatermark': _events.isEmpty ? 0 : _events.last.sequence,
      },
    );
  }
}

void main() {
  test(
      'Task117 app closure resumes the same durable build from persisted N+1 without duplicate admission',
      () {
    final server = _FakeDurableBuildServer();
    final admitted = server.admit();
    expect(server.admissionCount, 1);

    server.advanceThrough(2);

    var persistedCursor = 0;
    {
      final firstViewer = ProjectBuildStreamReconciler();
      firstViewer.seedCursor(persistedCursor);
      final firstSnapshot = firstViewer.mergeReplay(
        server.replayAfter(persistedCursor),
      );
      persistedCursor = firstSnapshot.latestSequence;

      expect(firstSnapshot.events.map((event) => event.sequence), <int>[1, 2]);
      expect(firstSnapshot.buildJobId, admitted.buildJobId);
      expect(persistedCursor, 2);
    }

    server.advanceThrough(5);

    final secondViewer = ProjectBuildStreamReconciler();
    secondViewer.seedCursor(persistedCursor);
    final resumed = secondViewer.mergeReplay(
      server.replayAfter(persistedCursor),
      reconnecting: true,
    );

    expect(server.admissionCount, 1,
        reason: 'Reopening a viewer must not submit a second build admission.');
    expect(resumed.buildJobId, admitted.buildJobId);
    expect(resumed.latestSequence, 5);
    expect(resumed.reconnecting, isTrue);
    expect(
      resumed.events.map((event) => event.sequence),
      <int>[3, 4, 5],
      reason: 'The new viewer must resume at persisted cursor N+1.',
    );
    expect(
      resumed.events.map((event) => event.sequence).toSet().length,
      resumed.events.length,
      reason: 'Reopen replay must not duplicate already-observed events.',
    );
  });
}
