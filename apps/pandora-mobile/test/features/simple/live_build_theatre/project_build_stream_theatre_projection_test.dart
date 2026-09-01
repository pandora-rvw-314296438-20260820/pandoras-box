import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/project_experience_api.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/project_build_stream_theatre_projection.dart';

ProjectBuildStreamEvent streamEvent(
  int sequence,
  String type, {
  String? filePath,
  String? content,
  Map<String, Object?> payload = const <String, Object?>{},
  int schemaVersion = 2,
  String retentionClass = 'durable_projection',
}) {
  return ProjectBuildStreamEvent(
    id: sequence,
    sequence: sequence,
    eventSchemaVersion: schemaVersion,
    eventType: type,
    retentionClass: retentionClass,
    filePath: filePath,
    contentChunk: content,
    safePayload: payload,
    createdAt: DateTime.utc(2026, 9, 1, 10, 0, sequence),
  );
}

ProjectBuildStreamSnapshot snapshot(
  List<ProjectBuildStreamEvent> events, {
  bool historyGap = false,
  int? latestSequence,
  String? projectVersionId,
}) {
  return ProjectBuildStreamSnapshot(
    events: events,
    latestSequence:
        latestSequence ??
        events.fold<int>(
          0,
          (value, event) => event.sequence > value ? event.sequence : value,
        ),
    historyGapDueToRetention: historyGap,
    requiresReplay: false,
    reconnecting: false,
    streamStatus: 'building',
    buildStatus: 'building',
    buildStage: 'building',
    buildJobId: 'job-1',
    projectVersionId: projectVersionId,
    publicErrorCode: null,
    durableSummary: const <String, Object?>{},
  );
}

void main() {
  test(
    'projection preserves exact source bytes and authoritative ordering',
    () {
      final state = ProjectBuildStreamTheatreProjection.fromSnapshot(
        streamId: 'stream-1',
        snapshot: snapshot(<ProjectBuildStreamEvent>[
          streamEvent(
            4,
            'generation_completed',
            payload: const <String, Object?>{'file_count': 1},
          ),
          streamEvent(
            3,
            'code_chunk',
            filePath: 'lib/main.dart',
            content: '}\n',
            retentionClass: 'ephemeral',
          ),
          streamEvent(
            1,
            'file_started',
            filePath: 'lib/main.dart',
            retentionClass: 'ephemeral',
          ),
          streamEvent(
            2,
            'code_chunk',
            filePath: 'lib/main.dart',
            content: 'void main() {\n',
            retentionClass: 'ephemeral',
          ),
        ]),
      );

      expect(state.streamId, 'stream-1');
      expect(state.latestSequence, 4);
      expect(state.visibleCode, 'void main() {\n}\n');
      expect(state.sourceByteCount, 16);
      expect(state.sourceLineCount, 3);
      expect(state.sourceHistoryComplete, isTrue);
      expect(state.locallyCompleteSourceMetrics, isTrue);
    },
  );

  test('projection refuses non-v2 stream evidence', () {
    expect(
      () => ProjectBuildStreamTheatreProjection.fromSnapshot(
        streamId: 'stream-1',
        snapshot: snapshot(<ProjectBuildStreamEvent>[
          streamEvent(1, 'stream_started', schemaVersion: 1),
        ]),
      ),
      throwsFormatException,
    );
  });

  test('retention gap never becomes complete local source history', () {
    final state = ProjectBuildStreamTheatreProjection.fromSnapshot(
      streamId: 'stream-1',
      snapshot: snapshot(
        <ProjectBuildStreamEvent>[
          streamEvent(
            11,
            'generation_completed',
            payload: const <String, Object?>{'file_count': 7},
          ),
        ],
        historyGap: true,
        latestSequence: 11,
      ),
    );

    expect(state.historyGapDueToRetention, isTrue);
    expect(state.sourceHistoryComplete, isFalse);
    expect(state.locallyCompleteSourceMetrics, isFalse);
    expect(state.reportedFileCount, 7);
  });

  test('candidate identity does not invent preview readiness', () {
    final state = ProjectBuildStreamTheatreProjection.fromSnapshot(
      streamId: 'stream-1',
      snapshot: snapshot(<ProjectBuildStreamEvent>[
        streamEvent(
          1,
          'job_state',
          payload: const <String, Object?>{
            'status': 'building',
            'stage': 'previewing',
          },
        ),
      ], projectVersionId: 'version-1'),
    );

    expect(state.previewReady, isFalse);
  });
}
